#!/usr/bin/env node
// Inspect the built 1.0.37 distributables: npm archives, Python wheels and the enterprise bundle.
//
// Checks, per artifact: the declared version matches the canonical release, the shared installation-reporting
// files are present and byte-identical to the single owner in src/installation-reporting (no forked reporter),
// and nothing ships a handoff, credential, user state, or temporary build artifact.
//
// Writes a JSON evidence summary to stdout (or --out <path>) for the release-verification record. This script
// only reads built artifacts; it never publishes, installs globally, or contacts a registry.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const reporterSourceDir = join(root, "src/installation-reporting");

const args = process.argv.slice(2);
const outIndex = args.indexOf("--out");
const outPath = outIndex === -1 ? null : args[outIndex + 1];
const npmDirIndex = args.indexOf("--npm-dir");
const npmDir = npmDirIndex === -1 ? null : args[npmDirIndex + 1];

const canonicalVersion = JSON.parse(
  readFileSync(join(root, "packages/core/package.json"), "utf8"),
).version;

const problems = [];
const fail = (message) => problems.push(message);

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

// The single reporter owner. Every packaged copy must match these bytes exactly.
const reporterSource = new Map();
for (const name of readdirSync(reporterSourceDir)) {
  if (name.endsWith(".js")) {
    reporterSource.set(name, sha256(readFileSync(join(reporterSourceDir, name))));
  }
}
if (reporterSource.size === 0) {
  fail("no reporter source files found in src/installation-reporting");
}

// Names that must never appear inside a published artifact.
const FORBIDDEN_PATTERNS = [
  { label: "installation handoff", re: /(^|\/)[^/]*handoff[^/]*\.json$/i },
  { label: "reporting binding record", re: /installation-v1-[0-9a-f]{8}/i },
  { label: "reporting state directory", re: /(^|\/)\.aport-reporting(\/|$)/ },
  { label: "passport or decision state", re: /(^|\/)(passport|decision|session-decisions)\.(json|jsonl)$/i },
  { label: "credential material", re: /(^|\/)(\.env|\.npmrc|\.pypirc|credentials|id_rsa|id_ed25519)(\/|$)|\.(pem|key)$/i },
  { label: "guardrail mode env", re: /guardrail-mode\.env$/ },
  { label: "temporary build artifact", re: /(^|\/)(node_modules|\.git|__pycache__|\.pytest_cache|tests\/output|\.DS_Store)(\/|$)|\.(log|tmp|bak|tsbuildinfo)$/ },
];

function checkForbidden(artifact, entries) {
  for (const entry of entries) {
    for (const { label, re } of FORBIDDEN_PATTERNS) {
      if (re.test(entry)) {
        fail(`${artifact}: must not ship ${label}: ${entry}`);
      }
    }
  }
}

// --- npm archives -----------------------------------------------------------------------------------------
function inspectTarball(tgzPath) {
  const filename = basename(tgzPath);
  const listing = execFileSync("tar", ["-tzf", tgzPath], { encoding: "utf8" })
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  const manifestEntry = listing.find((e) => e === "package/package.json");
  if (!manifestEntry) {
    fail(`${filename}: no package/package.json`);
    return null;
  }

  const manifest = JSON.parse(
    execFileSync("tar", ["-xzOf", tgzPath, "package/package.json"], { encoding: "utf8" }),
  );

  // The deprecated compatibility alias intentionally keeps a floor on the root package instead of the
  // release version; it is still published in lockstep, so its own version must match.
  if (manifest.version !== canonicalVersion) {
    fail(`${filename}: declares ${manifest.version}, expected ${canonicalVersion}`);
  }

  checkForbidden(filename, listing);

  // Reporter copies inside this archive must be byte-identical to the single owner.
  const reporterEntries = listing.filter(
    (e) => /\/installation-reporting\/[^/]+\.js$/.test(e) && !e.endsWith("/package.json"),
  );
  const verified = [];
  for (const entry of reporterEntries) {
    const name = basename(entry);
    const expected = reporterSource.get(name);
    if (!expected) {
      fail(`${filename}: ships ${entry}, which is not part of the shared reporter owner (forked reporter)`);
      continue;
    }
    const actual = sha256(execFileSync("tar", ["-xzOf", tgzPath, entry], { maxBuffer: 64 * 1024 * 1024 }));
    if (actual !== expected) {
      fail(`${filename}: ${entry} differs from src/installation-reporting/${name} (forked reporter)`);
    } else {
      verified.push(entry);
    }
  }

  return {
    package: manifest.name,
    version: manifest.version,
    filename,
    sha256: sha256(readFileSync(tgzPath)),
    total_entries: listing.length,
    reporter_files: verified.sort(),
    reporter_bytes_match_source: verified.length === reporterEntries.length,
  };
}

// --- Python wheels ----------------------------------------------------------------------------------------
function inspectWheel(wheelPath) {
  const filename = basename(wheelPath);
  const listing = execFileSync(
    "python3",
    ["-c", "import sys,zipfile;print('\\n'.join(zipfile.ZipFile(sys.argv[1]).namelist()))", wheelPath],
    { encoding: "utf8" },
  )
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  const distInfo = listing.find((e) => /\.dist-info\/METADATA$/.test(e));
  if (!distInfo) {
    fail(`${filename}: no dist-info METADATA`);
    return null;
  }
  const metadata = execFileSync(
    "python3",
    [
      "-c",
      "import sys,zipfile;print(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]).decode())",
      wheelPath,
      distInfo,
    ],
    { encoding: "utf8" },
  );
  const nameMatch = metadata.match(/^Name:\s*(.+)$/m);
  const versionMatch = metadata.match(/^Version:\s*(.+)$/m);
  const declaredVersion = versionMatch ? versionMatch[1].trim() : null;
  if (declaredVersion !== canonicalVersion) {
    fail(`${filename}: declares ${declaredVersion}, expected ${canonicalVersion}`);
  }

  checkForbidden(filename, listing);

  const reporterEntries = listing.filter((e) => /\/installation-reporting\/[^/]+\.js$/.test(e));
  const verified = [];
  for (const entry of reporterEntries) {
    const name = basename(entry);
    const expected = reporterSource.get(name);
    if (!expected) {
      fail(`${filename}: ships ${entry}, which is not part of the shared reporter owner (forked reporter)`);
      continue;
    }
    const actual = execFileSync(
      "python3",
      [
        "-c",
        "import sys,zipfile,hashlib;print(hashlib.sha256(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2])).hexdigest())",
        wheelPath,
        entry,
      ],
      { encoding: "utf8" },
    ).trim();
    if (actual !== expected) {
      fail(`${filename}: ${entry} differs from src/installation-reporting/${name} (forked reporter)`);
    } else {
      verified.push(entry);
    }
  }

  return {
    package: nameMatch ? nameMatch[1].trim() : null,
    version: declaredVersion,
    filename,
    sha256: sha256(readFileSync(wheelPath)),
    total_entries: listing.length,
    reporter_files: verified.sort(),
    reporter_bytes_match_source: verified.length === reporterEntries.length,
  };
}

// --- Enterprise bundle ------------------------------------------------------------------------------------
function inspectEnterpriseBundle() {
  const bundler = join(root, "scripts/bundle-enterprise-scripts.sh");
  if (!existsSync(bundler)) {
    fail("missing scripts/bundle-enterprise-scripts.sh");
    return null;
  }
  const dir = mkdtempSync(join(process.env.TMPDIR || tmpdir(), "aport-enterprise-"));
  try {
    // The bundler takes its output directory and version from the environment, not argv.
    execFileSync("bash", [bundler], {
      stdio: "pipe",
      env: { ...process.env, APORT_BUNDLE_DIST_DIR: dir, APORT_BUNDLE_VERSION: canonicalVersion },
    });
    const files = readdirSync(dir).filter((f) => statSync(join(dir, f)).isFile());
    const variants = [];
    for (const file of files.sort()) {
      const bytes = readFileSync(join(dir, file));
      variants.push({ filename: file, sha256: sha256(bytes), bytes: bytes.length });
    }
    if (variants.length === 0) {
      fail("enterprise bundle produced no files");
    }
    // The bundled device variants install the same runtime through the shared CLI rather than inlining the
    // reporter, so each must pin this release. aport-device-core.mjs is the shared inlined core; its wrappers
    // supply the version, so it is checked for the reporting delegation only.
    const bundledVariants = variants.filter((v) => /\.bundled\.(sh|ps1)$/.test(v.filename));
    if (bundledVariants.length === 0) {
      fail("enterprise bundle produced no bundled device variants");
    }
    for (const variant of bundledVariants) {
      const content = readFileSync(join(dir, variant.filename), "utf8");
      if (!content.includes("reporting")) {
        fail(`enterprise bundle ${variant.filename} does not delegate to the shared reporting CLI`);
      }
      if (!content.includes(canonicalVersion)) {
        fail(`enterprise bundle ${variant.filename} does not pin version ${canonicalVersion}`);
      }
    }
    const core = variants.find((v) => v.filename === "aport-device-core.mjs");
    if (!core) {
      fail("enterprise bundle is missing the shared aport-device-core.mjs");
    } else if (!readFileSync(join(dir, core.filename), "utf8").includes("reporting")) {
      fail("enterprise bundle core does not reference the shared reporting runtime");
    }
    // The manifest is what a device downloads by; it must name this release.
    const manifestFile = join(dir, "enterprise-scripts-manifest.json");
    let manifestVersion = null;
    if (existsSync(manifestFile)) {
      const manifest = JSON.parse(readFileSync(manifestFile, "utf8"));
      manifestVersion = manifest.version;
      if (manifest.version !== canonicalVersion) {
        fail(`enterprise manifest declares ${manifest.version}, expected ${canonicalVersion}`);
      }
      if (manifest.tag !== `v${canonicalVersion}`) {
        fail(`enterprise manifest tag is ${manifest.tag}, expected v${canonicalVersion}`);
      }
    } else {
      fail("enterprise bundle has no enterprise-scripts-manifest.json");
    }
    return {
      version: canonicalVersion,
      manifest_version: manifestVersion,
      files: variants,
      bundled_variants_pinning_release: bundledVariants.map((v) => v.filename),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// --- Collect ----------------------------------------------------------------------------------------------
const npmArtifacts = [];
if (npmDir && existsSync(npmDir)) {
  for (const file of readdirSync(npmDir).sort()) {
    if (file.endsWith(".tgz")) {
      const result = inspectTarball(join(npmDir, file));
      if (result) npmArtifacts.push(result);
    }
  }
}
if (npmArtifacts.length === 0) {
  fail("no npm archives inspected; pass --npm-dir <dir> containing packed .tgz files");
}

const wheelArtifacts = [];
for (const pkg of ["aport_guardrails", "langchain_adapter", "crewai_adapter"]) {
  const dist = join(root, "python", pkg, "dist");
  if (!existsSync(dist)) {
    fail(`missing built distribution directory python/${pkg}/dist`);
    continue;
  }
  const wheels = readdirSync(dist).filter((f) => f.endsWith(`-${canonicalVersion}-py3-none-any.whl`));
  if (wheels.length === 0) {
    fail(`python/${pkg}/dist has no ${canonicalVersion} wheel`);
    continue;
  }
  for (const wheel of wheels.sort()) {
    const result = inspectWheel(join(dist, wheel));
    if (result) wheelArtifacts.push(result);
  }
}
if (wheelArtifacts.length !== 3) {
  fail(`expected three Python wheels at ${canonicalVersion}, inspected ${wheelArtifacts.length}`);
}

const enterprise = inspectEnterpriseBundle();

const summary = {
  canonical_version: canonicalVersion,
  reporter_source: {
    directory: relative(root, reporterSourceDir),
    files: [...reporterSource.keys()].sort(),
    sha256: Object.fromEntries([...reporterSource.entries()].sort()),
  },
  npm_artifacts: npmArtifacts,
  python_wheels: wheelArtifacts,
  enterprise_bundle: enterprise,
  problems,
};

const json = JSON.stringify(summary, null, 2);
if (outPath) {
  const { writeFileSync } = await import("node:fs");
  writeFileSync(outPath, json + "\n");
  console.log(`validate-release-artifacts: wrote ${outPath}`);
} else {
  console.log(json);
}

if (problems.length > 0) {
  console.error(`\nvalidate-release-artifacts: ${problems.length} problem(s):`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.error(
  `validate-release-artifacts: ${npmArtifacts.length} npm archives, ${wheelArtifacts.length} wheels, ` +
    `${enterprise ? enterprise.files.length : 0} enterprise files verified at ${canonicalVersion}`,
);

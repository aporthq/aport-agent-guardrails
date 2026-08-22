#!/usr/bin/env node
// Sync version from the canonical fixed workspace package to the root CLI package,
// all Node/Python packages, manifests, lockfiles, and release docs.

import { createRequire } from 'module';
const require = createRequire(import.meta.url);
import { existsSync, readFileSync, writeFileSync, readdirSync, statSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join, relative } from "path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const canonicalPackagePath = join(root, "packages", "core", "package.json");
const rootPackagePath = join(root, "package.json");
const rootPkg = JSON.parse(readFileSync(rootPackagePath, "utf8"));
const canonicalPkg = JSON.parse(readFileSync(canonicalPackagePath, "utf8"));
const version = canonicalPkg.version || rootPkg.version;
const today = new Date().toISOString().slice(0, 10);

if (!version) {
  console.error("sync-version: no canonical version found");
  process.exit(1);
}

console.log(`sync-version: syncing repo to ${version} (source: ${canonicalPkg.name})`);

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function writeJson(path, value) {
  writeFileSync(path, JSON.stringify(value, null, 2) + "\n");
}

function updateTextFile(path, updater) {
  const current = readFileSync(path, "utf8");
  const next = updater(current);
  if (next !== current) {
    writeFileSync(path, next);
    console.log(`Updated ${relative(root, path)} -> ${version}`);
  }
}

function updateLockfile(path, { rootName, workspaceVersions = {} } = {}) {
  if (!existsSync(path)) {
    return;
  }
  const lock = readJson(path);
  if (rootName) {
    lock.name = rootName;
  }
  lock.version = version;
  if (lock.packages && lock.packages[""]) {
    if (rootName) {
      lock.packages[""].name = rootName;
    }
    lock.packages[""].version = version;
  }
  for (const [workspacePath, workspaceVersion] of Object.entries(workspaceVersions)) {
    if (lock.packages && lock.packages[workspacePath]) {
      lock.packages[workspacePath].version = workspaceVersion;
    }
  }
  writeJson(path, lock);
  console.log(`Updated ${relative(root, path)} -> ${version}`);
}

function promoteRootChangelog(path) {
  if (!existsSync(path)) {
    return;
  }
  updateTextFile(path, (content) => {
    const marker = "## [Unreleased]";
    const unreleasedMatch = content.match(/## \[Unreleased\]([\s\S]*?)(?=\n## \[|$)/);
    if (!unreleasedMatch) {
      return content;
    }

    const unreleasedBody = unreleasedMatch[1].trim();
    let normalized = content.replace(unreleasedMatch[0], "").replace(/\n{3,}/g, "\n\n");

    const escapedVersion = version.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const versionPattern = new RegExp(`## \\[${escapedVersion}\\]([\\s\\S]*?)(?=\\n## \\[|$)`);
    const existingVersionMatch = normalized.match(versionPattern);

    let versionSection = "";
    if (existingVersionMatch) {
      versionSection = `${existingVersionMatch[0].trim()}\n\n`;
      normalized = normalized.replace(existingVersionMatch[0], "").replace(/\n{3,}/g, "\n\n");
    } else if (unreleasedBody) {
      versionSection = `## [${version}] - ${today}\n\n${unreleasedBody}\n\n`;
    }

    const firstVersionIndex = normalized.search(/\n## \[/);
    if (firstVersionIndex === -1) {
      return `${normalized.trimEnd()}\n\n${marker}\n\n${versionSection}`.trimEnd() + "\n";
    }

    const prefix = normalized.slice(0, firstVersionIndex + 1);
    const suffix = normalized.slice(firstVersionIndex + 1).replace(/^\n+/, "");
    return `${prefix}${marker}\n\n${versionSection}${suffix}`.replace(/\n{3,}/g, "\n\n");
  });
}

// Root CLI package is not a Changesets workspace package, so keep it aligned here.
rootPkg.version = version;
writeJson(rootPackagePath, rootPkg);
console.log(`Updated package.json -> ${version}`);

// --- Node workspace packages (packages/ + extensions/) ---
const workspaceVersions = {};
for (const subDir of ["packages", "extensions"]) {
  const workspaceDir = join(root, subDir);
  try {
    const entries = readdirSync(workspaceDir);
    for (const entry of entries) {
      const packageDir = join(workspaceDir, entry);
      const pkgJsonPath = join(packageDir, "package.json");
      try {
        const stat = statSync(pkgJsonPath);
        if (stat.isFile()) {
          const pkg = readJson(pkgJsonPath);
          pkg.version = version;
          writeJson(pkgJsonPath, pkg);
          const workspacePath = relative(root, packageDir).replace(/\\/g, "/");
          workspaceVersions[workspacePath] = version;
          console.log(`Updated ${subDir}/${entry}/package.json -> ${version}`);
        }
      } catch {
        // No package.json in this dir, skip
      }
    }
  } catch (error) {
    console.warn(`sync-version: could not read ${subDir}/ directory:`, error.message);
  }
}

// Keep OpenClaw plugin manifest version in sync with root/package versions.
const openclawManifestPath = join(root, "extensions", "openclaw-aport", "openclaw.plugin.json");
try {
  const manifest = readJson(openclawManifestPath);
  manifest.version = version;
  writeJson(openclawManifestPath, manifest);
  console.log(`Updated extensions/openclaw-aport/openclaw.plugin.json -> ${version}`);
} catch (error) {
  console.warn(
    "sync-version: could not update extensions/openclaw-aport/openclaw.plugin.json:",
    error.message,
  );
}

// --- Claude Code plugin manifest + marketplace ---
const pluginJsonPath = join(root, ".claude-plugin", "plugin.json");
try {
  const pluginJson = readJson(pluginJsonPath);
  pluginJson.version = version;
  writeJson(pluginJsonPath, pluginJson);
  console.log(`Updated .claude-plugin/plugin.json -> ${version}`);
} catch {
  // No plugin.json, skip
}

const marketplacePath = join(root, ".claude-plugin", "marketplace.json");
try {
  const marketplace = readJson(marketplacePath);
  if (marketplace.metadata) {
    marketplace.metadata.version = version;
  }
  for (const plugin of marketplace.plugins || []) {
    if (plugin.source && plugin.source.ref) {
      plugin.source.ref = `v${version}`;
    }
  }
  writeJson(marketplacePath, marketplace);
  console.log(`Updated .claude-plugin/marketplace.json -> ${version}`);
} catch {
  // No marketplace.json, skip
}

// --- Python packages ---
const pyPackages = [
  { dir: "python/aport_guardrails", pyproject: "pyproject.toml", init: "__init__.py" },
  { dir: "python/langchain_adapter", pyproject: "pyproject.toml", coreDependency: true },
  { dir: "python/crewai_adapter", pyproject: "pyproject.toml", coreDependency: true },
];

for (const p of pyPackages) {
  const pyprojectPath = join(root, p.dir, p.pyproject);
  let content = readFileSync(pyprojectPath, "utf8");
  content = content.replace(/^version\s*=\s*"[^"]+"/m, `version = "${version}"`);
  if (p.coreDependency) {
    content = content.replace(
      /^(\s*)"aport-agent-guardrails[^"]*",\s*$/m,
      `$1"aport-agent-guardrails>=${version},<2",`,
    );
  }
  writeFileSync(pyprojectPath, content);
  console.log(`Updated ${p.dir}/${p.pyproject} -> ${version}`);

  if (p.init) {
    const initPath = join(root, p.dir, p.init);
    let initContent = readFileSync(initPath, "utf8");
    initContent = initContent.replace(/__version__\s*=\s*"[^"]+"/, `__version__ = "${version}"`);
    writeFileSync(initPath, initContent);
    console.log(`Updated ${p.dir}/${p.init} -> ${version}`);
  }
}

// Keep the deprecated npm shim pointing at the current package line.
const deprecatedShimPath = join(root, "packages", "deprecated-agent-guardrails", "package.json");
try {
  const deprecatedShim = readJson(deprecatedShimPath);
  if (deprecatedShim.dependencies && deprecatedShim.dependencies["@aporthq/aport-agent-guardrails"]) {
    deprecatedShim.dependencies["@aporthq/aport-agent-guardrails"] = `^${version}`;
    writeJson(deprecatedShimPath, deprecatedShim);
    console.log(`Updated packages/deprecated-agent-guardrails/package.json dependency -> ^${version}`);
  }
} catch (error) {
  console.warn("sync-version: could not update deprecated npm shim dependency:", error.message);
}

// --- Lockfiles ---
updateLockfile(join(root, "package-lock.json"), {
  rootName: rootPkg.name,
  workspaceVersions,
});
updateLockfile(join(root, "extensions", "openclaw-aport", "package-lock.json"), {
  rootName: "@aporthq/openclaw-aport",
});

// --- Release docs + changelog ---
updateTextFile(join(root, "docs", "RELEASE.md"), (content) =>
  content.replace(/\*\*Current release:\*\*\s*[^\n]+/, `**Current release:** ${version} (see [CHANGELOG.md](../CHANGELOG.md)).`),
);
promoteRootChangelog(join(root, "CHANGELOG.md"));

console.log("sync-version: done.");

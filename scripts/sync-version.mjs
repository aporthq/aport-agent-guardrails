#!/usr/bin/env node
// Sync version from root package.json to ALL Node + Python sub-packages.
// Run after `changeset version` so everything shares the same version.

import { readFileSync, writeFileSync, readdirSync, statSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const rootPkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const version = rootPkg.version;

if (!version) {
  console.error("sync-version: no version in root package.json");
  process.exit(1);
}

console.log(`sync-version: syncing all packages to ${version}`);

// --- Node workspace packages (packages/ + extensions/) ---
for (const subDir of ["packages", "extensions"]) {
  const workspaceDir = join(root, subDir);
  try {
    const entries = readdirSync(workspaceDir);
    for (const entry of entries) {
      const pkgJsonPath = join(workspaceDir, entry, "package.json");
      try {
        const stat = statSync(pkgJsonPath);
        if (stat.isFile()) {
          const pkg = JSON.parse(readFileSync(pkgJsonPath, "utf8"));
          pkg.version = version;
          writeFileSync(pkgJsonPath, JSON.stringify(pkg, null, 2) + "\n");
          console.log(`Updated ${subDir}/${entry}/package.json -> ${version}`);
        }
      } catch (e) {
        // No package.json in this dir, skip
      }
    }
  } catch (e) {
    console.warn(`sync-version: could not read ${subDir}/ directory:`, e.message);
  }
}

// Keep OpenClaw plugin manifest version in sync with root/package versions.
const openclawManifestPath = join(
  root,
  "extensions",
  "openclaw-aport",
  "openclaw.plugin.json",
);
try {
  const manifest = JSON.parse(readFileSync(openclawManifestPath, "utf8"));
  manifest.version = version;
  writeFileSync(openclawManifestPath, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`Updated extensions/openclaw-aport/openclaw.plugin.json -> ${version}`);
} catch (e) {
  console.warn(
    "sync-version: could not update extensions/openclaw-aport/openclaw.plugin.json:",
    e.message,
  );
}

// --- Python packages ---
const pyPackages = [
  { dir: "python/aport_guardrails", pyproject: "pyproject.toml", init: "__init__.py" },
  { dir: "python/langchain_adapter", pyproject: "pyproject.toml" },
  { dir: "python/crewai_adapter", pyproject: "pyproject.toml" },
];

for (const p of pyPackages) {
  const pyprojectPath = join(root, p.dir, p.pyproject);
  let content = readFileSync(pyprojectPath, "utf8");
  content = content.replace(/^version\s*=\s*"[^"]+"/m, `version = "${version}"`);
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

console.log("sync-version: done.");

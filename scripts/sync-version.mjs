#!/usr/bin/env node
/**
 * Sync version from root package.json to all Python packages.
 * Run after `changeset version` so Node and Python share the same version.
 *
 * Updates:
 * - python/aport_guardrails/pyproject.toml [project].version
 * - python/aport_guardrails/__init__.py __version__
 * - python/langchain_adapter/pyproject.toml [project].version
 * - python/crewai_adapter/pyproject.toml [project].version
 */

import { readFileSync, writeFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const rootPkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const version = rootPkg.version;

if (!version) {
  console.error("sync-version: no version in root package.json");
  process.exit(1);
}

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

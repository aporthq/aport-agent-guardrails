#!/usr/bin/env node
// Keep guardrails releases on the current 1.0.x line unless a non-patch release
// is made explicit. This prevents accidental minor bumps from normal feature PRs.

import { existsSync, readdirSync, readFileSync, writeFileSync } from "fs";
import { dirname, join, relative } from "path";
import { fileURLToPath } from "url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const changesetDir = join(root, ".changeset");
const allowNonPatch = process.env.APORT_ALLOW_NON_PATCH_RELEASE === "1";

if (!existsSync(changesetDir)) {
  process.exit(0);
}

const changesetFiles = readdirSync(changesetDir)
  .filter((file) => file.endsWith(".md") && file !== "README.md")
  .map((file) => join(changesetDir, file));

let normalizedCount = 0;
const majorBumps = [];
const bumpLinePattern =
  /^(\s*(?:"[^"\r\n]+"|'[^'\r\n]+'|[@A-Za-z0-9_./-]+)\s*:\s*)(["']?)(patch|minor|major)\2(\s*(?:#.*)?)$/gm;

for (const filePath of changesetFiles) {
  const current = readFileSync(filePath, "utf8");
  const frontmatter = current.match(/^---\n([\s\S]*?)\n---/);
  if (!frontmatter) {
    continue;
  }

  const nextFrontmatter = frontmatter[1].replace(
    bumpLinePattern,
    (match, prefix, quote, bump, suffix) => {
      if (bump === "patch" || allowNonPatch) {
        return match;
      }
      if (bump === "major") {
        majorBumps.push(`${relative(root, filePath)} requested a major bump`);
        return match;
      }
      normalizedCount += 1;
      return `${prefix}${quote}patch${quote}${suffix}`;
    },
  );

  if (nextFrontmatter !== frontmatter[1]) {
    writeFileSync(filePath, current.replace(frontmatter[1], nextFrontmatter));
  }
}

if (majorBumps.length > 0 && !allowNonPatch) {
  for (const message of majorBumps) {
    console.error(`normalize-changeset-bumps: ${message}`);
  }
  console.error(
    "normalize-changeset-bumps: major releases must be explicit; rerun with APORT_ALLOW_NON_PATCH_RELEASE=1 if intentional.",
  );
  process.exit(1);
}

if (normalizedCount > 0) {
  console.log(`normalize-changeset-bumps: normalized ${normalizedCount} minor bump(s) to patch.`);
}

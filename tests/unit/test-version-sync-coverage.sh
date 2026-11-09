#!/bin/bash
# Unit test: the lockstep release version reaches every package the existing release owners already declare.
#
# The inventory is derived, never duplicated here: Node packages come from the root package.json "workspaces"
# globs, the Python distributions and their first-party constraints come from scripts/sync-version.mjs, and the
# published set comes from .changeset/config.json "fixed". A package added to any of those owners is covered by
# this test on its next run without editing this file. Regression for a release that bumps most manifests but
# silently leaves one package, dependency range, manifest, lockfile or the reporter runtime on the old version.
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_OWNER="$REPO_ROOT/scripts/sync-version.mjs"
CANONICAL="$REPO_ROOT/packages/core/package.json"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

command -v node > /dev/null || fail "node is required"
[ -f "$SYNC_OWNER" ] || fail "missing sync owner scripts/sync-version.mjs"

echo ""
echo "  Unit - lockstep version sync coverage"
echo ""

# The canonical version is whatever the fixed workspace group carries; this test never hard-codes a release.
VERSION="$(node -p "require('$CANONICAL').version")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "canonical version is not a release version: $VERSION"
echo "  Canonical version from $(node -p "require('$CANONICAL').name"): $VERSION"

# --- Node packages, derived from the root "workspaces" globs plus the root CLI itself ---
# packages/deprecated-agent-guardrails is a workspace entry, so the glob covers the compatibility alias too.
NODE_MANIFESTS=()
while IFS= read -r line; do
    [ -n "$line" ] && NODE_MANIFESTS[${#NODE_MANIFESTS[@]}]="$line"
done << EOF
$(node -e '
const { readFileSync, existsSync } = require("fs");
const { join } = require("path");
const root = process.argv[1];
const rootPkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const out = ["package.json"];
for (const pattern of rootPkg.workspaces || []) {
  if (pattern.endsWith("/*")) {
    const dir = pattern.slice(0, -2);
    const { readdirSync } = require("fs");
    for (const entry of readdirSync(join(root, dir))) {
      const rel = `${dir}/${entry}/package.json`;
      if (existsSync(join(root, rel))) out.push(rel);
    }
  } else {
    const rel = `${pattern}/package.json`;
    if (existsSync(join(root, rel))) out.push(rel);
  }
}
console.log(out.join("\n"));
' "$REPO_ROOT")
EOF

[ "${#NODE_MANIFESTS[@]}" -ge 2 ] || fail "derived no Node workspace manifests from the root workspaces globs"

for rel in "${NODE_MANIFESTS[@]}"; do
    actual="$(node -p "require('$REPO_ROOT/$rel').version")"
    [ "$actual" = "$VERSION" ] || fail "$rel is $actual, expected the lockstep $VERSION"
done
echo "  OK ${#NODE_MANIFESTS[@]} Node package manifests are $VERSION"

# --- First-party dependency ranges must not pin a superseded release ---
# Any @aporthq first-party range must admit the new version. The deprecated alias intentionally keeps a floor
# of >=1.0.0 on the root package so it stays installable before the release exists on npm; sync-version.mjs is
# the owner of that exception, so it is read from there instead of being restated as a second rule.
node -e '
const { readFileSync } = require("fs");
const { join } = require("path");
const [root, version, ...rels] = process.argv.slice(1);
const rootPkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const syncOwner = readFileSync(join(root, "scripts/sync-version.mjs"), "utf8");
// sync-version.mjs decides which names are synced first-party and which range is written.
const isFirstParty = (name) =>
  name === rootPkg.name || name === "@aporthq/openclaw-aport" || name.startsWith("@aporthq/aport-agent-guardrails-");
const shimFloorMatch = syncOwner.match(/dependencies\["@aporthq\/aport-agent-guardrails"\]\s*=\s*"([^"]+)"/);
const shimFloor = shimFloorMatch ? shimFloorMatch[1] : null;
let checked = 0;
const problems = [];
for (const rel of rels) {
  const pkg = JSON.parse(readFileSync(join(root, rel), "utf8"));
  for (const field of ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]) {
    for (const [dep, range] of Object.entries(pkg[field] || {})) {
      if (!isFirstParty(dep)) continue;
      checked += 1;
      if (pkg.name === "@aporthq/agent-guardrails" && dep === rootPkg.name) {
        if (shimFloor && range !== shimFloor) {
          problems.push(`${rel} ${field}.${dep} is ${range}, expected the shim floor ${shimFloor} owned by sync-version.mjs`);
        }
        continue;
      }
      if (range !== `>=${version}`) {
        problems.push(`${rel} ${field}.${dep} is ${range}, expected >=${version}`);
      }
    }
  }
}
if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
if (checked === 0) {
  console.error("derived no first-party dependency ranges to check");
  process.exit(1);
}
console.log(`  OK ${checked} first-party dependency ranges admit ${version}`);
' "$REPO_ROOT" "$VERSION" "${NODE_MANIFESTS[@]}" || fail "first-party dependency ranges are not in lockstep"

# --- Python distributions, derived from the pyPackages list in the sync owner ---
PY_DIR_LIST="$(node -e '
const { readFileSync } = require("fs");
const source = readFileSync(process.argv[1], "utf8");
const block = source.match(/const pyPackages = \[([\s\S]*?)\];/);
if (!block) { console.error("could not read pyPackages from sync-version.mjs"); process.exit(1); }
// Keep the sync owner as the source of truth for which distributions constrain the Python core.
const entries = block[1].split("{").slice(1).map((chunk) => {
  const dir = chunk.match(/dir:\s*"([^"]+)"/);
  return dir ? `${dir[1]}\t${/coreDependency:\s*true/.test(chunk) ? "core-dep" : "core"}` : null;
}).filter(Boolean);
if (!entries.length) { console.error("pyPackages declared no directories"); process.exit(1); }
console.log(entries.join("\n"));
' "$SYNC_OWNER")" || fail "could not derive the Python distribution list from the sync owner"

PY_DIRS=()
while IFS= read -r line; do
    [ -n "$line" ] && PY_DIRS[${#PY_DIRS[@]}]="$line"
done << EOF
$PY_DIR_LIST
EOF

[ "${#PY_DIRS[@]}" -eq 3 ] || fail "expected the three declared Python distributions, derived ${#PY_DIRS[@]}"

for entry in "${PY_DIRS[@]}"; do
    dir="${entry%%	*}"
    kind="${entry##*	}"
    pyproject="$REPO_ROOT/$dir/pyproject.toml"
    [ -f "$pyproject" ] || fail "missing $dir/pyproject.toml"
    grep -qE "^version = \"$VERSION\"\$" "$pyproject" \
        || fail "$dir/pyproject.toml does not declare version $VERSION"
    # Only the distributions the sync owner marks coreDependency constrain the Python core.
    if [ "$kind" = "core-dep" ]; then
        grep -qE "\"aport-agent-guardrails>=$VERSION,<2\"" "$pyproject" \
            || fail "$dir/pyproject.toml does not constrain aport-agent-guardrails to >=$VERSION,<2"
    fi
done
echo "  OK ${#PY_DIRS[@]} Python distributions and their first-party constraints are $VERSION"

# The Python core also exports __version__, which installers and the runtime smoke check read.
grep -qE "^__version__ = \"$VERSION\"\$" "$REPO_ROOT/python/aport_guardrails/__init__.py" \
    || fail "python/aport_guardrails/__init__.py does not export __version__ $VERSION"
echo "  OK python/aport_guardrails/__init__.py exports $VERSION"

# --- Plugin manifests and lockfiles ---
for rel in extensions/openclaw-aport/openclaw.plugin.json .claude-plugin/plugin.json; do
    [ -f "$REPO_ROOT/$rel" ] || fail "missing $rel"
    actual="$(node -p "require('$REPO_ROOT/$rel').version")"
    [ "$actual" = "$VERSION" ] || fail "$rel is $actual, expected $VERSION"
done
echo "  OK OpenClaw and Claude plugin manifests are $VERSION"

# The marketplace pins each plugin to the release tag, so a stale ref would install the previous runtime.
node -e '
const { readFileSync } = require("fs");
const [path, version] = process.argv.slice(1);
const marketplace = JSON.parse(readFileSync(path, "utf8"));
if (marketplace.metadata && marketplace.metadata.version !== version) {
  console.error(`marketplace metadata.version is ${marketplace.metadata.version}, expected ${version}`);
  process.exit(1);
}
for (const plugin of marketplace.plugins || []) {
  if (plugin.source && plugin.source.ref && plugin.source.ref !== `v${version}`) {
    console.error(`marketplace plugin ${plugin.name || "?"} ref is ${plugin.source.ref}, expected v${version}`);
    process.exit(1);
  }
}
' "$REPO_ROOT/.claude-plugin/marketplace.json" "$VERSION" || fail "marketplace.json does not point at v$VERSION"
echo "  OK marketplace metadata and plugin refs point at v$VERSION"

for rel in package-lock.json extensions/openclaw-aport/package-lock.json; do
    [ -f "$REPO_ROOT/$rel" ] || continue
    node -e '
const { readFileSync } = require("fs");
const [path, version, rel] = process.argv.slice(1);
const lock = JSON.parse(readFileSync(path, "utf8"));
if (lock.version !== version) {
  console.error(`${rel} top-level version is ${lock.version}, expected ${version}`);
  process.exit(1);
}
const self = lock.packages && lock.packages[""];
if (self && self.version !== version) {
  console.error(`${rel} packages[""] version is ${self.version}, expected ${version}`);
  process.exit(1);
}
' "$REPO_ROOT/$rel" "$VERSION" "$rel" || fail "$rel is not at $VERSION"
done
echo "  OK lockfiles are $VERSION"

# Workspace entries inside the root lockfile must track the release too, or npm ci installs a stale version.
node -e '
const { readFileSync } = require("fs");
const [lockPath, version, ...rels] = process.argv.slice(1);
const lock = JSON.parse(readFileSync(lockPath, "utf8"));
const problems = [];
let checked = 0;
for (const rel of rels) {
  if (rel === "package.json") continue;
  const dir = rel.replace(/\/package\.json$/, "");
  const entry = lock.packages && lock.packages[dir];
  if (!entry || entry.link) continue;
  checked += 1;
  if (entry.version !== version) problems.push(`${lockPath}: ${dir} is ${entry.version}, expected ${version}`);
}
if (problems.length) { console.error(problems.join("\n")); process.exit(1); }
console.log(`  OK ${checked} lockfile workspace entries are ${version}`);
' "$REPO_ROOT/package-lock.json" "$VERSION" "${NODE_MANIFESTS[@]}" || fail "lockfile workspace entries are not in lockstep"

# --- Reporter runtime metadata ---
# The shared reporter reports its own version to the server, so a stale constant misidentifies every receipt.
RUNTIME_JS="$REPO_ROOT/src/installation-reporting/runtime.js"
grep -qE "^const VERSION = '$VERSION';" "$RUNTIME_JS" \
    || fail "src/installation-reporting/runtime.js does not declare VERSION $VERSION"
echo "  OK reporter runtime metadata is $VERSION"

# --- Published set from the changeset fixed group must all be at the release version ---
node -e '
const { readFileSync } = require("fs");
const { join } = require("path");
const [root, version] = process.argv.slice(1);
const config = JSON.parse(readFileSync(join(root, ".changeset/config.json"), "utf8"));
const fixed = (config.fixed || []).flat();
if (!fixed.length) { console.error("changeset config declares no fixed group"); process.exit(1); }
const rootPkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const byName = new Map();
const { readdirSync, existsSync } = require("fs");
for (const pattern of rootPkg.workspaces || []) {
  const dir = pattern.endsWith("/*") ? pattern.slice(0, -2) : null;
  const entries = dir ? readdirSync(join(root, dir)).map((e) => `${dir}/${e}`) : [pattern];
  for (const entry of entries) {
    const manifest = join(root, entry, "package.json");
    if (!existsSync(manifest)) continue;
    const pkg = JSON.parse(readFileSync(manifest, "utf8"));
    byName.set(pkg.name, { version: pkg.version, entry });
  }
}
const problems = [];
for (const name of fixed) {
  const found = byName.get(name);
  if (!found) { problems.push(`fixed group member ${name} has no workspace package`); continue; }
  if (found.version !== version) problems.push(`${name} (${found.entry}) is ${found.version}, expected ${version}`);
}
if (problems.length) { console.error(problems.join("\n")); process.exit(1); }
console.log(`  OK all ${fixed.length} changeset fixed-group packages are ${version}`);
' "$REPO_ROOT" "$VERSION" || fail "changeset fixed group is not in lockstep"

# --- Release docs must name the release that is actually prepared ---
grep -qE "^\*\*Current release:\*\* $VERSION " "$REPO_ROOT/docs/RELEASE.md" \
    || fail "docs/RELEASE.md does not name $VERSION as the current release"
grep -qE "^## \[$VERSION\]" "$REPO_ROOT/CHANGELOG.md" \
    || fail "CHANGELOG.md has no released section for $VERSION"
echo "  OK docs/RELEASE.md and CHANGELOG.md describe $VERSION"

# Every published workspace package ships release notes for the version it declares. Changesets writes these
# in its own "## <version>" form; the root CHANGELOG is Keep a Changelog and is checked above.
workspace_changelogs=0
for rel in "${NODE_MANIFESTS[@]}"; do
    [ "$rel" = "package.json" ] && continue
    changelog="$REPO_ROOT/${rel%/package.json}/CHANGELOG.md"
    [ -f "$changelog" ] || continue
    grep -qE "^## $VERSION\$" "$changelog" \
        || fail "${rel%/package.json}/CHANGELOG.md has no $VERSION section"
    workspace_changelogs=$((workspace_changelogs + 1))
done
[ "$workspace_changelogs" -gt 0 ] || fail "found no workspace changelogs to check"
echo "  OK $workspace_changelogs workspace changelogs record $VERSION"

# --- Consumed changesets ---
# A leftover changeset means the release notes for this version were not actually generated.
leftover="$(find "$REPO_ROOT/.changeset" -maxdepth 1 -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')"
[ "$leftover" = "0" ] || fail "$leftover unconsumed changeset(s) remain after the version bump"
echo "  OK no unconsumed changesets remain"

echo ""
echo "  All lockstep version sync coverage tests passed."

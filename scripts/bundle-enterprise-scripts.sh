#!/usr/bin/env bash
# Bundle enterprise device scripts: config header + inlined aport-device-core.mjs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENT="$ROOT/enterprise-scripts"
CORE="$ENT/aport-device-core.mjs"
DIST="$ROOT/dist/enterprise-scripts"
VERSION="${APORT_BUNDLE_VERSION:-$(node -p "require('$ROOT/package.json').version")}"

header_through_config() {
    local script="$1"
    local line
    line="$(grep -n '^# NO CHANGES NEEDED BELOW' "$script" | head -1 | cut -d: -f1)"
    sed -n "1,${line}p" "$script"
}

bundle_entry() {
    local entry="$1"
    local command="$2"
    local out="$3"
    {
        header_through_config "$entry"
        printf '# APORT_PACKAGE_VERSION=%s (pinned to this release)\n' "$VERSION"
        printf 'export APORT_PACKAGE_VERSION=%s\n' "$VERSION"
        printf 'export APORT_DEVICE_COMMAND=%s\n' "$command"
        printf '# Bundled from aport-agent-guardrails v%s — do not edit below.\n' "$VERSION"
        printf 'exec node - %s <<'"'"'APORT_DEVICE_CORE'"'"'\n' "$command"
        cat "$CORE"
        printf '\nAPORT_DEVICE_CORE\n'
    } > "$out"
    chmod +x "$out"
    shasum -a 256 "$out" | awk '{print $1}' > "${out}.sha256"
}

mkdir -p "$DIST"

bundle_entry "$ENT/aport-device-deploy.sh" "install" "$DIST/aport-device-deploy.bundled.sh"
bundle_entry "$ENT/aport-device-enforce.sh" "enforce" "$DIST/aport-device-enforce.bundled.sh"
bundle_entry "$ENT/aport-device-uninstall.sh" "uninstall" "$DIST/aport-device-uninstall.bundled.sh"

cp "$CORE" "$DIST/aport-device-core.mjs"
shasum -a 256 "$DIST/aport-device-core.mjs" | awk '{print $1}' > "$DIST/aport-device-core.mjs.sha256"
cp "$ENT"/aport-device-*.ps1 "$DIST/" 2> /dev/null || true
for f in "$DIST"/aport-device-*.ps1; do
    [ -f "$f" ] || continue
    printf '%s\n' "$VERSION" > "${f}.version"
done

DIST="$DIST" VERSION="$VERSION" node << 'NODE'
const fs = require('fs');
const path = require('path');
const dist = process.env.DIST;
const version = process.env.VERSION;
const ids = ['deploy', 'enforce', 'uninstall'];
const scripts = ids.map((id) => {
  const file = 'aport-device-' + id + '.bundled.sh';
  const sha = fs.readFileSync(path.join(dist, file + '.sha256'), 'utf8').trim();
  return { id, filename: file, sha256: sha, download_path: '/enterprise/scripts/' + id };
});
const coreSha = require('crypto')
  .createHash('sha256')
  .update(fs.readFileSync(path.join(dist, 'aport-device-core.mjs')))
  .digest('hex');
scripts.push({
  id: 'core',
  filename: 'aport-device-core.mjs',
  sha256: coreSha,
  download_path: '/enterprise/scripts/core',
});
fs.writeFileSync(
  path.join(dist, 'enterprise-scripts-manifest.json'),
  JSON.stringify(
    {
      version,
      tag: 'v' + version,
      repository: 'https://github.com/aporthq/aport-agent-guardrails',
      platforms: ['darwin', 'linux', 'win32'],
      scripts,
    },
    null,
    2
  )
);
NODE

printf 'Bundled enterprise scripts v%s -> %s\n' "$VERSION" "$DIST"

#!/usr/bin/env bash
# Unit smoke test for the framework drift checker. Uses --offline so make test
# remains deterministic and never depends on upstream framework availability.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aport-framework-drift.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

JSON_OUT="$TEST_DIR/report.json"
MD_OUT="$TEST_DIR/report.md"

echo ""
echo "  Unit — framework drift checker"

node "$REPO_ROOT/scripts/framework-drift-check.mjs" \
    --offline \
    --timeout-ms 5000 \
    --json "$JSON_OUT" \
    --markdown "$MD_OUT"

node -e "
  const fs = require('node:fs');
  const report = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  const ids = report.frameworks.map((item) => item.id);
  for (const id of ['openclaw', 'cursor', 'claude-code', 'langchain', 'crewai', 'deerflow', 'n8n', 'github']) {
    if (!ids.includes(id)) throw new Error('missing framework ' + id);
  }
  if (report.summary.frameworks !== 8) throw new Error('unexpected framework count');
  if (report.summary.driftCount !== 0) throw new Error('offline mode should not report drift');
" "$JSON_OUT"

grep -q "APort Framework Drift Report" "$MD_OUT"
grep -q "OpenClaw" "$MD_OUT"
grep -q "GitHub Repository Guard" "$MD_OUT"

if node "$REPO_ROOT/scripts/framework-drift-check.mjs" \
    --baseline "$TEST_DIR/missing-baseline.json" \
    --json "$TEST_DIR/missing.json" \
    --markdown "$TEST_DIR/missing.md" \
    --timeout-ms 5000 > "$TEST_DIR/missing.out" 2> "$TEST_DIR/missing.err"; then
    echo "FAIL: online drift checker should require a committed baseline" >&2
    exit 1
fi
grep -q "Framework drift baseline not found" "$TEST_DIR/missing.err"

BASELINE="$TEST_DIR/baseline.json"
cat > "$BASELINE" << 'EOF'
{
  "generatedAt": "2026-09-01T00:00:00.000Z",
  "sources": {
    "openclaw-hooks-doc": {
      "framework": "openclaw",
      "type": "http",
      "label": "Plugin hooks doc",
      "url": "https://docs.openclaw.ai/plugins/hooks",
      "sha256": "known-openclaw-doc-hash",
      "capturedAt": "2026-09-01T00:00:00.000Z"
    },
    "openclaw-tags": {
      "framework": "openclaw",
      "type": "github-tags",
      "label": "Latest repository tag",
      "url": "https://github.com/openclaw/openclaw",
      "latestTag": "v2026.9.1",
      "capturedAt": "2026-09-01T00:00:00.000Z"
    }
  }
}
EOF
node "$REPO_ROOT/scripts/framework-drift-check.mjs" \
    --offline \
    --update-baseline \
    --baseline "$BASELINE" \
    --json "$TEST_DIR/offline-update.json" \
    --markdown "$TEST_DIR/offline-update.md" \
    --timeout-ms 5000

node -e "
  const fs = require('node:fs');
  const baseline = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  if (baseline.sources['openclaw-hooks-doc'].sha256 !== 'known-openclaw-doc-hash') {
    throw new Error('offline baseline update erased existing sha256');
  }
  if (baseline.sources['openclaw-tags'].latestTag !== 'v2026.9.1') {
    throw new Error('offline baseline update erased existing latestTag');
  }
" "$BASELINE"

echo "  ✅ framework drift checker offline report"

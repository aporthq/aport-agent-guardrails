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

echo "  ✅ framework drift checker offline report"

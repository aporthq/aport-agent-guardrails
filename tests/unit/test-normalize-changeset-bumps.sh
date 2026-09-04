#!/bin/bash
# Unit tests for Changesets release bump normalization.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/normalize-changeset-bumps.mjs"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output/normalize-changesets")}"
WORK_DIR="$TEST_DIR/work"

mkdir -p "$WORK_DIR/scripts" "$WORK_DIR/.changeset"
cp "$SCRIPT" "$WORK_DIR/scripts/normalize-changeset-bumps.mjs"

echo ""
echo "  Unit - normalize changeset bumps"
echo ""

cat > "$WORK_DIR/.changeset/minor.md" << 'EOF'
---
"@aporthq/aport-agent-guardrails-core": minor
"@aporthq/aport-agent-guardrails": "minor"
'@aporthq/openclaw-aport': minor # release helper should keep comments
---

Release notes.
EOF

node "$WORK_DIR/scripts/normalize-changeset-bumps.mjs" > "$TEST_DIR/minor.out"
grep -q '"@aporthq/aport-agent-guardrails-core": patch' "$WORK_DIR/.changeset/minor.md" || {
    echo "FAIL: unquoted minor bump should normalize to patch" >&2
    cat "$WORK_DIR/.changeset/minor.md" >&2
    exit 1
}
grep -q '"@aporthq/aport-agent-guardrails": "patch"' "$WORK_DIR/.changeset/minor.md" || {
    echo "FAIL: quoted minor bump should normalize to quoted patch" >&2
    cat "$WORK_DIR/.changeset/minor.md" >&2
    exit 1
}
grep -q "'@aporthq/openclaw-aport': patch # release helper should keep comments" "$WORK_DIR/.changeset/minor.md" || {
    echo "FAIL: normalized bump should preserve line comments" >&2
    cat "$WORK_DIR/.changeset/minor.md" >&2
    exit 1
}
grep -q "normalized 3 minor bump" "$TEST_DIR/minor.out" || {
    echo "FAIL: expected normalization count" >&2
    cat "$TEST_DIR/minor.out" >&2
    exit 1
}
echo "  OK minor bumps normalize to patch"

cat > "$WORK_DIR/.changeset/major.md" << 'EOF'
---
"@aporthq/aport-agent-guardrails-core": major
---

Breaking release notes.
EOF

if node "$WORK_DIR/scripts/normalize-changeset-bumps.mjs" > "$TEST_DIR/major.out" 2> "$TEST_DIR/major.err"; then
    echo "FAIL: major bump should fail without explicit override" >&2
    cat "$TEST_DIR/major.out" >&2
    exit 1
fi
grep -q "requested a major bump" "$TEST_DIR/major.err" || {
    echo "FAIL: expected major bump diagnostic" >&2
    cat "$TEST_DIR/major.err" >&2
    exit 1
}
echo "  OK major bumps require explicit override"

APORT_ALLOW_NON_PATCH_RELEASE=1 node "$WORK_DIR/scripts/normalize-changeset-bumps.mjs" > "$TEST_DIR/allow-major.out"
grep -q '"@aporthq/aport-agent-guardrails-core": major' "$WORK_DIR/.changeset/major.md" || {
    echo "FAIL: explicit non-patch release should preserve major bump" >&2
    cat "$WORK_DIR/.changeset/major.md" >&2
    exit 1
}
echo "  OK explicit non-patch override is honored"

echo ""
echo "  All normalize changeset bump tests passed."

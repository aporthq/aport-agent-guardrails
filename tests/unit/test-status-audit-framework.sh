#!/bin/bash
# Unit test: aport-status must read the structured framework field, not context text.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

STATUS_CONFIG="$TEST_DIR/status-config"
TEST_HOME="$TEST_DIR/home"
mkdir -p "$STATUS_CONFIG/aport" "$TEST_HOME/.openclaw"

cat > "$STATUS_CONFIG/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_status_framework_test",
  "kind": "agent",
  "owner_id": "test@example.com",
  "owner_type": "user",
  "spec_version": "oap/1.0",
  "assurance_level": "L1",
  "status": "active",
  "never_expires": true,
  "capabilities": [],
  "limits": {}
}
EOF

cat > "$STATUS_CONFIG/aport/audit.log" << 'EOF'
[2026-09-25 10:00:00.000] tool=bash framework=codex decision_id=dec_context allow=true policy_id=system.command.execute.v1 context="echo framework=goose"
[2026-09-25 10:00:01.000] tool=bash framework=codex decision_id=dec_reason allow=false policy_id=system.command.execute.v1 reason="blocked framework=goose" context="ls -la"
EOF

OUT="$TEST_DIR/status.out"
HOME="$TEST_HOME" OPENCLAW_CONFIG_DIR="$STATUS_CONFIG" "$REPO_ROOT/bin/aport-status.sh" > "$OUT"

grep -q 'codex/bash | echo framework=goose' "$OUT" \
    || fail "status should render the structured codex framework for context line: $(cat "$OUT")"
grep -q 'codex/bash | ls -la' "$OUT" \
    || fail "status should render the structured codex framework for reason line: $(cat "$OUT")"
if grep -q 'goose/bash' "$OUT"; then
    fail "status must not read framework= from context or reason text: $(cat "$OUT")"
fi

echo "PASS: status audit framework parsing"

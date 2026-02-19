#!/bin/bash
# Unit tests for Cursor hook script: mock stdin (allow/deny), assert exit 0/2 and output JSON.
# Uses test passport and guardrail; hook reads stdin and calls guardrail.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "$0")/../setup.sh"
# Use test dir for config so guardrail finds fixture passport (must export for guardrail subprocess)
mkdir -p "$TEST_DIR/aport"
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
export OPENCLAW_CONFIG_DIR="$TEST_DIR"
export OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/decision.json"
export OPENCLAW_AUDIT_LOG="$TEST_DIR/audit.log"

HOOK_SCRIPT="$REPO_ROOT/bin/aport-cursor-hook.sh"
chmod +x "$HOOK_SCRIPT" 2> /dev/null || true

echo ""
echo "  Unit — Cursor hook script (allow/deny, exit 0/2)"
echo "  Hook: $HOOK_SCRIPT"
echo ""

# 1. Allow: command in allowlist (e.g. ls) -> exit 0, allowed: true
echo "  Test: stdin allow (command allowed by passport)..."
OUT1="$TEST_DIR/hook-allow-out.txt"
echo '{"command":"ls -la"}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT1" 2> /dev/null
EXIT1=$?
[[ "$EXIT1" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for allow, got $EXIT1" >&2
    exit 1
}
grep -q '"allowed":true' "$OUT1" || {
    echo "FAIL: output should contain allowed:true" >&2
    cat "$OUT1" >&2
    exit 1
}
grep -q '"permission":"allow"' "$OUT1" || {
    echo "FAIL: output should contain permission:allow" >&2
    exit 1
}
echo "  ✅ Allow: exit 0, permission allow, allowed true"

# 2. Deny: blocked pattern (e.g. rm -rf) -> exit 2, allowed: false
echo "  Test: stdin deny (blocked pattern)..."
OUT2="$TEST_DIR/hook-deny-out.txt"
set +e
echo '{"command":"rm -rf /tmp/x"}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" "$HOOK_SCRIPT" > "$OUT2" 2> /dev/null
EXIT2=$?
set -e
[[ "$EXIT2" -eq 2 ]] || {
    echo "FAIL: expected exit 2 for deny, got $EXIT2 (output: $(cat "$OUT2"))" >&2
    exit 1
}
grep -q '"allowed":false' "$OUT2" || {
    echo "FAIL: output should contain allowed:false" >&2
    cat "$OUT2" >&2
    exit 1
}
grep -q '"permission":"deny"' "$OUT2" || {
    echo "FAIL: output should contain permission:deny" >&2
    exit 1
}
echo "  ✅ Deny: exit 2, permission deny, allowed false"

# 3. Copilot-style input: input.command
echo "  Test: Copilot-style JSON (input.command)..."
OUT3="$TEST_DIR/hook-copilot-out.txt"
echo '{"tool":"runTerminalCommand","input":{"command":"npm install"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT3" 2> /dev/null
EXIT3=$?
[[ "$EXIT3" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for npm install, got $EXIT3" >&2
    exit 1
}
grep -q '"allowed":true' "$OUT3" || {
    echo "FAIL: Copilot-style allow" >&2
    exit 1
}
echo "  ✅ Copilot-style input -> allow"

# 4. Empty stdin -> fail-open allow (per script)
echo "  Test: empty stdin -> allow with message..."
OUT4="$TEST_DIR/hook-empty-out.txt"
printf '' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT4" 2> /dev/null
EXIT4=$?
[[ "$EXIT4" -eq 0 ]] || {
    echo "FAIL: empty stdin should exit 0 (fail-open)" >&2
    exit 1
}
grep -q '"allowed":true' "$OUT4" || {
    echo "FAIL: empty stdin allow" >&2
    exit 1
}
echo "  ✅ Empty stdin -> allow (fail-open)"

echo ""
echo "  All Cursor hook unit tests passed."
echo ""

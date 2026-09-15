#!/bin/bash
# Unit test: framework-specific passport defaults in bin/aport-create-passport.sh
# Ensures agent name/description defaults are framework-aware (no OpenClaw leakage).

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASSPORT_SCRIPT="$REPO_ROOT/bin/aport-create-passport.sh"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"

assert_eq() {
    local actual="$1" expected="$2" msg="${3:-expected '$expected', got '$actual'}"
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $msg" >&2
        exit 1
    fi
}

run_noninteractive_for_framework() {
    local framework="$1"
    local out_file="$2"
    APORT_FRAMEWORK="$framework" "$PASSPORT_SCRIPT" --framework="$framework" --non-interactive --output "$out_file" > /dev/null
}

echo ""
echo "  Unit — framework-specific passport defaults"
echo "  Test dir: $TEST_DIR"
echo ""

cursor_passport="$TEST_DIR/cursor-passport.json"
run_noninteractive_for_framework "cursor" "$cursor_passport"
cursor_name="$(jq -r '.metadata.name' "$cursor_passport")"
cursor_desc="$(jq -r '.metadata.description' "$cursor_passport")"
assert_eq "$cursor_name" "Cursor Agent" "cursor default agent name"
assert_eq "$cursor_desc" "Cursor IDE AI agent with APort guardrails" "cursor default agent description"
jq -e '
  (.capabilities | map(.id) | index("agent.session.create"))
  and ((.limits["agent.session.create"].max_concurrent // null) == null)
' "$cursor_passport" > /dev/null || {
    echo "FAIL: cursor defaults should include agent.session.create capability without an unenforceable max_concurrent limit" >&2
    cat "$cursor_passport" >&2
    exit 1
}
echo "  ✅ cursor defaults are framework-specific"

claude_passport="$TEST_DIR/claude-code-passport.json"
run_noninteractive_for_framework "claude-code" "$claude_passport"
claude_name="$(jq -r '.metadata.name' "$claude_passport")"
claude_desc="$(jq -r '.metadata.description' "$claude_passport")"
assert_eq "$claude_name" "Claude Code Agent" "claude-code default agent name"
assert_eq "$claude_desc" "Claude Code AI agent with APort guardrails" "claude-code default agent description"
jq -e '
  (.capabilities | map(.id) | index("agent.session.create"))
  and ((.limits["agent.session.create"].max_concurrent // null) == null)
' "$claude_passport" > /dev/null || {
    echo "FAIL: claude-code defaults should include agent.session.create capability without an unenforceable max_concurrent limit" >&2
    cat "$claude_passport" >&2
    exit 1
}
echo "  ✅ claude-code defaults are framework-specific"

openclaw_passport="$TEST_DIR/openclaw-passport.json"
run_noninteractive_for_framework "openclaw" "$openclaw_passport"
openclaw_name="$(jq -r '.metadata.name' "$openclaw_passport")"
openclaw_desc="$(jq -r '.metadata.description' "$openclaw_passport")"
assert_eq "$openclaw_name" "OpenClaw Agent" "openclaw default agent name"
assert_eq "$openclaw_desc" "Local OpenClaw AI agent with APort guardrails" "openclaw default agent description"
echo "  ✅ openclaw defaults are framework-specific"

echo ""
echo "  Framework default tests passed."
echo ""

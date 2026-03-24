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
echo "  ✅ cursor defaults are framework-specific"

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

#!/bin/bash
# Framework hook config merges must not overwrite invalid existing JSON.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"

echo ""
echo "  Unit — framework hook config safety"
echo ""

CLAUDE_DIR="$TEST_DIR/invalid-claude"
mkdir -p "$CLAUDE_DIR/aport"
printf '{ invalid json\n' > "$CLAUDE_DIR/settings.json"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$CLAUDE_DIR/aport/passport.json"

set +e
APORT_CLAUDE_CODE_CONFIG_DIR="$CLAUDE_DIR" \
    "$DISPATCHER" --framework=claude-code --output "$CLAUDE_DIR/aport/passport.json" --non-interactive --mode=api --api-url="https://api.aport.io" \
    > "$TEST_DIR/invalid-claude.out" 2>&1
CLAUDE_EXIT=$?
set -e

if [[ "$CLAUDE_EXIT" -eq 0 ]]; then
    echo "FAIL: Claude installer should reject invalid existing settings.json" >&2
    cat "$TEST_DIR/invalid-claude.out" >&2
    exit 1
fi
grep -q "Refusing to overwrite invalid Claude Code settings JSON" "$TEST_DIR/invalid-claude.out" || {
    echo "FAIL: expected invalid Claude settings error" >&2
    cat "$TEST_DIR/invalid-claude.out" >&2
    exit 1
}
grep -q '{ invalid json' "$CLAUDE_DIR/settings.json" || {
    echo "FAIL: invalid Claude settings file should be left intact" >&2
    cat "$CLAUDE_DIR/settings.json" >&2
    exit 1
}
echo "  ✅ Claude Code invalid settings are not overwritten"

CURSOR_DIR="$TEST_DIR/invalid-cursor"
mkdir -p "$CURSOR_DIR/aport"
printf '{ invalid json\n' > "$CURSOR_DIR/hooks.json"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$CURSOR_DIR/aport/passport.json"

set +e
APORT_CURSOR_CONFIG_DIR="$CURSOR_DIR" CURSOR_HOOKS_DIR="$CURSOR_DIR" \
    "$DISPATCHER" --framework=cursor --output "$CURSOR_DIR/aport/passport.json" --non-interactive --mode=api --api-url="https://api.aport.io" \
    > "$TEST_DIR/invalid-cursor.out" 2>&1
CURSOR_EXIT=$?
set -e

if [[ "$CURSOR_EXIT" -eq 0 ]]; then
    echo "FAIL: Cursor installer should reject invalid existing hooks.json" >&2
    cat "$TEST_DIR/invalid-cursor.out" >&2
    exit 1
fi
grep -q "Refusing to overwrite invalid Cursor hooks JSON" "$TEST_DIR/invalid-cursor.out" || {
    echo "FAIL: expected invalid Cursor hooks error" >&2
    cat "$TEST_DIR/invalid-cursor.out" >&2
    exit 1
}
grep -q '{ invalid json' "$CURSOR_DIR/hooks.json" || {
    echo "FAIL: invalid Cursor hooks file should be left intact" >&2
    cat "$CURSOR_DIR/hooks.json" >&2
    exit 1
}
echo "  ✅ Cursor invalid hooks are not overwritten"

echo ""
echo "  Framework hook config safety tests passed."
echo ""

#!/bin/bash
# Unit tests for Claude Code hook script: mock stdin (allow/deny), assert exit 0/2 and hookSpecificOutput format.
# Uses test passport and guardrail; hook reads tool_name + tool_input from JSON stdin.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "$0")/../setup.sh"
mkdir -p "$TEST_DIR/aport"
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
export OPENCLAW_CONFIG_DIR="$TEST_DIR"
export OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/decision.json"
export OPENCLAW_AUDIT_LOG="$TEST_DIR/audit.log"

HOOK_SCRIPT="$REPO_ROOT/bin/aport-claude-code-hook.sh"
chmod +x "$HOOK_SCRIPT" 2> /dev/null || true

echo ""
echo "  Unit — Claude Code hook script (allow/deny, exit 0/2, hookSpecificOutput)"
echo "  Hook: $HOOK_SCRIPT"
echo ""

# 1. Allow: Read-family (exit 0 immediately, no evaluator call)
echo "  Test: Read tool -> allow (exit 0)..."
OUT1="$TEST_DIR/claude-allow-read.txt"
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT1" 2> /dev/null
EXIT1=$?
[[ "$EXIT1" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for Read allow, got $EXIT1" >&2
    exit 1
}
echo "  ✅ Read: exit 0"

# 2. Allow: Bash with allowed command (ls)
echo "  Test: Bash allow (command in allowlist)..."
OUT2="$TEST_DIR/claude-allow-bash.txt"
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT2" 2> /dev/null
EXIT2=$?
[[ "$EXIT2" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for Bash allow, got $EXIT2" >&2
    exit 1
}
echo "  ✅ Bash allow: exit 0"

# 3. Deny: Bash with blocked pattern (rm -rf) -> exit 2, hookSpecificOutput
echo "  Test: Bash deny (blocked pattern)..."
OUT3="$TEST_DIR/claude-deny-bash.txt"
set +e
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" "$HOOK_SCRIPT" > "$OUT3" 2> /dev/null
EXIT3=$?
set -e
[[ "$EXIT3" -eq 2 ]] || {
    echo "FAIL: expected exit 2 for deny, got $EXIT3 (output: $(cat "$OUT3"))" >&2
    exit 1
}
grep -q 'hookSpecificOutput' "$OUT3" || {
    echo "FAIL: output should contain hookSpecificOutput" >&2
    cat "$OUT3" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT3" || {
    echo "FAIL: output should contain permissionDecision deny" >&2
    cat "$OUT3" >&2
    exit 1
}
echo "  ✅ Deny: exit 2, hookSpecificOutput.permissionDecision deny"

# 4. Deny: Unknown tool (fail-closed)
echo "  Test: Unknown tool -> deny (fail-closed)..."
OUT4="$TEST_DIR/claude-deny-unknown.txt"
set +e
echo '{"tool_name":"UnknownTool","tool_input":{}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT4" 2> /dev/null
EXIT4=$?
set -e
[[ "$EXIT4" -eq 2 ]] || {
    echo "FAIL: expected exit 2 for unknown tool, got $EXIT4" >&2
    exit 1
}
grep -q 'fail-closed' "$OUT4" || {
    echo "FAIL: output should mention fail-closed" >&2
    cat "$OUT4" >&2
    exit 1
}
echo "  ✅ Unknown tool: exit 2, fail-closed"

# 5. Empty stdin -> allow (fail-open)
echo "  Test: empty stdin -> allow..."
OUT5="$TEST_DIR/claude-empty.txt"
printf '' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT5" 2> /dev/null
EXIT5=$?
[[ "$EXIT5" -eq 0 ]] || {
    echo "FAIL: empty stdin should exit 0" >&2
    exit 1
}
echo "  ✅ Empty stdin -> exit 0"

# 6. Glob (read-family) -> allow without calling evaluator
echo "  Test: Glob tool -> allow (read-family)..."
OUT6="$TEST_DIR/claude-allow-glob.txt"
echo '{"tool_name":"Glob","tool_input":{"pattern":"*.ts","path":"/tmp"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT6" 2> /dev/null
EXIT6=$?
[[ "$EXIT6" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for Glob, got $EXIT6" >&2
    exit 1
}
echo "  ✅ Glob: exit 0"

# 7. Shell alias (Cursor/tool-wrapper style) -> allow
echo "  Test: Shell alias -> allow..."
OUT7="$TEST_DIR/claude-allow-shell-alias.txt"
echo '{"tool_name":"Shell","tool_input":{"command":"ls -la"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT7" 2> /dev/null
EXIT7=$?
[[ "$EXIT7" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for Shell alias, got $EXIT7" >&2
    exit 1
}
echo "  ✅ Shell alias: exit 0"

# 8. mode selection (api -> deny on unreachable API; local -> allow)
MODE_FILE="$TEST_DIR/aport/guardrail-mode.env"
cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_API_URL=http://127.0.0.1:9
EOF
OUT8="$TEST_DIR/claude-api-mode-unreachable.txt"
set +e
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT8" 2> /dev/null
EXIT8=$?
set -e
[[ "$EXIT8" -eq 2 ]] || {
    echo "FAIL: expected exit 2 in api mode with unreachable API, got $EXIT8" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT8" || {
    echo "FAIL: expected deny payload in api mode failure path" >&2
    cat "$OUT8" >&2
    exit 1
}
echo "  ✅ API mode with unreachable endpoint denies"

cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
OUT9="$TEST_DIR/claude-local-mode-after-api.txt"
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT9" 2> /dev/null
EXIT9=$?
[[ "$EXIT9" -eq 0 ]] || {
    echo "FAIL: expected exit 0 after switching back to local mode, got $EXIT9" >&2
    exit 1
}
echo "  ✅ local mode after switch allows"

echo ""
echo "  All Claude Code hook unit tests passed."
echo ""

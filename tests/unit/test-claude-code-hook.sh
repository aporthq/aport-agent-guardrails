#!/bin/bash
# Unit tests for Claude Code hook script: mock stdin (allow/deny), assert exit 0/2 and hookSpecificOutput format.
# Uses test passport and guardrail; hook reads tool_name + tool_input from JSON stdin.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "$0")/../setup.sh"
mkdir -p "$TEST_DIR/aport"
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
export OPENCLAW_CONFIG_DIR="$TEST_DIR"
export OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json"
export OPENCLAW_AUDIT_LOG="$TEST_DIR/aport/audit.log"

HOOK_SCRIPT="$REPO_ROOT/bin/aport-claude-code-hook.sh"
MODE_FILE="$TEST_DIR/aport/guardrail-mode.env"
chmod +x "$HOOK_SCRIPT" 2> /dev/null || true

echo ""
echo "  Unit — Claude Code hook script (allow/deny, exit 0/2, hookSpecificOutput)"
echo "  Hook: $HOOK_SCRIPT"
echo ""

# 1. Allow: Read with allowed path (local evaluator)
echo "  Test: Read tool -> allow (allowed path)..."
OUT1="$TEST_DIR/claude-allow-read.txt"
set +e
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}' \
    | OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
        OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" > "$OUT1" 2> /dev/null
EXIT1=$?
set -e
[[ "$EXIT1" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for Read allow, got $EXIT1" >&2
    exit 1
}
echo "  ✅ Read allowed path: exit 0"

# 1b. Deny: Read sensitive path (.env default block)
echo "  Test: Read tool -> deny (.env)..."
OUT1B="$TEST_DIR/claude-deny-read-env.txt"
set +e
echo '{"tool_name":"Read","tool_input":{"file_path":"/repo/.env.local"}}' \
    | OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
        OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" > "$OUT1B" 2> /dev/null
EXIT1B=$?
set -e
[[ "$EXIT1B" -eq 2 ]] || {
    echo "FAIL: expected exit 2 for Read .env deny, got $EXIT1B" >&2
    exit 1
}
echo "  ✅ Read sensitive path: exit 2"

# 1c. API mode: Read calls guardrail (unreachable API -> deny)
cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_API_URL=http://127.0.0.1:9
EOF
echo "  Test: Read in API mode with unreachable API -> deny..."
OUT1C="$TEST_DIR/claude-api-read-deny.txt"
set +e
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}' \
    | OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
        OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" > "$OUT1C" 2> /dev/null
EXIT1C=$?
set -e
[[ "$EXIT1C" -eq 2 ]] || {
    echo "FAIL: expected exit 2 for Read in api mode, got $EXIT1C" >&2
    exit 1
}
cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
echo "  ✅ Read API mode: exit 2 when API unreachable"

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

# 10. Agent tool -> session.create policy path (allow with fixture passport)
echo "  Test: Agent tool -> allow..."
OUT10="$TEST_DIR/claude-allow-agent.txt"
echo '{"tool_name":"Agent","tool_input":{"description":"explore codebase","prompt":"find auth flow"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT10" 2> /dev/null
EXIT10=$?
[[ "$EXIT10" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for Agent, got $EXIT10 (output: $(cat "$OUT10" 2> /dev/null))" >&2
    exit 1
}
echo "  ✅ Agent: exit 0"

# 11. Agent(Explore) specifier stripped -> allow
echo "  Test: Agent(Explore) specifier -> allow..."
OUT11="$TEST_DIR/claude-allow-agent-spec.txt"
echo '{"tool_name":"Agent(Explore)","tool_input":{"description":"search"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT11" 2> /dev/null
EXIT11=$?
[[ "$EXIT11" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for Agent(Explore), got $EXIT11" >&2
    exit 1
}
echo "  ✅ Agent(Explore): exit 0"

# 12. WebSearch -> allow
echo "  Test: WebSearch -> allow..."
OUT12="$TEST_DIR/claude-allow-websearch.txt"
echo '{"tool_name":"WebSearch","tool_input":{"query":"claude code hooks"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT12" 2> /dev/null
EXIT12=$?
[[ "$EXIT12" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for WebSearch, got $EXIT12" >&2
    exit 1
}
echo "  ✅ WebSearch: exit 0"

# 13. PowerShell -> allow (maps to bash policy)
echo "  Test: PowerShell -> allow..."
OUT13="$TEST_DIR/claude-allow-powershell.txt"
echo '{"tool_name":"PowerShell","tool_input":{"command":"pnpm --version"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT13" 2> /dev/null
EXIT13=$?
[[ "$EXIT13" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for PowerShell, got $EXIT13" >&2
    exit 1
}
echo "  ✅ PowerShell: exit 0"

# 14. Hosted-style install: no passport.json — resolver must not fall back to ~/.openclaw
echo "  Test: OPENCLAW_CONFIG_DIR anchors paths without passport.json..."
HOSTED_DIR="$TEST_DIR/hosted-no-passport"
mkdir -p "$HOSTED_DIR/aport"
RESOLVED_AUDIT="$(
    bash -c '
        export OPENCLAW_CONFIG_DIR="'"$HOSTED_DIR"'"
        unset OPENCLAW_PASSPORT_FILE OPENCLAW_DECISION_FILE OPENCLAW_AUDIT_LOG
        unset APORT_PASSPORT_FILE APORT_DECISION_FILE APORT_AUDIT_LOG
        # shellcheck source=bin/aport-resolve-paths.sh
        . "'"$REPO_ROOT"'/bin/aport-resolve-paths.sh"
        printf "%s" "$AUDIT_LOG"
    '
)"
[[ "$RESOLVED_AUDIT" == "$HOSTED_DIR/aport/audit.log" ]] || {
    echo "FAIL: expected $HOSTED_DIR/aport/audit.log, got $RESOLVED_AUDIT" >&2
    exit 1
}
echo "  ✅ Resolver uses OPENCLAW_CONFIG_DIR when no passport.json"

echo ""
echo "  All Claude Code hook unit tests passed."
echo ""

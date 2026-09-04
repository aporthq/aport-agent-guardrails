#!/bin/bash
# Unit tests for Cursor hook script: tests all hook event types (beforeShellExecution,
# preToolUse with Shell/Read/Write/Delete/Task/MCP, beforeMCPExecution, subagentStart).
# Uses test passport and guardrail; hook reads stdin and calls guardrail.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "$0")/../setup.sh"
# Use test dir for config so guardrail finds fixture passport (must export for guardrail subprocess)
mkdir -p "$TEST_DIR/aport"
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
export OPENCLAW_CONFIG_DIR="$TEST_DIR"
export OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json"
export OPENCLAW_AUDIT_LOG="$TEST_DIR/aport/audit.log"

HOOK_SCRIPT="$REPO_ROOT/bin/aport-cursor-hook.sh"
chmod +x "$HOOK_SCRIPT" 2> /dev/null || true

echo ""
echo "  Unit — Cursor hook script (all hook events)"
echo "  Hook: $HOOK_SCRIPT"
echo ""

# Empty stdin must fail closed. This catches broken host pipes or direct hook
# invocation without a tool-call payload.
OUT0="$TEST_DIR/cursor-empty-input.txt"
set +e
OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
    OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" < /dev/null > "$OUT0" 2> /dev/null
EXIT0=$?
set -e
[[ "$EXIT0" -eq 2 ]] || {
    echo "FAIL: empty stdin should deny with exit 2, got $EXIT0 (output: $(cat "$OUT0"))" >&2
    exit 1
}
jq -e '.permission == "deny" and .allowed == false' "$OUT0" > /dev/null || {
    echo "FAIL: empty stdin should return Cursor deny JSON" >&2
    cat "$OUT0" >&2
    exit 1
}
echo "  ✅ empty stdin: fail-closed deny"

OUT0B="$TEST_DIR/cursor-oversized-input.txt"
set +e
echo '{"tool_name":"Shell","tool_input":{"command":"ls -la"}}' \
    | APORT_HOOK_STDIN_MAX_BYTES=20 OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
        OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" > "$OUT0B" 2> /dev/null
EXIT0B=$?
set -e
[[ "$EXIT0B" -eq 2 ]] || {
    echo "FAIL: oversized stdin should deny with exit 2, got $EXIT0B (output: $(cat "$OUT0B"))" >&2
    exit 1
}
jq -e '.permission == "deny" and .allowed == false and (.reason | contains("oap.input_too_large"))' "$OUT0B" > /dev/null || {
    echo "FAIL: oversized stdin should return Cursor deny JSON with oap.input_too_large" >&2
    cat "$OUT0B" >&2
    exit 1
}
echo "  ✅ oversized stdin: fail-closed deny"

# Helper: run hook with input, check exit code and output
run_hook() {
    local desc="$1" input="$2" expect_exit="$3" expect_field="$4"
    local out="$TEST_DIR/hook-out-$RANDOM.txt"
    set +e
    echo "$input" | OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
        OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" > "$out" 2> /dev/null
    local actual_exit=$?
    set -e
    if [[ "$actual_exit" -ne "$expect_exit" ]]; then
        echo "FAIL: $desc — expected exit $expect_exit, got $actual_exit (output: $(cat "$out"))" >&2
        exit 1
    fi
    if ! jq -e . "$out" > /dev/null 2>&1; then
        echo "FAIL: $desc — hook stdout must be valid JSON: $(cat "$out")" >&2
        exit 1
    fi
    if [ -n "$expect_field" ] && ! grep -q "$expect_field" "$out"; then
        echo "FAIL: $desc — expected '$expect_field' in output: $(cat "$out")" >&2
        exit 1
    fi
    echo "  ✅ $desc"
}

# --- beforeShellExecution ---
run_hook "beforeShellExecution: allow (ls)" \
    '{"command":"ls -la"}' 0 '"permission":"allow"'

run_hook "beforeShellExecution: deny (rm -rf)" \
    '{"command":"rm -rf /tmp/x"}' 2 '"permission":"deny"'

# --- preToolUse: Shell ---
run_hook "preToolUse Shell: allow (ls)" \
    '{"tool_name":"Shell","tool_input":{"command":"ls -la"}}' 0 '"permission":"allow"'

run_hook "preToolUse run_terminal_cmd: allow (ls)" \
    '{"tool_name":"run_terminal_cmd","tool_input":{"args":{"command":"ls -la"}}}' 0 '"permission":"allow"'

run_hook "preToolUse Shell: deny (sudo)" \
    '{"tool_name":"Shell","tool_input":{"command":"sudo reboot"}}' 2 '"permission":"deny"'

# --- preToolUse: Read (evaluator: allow allowed path) ---
run_hook "preToolUse Read: allow (allowed path)" \
    '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}' 0 '"permission":"allow"'

run_hook "preToolUse read_file: allow (args path)" \
    '{"tool_name":"read_file","tool_input":{"args":{"path":"/tmp/test.txt"}}}' 0 '"permission":"allow"'

run_hook "preToolUse Read: deny (.env sensitive path)" \
    '{"tool_name":"Read","tool_input":{"file_path":"/repo/.env.local"}}' 2 '"permission":"deny"'

run_hook "preToolUse present_file: deny (.env sensitive path)" \
    '{"tool_name":"present_file","tool_input":{"path":"/repo/.env.local"}}' 2 '"permission":"deny"'

# --- preToolUse: Grep (allow without evaluator) ---
run_hook "preToolUse Grep: allow (no evaluator)" \
    '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}' 0 '"permission":"allow"'

run_hook "preToolUse grep_search: allow (no evaluator)" \
    '{"tool_name":"grep_search","tool_input":{"pattern":"TODO"}}' 0 '"permission":"allow"'

# --- preToolUse: Write ---
run_hook "preToolUse Write: allow" \
    '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.txt"}}' 0 '"permission":"allow"'

run_hook "preToolUse edit_file: allow (args path)" \
    '{"tool_name":"edit_file","tool_input":{"args":{"path":"/tmp/test.txt"}}}' 0 '"permission":"allow"'

# --- preToolUse: Delete ---
run_hook "preToolUse Delete: allow" \
    '{"tool_name":"Delete","tool_input":{"file_path":"/tmp/test.txt"}}' 0 '"permission":"allow"'

# --- preToolUse: Task ---
run_hook "preToolUse Task: allow" \
    '{"tool_name":"Task","tool_input":{"description":"run tests"}}' 0 '"permission":"allow"'

# --- preToolUse: Agent / WebSearch (Claude Code parity) ---
run_hook "preToolUse Agent: allow" \
    '{"tool_name":"Agent","tool_input":{"description":"explore repo"}}' 0 '"permission":"allow"'

run_hook "preToolUse WebSearch: allow" \
    '{"tool_name":"WebSearch","tool_input":{"query":"aport guardrails"}}' 0 '"permission":"allow"'

run_hook "preToolUse Edit: allow" \
    '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.txt"}}' 0 '"permission":"allow"'

# --- preToolUse: MCP:<name> ---
run_hook "preToolUse MCP:tool: allow" \
    '{"tool_name":"MCP:github_search","tool_input":{"query":"test"}}' 0 '"permission":"allow"'

# --- preToolUse: unknown tool (fail-closed) ---
run_hook "preToolUse unknown: deny (fail-closed)" \
    '{"tool_name":"SomethingNew","tool_input":{}}' 2 '"permission":"deny"'

# --- beforeMCPExecution ---
run_hook "beforeMCPExecution: allow" \
    '{"tool_name":"github_search","tool_input":{"query":"test"},"server":"github","url":"http://localhost:3000"}' 0 '"permission":"allow"'

# --- subagentStart ---
run_hook "subagentStart: allow" \
    '{"subagent_id":"abc-123","subagent_type":"worker","task":"run unit tests"}' 0 '"permission":"allow"'

# --- Legacy Copilot-style ---
run_hook "Copilot-style: allow (npm install)" \
    '{"tool":"runTerminalCommand","input":{"command":"npm install"}}' 0 '"permission":"allow"'

run_hook "Guardrail self-check with chained command: deny" \
    '{"command":"'"$REPO_ROOT"'/bin/aport-guardrail-bash.sh system.command.execute '\''{}'\''; sudo reboot"}' 2 '"permission":"deny"'

# --- Invalid JSON -> fail-closed with Cursor JSON ---
run_hook "Invalid JSON: deny (fail-closed)" \
    '{"tool_name":"Shell","tool_input":' 2 '"permission":"deny"'

# --- mode selection: local vs api ---
MODE_FILE="$TEST_DIR/aport/guardrail-mode.env"
cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_API_URL=http://127.0.0.1:9
EOF
run_hook "Mode=api with unreachable API: deny" \
    '{"tool_name":"Shell","tool_input":{"command":"ls -la"}}' 2 '"permission":"deny"'

cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_API_URL=http://127.0.0.1:9
APORT_ENFORCEMENT=warn
APORT_AGENT_ID=ap_1234567890abcdef1234567890abcdef
APORT_API_KEY=apk_cursor_secret_should_redact
EOF
run_hook "Mode=api warn with unreachable API: allow with warning" \
    '{"tool_name":"Shell","tool_input":{"command":"ls -la"}}' 0 '"permission":"allow"'
WARN_OUT="$(ls -t "$TEST_DIR"/hook-out-*.txt | head -n 1)"
grep -q "APort warning" "$WARN_OUT" || {
    echo "FAIL: warn mode should emit APort warning" >&2
    cat "$WARN_OUT" >&2
    exit 1
}
grep -q "https://aport.io/passports?details=ap_1234567890abcdef1234567890abcdef" "$WARN_OUT" || {
    echo "FAIL: hosted warn message should include passport review link" >&2
    cat "$WARN_OUT" >&2
    exit 1
}
if grep -q "apk_cursor_secret" "$WARN_OUT"; then
    echo "FAIL: warning output must not leak API keys" >&2
    cat "$WARN_OUT" >&2
    exit 1
fi

cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
run_hook "Mode=local after switch: allow" \
    '{"tool_name":"Shell","tool_input":{"command":"ls -la"}}' 0 '"permission":"allow"'

echo ""
echo "  All Cursor hook unit tests passed."
echo ""

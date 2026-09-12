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
if jq -e 'has("hookSpecificOutput")' "$OUT0B" > /dev/null; then
    echo "FAIL: Cursor hook must not emit Claude hookSpecificOutput schema" >&2
    cat "$OUT0B" >&2
    exit 1
fi
echo "  ✅ oversized stdin: fail-closed deny"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
OUT0C="$TEST_DIR/cursor-oversized-input-warn.txt"
set +e
echo '{"tool_name":"Shell","tool_input":{"command":"ls -la"}}' \
    | APORT_HOOK_STDIN_MAX_BYTES=20 OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
        OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" > "$OUT0C" 2> /dev/null
EXIT0C=$?
set -e
[[ "$EXIT0C" -eq 2 ]] || {
    echo "FAIL: oversized stdin should return Cursor deny JSON in warn mode, got $EXIT0C (output: $(cat "$OUT0C"))" >&2
    exit 1
}
jq -e '.permission == "deny" and .allowed == false and (.reason | contains("oap.input_too_large"))' "$OUT0C" > /dev/null || {
    echo "FAIL: oversized stdin should fail closed with oap.input_too_large even in warn mode" >&2
    cat "$OUT0C" >&2
    exit 1
}
if jq -e 'has("hookSpecificOutput")' "$OUT0C" > /dev/null; then
    echo "FAIL: Cursor warn response must not emit Claude hookSpecificOutput schema" >&2
    cat "$OUT0C" >&2
    exit 1
fi
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
echo "  ✅ oversized stdin: warn mode still fails closed"

# Byte cap must count UTF-8 bytes, not shell characters. Two emoji are 8 bytes.
# Use octal escapes to keep this source file ASCII-stable.
# shellcheck source=bin/lib/hook-runtime.sh
source "$REPO_ROOT/bin/lib/hook-runtime.sh"
JQ_BIN="$(command -v jq)"
JQ_JSON="$(
    aport_hook_build_response_cursor \
        deny \
        'APort denied: command not allowed' \
        ''
)"
printf '%s' "$JQ_JSON" | "$JQ_BIN" -e '
  .permission == "deny"
  and .allowed == false
  and .agentMessage == "APort denied: command not allowed"
  and .agent_message == .agentMessage
  and .user_message == .agentMessage
' > /dev/null || {
    echo "FAIL: Cursor response should preserve camel-case and snake-case message fields" >&2
    printf '%s\n' "$JQ_JSON" >&2
    exit 1
}
NO_JQ_PATH="$TEST_DIR/no-jq-path"
mkdir -p "$NO_JQ_PATH"
FALLBACK_JSON="$(
    PATH="$NO_JQ_PATH"
    hash -r
    aport_hook_build_response_cursor \
        allow \
        'APort warning: quoted "reason" with backslash \ content' \
        $'Warn "quoted" text\nReview: https://aport.io/passports?details=ap_test'
)"
printf '%s' "$FALLBACK_JSON" | "$JQ_BIN" -e '
  .permission == "allow"
  and .allowed == true
  and .agentMessage == .user_message
  and (.user_message | contains("Warn \"quoted\" text"))
  and (.reason | contains("quoted \"reason\""))
' > /dev/null || {
    echo "FAIL: Cursor no-jq fallback should emit valid escaped JSON" >&2
    printf '%s\n' "$FALLBACK_JSON" >&2
    exit 1
}
echo "  ✅ no-jq Cursor response fallback: valid escaped JSON"
MULTIBYTE_RESULT="$(
    APORT_HOOK_STDIN_MAX_BYTES=4 APORT_HOOK_STDIN_CHUNK_BYTES=8 \
        aport_read_stdin_with_timeout < <(printf '\360\237\230\200\360\237\230\200')
)"
[[ "$MULTIBYTE_RESULT" = "$APORT_HOOK_STDIN_TOO_LARGE_SENTINEL" ]] || {
    echo "FAIL: hook stdin cap must enforce bytes for multibyte payloads" >&2
    exit 1
}
echo "  ✅ multibyte oversized stdin: byte cap enforced"

# Helper: run hook with input, check exit code and output
run_hook() {
    local desc="$1" input="$2" expect_exit="$3" expect_field="$4"
    local out="$TEST_DIR/hook-out-$RANDOM.txt"
    LAST_HOOK_OUTPUT="$out"
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

run_hook "beforeShellExecution: missing command fails closed" \
    '{"cwd":"/tmp"}' 2 '"permission":"deny"'

# --- preToolUse: Shell ---
run_hook "preToolUse Shell: allow (ls)" \
    '{"tool_name":"Shell","tool_input":{"command":"ls -la"}}' 0 '"permission":"allow"'

run_hook "preToolUse run_terminal_cmd: allow (ls)" \
    '{"tool_name":"run_terminal_cmd","tool_input":{"args":{"command":"ls -la"}}}' 0 '"permission":"allow"'

run_hook "preToolUse Shell: deny (sudo)" \
    '{"tool_name":"Shell","tool_input":{"command":"sudo reboot"}}' 2 '"permission":"deny"'

run_hook "preToolUse Shell: missing command fails closed" \
    '{"tool_name":"Shell","tool_input":{"description":"missing command"}}' 2 '"permission":"deny"'

# --- preToolUse: Read (evaluator: allow allowed path) ---
run_hook "preToolUse Read: allow (allowed path)" \
    '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}' 0 '"permission":"allow"'

run_hook "preToolUse read_file: allow (args path)" \
    '{"tool_name":"read_file","tool_input":{"args":{"path":"/tmp/test.txt"}}}' 0 '"permission":"allow"'

run_hook "preToolUse Read: deny (.env sensitive path)" \
    '{"tool_name":"Read","tool_input":{"file_path":"/repo/.env.local"}}' 2 '"permission":"deny"'

run_hook "preToolUse present_file: deny (.env sensitive path)" \
    '{"tool_name":"present_file","tool_input":{"path":"/repo/.env.local"}}' 2 '"permission":"deny"'

# --- preToolUse: Grep/search reads ---
run_hook "preToolUse Grep: missing path fails closed" \
    '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}' 2 '"permission":"deny"'

mkdir -p "$TEST_DIR/cursor-search-root"
run_hook "preToolUse Grep: directory search fails closed" \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"SECRET\",\"path\":\"$TEST_DIR/cursor-search-root\"}}" 2 '"permission":"deny"'
grep -q 'oap.recursive_search_unsupported' "$LAST_HOOK_OUTPUT" || {
    echo "FAIL: expected recursive search deny for directory-scoped Grep" >&2
    cat "$LAST_HOOK_OUTPUT" >&2
    exit 1
}

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
run_hook "preToolUse Grep: directory search still fails closed in warn mode" \
    "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"SECRET\",\"path\":\"$TEST_DIR/cursor-search-root\"}}" 2 '"permission":"deny"'
grep -q 'oap.recursive_search_unsupported' "$LAST_HOOK_OUTPUT" || {
    echo "FAIL: expected recursive search deny for directory-scoped Grep in warn mode" >&2
    cat "$LAST_HOOK_OUTPUT" >&2
    exit 1
}
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF

run_hook "preToolUse grep_search: path is evaluated" \
    '{"tool_name":"grep_search","tool_input":{"pattern":"TODO","dir_path":"/repo/.ssh"}}' 2 '"permission":"deny"'

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

run_hook "preToolUse WebSearch without URL/domain: deny" \
    '{"tool_name":"WebSearch","tool_input":{"query":"aport guardrails"}}' 2 '"permission":"deny"'
grep -q 'oap.missing_required_context' "$LAST_HOOK_OUTPUT" || {
    echo "FAIL: expected missing context deny for WebSearch without URL/domain" >&2
    cat "$LAST_HOOK_OUTPUT" >&2
    exit 1
}

run_hook "preToolUse Edit: allow" \
    '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.txt"}}' 0 '"permission":"allow"'

# --- preToolUse: MCP:<name> ---
run_hook "preToolUse MCP:tool: allow" \
    '{"tool_name":"MCP:github_search","tool_input":{"query":"test"}}' 0 '"permission":"allow"'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_restricted_cursor_mcp",
  "agent_id": "ap_restricted_cursor_mcp",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"],
      "allowed_tools": ["issues.*"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "preToolUse MCP cannot spoof server through tool input" \
    '{"tool_name":"mcp__evil__issues_list","tool_input":{"server":"github","tool":"issues.list","id":"x"}}' 2 '"permission":"deny"'
grep -q 'oap.mcp_server_not_allowed' "$LAST_HOOK_OUTPUT" || {
    echo "FAIL: expected Cursor MCP spoof to deny on server allowlist" >&2
    cat "$LAST_HOOK_OUTPUT" >&2
    exit 1
}

run_hook "preToolUse ReadMcpResourceTool cannot spoof server through URI" \
    '{"tool_name":"ReadMcpResourceTool","tool_input":{"server":"evil","tool":"resources.read","uri":"mcp://github/repo/README.md"}}' 2 '"permission":"deny"'
grep -q 'oap.mcp_server_not_allowed' "$LAST_HOOK_OUTPUT" || {
    echo "FAIL: expected Cursor MCP resource spoof to deny on routing server" >&2
    cat "$LAST_HOOK_OUTPUT" >&2
    exit 1
}

run_hook "beforeMCPExecution trusts native server metadata" \
    '{"hook_event_name":"beforeMCPExecution","tool_name":"issues.list","server":"github","tool_input":{"query":"test"}}' 0 '"permission":"allow"'

run_hook "legacy MCP event preserves top-level server metadata" \
    '{"tool_name":"issues.list","server":"github","tool_input":{"query":"test"}}' 0 '"permission":"allow"'
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "preToolUse ReadMcpResourceTool: preserve resource operation" \
    '{"tool_name":"ReadMcpResourceTool","mcp_server_name":"github","tool_input":{"tool":"github.resources.read","uri":"mcp://github/repo/README.md"}}' 0 '"permission":"allow"'
tail -n 1 "$TEST_DIR/aport/session-decisions.jsonl" | jq -e '
    .context.tool == "github.resources.read"
    and .context.mcp_tool == "github.resources.read"
    and (.context.parameter_keys | index("uri"))
    and (.context | has("tool_input") | not)
    and (.context | has("parameters") | not)
' > /dev/null || {
    echo "FAIL: ReadMcpResourceTool should evaluate the resource operation, not the wrapper tool name" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}

# --- preToolUse: unknown tool (fail-closed) ---
run_hook "preToolUse unknown: deny (fail-closed)" \
    '{"tool_name":"SomethingNew","tool_input":{}}' 2 '"permission":"deny"'

# --- beforeMCPExecution ---
run_hook "beforeMCPExecution: allow with legacy server field" \
    '{"tool_name":"github_search","tool_input":{"query":"test"},"server":"github","url":"http://localhost:3000"}' 0 '"permission":"allow"'

# --- subagentStart ---
rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "subagentStart: allow" \
    '{"subagent_id":"abc-123","subagent_type":"worker","task":"secret_task_should_not_persist"}' 0 '"permission":"allow"'
if grep -q 'secret_task_should_not_persist' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: Cursor session decisions must not persist raw subagent prompts" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
tail -n 1 "$TEST_DIR/aport/session-decisions.jsonl" | jq -e '.guardrail_tool == "session.create" and .context.description_length > 0 and .context.subagent_type == "worker"' > /dev/null || {
    echo "FAIL: Cursor subagent context should include description length and subagent type only" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}

# --- Legacy Copilot-style ---
run_hook "Copilot-style: allow (npm install)" \
    '{"tool":"runTerminalCommand","input":{"command":"npm install"}}' 0 '"permission":"allow"'

run_hook "Guardrail self-check with chained command: deny" \
    '{"command":"'"$REPO_ROOT"'/bin/aport-guardrail-bash.sh system.command.execute '\''{}'\''; sudo reboot"}' 2 '"permission":"deny"'

# --- Invalid JSON -> fail-closed with Cursor JSON ---
MODE_FILE="$TEST_DIR/aport/guardrail-mode.env"
run_hook "Invalid JSON: deny (fail-closed)" \
    '{"tool_name":"Shell","tool_input":' 2 '"permission":"deny"'

cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
run_hook "Invalid JSON: warn mode still denies" \
    '{"tool_name":"Shell","tool_input":' 2 '"permission":"deny"'
cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF

# --- mode selection: local vs api ---
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
run_hook "Mode=api warn with unreachable API: deny" \
    '{"tool_name":"Shell","tool_input":{"command":"ls -la"}}' 2 '"permission":"deny"'
WARN_OUT="$(ls -t "$TEST_DIR"/hook-out-*.txt | head -n 1)"
grep -q "oap.evaluation_error" "$WARN_OUT" || {
    echo "FAIL: unreachable API should surface evaluation error" >&2
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

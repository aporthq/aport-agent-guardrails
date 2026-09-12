#!/bin/bash
# Unit tests for Claude Code hook script: mock stdin, assert allow and structured deny output.
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
echo "  Unit — Claude Code hook script (allow/structured deny, hookSpecificOutput)"
echo "  Hook: $HOOK_SCRIPT"
echo ""

# 0. Deny: empty stdin must fail closed
echo "  Test: empty stdin -> structured deny..."
OUT0="$TEST_DIR/claude-empty-input.txt"
set +e
OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
    OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" < /dev/null > "$OUT0" 2> /dev/null
EXIT0=$?
set -e
[[ "$EXIT0" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for empty input, got $EXIT0" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT0" || {
    echo "FAIL: expected structured deny payload for empty input" >&2
    cat "$OUT0" >&2
    exit 1
}
echo "  ✅ Empty input: structured deny"

# 0b. Deny: oversized stdin must fail closed before JSON parsing
echo "  Test: oversized stdin -> structured deny..."
OUT0B="$TEST_DIR/claude-oversized-input.txt"
set +e
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    | APORT_HOOK_STDIN_MAX_BYTES=20 OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
        OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" > "$OUT0B" 2> /dev/null
EXIT0B=$?
set -e
[[ "$EXIT0B" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for oversized input, got $EXIT0B" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT0B" || {
    echo "FAIL: expected structured deny payload for oversized input" >&2
    cat "$OUT0B" >&2
    exit 1
}
grep -q 'oap.input_too_large' "$OUT0B" || {
    echo "FAIL: expected oversized input deny code" >&2
    cat "$OUT0B" >&2
    exit 1
}
echo "  ✅ Oversized input: structured deny"

cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
echo "  Test: oversized stdin in warn mode -> structured deny..."
OUT0C="$TEST_DIR/claude-oversized-input-warn.txt"
set +e
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    | APORT_HOOK_STDIN_MAX_BYTES=20 OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" \
        OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json" "$HOOK_SCRIPT" > "$OUT0C" 2> /dev/null
EXIT0C=$?
set -e
[[ "$EXIT0C" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for oversized warn input, got $EXIT0C" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT0C" || {
    echo "FAIL: expected structured deny payload for oversized warn input" >&2
    cat "$OUT0C" >&2
    exit 1
}
grep -q 'oap.input_too_large' "$OUT0C" || {
    echo "FAIL: expected oversized input warn code" >&2
    cat "$OUT0C" >&2
    exit 1
}
grep -q 'Review:' "$OUT0C" || {
    echo "FAIL: oversized input deny should include remediation/review reference" >&2
    cat "$OUT0C" >&2
    exit 1
}
cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
echo "  ✅ Oversized input: warn mode still fails closed"

# shellcheck source=bin/lib/hook-runtime.sh
source "$REPO_ROOT/bin/lib/hook-runtime.sh"
JQ_BIN="$(command -v jq)"
NO_JQ_PATH="$TEST_DIR/no-jq-path"
mkdir -p "$NO_JQ_PATH"
FALLBACK_JSON="$(
    PATH="$NO_JQ_PATH"
    hash -r
    aport_hook_build_response_claude_code \
        allow \
        'APort warning: quoted "reason" with backslash \ content' \
        $'Warn "quoted" text\nReview: https://aport.io/passports?details=ap_test'
)"
printf '%s' "$FALLBACK_JSON" | "$JQ_BIN" -e '
  .hookSpecificOutput.permissionDecision == "allow"
  and (.systemMessage | contains("Warn \"quoted\" text"))
  and (.hookSpecificOutput.permissionDecisionReason | contains("quoted \"reason\""))
' > /dev/null || {
    echo "FAIL: Claude Code no-jq fallback should emit valid escaped JSON" >&2
    printf '%s\n' "$FALLBACK_JSON" >&2
    exit 1
}
echo "  ✅ no-jq Claude Code response fallback: valid escaped JSON"

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
[[ "$EXIT1B" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for Read .env, got $EXIT1B" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT1B" || {
    echo "FAIL: expected structured deny payload for Read .env" >&2
    cat "$OUT1B" >&2
    exit 1
}
echo "  ✅ Read sensitive path: structured deny"

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
[[ "$EXIT1C" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for Read in api mode, got $EXIT1C" >&2
    exit 1
}
cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
grep -q 'permissionDecision.*deny' "$OUT1C" || {
    echo "FAIL: expected structured deny payload for Read in api mode" >&2
    cat "$OUT1C" >&2
    exit 1
}
echo "  ✅ Read API mode: structured deny when API unreachable"

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

# 3. Deny: Bash with blocked pattern (rm -rf) -> hookSpecificOutput
echo "  Test: Bash deny (blocked pattern)..."
OUT3="$TEST_DIR/claude-deny-bash.txt"
set +e
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" "$HOOK_SCRIPT" > "$OUT3" 2> /dev/null
EXIT3=$?
set -e
[[ "$EXIT3" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny, got $EXIT3 (output: $(cat "$OUT3"))" >&2
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
echo "  ✅ Deny: hookSpecificOutput.permissionDecision deny"

echo "  Test: Bash missing command -> deny..."
OUT3B="$TEST_DIR/claude-deny-empty-command.txt"
set +e
echo '{"tool_name":"Bash","tool_input":{"description":"missing command"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" "$HOOK_SCRIPT" > "$OUT3B" 2> /dev/null
EXIT3B=$?
set -e
[[ "$EXIT3B" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for Bash missing command, got $EXIT3B" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT3B" || {
    echo "FAIL: expected structured deny payload for Bash missing command" >&2
    cat "$OUT3B" >&2
    exit 1
}
grep -q 'oap.missing_command' "$OUT3B" || {
    echo "FAIL: expected missing-command reason" >&2
    cat "$OUT3B" >&2
    exit 1
}
echo "  ✅ Bash missing command: structured deny"

# 4. Deny: Unknown tool (fail-closed)
echo "  Test: Unknown tool -> deny (fail-closed)..."
OUT4="$TEST_DIR/claude-deny-unknown.txt"
set +e
echo '{"tool_name":"UnknownTool","tool_input":{}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT4" 2> /dev/null
EXIT4=$?
set -e
[[ "$EXIT4" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for unknown tool, got $EXIT4" >&2
    exit 1
}
grep -q 'fail-closed' "$OUT4" || {
    echo "FAIL: output should mention fail-closed" >&2
    cat "$OUT4" >&2
    exit 1
}
echo "  ✅ Unknown tool: structured deny, fail-closed"

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

echo "  Test: Grep without path -> deny..."
OUT6B="$TEST_DIR/claude-deny-grep-no-path.txt"
set +e
echo '{"tool_name":"Grep","tool_input":{"pattern":"SECRET"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT6B" 2> /dev/null
EXIT6B=$?
set -e
[[ "$EXIT6B" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for Grep without path, got $EXIT6B" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT6B" || {
    echo "FAIL: expected structured deny payload for Grep without path" >&2
    cat "$OUT6B" >&2
    exit 1
}
grep -q 'oap.missing_file_path' "$OUT6B" || {
    echo "FAIL: expected missing-file-path reason" >&2
    cat "$OUT6B" >&2
    exit 1
}
echo "  ✅ Grep without path: structured deny"

echo "  Test: Grep directory target -> deny..."
mkdir -p "$TEST_DIR/claude-search-root"
OUT6C="$TEST_DIR/claude-deny-grep-directory.txt"
set +e
echo "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"SECRET\",\"path\":\"$TEST_DIR/claude-search-root\"}}" | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT6C" 2> /dev/null
EXIT6C=$?
set -e
[[ "$EXIT6C" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for Grep directory target, got $EXIT6C" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT6C" || {
    echo "FAIL: expected structured deny payload for Grep directory target" >&2
    cat "$OUT6C" >&2
    exit 1
}
grep -q 'oap.recursive_search_unsupported' "$OUT6C" || {
    echo "FAIL: expected recursive-search reason" >&2
    cat "$OUT6C" >&2
    exit 1
}
echo "  ✅ Grep directory target: structured deny"

cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
echo "  Test: Grep directory target in warn mode -> deny..."
OUT6D="$TEST_DIR/claude-deny-grep-directory-warn.txt"
set +e
echo "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"SECRET\",\"path\":\"$TEST_DIR/claude-search-root\"}}" | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT6D" 2> /dev/null
EXIT6D=$?
set -e
[[ "$EXIT6D" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for Grep directory target in warn mode, got $EXIT6D" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT6D" || {
    echo "FAIL: expected structured deny payload for Grep directory target in warn mode" >&2
    cat "$OUT6D" >&2
    exit 1
}
grep -q 'oap.recursive_search_unsupported' "$OUT6D" || {
    echo "FAIL: expected recursive-search reason in warn mode" >&2
    cat "$OUT6D" >&2
    exit 1
}
cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
echo "  ✅ Grep directory target: warn mode still fails closed"

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
APORT_ENFORCEMENT=warn
APORT_AGENT_ID=ap_1234567890abcdef1234567890abcdef
APORT_API_KEY=apk_claude_secret_should_redact
EOF
OUT8W="$TEST_DIR/claude-api-mode-warn.txt"
echo "  Test: API mode warn with unreachable endpoint -> deny..."
set +e
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT8W" 2> /dev/null
EXIT8W=$?
set -e
[[ "$EXIT8W" -eq 0 ]] || {
    echo "FAIL: expected exit 0 in warn mode, got $EXIT8W" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT8W" || {
    echo "FAIL: expected deny payload in warn mode for unreachable API" >&2
    cat "$OUT8W" >&2
    exit 1
}
grep -q 'oap.evaluation_error' "$OUT8W" || {
    echo "FAIL: expected evaluation error in unreachable API deny" >&2
    cat "$OUT8W" >&2
    exit 1
}
grep -q 'https://aport.io/passports?details=ap_1234567890abcdef1234567890abcdef' "$OUT8W" || {
    echo "FAIL: hosted warn message should include passport review link" >&2
    cat "$OUT8W" >&2
    exit 1
}
if grep -q 'apk_claude_secret' "$OUT8W"; then
    echo "FAIL: warning output must not leak API keys" >&2
    cat "$OUT8W" >&2
    exit 1
fi
echo "  ✅ API mode warn still denies evaluator failures"

cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_API_URL=http://127.0.0.1:9
EOF
OUT8="$TEST_DIR/claude-api-mode-unreachable.txt"
set +e
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT8" 2> /dev/null
EXIT8=$?
set -e
[[ "$EXIT8" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny in api mode with unreachable API, got $EXIT8" >&2
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
rm -f "$TEST_DIR/aport/session-decisions.jsonl"
OUT10="$TEST_DIR/claude-allow-agent.txt"
echo '{"tool_name":"Agent","tool_input":{"description":"explore codebase","prompt":"secret_prompt_should_not_persist","subagent_type":"reviewer"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT10" 2> /dev/null
EXIT10=$?
[[ "$EXIT10" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for Agent, got $EXIT10 (output: $(cat "$OUT10" 2> /dev/null))" >&2
    exit 1
}
if grep -q 'secret_prompt_should_not_persist\|explore codebase' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: Claude session decisions must not persist raw agent prompts" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.guardrail_tool == "session.create" and .context.description_length > 0 and .context.subagent_type == "reviewer"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Claude session context should include description length and subagent type only" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Agent: exit 0"

# 10b. MCP resource reads should keep operation metadata without raw payload copies
echo "  Test: ReadMcpResourceTool -> minimal MCP context..."
rm -f "$TEST_DIR/aport/session-decisions.jsonl"
OUT10B="$TEST_DIR/claude-allow-read-mcp-resource.txt"
echo '{"tool_name":"ReadMcpResourceTool","tool_input":{"server":"github","tool":"github.resources.read","uri":"mcp://github/repo/README.md","token":"secret_mcp_param_should_not_persist"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT10B" 2> /dev/null
EXIT10B=$?
[[ "$EXIT10B" -eq 0 ]] || {
    echo "FAIL: expected exit 0 for ReadMcpResourceTool, got $EXIT10B (output: $(cat "$OUT10B" 2> /dev/null))" >&2
    exit 1
}
if grep -q 'secret_mcp_param_should_not_persist' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: Claude MCP decisions must not persist raw MCP parameter values" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.guardrail_tool == "mcp.tool" and .context.tool == "github.resources.read" and (.context.parameter_keys | index("uri")) and (.context | has("parameters") | not)' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Claude MCP context should include resource operation metadata only" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ ReadMcpResourceTool: minimal MCP context"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_restricted_claude_mcp",
  "agent_id": "ap_restricted_claude_mcp",
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

echo "  Test: MCP tool cannot spoof server through tool input..."
OUT10C="$TEST_DIR/claude-deny-mcp-server-spoof.txt"
echo '{"tool_name":"mcp__evil__issues_list","tool_input":{"server":"github","tool":"issues.list","id":"x"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT10C" 2> /dev/null
EXIT10C=$?
[[ "$EXIT10C" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for MCP spoof, got $EXIT10C (output: $(cat "$OUT10C" 2> /dev/null))" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT10C" || {
    echo "FAIL: expected MCP spoof to produce structured deny" >&2
    cat "$OUT10C" >&2
    exit 1
}
grep -q 'oap.mcp_server_not_allowed' "$OUT10C" || {
    echo "FAIL: expected MCP spoof to deny on server allowlist" >&2
    cat "$OUT10C" >&2
    exit 1
}
echo "  ✅ MCP spoofed server denied"

echo "  Test: ReadMcpResourceTool cannot spoof server through URI..."
OUT10D="$TEST_DIR/claude-deny-mcp-resource-server-spoof.txt"
echo '{"tool_name":"ReadMcpResourceTool","tool_input":{"server":"evil","tool":"resources.read","uri":"mcp://github/repo/README.md"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT10D" 2> /dev/null
EXIT10D=$?
[[ "$EXIT10D" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for MCP resource spoof, got $EXIT10D (output: $(cat "$OUT10D" 2> /dev/null))" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT10D" || {
    echo "FAIL: expected MCP resource spoof to produce structured deny" >&2
    cat "$OUT10D" >&2
    exit 1
}
grep -q 'oap.mcp_server_not_allowed' "$OUT10D" || {
    echo "FAIL: expected MCP resource spoof to deny on routing server" >&2
    cat "$OUT10D" >&2
    exit 1
}
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
echo "  ✅ MCP resource URI spoof denied"

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

# 12. WebSearch without URL/domain -> deny
echo "  Test: WebSearch without URL/domain -> deny..."
OUT12="$TEST_DIR/claude-deny-websearch.txt"
echo '{"tool_name":"WebSearch","tool_input":{"query":"claude code hooks"}}' | OPENCLAW_CONFIG_DIR="$TEST_DIR" "$HOOK_SCRIPT" > "$OUT12" 2> /dev/null
EXIT12=$?
[[ "$EXIT12" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for WebSearch, got $EXIT12" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT12" || {
    echo "FAIL: expected structured deny payload for WebSearch without URL/domain" >&2
    cat "$OUT12" >&2
    exit 1
}
grep -q 'oap.missing_required_context' "$OUT12" || {
    echo "FAIL: expected missing context deny for WebSearch without URL/domain" >&2
    cat "$OUT12" >&2
    exit 1
}
echo "  ✅ WebSearch without URL/domain: structured deny"

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

# 14. Reentrant guardrail shortcut must not allow chained shell commands
echo "  Test: guardrail self-check with chained command -> deny..."
OUT14="$TEST_DIR/claude-deny-reentrant-chain.txt"
set +e
echo '{"tool_name":"Bash","tool_input":{"command":"'"$REPO_ROOT"'/bin/aport-guardrail-bash.sh system.command.execute '\''{}'\''; sudo reboot"}}' \
    | OPENCLAW_CONFIG_DIR="$TEST_DIR" OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json" "$HOOK_SCRIPT" > "$OUT14" 2> /dev/null
EXIT14=$?
set -e
[[ "$EXIT14" -eq 0 ]] || {
    echo "FAIL: expected exit 0 with structured deny for chained guardrail command, got $EXIT14" >&2
    exit 1
}
grep -q 'permissionDecision.*deny' "$OUT14" || {
    echo "FAIL: expected structured deny payload for chained guardrail command" >&2
    cat "$OUT14" >&2
    exit 1
}
echo "  ✅ chained guardrail command denied"

# 15. Hosted-style install: no passport.json — resolver must not fall back to ~/.openclaw
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

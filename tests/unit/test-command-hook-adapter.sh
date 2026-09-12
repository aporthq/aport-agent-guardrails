#!/bin/bash
# Shared adapter tests for Codex, Gemini CLI, and Goose hooks.

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

chmod +x "$REPO_ROOT/bin/aport-codex-hook.sh" "$REPO_ROOT/bin/aport-gemini-cli-hook.sh" "$REPO_ROOT/bin/aport-goose-hook.sh" 2> /dev/null || true

run_hook() {
    local desc="$1"
    local framework="$2"
    local script="$3"
    local input="$4"
    local jq_assertion="$5"
    local out="$TEST_DIR/out-${framework}-${RANDOM}.json"
    local err="$TEST_DIR/err-${framework}-${RANDOM}.txt"

    set +e
    printf '%s' "$input" | "$script" > "$out" 2> "$err"
    local exit_code=$?
    set -e

    if [[ "$exit_code" -ne 0 ]]; then
        echo "FAIL: $desc exited $exit_code" >&2
        cat "$out" >&2 || true
        cat "$err" >&2 || true
        exit 1
    fi
    if [[ -s "$out" ]]; then
        jq -e . "$out" > /dev/null || {
            echo "FAIL: $desc stdout must be valid JSON" >&2
            cat "$out" >&2
            exit 1
        }
        jq -e "$jq_assertion" "$out" > /dev/null || {
            echo "FAIL: $desc did not match expected response" >&2
            cat "$out" >&2
            exit 1
        }
    else
        [[ "$jq_assertion" = "empty" ]] || {
            echo "FAIL: $desc expected JSON output" >&2
            exit 1
        }
    fi

    echo "  ✅ $desc"
}

echo ""
echo "  Unit — shared command-hook adapter"
echo ""

CODEX="$REPO_ROOT/bin/aport-codex-hook.sh"
GEMINI="$REPO_ROOT/bin/aport-gemini-cli-hook.sh"
GOOSE="$REPO_ROOT/bin/aport-goose-hook.sh"

run_hook "Codex Bash allow returns empty success JSON" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    '. == {}'

run_hook "Codex exec_command maps to shell policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"ls -la"}}' \
    '. == {}'

run_hook "Codex Bash deny uses PreToolUse permissionDecision" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny"'

run_hook "Codex Bash without command fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"description":"missing command"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_command"))'

run_hook "Codex shell allowlist rejects prefixed executable names" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git-malware status"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_not_allowed"))'

run_hook "Gemini shell allowlist rejects prefixed executable names" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"git-malware status"}}' \
    '.decision == "deny" and (.reason | contains("oap.command_not_allowed"))'

run_hook "Goose shell allowlist rejects prefixed executable names" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__shell","tool_input":{"command":"git-malware status"}}' \
    '.decision == "block" and (.reason | contains("oap.command_not_allowed"))'

run_hook "Codex PermissionRequest deny uses decision.behavior" \
    codex "$CODEX" \
    '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"sudo reboot"}}' \
    '.hookSpecificOutput.hookEventName == "PermissionRequest" and .hookSpecificOutput.decision.behavior == "deny"'

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
run_hook "Codex warn mode allows with additionalContext" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.systemMessage and .hookSpecificOutput.additionalContext'

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF

run_hook "Gemini run_shell_command deny uses Gemini decision JSON" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.decision == "deny" and (.reason | contains("APort denied"))'

run_hook "Gemini valid shell allow returns allow JSON" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls -la"}}' \
    '.decision == "allow"'

run_hook "Gemini list_directory fails closed as metadata enumeration" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"list_directory","tool_input":{"dir_path":"/tmp/.ssh"}}' \
    '.decision == "deny" and (.reason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Gemini list_directory with broad root fails closed as metadata enumeration" \
    gemini "$GEMINI" \
    "{\"hook_event_name\":\"BeforeTool\",\"tool_name\":\"list_directory\",\"tool_input\":{\"dir_path\":\"$TEST_DIR\"}}" \
    '.decision == "deny" and (.reason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Gemini read_many_files denies multi-target reads" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_many_files","tool_input":{"include":["README.md","docs/guide.md"]}}' \
    '.decision == "deny" and (.reason | contains("oap.multi_path_read_unsupported"))'

run_hook "Gemini read_many_files denies glob-expanded single target" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_many_files","tool_input":{"include":["/home/user/**"]}}' \
    '.decision == "deny" and (.reason | contains("oap.glob_read_unsupported"))'

run_hook "Gemini grep_search denies recursive directory search" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"grep_search","tool_input":{"pattern":"SECRET","dir_path":"/tmp/project"}}' \
    '.decision == "deny" and (.reason | contains("oap.recursive_search_unsupported"))'

run_hook "Gemini MCP shorthand routes to MCP policy" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp_stripe_create_refund","tool_input":{"amount":1000}}' \
    '.decision == "allow"'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Gemini mcp_context routes to MCP policy before built-in names" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"github__create_issue","mcp_context":{"server_name":"github","tool_name":"create_issue"},"tool_input":{"title":"test"}}' \
    '.decision == "allow"'
jq -e '.guardrail_tool == "mcp.tool" and .context.mcp_server == "github" and .context.mcp_tool == "create_issue"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Gemini mcp_context should force MCP policy mapping" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Gemini mcp_context maps to MCP policy"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Gemini MCP URL routing strips credentials before audit" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://user:password@github/tools?token=secret","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'
if grep -q 'password\|token=secret\|user:' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: MCP server context must not persist URL credentials" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.guardrail_tool == "mcp.tool" and .context.mcp_server == "https://github/tools" and .context.mcp_tool == "issues.list"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: MCP URL routing should strip secrets while preserving endpoint scope" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ MCP URL routing strips credentials before audit"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_url_mcp_allowlist",
  "agent_id": "ap_url_mcp_allowlist",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["https://mcp.github.com"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP URL allowlist preserves host compatibility" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://user:password@mcp.github.com/tools?token=secret","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_scheme_mcp_allowlist",
  "agent_id": "ap_scheme_mcp_allowlist",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["mcp://github"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP scheme allowlist normalizes safely" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github/tools","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'
run_hook "Gemini MCP scheme allowlist preserves bare server compatibility" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp__github__issues.list","tool_input":{"id":"x"}}' \
    '.decision == "allow"'
run_hook "Gemini MCP scheme allowlist rejects different server" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://evil/tools","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_scheme_mcp_wildcard_allowlist",
  "agent_id": "ap_scheme_mcp_wildcard_allowlist",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["mcp://github*"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex MCP scheme wildcard preserves bare server compatibility" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"mcp__github-prod__issues.list","tool_input":{"id":"x"}}' \
    '. == {}'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_url_mcp_path_scope",
  "agent_id": "ap_url_mcp_path_scope",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["https://example.com:8443/trusted"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP URL allowlist preserves port and path boundaries" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"http://example.com:9999/untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP URL allowlist rejects ambiguous authority backslash" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://evil.com\\@example.com:8443/trusted/issues","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.missing_required_context"))'
run_hook "Gemini MCP URL allowlist rejects dot-segment path traversal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/../untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP URL allowlist rejects encoded separator traversal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/..%2funtrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP URL allowlist rejects control-character path normalization" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/.\t./untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.missing_required_context"))'
run_hook "Gemini MCP URL allowlist rejects backslash path traversal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/..\\untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.missing_required_context"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_url_mcp_trailing_path_scope",
  "agent_id": "ap_url_mcp_trailing_path_scope",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["https://example.com:8443/trusted/"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP URL allowlist treats trailing slash scope as directory" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/issues","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_mcp_scheme_path_scope",
  "agent_id": "ap_mcp_scheme_path_scope",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["mcp://github/trusted"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP scoped scheme allowlist permits matching path" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github/trusted/issues","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'
run_hook "Gemini MCP scoped scheme allowlist rejects bare server fallback" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp__github__issues.list","tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP scoped scheme allowlist rejects other schemes" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://github/untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP scoped scheme allowlist rejects dot-segment traversal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github/trusted/../untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_scoped_mcp_glob",
  "agent_id": "ap_scoped_mcp_glob",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["https://mcp.example/trusted/**"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP scoped glob rejects dot-segment traversal before glob match" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://mcp.example/trusted/../untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

write_restricted_local_hooks_passport() {
    cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_restricted_local_hooks",
  "agent_id": "ap_restricted_local_hooks",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [
    {"id": "mcp.tool.execute"},
    {"id": "web.fetch"},
    {"id": "data.file.read"},
    {"id": "data.file.write"}
  ],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"],
      "allowed_tools": ["issues.*"],
      "max_timeout": 30
    },
    "web.fetch": {
      "allowed_domains": ["*"],
      "blocked_domains": ["evil.test"],
      "allowed_methods": ["GET", "POST"]
    },
    "data.file.read": {
      "allowed_paths": ["*"]
    },
    "data.file.write": {
      "allowed_paths": ["*"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
}

write_restricted_local_hooks_passport

run_hook "Gemini MCP denies disallowed local server" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"evil__steal","mcp_context":{"server_name":"evil","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

run_hook "Gemini MCP denies disallowed local tool" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"github__chat_postMessage","mcp_context":{"server_name":"github","tool_name":"chat.postMessage"},"tool_input":{"channel":"secrets"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_tool_not_allowed"))'

run_hook "Gemini MCP denies timeout above local max" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"github__issues.list","mcp_context":{"server_name":"github","tool_name":"issues.list"},"tool_input":{"timeout":60,"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.timeout_exceeded"))'

run_hook "Codex MCP denies server spoofed through tool input" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"mcp__evil__issues_list","tool_input":{"server":"github","tool":"issues.list","id":"x"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.mcp_server_not_allowed"))'

run_hook "Codex MCP strips functions namespace before server parsing" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"functions.mcp__github__issues.list","tool_input":{"id":"x"}}' \
    '. == {}'

run_hook "Codex generic MCP wrapper preserves routing server" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"CallMcpTool","tool_input":{"server":"github","mcp_tool":"issues.list","id":"x"}}' \
    '. == {}'

run_hook "Goose MCP denies server spoofed through tool input" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"evil__issues_list","tool_input":{"server":"github","tool":"issues.list","id":"x"}}' \
    '.decision == "block" and (.reason | contains("oap.mcp_server_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_restricted_mcp_server_only",
  "agent_id": "ap_restricted_mcp_server_only",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP does not infer ambiguous single-underscore server" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp_github_internal_delete_issue","tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.missing_required_context"))'
write_restricted_local_hooks_passport

run_hook "Gemini MCP bare allowlist permits unscoped mcp URL identifier" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'
run_hook "Gemini MCP bare allowlist rejects scoped mcp URL identifier" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github/tools","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

run_hook "Codex MCP resource read uses routing server instead of URI authority" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"ReadMcpResourceTool","tool_input":{"server":"evil","tool":"resources.read","uri":"mcp://github/repo/README.md"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.mcp_server_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_case_sensitive_mcp",
  "agent_id": "ap_case_sensitive_mcp",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"],
      "allowed_tools": ["chat.postMessage", "resources.read"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF

run_hook "Codex MCP preserves case-sensitive qualified tool names" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"mcp__github__chat.postMessage","tool_input":{"channel":"general"}}' \
    '. == {}'

run_hook "Codex MCP resource read defaults to resources.read" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"ReadMcpResourceTool","tool_input":{"server":"github","uri":"repo://github/README.md"}}' \
    '. == {}'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_case_sensitive_mcp_server",
  "agent_id": "ap_case_sensitive_mcp_server",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["GitHub"],
      "allowed_tools": ["resources.read"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex MCP preserves case-sensitive bare server names" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"ReadMcpResourceTool","tool_input":{"server":"github","uri":"repo://github/README.md"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.mcp_server_not_allowed"))'

write_restricted_local_hooks_passport

run_hook "Gemini web_fetch denies blocked local domain" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://evil.test/collect","method":"POST"}}' \
    '.decision == "deny" and (.reason | contains("oap.domain_blocked"))'

run_hook "Gemini web_fetch denies userinfo-obfuscated blocked domain" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://user@evil.test/collect","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.domain_blocked"))'

run_hook "Gemini web_fetch rejects backslash-obfuscated URL authority" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://evil.test\\@example.com/collect","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_url"))'

run_hook "Gemini web_fetch rejects percent-encoded URL authority" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://127%2e0%2e0%2e1/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_url"))'

run_hook "Gemini web_fetch denies private metadata IP" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://169.254.169.254/latest/meta-data","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies shortened loopback IPv4 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://127.1/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies integer loopback IPv4 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://2130706433/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies IPv4-mapped private IPv6 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://[::ffff:127.0.0.1]/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies hex IPv4-mapped private IPv6 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://[::ffff:7f00:1]/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies compressed IPv6 loopback literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://[0:0:0:0:0:0::1]/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies link-local IPv6 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://[fe90::1]/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies private IPv6 domain literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"domain":"fd00::1","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch rejects domain spoofing when URL is present" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://evil.test/collect","domain":"example.com","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.domain_mismatch"))'

run_hook "Gemini web_fetch denies disallowed local method" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/resource","method":"DELETE"}}' \
    '.decision == "deny" and (.reason | contains("oap.method_not_allowed"))'

cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"

run_hook "Gemini missing tool_name fails closed" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_input":{"command":"ls -la"}}' \
    '.decision == "deny" and (.reason | contains("oap.missing_tool_name"))'

run_hook "Goose shell deny uses block decision" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__shell","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.decision == "block" and (.reason | contains("APort denied"))'

run_hook "Goose missing tool_name fails closed" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_input":{"command":"ls -la"}}' \
    '.decision == "block" and (.reason | contains("oap.missing_tool_name"))'

run_hook "Goose clean allow stays silent" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__shell","tool_input":{"command":"ls -la"}}' \
    'empty'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Goose read_image local source maps to file read" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__read_image","tool_input":{"source":"/tmp/diagram.png"}}' \
    'empty'
jq -e '.guardrail_tool == "read" and .decision.policy_id == "data.file.read.v1" and .context.file_path == "/tmp/diagram.png"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Goose local read_image should map source to data.file.read context" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Goose local read_image maps to file read"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Goose read_image URL source maps to web access" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__read_image","tool_input":{"source":"https://example.com/diagram.png"}}' \
    'empty'
jq -e '.guardrail_tool == "websearch" and .decision.policy_id == "web.fetch.v1" and .context.url == "https://example.com/diagram.png"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Goose URL read_image should map source to web context" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Goose URL read_image maps to web access"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Goose web fetch strips URL credentials from recorded context" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__fetch","tool_input":{"url":"https://user:password@example.com/file?token=secret#frag","method":"GET"}}' \
    'empty'
if grep -Eq 'password|token=secret|#frag' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: web context must not persist URL credentials, query tokens, or fragments" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.guardrail_tool == "websearch" and .decision.policy_id == "web.fetch.v1" and .context.url == "https://example.com/file" and .context.domain == "example.com"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Goose web fetch should record sanitized URL context" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Goose web fetch strips URL credentials"

run_hook "Goose text_editor view routes through read policy" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__text_editor","tool_input":{"command":"view","path":"/tmp/.ssh/id_rsa"}}' \
    '.decision == "block" and (.reason | contains("oap.blocked_pattern"))'

run_hook "Goose tree with broad root fails closed as metadata enumeration" \
    goose "$GOOSE" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"developer__tree\",\"tool_input\":{\"path\":\"$TEST_DIR\"}}" \
    '.decision == "block" and (.reason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Goose text_editor missing command fails closed" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__text_editor","tool_input":{"path":"/tmp/file.txt"}}' \
    '.decision == "block" and (.reason | contains("oap.missing_editor_command"))'

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
run_hook "Goose warn mode allows with reason" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__shell","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.decision == "allow" and (.reason | contains("APort Warning"))'

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex file write strips raw content from recorded context" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: /tmp/aport-test.txt\n+secret_token=should_not_leave\n*** End Patch","content":"secret_token=should_not_leave"}}' \
    '. == {}'

if grep -q 'should_not_leave' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: session decision context must not contain raw file contents" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.context.file_path == "/tmp/aport-test.txt" and (.context.content_length | type == "number")' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: file-write context should include path and content length" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ File-write context is minimized"

run_hook "Codex multi-file apply_patch fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: /tmp/allowed.txt\n+ok\n*** Add File: /tmp/forbidden.txt\n+secret\n*** End Patch"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.multi_path_write_unsupported"))'

run_hook "Codex Grep routes through file-read policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Grep","tool_input":{"pattern":"SECRET","path":"/tmp/.ssh"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.blocked_pattern"))'

mkdir -p "$TEST_DIR/search-root"
run_hook "Codex Grep rejects directory-scoped search" \
    codex "$CODEX" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"SECRET\",\"path\":\"$TEST_DIR/search-root\"}}" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.recursive_search_unsupported"))'

run_hook "Codex Glob with concrete sensitive path fails closed as metadata enumeration" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Glob","tool_input":{"pattern":"*","path":"/home/user/.ssh"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Codex Glob with broad allowed root still fails closed as metadata enumeration" \
    codex "$CODEX" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Glob\",\"tool_input\":{\"pattern\":\"**/.env\",\"path\":\"$TEST_DIR\"}}" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.metadata_enumeration_unsupported"))'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex WebSearch without destination fails closed through web policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"WebSearch","tool_input":{"query":"APort guardrails"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'
jq -e '.guardrail_tool == "websearch" and .decision.policy_id == "web.fetch.v1" and .decision.allow == false' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Codex WebSearch should map to web.fetch policy" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Codex WebSearch maps to web policy"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex spawn_agent maps to session policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex send_message maps to session update" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.send_message","tool_input":{"id":"child-1","message":"continue"}}' \
    '. == {}'
run_hook "Codex followup_task maps to session update" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.followup_task","tool_input":{"id":"child-1","prompt":"continue"}}' \
    '. == {}'
run_hook "Codex wait_agent maps to session status" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.wait_agent","tool_input":{"id":"child-1"}}' \
    '. == {}'
run_hook "Codex interrupt_agent maps to session close" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.interrupt_agent","tool_input":{"id":"child-1"}}' \
    '. == {}'
jq -e '.guardrail_tool == "session.create" and .decision.policy_id == "agent.session.create.v1"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Codex spawn_agent should map to agent.session.create" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Codex collaboration tools map to session policy"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_sessions",
  "agent_id": "ap_limited_sessions",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 2,
      "max_session_duration": 3600
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock"
mkdir "$TEST_DIR/aport/session-state.json.lock"
printf '999999 1\n' > "$TEST_DIR/aport/session-state.json.lock/owner"
run_hook "Codex session recovers stale local lock" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"stale-lock-child","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock"
echo "  ✅ Codex session stale lock recovery works"
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
mkdir "$TEST_DIR/aport/session-state.json.lock"
APORT_SESSION_LOCK_OWNERLESS_STALE_SECONDS=0 run_hook "Codex session recovers ownerless local lock" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"ownerless-lock-child","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
echo "  ✅ Codex session ownerless lock recovery works"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
mkdir "$TEST_DIR/aport/session-state.json.lock"
printf '%s %s\n' "$$" "$(date +%s)" > "$TEST_DIR/aport/session-state.json.lock/owner"
export APORT_SESSION_LOCK_RETRIES=0
export APORT_SESSION_LOCK_RETRY_DELAY=0
run_hook "Codex session fails closed on live local lock" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"live-lock-child","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
unset APORT_SESSION_LOCK_RETRIES APORT_SESSION_LOCK_RETRY_DELAY
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
echo "  ✅ Codex session live lock contention fails closed"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
mkdir "$TEST_DIR/aport/session-state.json.lock"
printf '%s %s\n' "$$" "$(date +%s)" > "$TEST_DIR/aport/session-state.json.lock/owner"
export APORT_SESSION_LOCK_RETRIES=0
export APORT_SESSION_LOCK_RETRY_DELAY=0
run_hook "Codex session state failure remains blocking in warn mode" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"warn-lock-child","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
unset APORT_SESSION_LOCK_RETRIES APORT_SESSION_LOCK_RETRY_DELAY
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"

cat > "$TEST_DIR/aport/session-state.json" << 'EOF'
{"leases":[{"session_id":"locked-close-child","session_call_id":"locked-close-call","expires_at_epoch":4102444800,"synthetic":false}]}
EOF
mkdir "$TEST_DIR/aport/session-state.json.lock"
printf '%s %s\n' "$$" "$(date +%s)" > "$TEST_DIR/aport/session-state.json.lock/owner"
export APORT_SESSION_LOCK_RETRIES=0
export APORT_SESSION_LOCK_RETRY_DELAY=0
run_hook "Codex post-tool close fails closed when session state lock is live" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_call_id":"locked-close-call","tool_input":{"id":"locked-close-child"},"tool_response":{"success":true}}' \
    '.hookSpecificOutput.hookEventName == "PostToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
unset APORT_SESSION_LOCK_RETRIES APORT_SESSION_LOCK_RETRY_DELAY
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
echo "  ✅ Codex session state failures remain blocking in warn mode"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_single_session",
  "agent_id": "ap_single_session",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 1,
      "max_session_duration": 3600
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex provisional session lease reserves capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"no-id-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex spawn output without session id releases provisional lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"no-id-call","tool_response":"agent creation failed"}' \
    '. == {}'
run_hook "Codex session lease after no-id spawn output is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-no-id-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex no-id spawn output releases provisional lease"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_sessions",
  "agent_id": "ap_limited_sessions",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 2,
      "max_session_duration": 3600
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"

"$REPO_ROOT/bin/aport-guardrail-bash.sh" "session.create" '{"session_operation":"other","description_length":12}' > /dev/null
jq -e '.allow == true and .policy_id == "agent.session.create.v1"' "$TEST_DIR/aport/decision.json" > /dev/null || {
    echo "FAIL: non-spawning session bookkeeping should still authorize under session policy" >&2
    cat "$TEST_DIR/aport/decision.json" >&2
    exit 1
}
if [[ -f "$TEST_DIR/aport/session-state.json" ]] && ! jq -e '.leases | length == 0' "$TEST_DIR/aport/session-state.json" > /dev/null; then
    echo "FAIL: non-spawning session bookkeeping should not consume a concurrency lease" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
fi
echo "  ✅ Session bookkeeping does not consume session capacity"

"$REPO_ROOT/bin/aport-guardrail-bash.sh" "session.create" '{"session_tracking":"host_active_count","session_operation":"create","description_length":12}' > /dev/null
if [[ -f "$TEST_DIR/aport/session-state.json" ]] && ! jq -e '.leases | length == 0' "$TEST_DIR/aport/session-state.json" > /dev/null; then
    echo "FAIL: host-active-count session tracking should not create persistent leases" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
fi
echo "  ✅ Host-count session tracking avoids stale local leases"

run_hook "Codex session first lease is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex session second lease is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex session third lease respects max_concurrent" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex unmatched close does not release synthetic session lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"not-running"}}' \
    '. == {}'
run_hook "Codex session remains capped after unmatched close" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
jq -e '.leases | length == 2' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: session limiter should retain only the two allowed leases" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
echo "  ✅ Codex session max_concurrent is enforced locally"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session ignores model-supplied tool_input call id" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"tool_call_id":"attacker-reused","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex session does not dedupe on model-supplied tool_input call id" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"tool_call_id":"attacker-reused","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex session repeated model-supplied call id still respects limit" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"tool_call_id":"attacker-reused","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
jq -e '.leases | length == 2 and all(.session_id != "call:attacker-reused")' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: session limiter must not trust tool_input.tool_call_id for dedupe" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
echo "  ✅ Codex session ignores model-controlled call IDs"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_session_lifecycle",
  "agent_id": "ap_limited_session_lifecycle",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 1,
      "max_session_duration": 3600
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session pre-tool reserves by tool_use_id" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-1","tool_input":{"id":"spoof-child-1","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "call:lease-call-1"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: pre-tool session create should reserve by tool_use_id, not model-supplied child id" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
run_hook "Codex duplicate model-supplied child id cannot bypass concurrency" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-2","tool_input":{"id":"spoof-child-1","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_session_short_duration",
  "agent_id": "ap_limited_session_short_duration",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 1,
      "max_session_duration": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex local session lease starts under short max duration" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"short-duration-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
sleep 2
run_hook "Codex local session lease is not expired by max_session_duration" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"short-duration-next","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_session_lifecycle",
  "agent_id": "ap_limited_session_lifecycle",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 1,
      "max_session_duration": 3600
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session pre-tool reserves lifecycle lease after short-duration test" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-1","tool_input":{"id":"spoof-child-1","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool spawn reconciles tool_use_id lease to child id" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-1","tool_response":{"success":true,"id":"child-1"}}' \
    '. == {}'
run_hook "Codex close_agent keeps lease before tool succeeds" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"child-pre-release","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex post-tool close releases matching child lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex session lease after close is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-3","tool_input":{"id":"spoof-child-2","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool spawn reconciles second tool_use_id lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-3","tool_response":{"success":true,"id":"child-2"}}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "child-2"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: session close should release the matching child lease" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
echo "  ✅ Codex session close releases child leases"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session lease reserves by tool call before child id exists" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"call-1","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool reconciles session lease to child id" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"call-1","tool_response":{"id":"child-1"}}' \
    '. == {}'
run_hook "Codex close_agent releases reconciled child lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"}}' \
    '. == {}'
run_hook "Codex nested-error post-tool close keeps reconciled lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":{"error":"close failed"}}' \
    '. == {}'
run_hook "Codex spawn remains capped after nested-error close" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"child-denied-nested-error","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex failed post-tool close keeps reconciled lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"result":{"success":false}}' \
    '. == {}'
run_hook "Codex spawn remains capped after failed close" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"child-denied","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex unstructured post-tool close keeps reconciled lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":"agent close failed"}' \
    '. == {}'
run_hook "Codex spawn remains capped after unstructured close" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"child-denied-unstructured","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex post-tool close releases reconciled child lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex session lease after reconciled close is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"call-2","tool_input":{"id":"spoof-child-2","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool reconciles second child lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"call-2","tool_response":{"id":"child-2"}}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "child-2"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: post-tool reconciliation should let close release the child lease" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
echo "  ✅ Codex PostToolUse reconciles session leases"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session lease reserves before string response id exists" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"string-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool parses string response session id" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"string-call","success":true,"tool_response":"{\"id\":\"child-string\"}"}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "child-string"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: string-valued Codex PostToolUse output should reconcile the reserved lease" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
run_hook "Codex string-response session remains capped" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"child-denied-after-string","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex post-tool close releases string-response lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-string"},"success":true}' \
    '. == {}'
echo "  ✅ Codex PostToolUse handles string-valued responses"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex failed spawn reserves before execution" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"failed-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex failed post-tool spawn releases reserved capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"failed-call","success":false}' \
    '. == {}'
run_hook "Codex session lease after failed spawn is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-failure-call","tool_input":{"id":"child-after-failure","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex failed session creation releases reserved capacity"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex failed string-response spawn reserves before execution" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"failed-string-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex failed string-response spawn releases reserved capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"failed-string-call","tool_response":"{\"success\":false}"}' \
    '. == {}'
run_hook "Codex session lease after failed string-response spawn is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-string-failure-call","tool_input":{"id":"child-after-string-failure","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex failed string response releases reserved capacity"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex successful resume preserves target session id" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_use_id":"resume-call","tool_input":{"id":"child-1"}}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "child-1" and .[0].session_call_id == "resume-call"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: resume should reserve the target session id with the host call id" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
run_hook "Codex status-only resume output keeps releaseable target id" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_use_id":"resume-call","tool_input":{"id":"child-1"},"tool_response":{"status":"running"}}' \
    '. == {}'
run_hook "Codex close after status-only resume releases lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex spawn after status-only resume close is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-successful-resume-close","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex successful resume leases remain releaseable"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex overlap test starts tracked session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"overlap-spawn","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex overlap test reconciles tracked session" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"overlap-spawn","tool_response":{"id":"child-overlap"}}' \
    '. == {}'
run_hook "Codex overlap close marks the active session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_call_id":"overlap-close","tool_input":{"id":"child-overlap"}}' \
    '. == {}'
run_hook "Codex overlap resume preserves the active session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"overlap-resume","tool_input":{"id":"child-overlap"}}' \
    '. == {}'
run_hook "Codex stale close completion does not clear resumed session" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_call_id":"overlap-close","tool_input":{"id":"child-overlap"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex overlap resume completion keeps session active" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"overlap-resume","tool_input":{"id":"child-overlap"},"tool_response":{"status":"running"}}' \
    '. == {}'
run_hook "Codex spawn remains capped after close-resume overlap" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-overlap-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
echo "  ✅ Codex overlapping close/resume keeps session capacity"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex failed resume reserves before execution" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"failed-resume","tool_input":{"id":"missing-child"}}' \
    '. == {}'
run_hook "Codex failed post-tool resume releases reserved capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"failed-resume","tool_input":{"id":"missing-child"},"success":false}' \
    '. == {}'
run_hook "Codex session lease after failed resume is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-failed-resume-call","tool_input":{"id":"child-after-failed-resume","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex failed resume releases reserved capacity"

run_hook "Codex resume_agent is blocked when concurrency is full" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_input":{"id":"child-1"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
echo "  ✅ Codex resume_agent respects session concurrency"
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
rm -f "$TEST_DIR/aport/session-state.json"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session context strips raw prompt text" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"prompt":"customer token secret_should_not_leave","subagent_type":"reviewer"}}' \
    '. == {}'

if grep -q 'secret_should_not_leave' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: session decision context must not contain raw prompts" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.context.description_length > 0 and .context.subagent_type == "reviewer"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: session context should include length and subagent type only" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Session context is minimized"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
OUT_TOO_LARGE="$TEST_DIR/gemini-too-large.json"
set +e
printf '%s' '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls -la"}}' \
    | APORT_HOOK_STDIN_MAX_BYTES=20 "$GEMINI" > "$OUT_TOO_LARGE" 2> /dev/null
TOO_LARGE_EXIT=$?
set -e
[[ "$TOO_LARGE_EXIT" -eq 0 ]] || {
    echo "FAIL: oversized Gemini payload should produce host JSON" >&2
    exit 1
}
jq -e '.decision == "deny" and (.reason | contains("oap.input_too_large"))' "$OUT_TOO_LARGE" > /dev/null || {
    echo "FAIL: oversized Gemini payload should fail closed even in warn mode" >&2
    cat "$OUT_TOO_LARGE" >&2
    exit 1
}
echo "  ✅ Oversized Gemini payload fails closed"

echo ""
echo "  Shared command-hook adapter tests passed."

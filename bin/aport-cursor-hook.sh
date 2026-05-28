#!/usr/bin/env bash
# APort Cursor hook: reads JSON from stdin, maps tool to APort policy, calls guardrail.
# Handles all Cursor hook events: beforeShellExecution, preToolUse, beforeMCPExecution,
# beforeReadFile, subagentStart.
# Output: JSON with "permission": "allow"|"deny"; optional "agentMessage"/"user_message".
# Exit: 0 = allow, 2 = block (deny). Other exits = hook error (Cursor may fail-open).
#
# Cursor preToolUse tool_name values: Shell, Read, Write, Grep, Delete, Task, MCP:<name>
# See: https://cursor.com/docs/hooks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Anchor data paths to Cursor config before resolve (hosted/API installs may have no passport.json).
export OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-${APORT_CURSOR_CONFIG_DIR:-$HOME/.cursor}}"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR/#\~/$HOME}"

# Passport/config: resolver probes ~/.cursor, ~/.openclaw, ~/.aport/*, etc.
# shellcheck source=bin/aport-resolve-paths.sh
. "$ROOT_DIR/bin/aport-resolve-paths.sh"
# shellcheck source=bin/lib/guardrail-mode.sh
. "$ROOT_DIR/bin/lib/guardrail-mode.sh"
# shellcheck source=bin/lib/hook-read-policy.sh
. "$ROOT_DIR/bin/lib/hook-read-policy.sh"
load_guardrail_mode_for_hooks "${OPENCLAW_CONFIG_DIR:-$HOME/.cursor}"

GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-bash.sh"
if [ "${APORT_GUARDRAIL_MODE:-local}" = "api" ]; then
    GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-api.sh"
    if [ -n "${APORT_API_URL:-}" ]; then
        export APORT_API_URL
    fi
fi

# Read stdin (single JSON object; Cursor sends one payload per invocation)
INPUT=""
if [ -t 0 ]; then
    INPUT='{}'
else
    INPUT="$(cat)"
fi

# Empty or invalid JSON -> allow with warning (fail-open for bad input)
if [ -z "$INPUT" ]; then
    echo '{"permission":"allow","allowed":true,"agentMessage":"APort: no input received"}'
    exit 0
fi

# Require jq for JSON parsing
if ! command -v jq &> /dev/null; then
    echo '{"permission":"deny","allowed":false,"agentMessage":"APort: jq is required"}'
    exit 2
fi

# Deny helper: outputs Cursor-format JSON and exits 2
deny() {
    local reason="$1"
    jq -n -c --arg reason "$reason" \
        '{permission:"deny",allowed:false,agentMessage:$reason,reason:$reason}'
    exit 2
}

# Safe jq extraction: returns '{}' on any jq error
safe_jq() {
    local input="$1" filter="$2"
    local result
    result="$(echo "$input" | jq -c "$filter" 2> /dev/null)" || result='{}'
    [ -z "$result" ] && result='{}'
    echo "$result"
}

# Detect hook event type from input fields and route accordingly.
# Cursor sends different JSON shapes per hook event:
#   beforeShellExecution: { "command": "...", "cwd": "..." }
#   preToolUse:           { "tool_name": "Shell|Read|Write|...", "tool_input": {...} }
#   beforeMCPExecution:   { "tool_name": "...", "tool_input": {...}, "server": "..." }
#   beforeReadFile:       { "file_path": "...", "content": "..." }
#   subagentStart:        { "subagent_id": "...", "subagent_type": "...", "task": "..." }
# We detect by checking for distinguishing fields.

GUARDRAIL_TOOL=""
CONTEXT_JSON="{}"

# Check for hook_event_name first (newer Cursor versions include it)
HOOK_EVENT="$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2> /dev/null)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""' 2> /dev/null)"

if [ "$HOOK_EVENT" = "beforeReadFile" ] || { [ -z "$HOOK_EVENT" ] && [ -z "$TOOL_NAME" ] && echo "$INPUT" | jq -e '.file_path and .content' &> /dev/null; }; then
    FILE_PATH="$(echo "$INPUT" | jq -r '.file_path // ""' 2> /dev/null || true)"
    if ! aport_hook_try_read_evaluation_from_file_path "$FILE_PATH"; then
        exit 0
    fi

elif [ "$HOOK_EVENT" = "subagentStart" ] || { [ -z "$HOOK_EVENT" ] && echo "$INPUT" | jq -e '.subagent_id' &> /dev/null; }; then
    # subagentStart: sub-agent spawning
    GUARDRAIL_TOOL="session.create"
    CONTEXT_JSON="$(safe_jq "$INPUT" '{description: (.task // ""), subagent_type: (.subagent_type // "")}')"

elif [ "$HOOK_EVENT" = "beforeMCPExecution" ] || { [ -n "$TOOL_NAME" ] && echo "$INPUT" | jq -e '.server // .url' &> /dev/null; }; then
    # beforeMCPExecution: MCP tool calls (has server/url field)
    GUARDRAIL_TOOL="mcp.tool"
    CONTEXT_JSON="$(safe_jq "$INPUT" '{tool_name: (.tool_name // ""), tool_input: (.tool_input // {})}')"

elif [ -n "$TOOL_NAME" ]; then
    # preToolUse: Shell, Read, Write, Grep, Delete, Task, WebSearch, Agent, MCP:*, etc.
    # See docs/FRAMEWORK_TOOL_MAPPING_AUDIT.md and https://cursor.com/docs/agent/hooks
    TOOL_NORM="$(printf '%s' "$TOOL_NAME" | tr -d '[:space:]' | sed 's/^functions\.//' | sed 's/(.*$//' | tr '[:upper:]' '[:lower:]')"
    case "$TOOL_NORM" in
        shell | bash)
            GUARDRAIL_TOOL="bash"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{command: (.tool_input.command // "")}')"
            ;;
        read | readfile | semanticsearch)
            TOOL_INPUT="$(safe_jq "$INPUT" '.tool_input // {}')"
            if ! aport_hook_try_read_evaluation "$TOOL_NORM" "$TOOL_INPUT"; then
                exit 0
            fi
            ;;
        grep | glob | ls | lsp | listmcpresourcestool | readmcpresourcetool | toolsearch | waitformcpservers | taskget | tasklist | taskoutput | cronlist)
            exit 0
            ;;
        write | strreplace | edit | multiedit | editnotebook | applypatch | notebookedit | delete)
            GUARDRAIL_TOOL="write"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{file_path: (.tool_input.file_path // .tool_input.path // "")}')"
            ;;
        websearch | webfetch)
            GUARDRAIL_TOOL="websearch"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{url: (.tool_input.url // ""), query: (.tool_input.query // "")}')"
            ;;
        browser)
            GUARDRAIL_TOOL="browser"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{url: (.tool_input.url // "")}')"
            ;;
        task | agent | taskcreate | taskupdate | taskstop | skill | subagent | subagentstart | sendmessage | teamcreate | teamdelete)
            GUARDRAIL_TOOL="session.create"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{description: (.tool_input.description // .tool_input.prompt // "")}')"
            ;;
        croncreate | crondelete)
            GUARDRAIL_TOOL="session.create"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{description: (.tool_input.description // .tool_input.schedule // "")}')"
            ;;
        mcp__* | mcp:* | callmcptool)
            GUARDRAIL_TOOL="mcp.tool"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{tool_name: (.tool_name // ""), tool_input: (.tool_input // {})}')"
            ;;
        *)
            deny "🛡️ APort: unknown tool '$TOOL_NAME' — fail-closed policy"
            ;;
    esac

elif echo "$INPUT" | jq -e '.command' &> /dev/null; then
    # beforeShellExecution: { "command": "..." }
    GUARDRAIL_TOOL="bash"
    CMD="$(echo "$INPUT" | jq -r '.command // ""' 2> /dev/null)"
    CONTEXT_JSON="$(jq -n -c --arg cmd "$CMD" '{command: $cmd}')"

elif echo "$INPUT" | jq -e '.tool // .input.command' &> /dev/null; then
    # Legacy Copilot-style: { "tool": "runTerminalCommand", "input": { "command": "..." } }
    GUARDRAIL_TOOL="bash"
    CMD="$(echo "$INPUT" | jq -r '.input.command // .input.cmd // .args[0] // ""' 2> /dev/null)"
    CONTEXT_JSON="$(jq -n -c --arg cmd "$CMD" '{command: $cmd}')"

else
    # Unrecognized input shape: fail-closed
    deny "🛡️ APort: unrecognized hook input — fail-closed policy"
fi

# Use a per-invocation decision file to avoid race conditions with concurrent tool calls
HOOK_DECISION_FILE="${OPENCLAW_DECISION_FILE:-}"
if [ -n "$HOOK_DECISION_FILE" ]; then
    HOOK_DECISION_FILE="${HOOK_DECISION_FILE%.json}-$$.json"
    export OPENCLAW_DECISION_FILE="$HOOK_DECISION_FILE"
fi

# Read tools: send only file_path to the evaluator (Cursor may attach large file bodies in tool_input).
if [ "$GUARDRAIL_TOOL" = "read" ]; then
    CONTEXT_JSON="$(printf '%s' "$CONTEXT_JSON" | jq -c '{file_path: (.file_path // .path // "")}' 2> /dev/null || echo '{"file_path":""}')"
    if [ -z "$(printf '%s' "$CONTEXT_JSON" | jq -r '.file_path // ""' 2> /dev/null)" ]; then
        echo '{"permission":"allow","allowed":true}'
        exit 0
    fi
fi

# Call core evaluator
set +e
"$GUARDRAIL" "$GUARDRAIL_TOOL" "$CONTEXT_JSON" 2> /dev/null
GUARDRAIL_EXIT=$?
set -e

# Clean up per-invocation decision file
cleanup_decision() { [ -n "$HOOK_DECISION_FILE" ] && rm -f "$HOOK_DECISION_FILE" 2> /dev/null; }

if [ "$GUARDRAIL_EXIT" -eq 0 ]; then
    cleanup_decision
    echo '{"permission":"allow","allowed":true}'
    exit 0
fi

# Deny: read reason from decision file
REASON="Policy denied this action."
if [ -n "$HOOK_DECISION_FILE" ] && [ -f "$HOOK_DECISION_FILE" ]; then
    R="$(jq -r '.reasons[0].message // empty' "$HOOK_DECISION_FILE" 2> /dev/null)"
    [ -n "$R" ] && REASON="$R"
fi
# Fallback: try common config dirs
if [ "$REASON" = "Policy denied this action." ]; then
    for DEC in "${OPENCLAW_CONFIG_DIR:-$HOME/.cursor}/aport/decision.json" "$HOME/.cursor/aport/decision.json" "$HOME/.openclaw/aport/decision.json"; do
        if [ -f "$DEC" ]; then
            R="$(jq -r '.reasons[0].message // empty' "$DEC" 2> /dev/null)"
            [ -n "$R" ] && REASON="$R" && break
        fi
    done
fi
cleanup_decision
deny "🛡️ APort: $REASON"

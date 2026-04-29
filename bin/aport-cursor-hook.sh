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

# Passport/config: resolver probes ~/.cursor, ~/.openclaw, ~/.aport/*, etc.
# shellcheck source=bin/aport-resolve-paths.sh
. "$ROOT_DIR/bin/aport-resolve-paths.sh"
# shellcheck source=bin/lib/guardrail-mode.sh
. "$ROOT_DIR/bin/lib/guardrail-mode.sh"
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
    # beforeReadFile: file reads — allow without evaluator (same as Claude Code)
    exit 0

elif [ "$HOOK_EVENT" = "subagentStart" ] || { [ -z "$HOOK_EVENT" ] && echo "$INPUT" | jq -e '.subagent_id' &> /dev/null; }; then
    # subagentStart: sub-agent spawning
    GUARDRAIL_TOOL="session.create"
    CONTEXT_JSON="$(safe_jq "$INPUT" '{description: (.task // ""), subagent_type: (.subagent_type // "")}')"

elif [ "$HOOK_EVENT" = "beforeMCPExecution" ] || { [ -n "$TOOL_NAME" ] && echo "$INPUT" | jq -e '.server // .url' &> /dev/null; }; then
    # beforeMCPExecution: MCP tool calls (has server/url field)
    GUARDRAIL_TOOL="mcp.tool"
    CONTEXT_JSON="$(safe_jq "$INPUT" '{tool_name: (.tool_name // ""), tool_input: (.tool_input // {})}')"

elif [ -n "$TOOL_NAME" ]; then
    # preToolUse: Cursor tool names — Shell, Read, Write, Grep, Delete, Task, MCP:<name>
    # Normalize: trim whitespace, lowercase (patterns must match TOOL_NORM)
    TOOL_NORM="$(echo "$TOOL_NAME" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    case "$TOOL_NORM" in
        shell)
            GUARDRAIL_TOOL="bash"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{command: (.tool_input.command // "")}')"
            ;;
        read | grep | glob | semanticsearch)
            # Read-family: allow without calling evaluator (matches Claude Code behavior)
            exit 0
            ;;
        write | strreplace | editnotebook)
            GUARDRAIL_TOOL="write"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{file_path: (.tool_input.file_path // .tool_input.path // "")}')"
            ;;
        delete)
            GUARDRAIL_TOOL="write"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{file_path: (.tool_input.file_path // .tool_input.path // "")}')"
            ;;
        task)
            GUARDRAIL_TOOL="session.create"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{description: (.tool_input.description // .tool_input.prompt // "")}')"
            ;;
        mcp:*)
            GUARDRAIL_TOOL="mcp.tool"
            CONTEXT_JSON="$(safe_jq "$INPUT" '{tool_name: (.tool_name // ""), tool_input: (.tool_input // {})}')"
            ;;
        *)
            # Unknown preToolUse tool: fail-closed
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

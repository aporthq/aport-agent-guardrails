#!/usr/bin/env bash
# APort Claude Code hook: reads tool_name + tool_input from JSON stdin,
# maps to APort policy, calls guardrail, outputs hookSpecificOutput deny or exit 0.
# Exit 0 = allow, exit 2 = block. Other exits = hook error (Claude Code may fail-open).
# Output format: Claude Code official schema (hookSpecificOutput.permissionDecision), NOT Cursor format.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-bash.sh"

# Path resolver: probes ~/.claude, ~/.cursor, ~/.openclaw, etc.
# shellcheck source=bin/aport-resolve-paths.sh
. "$ROOT_DIR/bin/aport-resolve-paths.sh"

# Read stdin
INPUT=""
if [ -t 0 ]; then
    INPUT='{}'
else
    INPUT="$(cat)"
fi

# No input = allow (fail-open for bad input)
[ -z "$INPUT" ] && exit 0

# Parse tool_name and tool_input (requires jq)
if ! command -v jq &> /dev/null; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"🛡️ APort: jq is required"}}'
    exit 2
fi

# Parse with error handling: jq failure must exit 2 (deny), never undefined exit codes
set +e
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2> /dev/null)"
JQ_EXIT=$?
set -e
if [ "$JQ_EXIT" -ne 0 ] || [ -z "$TOOL_NAME" ]; then
    TOOL_NAME="unknown"
fi
TOOL_NAME_NORM="$(printf '%s' "$TOOL_NAME" | tr -d '[:space:]' | sed 's/^functions\.//' | tr '[:upper:]' '[:lower:]')"
set +e
TOOL_INPUT="$(echo "$INPUT" | jq -c '.tool_input // {}' 2> /dev/null)"
JQ_EXIT=$?
set -e
if [ "$JQ_EXIT" -ne 0 ] || [ -z "$TOOL_INPUT" ]; then
    TOOL_INPUT='{}'
fi

# Safe jq extraction: returns '{}' on any jq error instead of crashing under set -e
safe_jq() {
    local input="$1" filter="$2"
    local result
    result="$(echo "$input" | jq -c "$filter" 2> /dev/null)" || result='{}'
    [ -z "$result" ] && result='{}'
    echo "$result"
}

# Deny helper: outputs Claude Code hookSpecificOutput JSON and exits 2
deny() {
    local reason="$1"
    jq -n --arg reason "$reason" \
        --arg event "PreToolUse" \
        '{hookSpecificOutput:{hookEventName:$event,permissionDecision:"deny",permissionDecisionReason:$reason}}'
    exit 2
}

# Tool name passed to guardrail (must match aport-guardrail-bash.sh case patterns)
GUARDRAIL_TOOL=""
CONTEXT_JSON="{}"

case "$TOOL_NAME_NORM" in
    bash | shell)
        GUARDRAIL_TOOL="bash"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{command: (.command // "")}')"
        ;;
    read | glob | ls | grep | todoread | toolsearch | askuserquestion | readfile | semanticsearch)
        # Read-family + user-interaction tools: allow without calling evaluator
        exit 0
        ;;
    taskget | tasklist | taskoutput | cronlist)
        # Read-only task/cron queries: allow without evaluator
        exit 0
        ;;
    enterplanmode | exitplanmode)
        # Internal state transitions: allow without evaluator
        exit 0
        ;;
    write | edit | multiedit | notebookedit | todowrite | delete | strreplace | editnotebook)
        GUARDRAIL_TOOL="write"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{file_path: (.file_path // .path // "")}')"
        ;;
    websearch | webfetch)
        GUARDRAIL_TOOL="webfetch"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{url: (.url // .query // "")}')"
        ;;
    browser)
        GUARDRAIL_TOOL="browser"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{url: (.url // "")}')"
        ;;
    task | taskcreate | taskupdate | taskstop | agent | skill | enterworktree | subagent | subagentstart)
        GUARDRAIL_TOOL="session.create"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{description: (.description // .prompt // "")}')"
        ;;
    croncreate | crondelete)
        GUARDRAIL_TOOL="cron"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{description: (.description // .schedule // "")}')"
        ;;
    mcp__* | mcp:* | callmcptool)
        GUARDRAIL_TOOL="mcp.tool"
        CONTEXT_JSON="$TOOL_INPUT"
        ;;
    unknown | *)
        # Unknown tool: fail-closed (deny)
        deny "🛡️ APort: unknown tool '$TOOL_NAME' — fail-closed policy"
        ;;
esac

# Use a per-invocation decision file to avoid race conditions with concurrent tool calls
HOOK_DECISION_FILE="${OPENCLAW_DECISION_FILE:-}"
if [ -n "$HOOK_DECISION_FILE" ]; then
    HOOK_DECISION_FILE="${HOOK_DECISION_FILE%.json}-$$.json"
    export OPENCLAW_DECISION_FILE="$HOOK_DECISION_FILE"
fi

# Call core evaluator (guardrail expects tool name, not policy ID)
set +e
"$GUARDRAIL" "$GUARDRAIL_TOOL" "$CONTEXT_JSON" 2> /dev/null
GUARDRAIL_EXIT=$?
set -e

# Clean up per-invocation decision file on exit
cleanup_decision() { [ -n "$HOOK_DECISION_FILE" ] && rm -f "$HOOK_DECISION_FILE" 2> /dev/null; }

if [ "$GUARDRAIL_EXIT" -eq 0 ]; then
    cleanup_decision
    exit 0
fi

# Deny: read reason from decision file
REASON="Policy denied this action."
if [ -n "$HOOK_DECISION_FILE" ] && [ -f "$HOOK_DECISION_FILE" ] && command -v jq &> /dev/null; then
    R="$(jq -r '.reasons[0].message // empty' "$HOOK_DECISION_FILE" 2> /dev/null)"
    [ -n "$R" ] && REASON="$R"
fi
cleanup_decision
deny "🛡️ APort: $REASON"

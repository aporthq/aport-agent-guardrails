#!/usr/bin/env bash
# APort Claude Code hook: reads tool_name + tool_input from JSON stdin (path-based Read uses guardrail).
# maps to APort policy, calls guardrail, outputs hookSpecificOutput deny or exit 0.
# Exit 0 = allow, exit 2 = block. Other exits = hook error (Claude Code may fail-open).
# Output format: Claude Code official schema (hookSpecificOutput.permissionDecision), NOT Cursor format.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Anchor data paths to Claude Code config before resolve (hosted/API installs may have no passport.json).
export OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-${APORT_CLAUDE_CODE_CONFIG_DIR:-$HOME/.claude}}"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR/#\~/$HOME}"

# Path resolver: probes ~/.claude, ~/.cursor, ~/.openclaw, etc.
# shellcheck source=bin/aport-resolve-paths.sh
. "$ROOT_DIR/bin/aport-resolve-paths.sh"
# shellcheck source=bin/lib/guardrail-mode.sh
. "$ROOT_DIR/bin/lib/guardrail-mode.sh"
# shellcheck source=bin/lib/hook-read-policy.sh
. "$ROOT_DIR/bin/lib/hook-read-policy.sh"
load_guardrail_mode_for_hooks "${OPENCLAW_CONFIG_DIR:-$HOME/.claude}"

GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-bash.sh"
if [ "${APORT_GUARDRAIL_MODE:-local}" = "api" ]; then
    GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-api.sh"
    if [ -n "${APORT_API_URL:-}" ]; then
        export APORT_API_URL
    fi
fi

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
# Strip permission-rule specifiers (e.g. Agent(Explore) -> Agent) before normalization.
TOOL_NAME_NORM="$(printf '%s' "$TOOL_NAME" | tr -d '[:space:]' | sed 's/^functions\.//' | sed 's/(.*$//' | tr '[:upper:]' '[:lower:]')"
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
    bash | shell | powershell | monitor)
        GUARDRAIL_TOOL="bash"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{command: (.command // .script // "")}')"
        ;;
    read | readfile | semanticsearch)
        if ! aport_hook_try_read_evaluation "$TOOL_NAME_NORM" "$TOOL_INPUT"; then
            exit 0
        fi
        ;;
    glob | ls | grep | lsp | todoread | toolsearch | askuserquestion | listmcpresourcestool | readmcpresourcetool | waitformcpservers)
        # Search/list/read tools without a single file_path: allow without evaluator
        exit 0
        ;;
    taskget | tasklist | taskoutput | cronlist | schedulewakeup | pushnotification)
        # Read-only task/cron queries and notifications: allow without evaluator
        exit 0
        ;;
    enterplanmode | exitplanmode)
        # Internal state transitions: allow without evaluator
        exit 0
        ;;
    write | edit | multiedit | notebookedit | todowrite | delete | strreplace | editnotebook | shareonboardingguide)
        GUARDRAIL_TOOL="write"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{file_path: (.file_path // .path // "")}')"
        ;;
    websearch | webfetch)
        GUARDRAIL_TOOL="websearch"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{url: (.url // ""), query: (.query // "")}')"
        ;;
    browser)
        GUARDRAIL_TOOL="browser"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{url: (.url // "")}')"
        ;;
    agent | task | taskcreate | taskupdate | taskstop | skill | enterworktree | exitworktree | subagent | subagentstart | sendmessage | teamcreate | teamdelete | remotetrigger)
        GUARDRAIL_TOOL="session.create"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{description: (.description // .prompt // .task // .message // ""), subagent_type: (.subagent_type // .agent_type // "")}')"
        ;;
    croncreate | crondelete)
        GUARDRAIL_TOOL="session.create"
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

# Read tools: send only file_path to the evaluator (Claude may attach large file bodies in tool_input).
if [ "$GUARDRAIL_TOOL" = "read" ]; then
    CONTEXT_JSON="$(printf '%s' "$CONTEXT_JSON" | jq -c '{file_path: (.file_path // .path // "")}' 2> /dev/null || echo '{"file_path":""}')"
    if [ -z "$(printf '%s' "$CONTEXT_JSON" | jq -r '.file_path // ""' 2> /dev/null)" ]; then
        exit 0
    fi
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

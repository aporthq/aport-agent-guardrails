#!/usr/bin/env bash
# APort Claude Code hook: reads tool_name + tool_input from JSON stdin (path-based Read uses guardrail).
# maps to APort policy, calls guardrail, outputs hookSpecificOutput deny or exit 0.
# Exit 0 with no output = allow; exit 0 with hookSpecificOutput deny = block.
# Exit 2 with stderr also blocks, but Claude Code ignores JSON on exit 2.
# Output format: Claude Code official schema (hookSpecificOutput.permissionDecision), NOT Cursor format.

set -e

# Trap any unexpected error (set -e exit, missing command, jq failure) and emit a
# meaningful deny JSON instead of letting the script die silently. Without this
# trap, callers (Claude Code) see "No stderr output" which hides the real reason.
# shellcheck disable=SC2317
__aport_emit_crash_deny() {
    local exit_code="$?"
    local line_no="$1"
    local script_name
    script_name="$(basename "${BASH_SOURCE[0]:-aport-claude-code-hook}")"
    local reason="🛡️ APort: hook internal error (exit=${exit_code} at ${script_name}:${line_no}). Run with DEBUG_APORT=1 for details."
    if command -v jq > /dev/null 2>&1; then
        jq -n --arg reason "$reason" --arg event "PreToolUse" \
            '{hookSpecificOutput:{hookEventName:$event,permissionDecision:"deny",permissionDecisionReason:$reason}}' 2> /dev/null \
            || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
    else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
    fi
    exit 0
}
trap '__aport_emit_crash_deny "$LINENO"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Anchor data paths to Claude Code config before resolve (hosted/API installs may have no passport.json).
# shellcheck source=bin/lib/framework-hook-paths.sh
. "$ROOT_DIR/bin/lib/framework-hook-paths.sh"
aport_hook_prepare_framework_paths "claude-code" "${APORT_CLAUDE_CODE_CONFIG_DIR:-}" "$HOME/.claude"

# Path resolver: probes ~/.claude, ~/.cursor, ~/.openclaw, etc.
# shellcheck source=bin/aport-resolve-paths.sh
. "$ROOT_DIR/bin/aport-resolve-paths.sh"
# shellcheck source=bin/lib/guardrail-mode.sh
. "$ROOT_DIR/bin/lib/guardrail-mode.sh"
# shellcheck source=bin/lib/hook-read-policy.sh
. "$ROOT_DIR/bin/lib/hook-read-policy.sh"
# shellcheck source=bin/lib/hook-runtime.sh
. "$ROOT_DIR/bin/lib/hook-runtime.sh"
load_guardrail_mode_for_hooks "${APORT_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-$HOME/.claude}}"

GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-bash.sh"
if [ "${APORT_GUARDRAIL_MODE:-local}" = "api" ]; then
    GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-api.sh"
    if [ -n "${APORT_API_URL:-}" ]; then
        export APORT_API_URL
    fi
fi

# Read stdin with a bounded wait so a broken host pipe cannot hang the agent session.
INPUT="$(aport_read_stdin_with_timeout)"

# No input means the host did not provide a tool-call payload. Fail closed.
if [ -z "$INPUT" ]; then
    if command -v jq > /dev/null 2>&1; then
        jq -n --arg reason "🛡️ APort: empty hook input — fail-closed policy" \
            --arg event "PreToolUse" \
            '{hookSpecificOutput:{hookEventName:$event,permissionDecision:"deny",permissionDecisionReason:$reason}}'
    else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"APort: empty hook input - fail-closed policy"}}\n'
    fi
    exit 0
fi

# Parse tool_name and tool_input (requires jq)
if ! command -v jq &> /dev/null; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"🛡️ APort: jq is required"}}'
    exit 0
fi

# Parse with error handling: jq failure must deny, never undefined exit codes.
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

# Deny helper: outputs Claude Code hookSpecificOutput JSON and exits 0.
deny() {
    local reason="$1"
    jq -n --arg reason "$reason" \
        --arg event "PreToolUse" \
        '{hookSpecificOutput:{hookEventName:$event,permissionDecision:"deny",permissionDecisionReason:$reason}}'
    exit 0
}

# Tool name passed to guardrail (must match aport-guardrail-bash.sh case patterns)
GUARDRAIL_TOOL=""
CONTEXT_JSON="{}"

case "$TOOL_NAME_NORM" in
    bash | shell | powershell | monitor)
        GUARDRAIL_TOOL="bash"
        CONTEXT_JSON="$(safe_jq "$TOOL_INPUT" '{command: (.command // .script // "")}')"
        COMMAND_TEXT="$(printf '%s' "$CONTEXT_JSON" | jq -r '.command // ""' 2> /dev/null || true)"
        if aport_is_reentrant_guardrail_command "$COMMAND_TEXT" "$ROOT_DIR"; then
            exit 0
        fi
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
HOOK_DECISION_FILE="${APORT_DECISION_FILE:-${OPENCLAW_DECISION_FILE:-}}"
if [ -n "$HOOK_DECISION_FILE" ]; then
    HOOK_DECISION_FILE="${HOOK_DECISION_FILE%.json}-$$.json"
    export APORT_DECISION_FILE="$HOOK_DECISION_FILE"
    export OPENCLAW_DECISION_FILE="$HOOK_DECISION_FILE"
fi

# Read tools: send only file_path to the evaluator (Claude may attach large file bodies in tool_input).
if [ "$GUARDRAIL_TOOL" = "read" ]; then
    CONTEXT_JSON="$(printf '%s' "$CONTEXT_JSON" | jq -c '{file_path: (.file_path // .path // "")}' 2> /dev/null || echo '{"file_path":""}')"
    if [ -z "$(printf '%s' "$CONTEXT_JSON" | jq -r '.file_path // ""' 2> /dev/null)" ]; then
        exit 0
    fi
fi

# Call core evaluator (guardrail expects tool name, not policy ID).
# Capture stderr so the real cause (network failure, missing passport, jq error,
# guardrail-script crash) is surfaced as the deny reason instead of being lost
# to /dev/null. Set DEBUG_APORT=1 to also write stderr to the terminal.
# Disable `set -e` and the ERR trap around the call: a non-zero exit here is
# the expected deny signal, not a hook crash. We re-enable both immediately
# after so any subsequent failure still surfaces via the trap.
set +e
trap - ERR
GUARDRAIL_STDERR="$({ "$GUARDRAIL" "$GUARDRAIL_TOOL" "$CONTEXT_JSON" 2>&1 1>&3 3>&-; } 3>&1)"
GUARDRAIL_EXIT=$?
set -e
trap '__aport_emit_crash_deny "$LINENO"' ERR
if [ -n "$DEBUG_APORT" ] && [ -n "$GUARDRAIL_STDERR" ]; then
    printf '%s\n' "$GUARDRAIL_STDERR" >&2
fi

# Clean up per-invocation decision file on exit
cleanup_decision() { [ -n "$HOOK_DECISION_FILE" ] && rm -f "$HOOK_DECISION_FILE" 2> /dev/null; }

if [ "$GUARDRAIL_EXIT" -eq 0 ]; then
    aport_append_local_session_decision "$HOOK_DECISION_FILE" "claude-code" "$INPUT" "$TOOL_NAME" "$GUARDRAIL_TOOL" "$CONTEXT_JSON"
    cleanup_decision
    exit 0
fi

# Deny: prefer reason from decision file (structured), fall back to captured
# stderr from the guardrail, then a generic message. Never silent.
REASON=""
if [ -n "$HOOK_DECISION_FILE" ] && [ -f "$HOOK_DECISION_FILE" ] && command -v jq &> /dev/null; then
    R="$(jq -r '.reasons[0].message // empty' "$HOOK_DECISION_FILE" 2> /dev/null)"
    [ -n "$R" ] && REASON="$R"
fi
if [ -z "$REASON" ] && [ -n "$GUARDRAIL_STDERR" ]; then
    # Take the last non-empty line of stderr as the most actionable signal.
    REASON="$(printf '%s' "$GUARDRAIL_STDERR" | awk 'NF{last=$0} END{print last}')"
fi
if [ -z "$REASON" ]; then
    REASON="Policy denied this action (guardrail exit=${GUARDRAIL_EXIT}, no reason recorded). Run with DEBUG_APORT=1 to see evaluator output."
fi
aport_append_local_session_decision "$HOOK_DECISION_FILE" "claude-code" "$INPUT" "$TOOL_NAME" "$GUARDRAIL_TOOL" "$CONTEXT_JSON"
cleanup_decision
deny "🛡️ APort: $REASON"

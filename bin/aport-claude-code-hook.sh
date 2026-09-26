#!/usr/bin/env bash
# APort Claude Code hook: reads tool_name + tool_input from JSON stdin (path-based Read uses guardrail).
# maps to APort policy, calls guardrail, outputs hookSpecificOutput deny or exit 0.
# Exit 0 with no output = allow; exit 0 with hookSpecificOutput deny = block.
# Exit 2 also blocks (reason taken from permissionDecisionReason when present, else stderr);
# this hook always exits 0 with JSON so the structured reason reaches Claude.
# A hook that exceeds the settings.json "timeout" does NOT block in Claude Code (the call
# continues through the normal permission flow), so the installer's timeout must stay
# above the evaluator's own timeouts (see bin/frameworks/claude-code.sh).
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
    local reason="APort denied this tool call. Policy: hook.runtime. Reason: oap.hook_error. Detail: ${script_name}:${line_no} exited ${exit_code}."
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
# shellcheck source=bin/lib/harness-context.sh
. "$ROOT_DIR/bin/lib/harness-context.sh"
load_guardrail_mode_for_hooks "${APORT_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-$HOME/.claude}}"

GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-bash.sh"
if [ "${APORT_GUARDRAIL_MODE:-local}" = "api" ]; then
    GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-api.sh"
    if [ -n "${APORT_API_URL:-}" ]; then
        export APORT_API_URL
    fi
fi

emit_claude_input_too_large() {
    local notice
    notice="$(aport_format_guardrail_notice deny hook.input oap.input_too_large "Hook payload exceeded ${APORT_HOOK_STDIN_MAX_BYTES} bytes.")"

    aport_hook_build_response "deny" "$notice" "" "claude-code"
    exit 0
}

# Read stdin with a bounded wait so a broken host pipe cannot hang the agent session.
INPUT="$(aport_read_stdin_with_timeout)"

if [ "$INPUT" = "$APORT_HOOK_STDIN_TOO_LARGE_SENTINEL" ]; then
    emit_claude_input_too_large
fi

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

# Deny helper: outputs hookSpecificOutput JSON and exits 0.
deny() {
    local reason="$1"
    aport_hook_build_response "deny" "$reason" "" "claude-code"
    exit 0
}

warn_allow() {
    local reason="$1"
    local user_warning="${2:-}"
    aport_hook_build_response "allow" "$reason" "$user_warning" "claude-code"
    exit 0
}

deny_or_warn() {
    local policy="$1"
    local code="${2:-oap.denied}"
    local message="${3:-}"
    local failure_class="${4:-hard}"
    local notice user_warning
    if [ "$failure_class" = "policy" ] && aport_hook_is_warn_mode; then
        notice="$(aport_format_guardrail_notice warn "$policy" "$code" "$message" "claude-code")"
        user_warning="$(aport_hook_format_user_warning "$policy" "$code" "$message" "claude-code")"
        warn_allow "$notice" "$user_warning"
    fi
    notice="$(aport_format_guardrail_notice deny "$policy" "$code" "$message" "claude-code")"
    deny "$notice"
}

map_claude_mcp_context() {
    if aport_hook_payload_has_conflicting_mcp_routing_aliases "$INPUT"; then
        deny_or_warn "mcp.tool.execute" "oap.invalid_tool_arguments" "MCP tool supplied conflicting server or tool aliases"
    fi
    GUARDRAIL_TOOL="mcp.tool"
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" mcp "$TOOL_NAME")"
}

if aport_hook_payload_has_malformed_tool_arguments "$INPUT"; then
    deny_or_warn "hook.input" "oap.invalid_tool_arguments" "Hook tool arguments must be a JSON object"
fi

# Tool name passed to guardrail (must match aport-guardrail-bash.sh case patterns)
GUARDRAIL_TOOL=""
CONTEXT_JSON="{}"

case "$TOOL_NAME_NORM" in
    bash | shell | powershell | monitor)
        GUARDRAIL_TOOL="bash"
        if aport_hook_payload_has_malformed_shell_command_aliases "$INPUT"; then
            deny_or_warn "system.command.execute" "oap.invalid_tool_arguments" "Shell command aliases must be strings"
        fi
        if aport_hook_payload_has_conflicting_shell_command_aliases "$INPUT"; then
            deny_or_warn "system.command.execute" "oap.invalid_tool_arguments" "Shell tool supplied conflicting command aliases"
        fi
        CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" shell "$TOOL_NAME" "claude-code")"
        COMMAND_TEXT="$(printf '%s' "$CONTEXT_JSON" | jq -r '.command // ""' 2> /dev/null || true)"
        SHELL_OVERRIDE="$(printf '%s' "$CONTEXT_JSON" | jq -r '.shell // ""' 2> /dev/null || true)"
        if [ -z "$COMMAND_TEXT" ]; then
            deny_or_warn "system.command.execute" "oap.missing_command" "Shell tool did not provide a command that APort can evaluate"
        fi
        if ! aport_hook_shell_override_is_trusted "$SHELL_OVERRIDE"; then
            deny_or_warn "system.command.execute" "oap.shell_not_allowed" "Shell override is not a trusted interpreter"
        fi
        if aport_is_reentrant_guardrail_command "$COMMAND_TEXT" "$ROOT_DIR"; then
            exit 0
        fi
        ;;
    read | readfile | semanticsearch | grep)
        set +e
        trap - ERR
        aport_hook_try_read_evaluation "$TOOL_NAME_NORM" "$TOOL_INPUT"
        READ_STATUS=$?
        set -e
        trap '__aport_emit_crash_deny "$LINENO"' ERR
        if [ "$READ_STATUS" -eq 2 ]; then
            deny_or_warn "data.file.read" "$APORT_HOOK_READ_ERROR_CODE" "$APORT_HOOK_READ_ERROR_MESSAGE"
        fi
        if [ "$READ_STATUS" -ne 0 ]; then
            if [ "$TOOL_NAME_NORM" = "grep" ]; then
                deny_or_warn "data.file.read" "oap.missing_file_path" "Search tool did not provide a path that APort can evaluate"
            fi
            exit 0
        fi
        :
        ;;
    artifact | endconversation | sendfeedback | reportfindings | subagenthandback)
        # Claude Code internal UX/feedback tools do not act on the user's system.
        # ReportFindings renders review findings in the transcript; SubagentHandback
        # delivers a subagent's final report to its parent conversation (auto mode).
        exit 0
        ;;
    readmcpresourcetool)
        map_claude_mcp_context
        ;;
    glob | ls | lsp | todoread | todowrite | toolsearch | askuserquestion | listmcpresourcestool | waitformcpservers)
        # Search/list/read tools without a single file_path: allow without evaluator
        exit 0
        ;;
    taskget | tasklist | taskoutput | cronlist | listagents | schedulewakeup | pushnotification)
        # Read-only task/cron/agent queries and notifications: allow without evaluator
        exit 0
        ;;
    enterplanmode | exitplanmode)
        # Internal state transitions: allow without evaluator
        exit 0
        ;;
    write | edit | multiedit | notebookedit | delete | strreplace | editnotebook | shareonboardingguide)
        GUARDRAIL_TOOL="write"
        CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" file_write)"
        ;;
    websearch | webfetch)
        GUARDRAIL_TOOL="websearch"
        CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" web)"
        ;;
    browser)
        if aport_hook_payload_has_malformed_browser_action_aliases "$INPUT"; then
            deny_or_warn "web.browser" "oap.invalid_tool_arguments" "Browser action aliases must be strings"
        fi
        if aport_hook_payload_has_conflicting_web_target_aliases "$INPUT"; then
            deny_or_warn "web.browser" "oap.invalid_tool_arguments" "Browser tool supplied conflicting URL or domain aliases"
        fi
        if aport_hook_payload_has_conflicting_browser_action_aliases "$INPUT"; then
            deny_or_warn "web.browser" "oap.invalid_tool_arguments" "Browser tool supplied conflicting action aliases"
        fi
        GUARDRAIL_TOOL="browser"
        CONTEXT_JSON="$(aport_hook_browser_context_from_payload "$INPUT")"
        ;;
    agent | task | taskcreate | taskupdate | taskstop | skill | enterworktree | exitworktree | subagent | subagentstart | sendmessage | teamcreate | teamdelete | remotetrigger)
        GUARDRAIL_TOOL="session.create"
        CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" session "$TOOL_NAME" "claude-code")"
        ;;
    croncreate | crondelete)
        GUARDRAIL_TOOL="session.create"
        CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" session "$TOOL_NAME" "claude-code")"
        ;;
    mcp__* | mcp:* | callmcptool)
        map_claude_mcp_context
        ;;
    workflow)
        GUARDRAIL_TOOL="session.create"
        CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" session "$TOOL_NAME" "claude-code")"
        ;;
    unknown | *)
        # Unknown tool: fail-closed (deny)
        deny_or_warn "hook.tool.map" "oap.unknown_tool" "Unknown tool: $TOOL_NAME (fail-closed)"
        ;;
esac

# Use a per-invocation decision file to avoid race conditions with concurrent tool calls
HOOK_DECISION_FILE="${APORT_DECISION_FILE:-${OPENCLAW_DECISION_FILE:-}}"
if [ -n "$HOOK_DECISION_FILE" ]; then
    HOOK_DECISION_FILE="${HOOK_DECISION_FILE%.json}-$$.json"
    export APORT_DECISION_FILE="$HOOK_DECISION_FILE"
    export OPENCLAW_DECISION_FILE="$HOOK_DECISION_FILE"
    if [ -e "$HOOK_DECISION_FILE" ] && [ ! -f "$HOOK_DECISION_FILE" ]; then
        deny_or_warn "hook.runtime" "oap.decision_state_unavailable" "APort decision state path is not a regular file" "hard"
    fi
    if ! rm -f "$HOOK_DECISION_FILE" 2> /dev/null; then
        deny_or_warn "hook.runtime" "oap.decision_state_unavailable" "APort decision state path could not be reset before evaluation" "hard"
    fi
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
    aport_sanitize_display_text "$GUARDRAIL_STDERR" >&2
    printf '\n' >&2
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
REASON_CODE=""
HAS_DECISION_FILE=0
if [ -n "$HOOK_DECISION_FILE" ] && [ -f "$HOOK_DECISION_FILE" ] && command -v jq &> /dev/null; then
    HAS_DECISION_FILE=1
    R="$(jq -r '.reasons[0].message // empty' "$HOOK_DECISION_FILE" 2> /dev/null)"
    [ -n "$R" ] && REASON="$R"
    C="$(aport_hook_reason_code "$HOOK_DECISION_FILE")"
    [ -n "$C" ] && REASON_CODE="$C"
fi
if [ -z "$REASON" ] && [ -n "$GUARDRAIL_STDERR" ]; then
    # Take the last non-empty line of stderr as the most actionable signal.
    REASON="$(printf '%s' "$GUARDRAIL_STDERR" | awk 'NF{last=$0} END{print last}')"
fi
if [ -z "$REASON" ]; then
    REASON="Policy denied this action (guardrail exit=${GUARDRAIL_EXIT}, no reason recorded)."
fi
aport_append_local_session_decision "$HOOK_DECISION_FILE" "claude-code" "$INPUT" "$TOOL_NAME" "$GUARDRAIL_TOOL" "$CONTEXT_JSON"
cleanup_decision
if [ "$HAS_DECISION_FILE" -ne 1 ]; then
    deny_or_warn "${GUARDRAIL_TOOL:-hook.input}" "oap.evaluator_failed" "$REASON" "hard"
fi
if aport_hook_is_hard_failure_reason "${REASON_CODE:-oap.denied}"; then
    deny_or_warn "${GUARDRAIL_TOOL:-hook.input}" "${REASON_CODE:-oap.denied}" "$REASON" "hard"
else
    deny_or_warn "${GUARDRAIL_TOOL:-hook.input}" "${REASON_CODE:-oap.denied}" "$REASON" "policy"
fi

#!/usr/bin/env bash
# APort Cursor hook: reads JSON from stdin, maps tool to APort policy, calls guardrail.
# Handles the Cursor permission hooks: beforeShellExecution, preToolUse,
# beforeMCPExecution, beforeReadFile, beforeTabFileRead (opt-in registration),
# subagentStart. Reference: https://cursor.com/docs/hooks
# Output: JSON with "permission": "allow"|"deny" plus user_message/agent_message
# on deny; legacy allowed/agentMessage/reason fields are kept for older consumers.
# Exit: 0 = allow, 2 = block (deny). Other exits = hook error. Cursor fails open on
# those unless the hooks.json entry sets failClosed: true (the installer does).
#
# Cursor preToolUse tool names vary by Cursor version. Keep mappings conservative
# and covered by tests rather than assuming every host event is always emitted.

set -e

# Trap unexpected errors and emit Cursor-format deny JSON instead of letting the
# host see non-JSON output or an ambiguous hook crash.
# shellcheck disable=SC2317
__aport_emit_crash_deny() {
    local exit_code="$?"
    local line_no="$1"
    local script_name
    script_name="$(basename "${BASH_SOURCE[0]:-aport-cursor-hook}")"
    local reason="APort denied this tool call. Policy: hook.runtime. Reason: oap.hook_error. Detail: ${script_name}:${line_no} exited ${exit_code}."
    if command -v jq > /dev/null 2>&1; then
        jq -n -c --arg reason "$reason" \
            '{permission:"deny",allowed:false,agentMessage:$reason,agent_message:$reason,user_message:$reason,reason:$reason}' 2> /dev/null \
            || printf '{"permission":"deny","allowed":false,"agentMessage":"%s","reason":"%s"}\n' "$reason" "$reason"
    else
        printf '{"permission":"deny","allowed":false,"agentMessage":"%s","reason":"%s"}\n' "$reason" "$reason"
    fi
    exit 2
}
trap '__aport_emit_crash_deny "$LINENO"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Anchor data paths to Cursor config before resolve (hosted/API installs may have no passport.json).
# shellcheck source=bin/lib/framework-hook-paths.sh
. "$ROOT_DIR/bin/lib/framework-hook-paths.sh"
aport_hook_prepare_framework_paths "cursor" "${APORT_CURSOR_CONFIG_DIR:-}" "$HOME/.cursor"

# Passport/config: resolver probes ~/.cursor, ~/.openclaw, ~/.aport/*, etc.
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
load_guardrail_mode_for_hooks "${APORT_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-$HOME/.cursor}}"

GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-bash.sh"
if [ "${APORT_GUARDRAIL_MODE:-local}" = "api" ]; then
    GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-api.sh"
    if [ -n "${APORT_API_URL:-}" ]; then
        export APORT_API_URL
    fi
fi

emit_cursor_input_too_large() {
    local notice
    notice="$(aport_format_guardrail_notice deny hook.input oap.input_too_large "Hook payload exceeded ${APORT_HOOK_STDIN_MAX_BYTES} bytes.")"
    aport_hook_build_response "deny" "$notice" "" "cursor"
    exit 2
}

# Read stdin with a bounded wait so a broken host pipe cannot hang the agent session.
INPUT="$(aport_read_stdin_with_timeout)"

if [ "$INPUT" = "$APORT_HOOK_STDIN_TOO_LARGE_SENTINEL" ]; then
    emit_cursor_input_too_large
fi

# Empty input means the host did not provide a tool-call payload. Fail closed.
if [ -z "$INPUT" ]; then
    echo '{"permission":"deny","allowed":false,"agentMessage":"🛡️ APort: empty hook input — fail-closed policy","agent_message":"🛡️ APort: empty hook input — fail-closed policy","user_message":"🛡️ APort: empty hook input — fail-closed policy","reason":"🛡️ APort: empty hook input — fail-closed policy"}'
    exit 2
fi

# Require jq for JSON parsing
if ! command -v jq &> /dev/null; then
    echo '{"permission":"deny","allowed":false,"agentMessage":"APort: jq is required","agent_message":"APort: jq is required","user_message":"APort: jq is required","reason":"APort: jq is required"}'
    exit 2
fi

# Deny helper: outputs hook response JSON and exits 2
deny() {
    local reason="$1"
    aport_hook_build_response "deny" "$reason" "" "cursor"
    exit 2
}

warn_allow() {
    local reason="$1"
    local user_warning="${2:-}"
    aport_hook_build_response "allow" "$reason" "$user_warning" "cursor"
    exit 0
}

deny_or_warn() {
    local policy="$1"
    local code="${2:-oap.denied}"
    local message="${3:-}"
    local failure_class="${4:-hard}"
    local notice user_warning
    if [ "$failure_class" = "policy" ] && aport_hook_is_warn_mode; then
        notice="$(aport_format_guardrail_notice warn "$policy" "$code" "$message" "cursor")"
        user_warning="$(aport_hook_format_user_warning "$policy" "$code" "$message" "cursor")"
        warn_allow "$notice" "$user_warning"
    fi
    notice="$(aport_format_guardrail_notice deny "$policy" "$code" "$message" "cursor")"
    deny "$notice"
}

if aport_hook_payload_has_malformed_tool_arguments "$INPUT"; then
    deny_or_warn "hook.input" "oap.invalid_tool_arguments" "Hook tool arguments must be a JSON object"
fi

allow() {
    echo '{"permission":"allow","allowed":true}'
    exit 0
}

if ! printf '%s' "$INPUT" | jq -e . > /dev/null 2>&1; then
    deny_or_warn "hook.input" "oap.invalid_json" "Invalid hook JSON"
fi

# Safe jq extraction: returns '{}' on any jq error
safe_jq() {
    local input="$1" filter="$2"
    local result
    result="$(echo "$input" | jq -c "$filter" 2> /dev/null)" || result='{}'
    [ -z "$result" ] && result='{}'
    echo "$result"
}

# Detect hook event type from input fields and route accordingly.
# Every Cursor hook payload carries hook_event_name plus conversation_id,
# generation_id, model, cursor_version, workspace_roots, user_email and
# transcript_path. Event-specific fields (Cursor hooks reference, 2026-09):
#   beforeShellExecution: { "command": "...", "cwd": "...", "sandbox": false }
#   preToolUse:           { "tool_name": "Shell|Read|Write|Grep|Delete|Task|MCP:<tool>",
#                           "tool_input": {...}, "tool_use_id": "...", "cwd": "...",
#                           "agent_message": "..." }
#   beforeMCPExecution:   { "tool_name": "...", "tool_input": "<json string>" | {...},
#                           "mcp_server_name": "...",
#                           HTTP/SSE: "url" + "mcp_server_url"; stdio: "command" (launch string) }
#   beforeReadFile:       { "file_path": "...", "content": "...", "attachments": [...] }
#   beforeTabFileRead:    { "file_path": "...", "content": "..." } (Tab completions, no attachments)
#   subagentStart:        { "subagent_id": "...", "subagent_type": "...", "task": "...",
#                           "parent_conversation_id": "...", "tool_call_id": "...", ... }
# Route on hook_event_name first; the field heuristics below cover older payloads
# that omit it. The top-level "command" of a stdio MCP payload is the server launch
# string, not a shell command, so the MCP branch must win before the shell branch.

GUARDRAIL_TOOL=""
CONTEXT_JSON="{}"

# hook_event_name is part of every documented Cursor payload; older builds may omit it.
HOOK_EVENT="$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2> /dev/null)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""' 2> /dev/null)"

if [ "$HOOK_EVENT" = "beforeReadFile" ] || [ "$HOOK_EVENT" = "beforeTabFileRead" ] || { [ -z "$HOOK_EVENT" ] && [ -z "$TOOL_NAME" ] && echo "$INPUT" | jq -e '.file_path and .content' &> /dev/null; }; then
    # beforeReadFile (Agent) and beforeTabFileRead (Tab completions) share the
    # same file_path/content input and the same permission output. Only
    # file_path is evaluated; content and attachments are never forwarded.
    # No usable path is no evidence, and a read hook with no evidence must not allow. Both events are
    # documented to carry file_path; a payload without one (or with one the read context builder rejects)
    # is a payload this hook cannot authorize, so it denies rather than waving the read through.
    FILE_PATH="$(echo "$INPUT" | jq -r '.file_path // ""' 2> /dev/null || true)"
    if ! aport_hook_try_read_evaluation_from_file_path "$FILE_PATH"; then
        deny_or_warn "data.file.read" "oap.missing_file_path" "$HOOK_EVENT did not provide a file path that APort can evaluate"
    fi

elif [ "$HOOK_EVENT" = "subagentStart" ] || { [ -z "$HOOK_EVENT" ] && echo "$INPUT" | jq -e '.subagent_id' &> /dev/null; }; then
    # subagentStart: sub-agent spawning
    GUARDRAIL_TOOL="session.create"
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" session "subagentStart" "cursor")"

elif [ "$HOOK_EVENT" = "beforeMCPExecution" ] || { [ -n "$TOOL_NAME" ] && echo "$INPUT" | jq -e '.mcp_server_name // .server // .url' &> /dev/null; }; then
    # beforeMCPExecution: MCP tool calls. Cursor's current native field is
    # mcp_server_name; server-qualified tool names are parsed by the shared
    # context helper. Do not trust ordinary tool_input.server values.
    GUARDRAIL_TOOL="mcp.tool"
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" mcp "$TOOL_NAME" "beforeMCPExecution")"

elif [ -n "$TOOL_NAME" ]; then
    # preToolUse: Shell, Read, Write, Grep, Delete, Task, WebSearch, Agent, MCP:*, etc.
    # See docs/FRAMEWORK_TOOL_MAPPING_AUDIT.md and https://cursor.com/docs/agent/hooks
    TOOL_NORM="$(printf '%s' "$TOOL_NAME" | tr -d '[:space:]' | sed 's/^functions\.//' | sed 's/(.*$//' | tr '[:upper:]' '[:lower:]')"
    case "$TOOL_NORM" in
        shell | bash | runterminalcmd | run_terminal_cmd | runcommand | run_command | terminal | terminalcommand | terminal_command)
            GUARDRAIL_TOOL="bash"
            if aport_hook_payload_has_malformed_shell_command_aliases "$INPUT"; then
                deny_or_warn "system.command.execute" "oap.invalid_tool_arguments" "Shell command aliases must be strings"
            fi
            if aport_hook_payload_has_conflicting_shell_command_aliases "$INPUT"; then
                deny_or_warn "system.command.execute" "oap.invalid_tool_arguments" "Shell tool supplied conflicting command aliases"
            fi
            CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" shell "$TOOL_NAME" "cursor")"
            COMMAND_TEXT="$(printf '%s' "$CONTEXT_JSON" | jq -r '.command // ""' 2> /dev/null || true)"
            SHELL_OVERRIDE="$(printf '%s' "$CONTEXT_JSON" | jq -r '.shell // ""' 2> /dev/null || true)"
            if [ -z "$COMMAND_TEXT" ]; then
                deny_or_warn "system.command.execute" "oap.missing_command" "Shell tool did not provide a command that APort can evaluate"
            fi
            if ! aport_hook_shell_override_is_trusted "$SHELL_OVERRIDE"; then
                deny_or_warn "system.command.execute" "oap.shell_not_allowed" "Shell override is not a trusted interpreter"
            fi
            if aport_is_reentrant_guardrail_command "$COMMAND_TEXT" "$ROOT_DIR"; then
                allow
            fi
            ;;
        read | readfile | read_file | semanticsearch | presentfile | present_file | viewimage | view_image)
            TOOL_INPUT="$(safe_jq "$INPUT" '.tool_input // {}')"
            set +e
            trap - ERR
            aport_hook_try_read_evaluation "$TOOL_NORM" "$TOOL_INPUT"
            READ_STATUS=$?
            set -e
            trap '__aport_emit_crash_deny "$LINENO"' ERR
            if [ "$READ_STATUS" -eq 2 ]; then
                deny_or_warn "data.file.read" "$APORT_HOOK_READ_ERROR_CODE" "$APORT_HOOK_READ_ERROR_MESSAGE"
            fi
            if [ "$READ_STATUS" -ne 0 ]; then
                allow
            fi
            :
            ;;
        readmcpresourcetool)
            GUARDRAIL_TOOL="mcp.tool"
            CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" mcp "$TOOL_NAME")"
            ;;
        grep | grepsearch | grep_search)
            TOOL_INPUT="$(safe_jq "$INPUT" '.tool_input // {}')"
            set +e
            trap - ERR
            aport_hook_try_read_evaluation "$TOOL_NORM" "$TOOL_INPUT"
            READ_STATUS=$?
            set -e
            trap '__aport_emit_crash_deny "$LINENO"' ERR
            if [ "$READ_STATUS" -eq 2 ]; then
                deny_or_warn "data.file.read" "$APORT_HOOK_READ_ERROR_CODE" "$APORT_HOOK_READ_ERROR_MESSAGE"
            fi
            if [ "$READ_STATUS" -ne 0 ]; then
                deny_or_warn "data.file.read" "oap.missing_file_path" "Search tool did not provide a path that APort can evaluate"
            fi
            :
            ;;
        glob | filesearch | file_search | codebasesearch | codebase_search | ls | listdir | list_dir | lsp | todoread | todowrite | askquestion | askuserquestion | listmcpresourcestool | toolsearch | waitformcpservers | taskget | tasklist | taskoutput | cronlist)
            allow
            ;;
        write | writefile | write_file | strreplace | str_replace | edit | editfile | edit_file | createfile | create_file | multiedit | editnotebook | applypatch | searchreplace | search_replace | notebookedit | delete | deletefile | delete_file | removefile | remove_file)
            GUARDRAIL_TOOL="write"
            CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" file_write)"
            ;;
        websearch | webfetch)
            GUARDRAIL_TOOL="websearch"
            CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" web)"
            ;;
        browser)
            if aport_hook_payload_has_conflicting_browser_action_aliases "$INPUT"; then
                deny_or_warn "web.browser" "oap.invalid_tool_arguments" "Browser tool supplied conflicting action aliases"
            fi
            GUARDRAIL_TOOL="browser"
            CONTEXT_JSON="$(aport_hook_browser_context_from_payload "$INPUT")"
            ;;
        task | agent | taskcreate | taskupdate | taskstop | skill | subagent | subagentstart | sendmessage | teamcreate | teamdelete)
            GUARDRAIL_TOOL="session.create"
            CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" session "$TOOL_NAME" "cursor")"
            ;;
        croncreate | crondelete)
            GUARDRAIL_TOOL="session.create"
            CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" session "$TOOL_NAME" "cursor")"
            ;;
        mcp__* | mcp:* | callmcptool)
            GUARDRAIL_TOOL="mcp.tool"
            CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" mcp "$TOOL_NAME")"
            ;;
        *)
            deny_or_warn "hook.tool.map" "oap.unknown_tool" "Unknown tool: $TOOL_NAME (fail-closed)"
            ;;
    esac

elif echo "$INPUT" | jq -e '.command' &> /dev/null; then
    # beforeShellExecution: { "command": "..." }
    GUARDRAIL_TOOL="bash"
    if aport_hook_payload_has_malformed_shell_command_aliases "$INPUT"; then
        deny_or_warn "system.command.execute" "oap.invalid_tool_arguments" "Shell command aliases must be strings"
    fi
    if aport_hook_payload_has_conflicting_shell_command_aliases "$INPUT"; then
        deny_or_warn "system.command.execute" "oap.invalid_tool_arguments" "Shell hook supplied conflicting command aliases"
    fi
    CMD="$(echo "$INPUT" | jq -r '.command // ""' 2> /dev/null)"
    if [ -z "$CMD" ]; then
        deny_or_warn "system.command.execute" "oap.missing_command" "Shell hook did not provide a command that APort can evaluate"
    fi
    if aport_is_reentrant_guardrail_command "$CMD" "$ROOT_DIR"; then
        allow
    fi
    CONTEXT_JSON="$(jq -n -c --arg cmd "$CMD" '{command: $cmd}')"

elif echo "$INPUT" | jq -e '.tool // .input.command' &> /dev/null; then
    # Legacy Copilot-style: { "tool": "runTerminalCommand", "input": { "command": "..." } }
    GUARDRAIL_TOOL="bash"
    if aport_hook_payload_has_malformed_shell_command_aliases "$INPUT"; then
        deny_or_warn "system.command.execute" "oap.invalid_tool_arguments" "Shell command aliases must be strings"
    fi
    if aport_hook_payload_has_conflicting_shell_command_aliases "$INPUT"; then
        deny_or_warn "system.command.execute" "oap.invalid_tool_arguments" "Shell tool supplied conflicting command aliases"
    fi
    CMD="$(echo "$INPUT" | jq -r '.input.command // .input.cmd // .args[0] // ""' 2> /dev/null)"
    if [ -z "$CMD" ]; then
        deny_or_warn "system.command.execute" "oap.missing_command" "Shell tool did not provide a command that APort can evaluate"
    fi
    if aport_is_reentrant_guardrail_command "$CMD" "$ROOT_DIR"; then
        allow
    fi
    CONTEXT_JSON="$(jq -n -c --arg cmd "$CMD" '{command: $cmd}')"

else
    # Unrecognized input shape: fail-closed
    deny_or_warn "hook.input" "oap.unrecognized_input" "Unrecognized hook input"
fi

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

# Read tools: send only file_path to the evaluator (Cursor may attach large file bodies in tool_input).
if [ "$GUARDRAIL_TOOL" = "read" ]; then
    CONTEXT_JSON="$(printf '%s' "$CONTEXT_JSON" | jq -c '{file_path: (.file_path // .path // "")}' 2> /dev/null || echo '{"file_path":""}')"
    if [ -z "$(printf '%s' "$CONTEXT_JSON" | jq -r '.file_path // ""' 2> /dev/null)" ]; then
        allow
    fi
fi

# Call core evaluator. Cursor requires stdout to be exactly one JSON object from
# this hook, so child evaluator output must be captured and only surfaced on
# stderr when DEBUG_APORT is enabled.
trap - ERR
set +e
GUARDRAIL_OUTPUT="$("$GUARDRAIL" "$GUARDRAIL_TOOL" "$CONTEXT_JSON" 2>&1)"
GUARDRAIL_EXIT=$?
set -e
trap '__aport_emit_crash_deny "$LINENO"' ERR
if [ -n "$DEBUG_APORT" ] && [ -n "$GUARDRAIL_OUTPUT" ]; then
    aport_sanitize_display_text "$GUARDRAIL_OUTPUT" >&2
    printf '\n' >&2
fi

# Clean up per-invocation decision file
cleanup_decision() { [ -n "$HOOK_DECISION_FILE" ] && rm -f "$HOOK_DECISION_FILE" 2> /dev/null; }

if [ "$GUARDRAIL_EXIT" -eq 0 ]; then
    aport_append_local_session_decision "$HOOK_DECISION_FILE" "cursor" "$INPUT" "$TOOL_NAME" "$GUARDRAIL_TOOL" "$CONTEXT_JSON"
    cleanup_decision
    allow
fi

# Deny: read reason from decision file
REASON="Policy denied this action."
REASON_CODE=""
HAS_DECISION_FILE=0
if [ -n "$HOOK_DECISION_FILE" ] && [ -f "$HOOK_DECISION_FILE" ]; then
    HAS_DECISION_FILE=1
    R="$(jq -r 'if (.allow == false) then (.reasons[0].message // empty) else empty end' "$HOOK_DECISION_FILE" 2> /dev/null)"
    [ -n "$R" ] && REASON="$R"
    C="$(aport_hook_reason_code "$HOOK_DECISION_FILE")"
    [ -n "$C" ] && REASON_CODE="$C"
fi
# Fallback: try common config dirs only when no per-invocation decision file was
# configured. Otherwise this can surface stale reasons from earlier tool calls.
if [ "$REASON" = "Policy denied this action." ] && [ -z "$HOOK_DECISION_FILE" ]; then
    for DEC in "${APORT_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-$HOME/.cursor}}/aport/decision.json" "$HOME/.cursor/aport/decision.json" "$HOME/.openclaw/aport/decision.json"; do
        if [ -f "$DEC" ]; then
            R="$(jq -r 'if (.allow == false) then (.reasons[0].message // empty) else empty end' "$DEC" 2> /dev/null)"
            [ -n "$R" ] && REASON="$R" && break
        fi
    done
fi
if [ "$REASON" = "Policy denied this action." ] && [ -n "$GUARDRAIL_OUTPUT" ]; then
    R="$(printf '%s' "$GUARDRAIL_OUTPUT" | awk 'NF{last=$0} END{print last}')"
    [ -n "$R" ] && REASON="$R"
fi
aport_append_local_session_decision "$HOOK_DECISION_FILE" "cursor" "$INPUT" "$TOOL_NAME" "$GUARDRAIL_TOOL" "$CONTEXT_JSON"
cleanup_decision
if [ "$HAS_DECISION_FILE" -ne 1 ]; then
    deny_or_warn "${GUARDRAIL_TOOL:-hook.input}" "oap.evaluator_failed" "$REASON" "hard"
fi
if aport_hook_is_hard_failure_reason "${REASON_CODE:-oap.denied}"; then
    deny_or_warn "${GUARDRAIL_TOOL:-hook.input}" "${REASON_CODE:-oap.denied}" "$REASON" "hard"
else
    deny_or_warn "${GUARDRAIL_TOOL:-hook.input}" "${REASON_CODE:-oap.denied}" "$REASON" "policy"
fi

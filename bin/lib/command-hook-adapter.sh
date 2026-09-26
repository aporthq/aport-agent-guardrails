#!/usr/bin/env bash
# Shared command-hook adapter for Codex, Gemini CLI, and Goose.
# Framework-specific wrappers pass the host name; this script keeps mapping,
# enforcement-mode handling, and APort evaluator invocation in one place.

set -e

FRAMEWORK="${1:-${APORT_HOOK_FRAMEWORK:-}}"
if [ $# -gt 0 ]; then
    shift || true
fi

case "$FRAMEWORK" in
    codex | gemini-cli | gemini | goose) ;;
    *)
        FRAMEWORK="codex"
        ;;
esac
[ "$FRAMEWORK" = "gemini" ] && FRAMEWORK="gemini-cli"
export APORT_HOOK_FRAMEWORK="$FRAMEWORK"

aport_adapter_json_escape() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    printf '%s' "$value"
}

aport_adapter_fail_closed() {
    local policy="${1:-hook.runtime}"
    local code="${2:-oap.hook_error}"
    local message="${3:-APort hook runtime failed before policy evaluation}"
    local reason escaped_reason event

    reason="APort denied this tool call. Policy: $policy. Reason: $code. Detail: $message"
    escaped_reason="$(aport_adapter_json_escape "$reason")"
    case "$FRAMEWORK" in
        codex)
            event="$(aport_adapter_json_escape "${APORT_CODEX_HOOK_EVENT_NAME:-PreToolUse}")"
            printf '{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$event" "$escaped_reason"
            ;;
        goose)
            printf '{"decision":"block","reason":"%s"}\n' "$escaped_reason"
            ;;
        gemini-cli | gemini)
            printf '{"decision":"deny","reason":"%s"}\n' "$escaped_reason"
            ;;
        *)
            printf '{"decision":"deny","reason":"%s"}\n' "$escaped_reason"
            ;;
    esac
    exit 0
}

# shellcheck disable=SC2317
aport_adapter_early_crash_deny() {
    local exit_code="$?"
    local line_no="${1:-unknown}"
    aport_adapter_fail_closed "hook.runtime" "oap.hook_error" "command-hook-adapter.sh:${line_no} exited ${exit_code}"
}
trap 'aport_adapter_early_crash_deny "$LINENO"' ERR

aport_adapter_source() {
    local source_path="$1"
    if [ ! -r "$source_path" ]; then
        aport_adapter_fail_closed "hook.runtime" "oap.missing_dependency" "Required APort runtime file is missing"
    fi
    # shellcheck disable=SC1090
    . "$source_path" || aport_adapter_fail_closed "hook.runtime" "oap.hook_error" "Required APort runtime file failed to load"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=bin/lib/framework-hook-paths.sh
aport_adapter_source "$ROOT_DIR/bin/lib/framework-hook-paths.sh"
case "$FRAMEWORK" in
    codex)
        aport_hook_prepare_framework_paths "codex" "${APORT_CODEX_CONFIG_DIR:-}" "$HOME/.aport/codex"
        ;;
    gemini-cli)
        aport_hook_prepare_framework_paths "gemini-cli" "${APORT_GEMINI_CLI_CONFIG_DIR:-}" "$HOME/.aport/gemini-cli"
        ;;
    goose)
        aport_hook_prepare_framework_paths "goose" "${APORT_GOOSE_CONFIG_DIR:-}" "$HOME/.aport/goose"
        ;;
esac

# shellcheck source=bin/aport-resolve-paths.sh
aport_adapter_source "$ROOT_DIR/bin/aport-resolve-paths.sh"
# shellcheck source=bin/lib/guardrail-mode.sh
aport_adapter_source "$ROOT_DIR/bin/lib/guardrail-mode.sh"
# shellcheck source=bin/lib/hook-runtime.sh
aport_adapter_source "$ROOT_DIR/bin/lib/hook-runtime.sh"
# shellcheck source=bin/lib/harness-context.sh
aport_adapter_source "$ROOT_DIR/bin/lib/harness-context.sh"

emit_response() {
    local disposition="$1"
    local policy="$2"
    local code="${3:-oap.denied}"
    local message="${4:-}"
    local failure_class="${5:-hard}"
    local notice user_warning

    if [ "$disposition" = "allow" ]; then
        aport_hook_build_response "allow" "" "" "$FRAMEWORK"
        exit 0
    fi

    if [ "$failure_class" = "policy" ] && aport_hook_is_warn_mode; then
        notice="$(aport_format_guardrail_notice warn "$policy" "$code" "$message" "$FRAMEWORK")"
        user_warning="$(aport_hook_format_user_warning "$policy" "$code" "$message" "$FRAMEWORK")"
        # Some hosts do not surface allow-response warnings consistently. Keep
        # stderr human-readable and sanitized while returning allow semantics.
        aport_sanitize_display_text "$user_warning" >&2
        printf '\n' >&2
        aport_hook_build_response "allow" "$notice" "$user_warning" "$FRAMEWORK"
        exit 0
    fi

    notice="$(aport_format_guardrail_notice deny "$policy" "$code" "$message" "$FRAMEWORK")"
    aport_hook_build_response "deny" "$notice" "" "$FRAMEWORK"
    exit 0
}

# shellcheck disable=SC2317
emit_crash_deny() {
    local exit_code="$?"
    local line_no="$1"
    emit_response "deny" "hook.runtime" "oap.hook_error" "command-hook-adapter.sh:${line_no} exited ${exit_code}"
}
trap 'emit_crash_deny "$LINENO"' ERR

if ! load_guardrail_mode_for_hooks "${APORT_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-}}"; then
    emit_response "deny" "hook.runtime" "oap.invalid_mode_file" "APort mode configuration could not be loaded"
fi

GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-bash.sh"
if [ "${APORT_GUARDRAIL_MODE:-local}" = "api" ]; then
    GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-api.sh"
    export APORT_API_URL="${APORT_API_URL:-https://api.aport.io}"
fi

INPUT="$(aport_read_stdin_with_timeout)"
if [ "$INPUT" = "$APORT_HOOK_STDIN_TOO_LARGE_SENTINEL" ]; then
    emit_response "deny" "hook.input" "oap.input_too_large" "Hook payload exceeded ${APORT_HOOK_STDIN_MAX_BYTES} bytes"
fi

if [ -z "$INPUT" ]; then
    emit_response "deny" "hook.input" "oap.empty_input" "Host did not provide a hook payload"
fi

if ! command -v jq > /dev/null 2>&1; then
    emit_response "deny" "hook.runtime" "oap.missing_dependency" "jq is required to parse hook payloads"
fi

if ! printf '%s' "$INPUT" | jq -e . > /dev/null 2>&1; then
    emit_response "deny" "hook.input" "oap.invalid_json" "Invalid hook JSON"
fi

if aport_hook_payload_has_malformed_tool_arguments "$INPUT"; then
    emit_response "deny" "hook.input" "oap.invalid_tool_arguments" "Hook tool arguments must be a JSON object"
fi

HOOK_EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // .event // ""' 2> /dev/null || true)"
ORIGINAL_TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // .tool // .name // ""' 2> /dev/null || true)"
TOOL_NORM="$(aport_hook_tool_name_normalize "$ORIGINAL_TOOL")"
if [ "$FRAMEWORK" = "codex" ]; then
    case "$HOOK_EVENT" in
        PermissionRequest | PreToolUse | PostToolUse) ;;
        "") HOOK_EVENT="PreToolUse" ;;
        *) emit_response "deny" "hook.input" "oap.unknown_hook_event" "Unsupported Codex hook event: $HOOK_EVENT" ;;
    esac
    export APORT_CODEX_HOOK_EVENT_NAME="$HOOK_EVENT"
elif [ "$FRAMEWORK" = "gemini-cli" ]; then
    case "$HOOK_EVENT" in
        BeforeTool) ;;
        "") HOOK_EVENT="BeforeTool" ;;
        *) emit_response "deny" "hook.input" "oap.unknown_hook_event" "Unsupported Gemini CLI hook event: $HOOK_EVENT" ;;
    esac
elif [ "$FRAMEWORK" = "goose" ]; then
    case "$HOOK_EVENT" in
        PreToolUse) ;;
        "") HOOK_EVENT="PreToolUse" ;;
        *) emit_response "deny" "hook.input" "oap.unknown_hook_event" "Unsupported Goose hook event: $HOOK_EVENT" ;;
    esac
fi

is_session_tool() {
    case "$1" in
        agent | task | subagent | subagentstart | subagent_start | sendmessage | send_message | collaboration.sendmessage | collaboration.send_message | followuptask | followup_task | collaboration.followuptask | collaboration.followup_task | waitagent | wait_agent | collaboration.waitagent | collaboration.wait_agent | interruptagent | interrupt_agent | collaboration.interruptagent | collaboration.interrupt_agent | spawnagent | spawn_agent | collaboration.spawnagent | collaboration.spawn_agent | sendinput | send_input | collaboration.sendinput | collaboration.send_input | closeagent | close_agent | collaboration.closeagent | collaboration.close_agent | resumeagent | resume_agent | collaboration.resumeagent | collaboration.resume_agent | listagents | list_agents | collaboration.listagents | collaboration.list_agents | multi_agent_v1.spawn_agent | multi_agent_v1.send_input | multi_agent_v1.resume_agent | multi_agent_v1.wait_agent | multi_agent_v1.close_agent | collaboration.create_channel | collaboration.get_channels | collaboration.list_threads | collaboration.search_posts | collaboration.read_thread | collaboration.read_post | collaboration.subscribe | collaboration.unsubscribe | collaboration.post)
            return 0
            ;;
    esac
    return 1
}

codex_post_tool_succeeded() {
    printf '%s' "$INPUT" | jq -e '
	  def obj(v):
	    if (v | type) == "object" then v
	    elif (v | type) == "string" then (try (v | fromjson) catch {})
	    else {}
	    end;
	  def failed(v):
	    (obj(v).success == false) or
	    (obj(v).error? != null) or
	    (obj(v).tool_error? != null);
	  (
	    .success == false or
	    failed(.tool_response) or
	    failed(.tool_output) or
	    failed(.result) or
	    failed(.output) or
	    (.tool_error? != null) or
	    (.error? != null)
	  ) | not
	' > /dev/null 2>&1
}

codex_post_tool_has_explicit_failure() {
    printf '%s' "$INPUT" | jq -e '
	  def obj(v):
	    if (v | type) == "object" then v
	    elif (v | type) == "string" then (try (v | fromjson) catch {})
	    else {}
	    end;
	  def failed(v):
	    (obj(v).success == false) or
	    (obj(v).ok == false) or
	    (obj(v).status == "error") or
	    (obj(v).status == "failed") or
	    (obj(v).error? != null) or
	    (obj(v).tool_error? != null);
	  (
	    .success == false or
	    .ok == false or
	    .status == "error" or
	    .status == "failed" or
	    failed(.tool_response) or
	    failed(.tool_output) or
	    failed(.result) or
	    failed(.output) or
	    (.tool_error? != null) or
	    (.error? != null)
	  )
	' > /dev/null 2>&1
}

codex_post_tool_has_explicit_success() {
    printf '%s' "$INPUT" | jq -e '
	  def obj(v):
	    if (v | type) == "object" then v
	    elif (v | type) == "string" then (try (v | fromjson) catch {})
	    else {}
	    end;
	  def successful(v):
	    (obj(v).success == true) or
	    (obj(v).ok == true) or
	    (obj(v).status == "success") or
	    (obj(v) | has("previous_status"));
	  (
	    .success == true or
	    has("previous_status") or
	    successful(.tool_response) or
	    successful(.tool_output) or
	    successful(.result) or
	    successful(.output)
	  )
	' > /dev/null 2>&1
}

apply_codex_post_tool_session_lifecycle() {
    local post_context session_id session_call_id operation lifecycle_decision_file lifecycle_context lifecycle_should_deny

    [ "${APORT_GUARDRAIL_MODE:-local}" = "local" ] || return 0
    is_session_tool "$TOOL_NORM" || return 0
    session_call_id="$(printf '%s' "$INPUT" | jq -r '.tool_call_id // .toolCallId // .tool_use_id // .toolUseId // .request_id // ""' 2> /dev/null || true)"
    post_context="$(aport_hook_context_from_payload "$INPUT" session "$ORIGINAL_TOOL" "$FRAMEWORK")"
    operation="$(printf '%s' "$post_context" | jq -r '.session_operation // ""' 2> /dev/null || true)"
    session_id="$(
        printf '%s' "$INPUT" | jq -r '
		  def obj(v):
		    if (v | type) == "object" then v
		    elif (v | type) == "string" then (try (v | fromjson) catch {})
		    else {}
		    end;
		  obj(.tool_response) as $response |
		  obj(.tool_output) as $output |
		  obj(.result) as $result |
		  obj(.output) as $raw_output |
		  [
            $response.session_id, $response.agent_id, $response.id,
            $output.session_id, $output.agent_id, $output.id,
            $result.session_id, $result.agent_id, $result.id,
            $raw_output.session_id, $raw_output.agent_id, $raw_output.id
          ]
          | map(select(type == "string" and length > 0))
		  | .[0] // ""
		' 2> /dev/null || true
    )"
    [ -n "$session_id" ] || session_id="$(printf '%s' "$post_context" | jq -r '.session_id // ""' 2> /dev/null || true)"

    if codex_post_tool_has_explicit_failure; then
        if { [ "$operation" = "create" ] || [ "$operation" = "resume" ]; } && [ -n "$session_call_id" ]; then
            lifecycle_context="$(jq -n -c --arg sid "$session_id" --arg call "$session_call_id" '{session_tracking:"persistent",hook_event:"PostToolUse",session_operation:"release_failed_create",session_id:$sid,session_call_id:$call}')"
        else
            return 0
        fi
    else
        lifecycle_context=""
    fi
    lifecycle_should_deny=0

    if [ -z "$lifecycle_context" ]; then
        case "$operation" in
            create | resume)
                [ -n "$session_call_id" ] || return 0
                if [ -z "$session_id" ]; then
                    CODEX_LIFECYCLE_REASON_CODE="oap.missing_required_context"
                    CODEX_LIFECYCLE_REASON_MESSAGE="Codex PostToolUse did not provide a session id or explicit failure; preserving provisional session lease"
                    lifecycle_context="$(jq -n -c --arg call "$session_call_id" '{session_tracking:"persistent",hook_event:"PostToolUse",session_operation:"mark_unresolved",session_id:"",session_call_id:$call}')"
                    lifecycle_should_deny=1
                else
                    lifecycle_context="$(jq -n -c --arg sid "$session_id" --arg call "$session_call_id" '{session_tracking:"persistent",hook_event:"PostToolUse",session_operation:"reconcile",session_id:$sid,session_call_id:$call}')"
                fi
                ;;
            close)
                [ -n "$session_id" ] || return 0
                codex_post_tool_has_explicit_success || return 0
                lifecycle_context="$(jq -n -c --arg sid "$session_id" --arg call "$session_call_id" '{session_tracking:"persistent",hook_event:"PostToolUse",session_operation:"close",session_id:$sid,session_call_id:$call}')"
                ;;
            *)
                return 0
                ;;
        esac
    fi

    lifecycle_decision_file="${APORT_DECISION_FILE:-${OPENCLAW_DECISION_FILE:-}}"
    if [ -n "$lifecycle_decision_file" ]; then
        lifecycle_decision_file="${lifecycle_decision_file%.json}-lifecycle-$$.json"
        if ! APORT_DECISION_FILE="$lifecycle_decision_file" OPENCLAW_DECISION_FILE="$lifecycle_decision_file" "$ROOT_DIR/bin/aport-guardrail-bash.sh" "session.create" "$lifecycle_context" > /dev/null 2>&1; then
            CODEX_LIFECYCLE_REASON_CODE="$(aport_hook_reason_code "$lifecycle_decision_file")"
            CODEX_LIFECYCLE_REASON_MESSAGE="$(aport_hook_reason_message "$lifecycle_decision_file")"
            [ -z "$CODEX_LIFECYCLE_REASON_CODE" ] && CODEX_LIFECYCLE_REASON_CODE="oap.session_state_unavailable"
            [ -z "$CODEX_LIFECYCLE_REASON_MESSAGE" ] && CODEX_LIFECYCLE_REASON_MESSAGE="Codex session lifecycle state could not be updated"
            rm -f "$lifecycle_decision_file" 2> /dev/null || true
            return 1
        fi
        rm -f "$lifecycle_decision_file" 2> /dev/null || true
    fi

    if [ "$lifecycle_should_deny" -eq 1 ]; then
        return 1
    fi
}

if [ "$FRAMEWORK" = "codex" ] && [ "$HOOK_EVENT" = "PostToolUse" ]; then
    CODEX_LIFECYCLE_REASON_CODE=""
    CODEX_LIFECYCLE_REASON_MESSAGE=""
    if ! apply_codex_post_tool_session_lifecycle; then
        emit_response "deny" "agent.session.create" "$CODEX_LIFECYCLE_REASON_CODE" "$CODEX_LIFECYCLE_REASON_MESSAGE" "hard"
    fi
    # PostToolUse cannot prevent side effects and may include tool output. Do not
    # forward response bodies; pre-action enforcement is handled by PreToolUse.
    emit_response "allow" "" "" ""
fi

GUARDRAIL_TOOL=""
CONTEXT_JSON="{}"

# The shape of an unmapped Codex tool's payload: shell, web, write, read, "mixed", or empty.
#
# STRICT BY DEFAULT. An unmapped tool denies oap.unknown_tool unless the operator sets
# APORT_CODEX_TOOL_FALLBACK=on. Routing by payload shape alone authorizes by shape, not by what the tool does:
# a name this list has never seen, carrying a generic `url`, `path` or `command`, would inherit whatever
# capability that field maps to. A payment or database tool with a `url` field would be judged by web.fetch.
# Naming the tool is the operator's job; guessing is not a substitute for it.
#
# Even when the operator opts in, a payload that carries MORE THAN ONE effect-bearing field is "mixed" and
# denies. Picking one effect means dropping the others unevaluated; a mixed command+URL payload must not be
# approved only because its URL looks acceptable.
#
# Looks at tool_input/input/args and their args/arguments children like aport_hook_context_from_payload does.
codex_payload_shape() {
    [ "${APORT_CODEX_TOOL_FALLBACK:-off}" = "on" ] || return 0
    printf '%s' "$1" | jq -r '
      def obj(v): if (v | type) == "object" then v elif (v | type) == "string" then (try (v | fromjson) catch {}) else {} end;
      def str(v): (v | type) == "string" and (v | length) > 0;
      def merged_args:
        [
          obj(.tool_input),
          obj(.input),
          obj(.args),
          obj(obj(.tool_input).args),
          obj(obj(.tool_input).arguments),
          obj(obj(.input).args),
          obj(obj(.input).arguments),
          obj(obj(.args).args),
          obj(obj(.args).arguments)
        ] | add;
      merged_args as $ti |
      (str($ti.command) or str($ti.cmd) or str($ti.script)) as $cmd |
      (str($ti.url)) as $url |
      (str($ti.file_path) or str($ti.path)) as $path |
      (str($ti.content) or ($ti.edits | type) == "array" or str($ti.new_string)) as $content |
      # A path is read evidence on its own and write evidence with content, so it counts once either way.
      ([$cmd, $url, $path] | map(select(. == true)) | length) as $effects |
      if $effects > 1 then "mixed"
      elif $url then "web"
      elif $path and $content then "write"
      elif $path then "read"
      elif $cmd then "shell"
      else "" end
    ' 2> /dev/null || true
}

map_shell() {
    GUARDRAIL_TOOL="bash"
    if aport_hook_payload_has_malformed_shell_command_aliases "$INPUT"; then
        emit_response "deny" "system.command.execute" "oap.invalid_tool_arguments" "Shell command aliases must be strings"
    fi
    if aport_hook_payload_has_conflicting_shell_command_aliases "$INPUT"; then
        emit_response "deny" "system.command.execute" "oap.invalid_tool_arguments" "Shell tool supplied conflicting command aliases"
    fi
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" shell "$TOOL_NORM" "$FRAMEWORK")"
    local command_text shell_override
    command_text="$(printf '%s' "$CONTEXT_JSON" | jq -r '.command // ""' 2> /dev/null || true)"
    shell_override="$(printf '%s' "$CONTEXT_JSON" | jq -r '.shell // ""' 2> /dev/null || true)"
    if [ -z "$command_text" ]; then
        emit_response "deny" "system.command.execute" "oap.missing_command" "Shell tool did not provide a command that APort can evaluate"
    fi
    if ! aport_hook_shell_override_is_trusted "$shell_override"; then
        emit_response "deny" "system.command.execute" "oap.shell_not_allowed" "Shell override is not a trusted interpreter"
    fi
    if aport_is_reentrant_guardrail_command "$command_text" "$ROOT_DIR"; then
        emit_response "allow" "" "" ""
    fi
}

map_file_read() {
    if aport_hook_payload_has_malformed_file_target_aliases "$INPUT"; then
        emit_response "deny" "data.file.read" "oap.invalid_tool_arguments" "File read path aliases must be strings"
    fi
    if aport_hook_payload_has_conflicting_file_target_aliases "$INPUT"; then
        emit_response "deny" "data.file.read" "oap.invalid_tool_arguments" "File read tool supplied conflicting path aliases"
    fi
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" file_read)"
    local file_path read_target_count read_has_glob has_directory_context is_search_tool is_directory_enumeration_tool
    file_path="$(printf '%s' "$CONTEXT_JSON" | jq -r '.file_path // ""' 2> /dev/null || true)"
    read_target_count="$(printf '%s' "$CONTEXT_JSON" | jq -r '.read_target_count // 0' 2> /dev/null || echo 0)"
    read_has_glob="$(printf '%s' "$CONTEXT_JSON" | jq -r '.read_has_glob // false' 2> /dev/null || echo false)"
    has_directory_context="$(printf '%s' "$CONTEXT_JSON" | jq -r '.has_directory_context // false' 2> /dev/null || echo false)"
    is_search_tool=false
    is_directory_enumeration_tool=false
    case "$TOOL_NORM" in
        grep | grepsearch | grep_search) is_search_tool=true ;;
    esac
    case "$TOOL_NORM" in
        glob | list_directory | listdirectory | developer__tree | tree) is_directory_enumeration_tool=true ;;
    esac
    case "$read_target_count" in
        "" | *[!0-9]*) read_target_count=0 ;;
    esac
    if [ "$is_directory_enumeration_tool" = true ]; then
        emit_response "deny" "data.file.read" "oap.metadata_enumeration_unsupported" "This hook cannot safely authorize directory enumeration; use an explicit file-read tool instead"
    fi
    if [ "$is_search_tool" = true ] && { [ "$has_directory_context" = "true" ] || [ -d "$file_path" ] || [[ "$file_path" == */ ]]; }; then
        emit_response "deny" "data.file.read" "oap.recursive_search_unsupported" "This hook cannot safely authorize recursive content searches; pass an explicit file path instead"
    fi
    if { [ "$TOOL_NORM" = "read_many_files" ] || [ "$TOOL_NORM" = "readmanyfiles" ]; } && [ "$read_has_glob" = "true" ]; then
        emit_response "deny" "data.file.read" "oap.glob_read_unsupported" "This hook cannot safely authorize glob-expanded reads; pass explicit file paths instead"
    fi
    if [ "$read_target_count" -gt 1 ]; then
        emit_response "deny" "data.file.read" "oap.multi_path_read_unsupported" "This hook can safely evaluate one read target at a time"
    fi
    if [ -z "$file_path" ]; then
        emit_response "deny" "data.file.read" "oap.missing_file_path" "File read tool did not provide a path that APort can evaluate"
    fi
    if [ -d "$file_path" ] || [[ "$file_path" == */ ]]; then
        emit_response "deny" "data.file.read" "oap.metadata_enumeration_unsupported" "This hook cannot safely authorize directory reads; use an explicit file-read tool instead"
    fi
    GUARDRAIL_TOOL="read"
}

map_image_read() {
    local source
    source="$(printf '%s' "$INPUT" | jq -r '.tool_input.source // .input.source // .args.source // ""' 2> /dev/null || true)"
    case "$source" in
        http://* | https://*)
            map_web
            ;;
        *)
            map_file_read
            ;;
    esac
}

map_file_write() {
    if aport_hook_payload_has_malformed_file_target_aliases "$INPUT"; then
        emit_response "deny" "data.file.write" "oap.invalid_tool_arguments" "File write path aliases must be strings"
    fi
    if aport_hook_payload_has_conflicting_file_target_aliases "$INPUT"; then
        emit_response "deny" "data.file.write" "oap.invalid_tool_arguments" "File write tool supplied conflicting path aliases"
    fi
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" file_write)"
    local file_path patch_paths patch_path_count patch_text patch_operation patch_content_length patch_size_line patch_add_bytes patch_delete_bytes patch_current_size patch_resulting_size
    file_path="$(printf '%s' "$CONTEXT_JSON" | jq -r '.file_path // ""' 2> /dev/null || true)"
    if [ "$TOOL_NORM" = "applypatch" ] || [ "$TOOL_NORM" = "apply_patch" ]; then
        patch_paths="$(aport_hook_extract_patch_paths "$INPUT")"
        patch_path_count="$(printf '%s' "$patch_paths" | jq -r 'if type == "array" then length else 0 end' 2> /dev/null || echo 0)"
        case "$patch_path_count" in
            "" | *[!0-9]*) patch_path_count=0 ;;
        esac
        if [ "$patch_path_count" -gt 1 ]; then
            emit_response "deny" "data.file.write" "oap.multi_path_write_unsupported" "This hook can safely evaluate one patch target at a time"
        fi
        if [ "$patch_path_count" -eq 1 ]; then
            file_path="$(printf '%s' "$patch_paths" | jq -r '.[0]' 2> /dev/null || true)"
            patch_text="$(printf '%s' "$INPUT" | jq -r '(.tool_input.command // .tool_input.patch // .command // .patch // "") | tostring' 2> /dev/null || true)"
            patch_operation="$(printf '%s\n' "$patch_text" | sed -n -E 's/^\*\*\* (Add|Update|Delete) File: .*/\1/p' | head -n 1 | tr '[:upper:]' '[:lower:]')"
            patch_content_length="$(printf '%s' "$patch_text" | LC_ALL=C wc -c | tr -d '[:space:]')"
            case "$patch_content_length" in
                "" | *[!0-9]*) patch_content_length=0 ;;
            esac
            patch_size_line="$(printf '%s\n' "$patch_text" | LC_ALL=C awk '
              BEGIN { add = 0; del = 0 }
              /^\+/ { add += length(substr($0, 2)) + 1; next }
              /^-/ { del += length(substr($0, 2)) + 1; next }
              END { printf "%d %d", add, del }
            ')"
            patch_add_bytes="${patch_size_line%% *}"
            patch_delete_bytes="${patch_size_line#* }"
            case "$patch_add_bytes" in "" | *[!0-9]*) patch_add_bytes=0 ;; esac
            case "$patch_delete_bytes" in "" | *[!0-9]*) patch_delete_bytes=0 ;; esac
            patch_resulting_size=""
            case "$patch_operation" in
                add)
                    patch_resulting_size="$patch_add_bytes"
                    ;;
                update)
                    patch_current_size="$(wc -c < "$file_path" 2> /dev/null | tr -d '[:space:]' || true)"
                    case "$patch_current_size" in "" | *[!0-9]*) patch_current_size="" ;; esac
                    if [ -n "$patch_current_size" ]; then
                        patch_resulting_size=$((patch_current_size + patch_add_bytes))
                        [ "$patch_resulting_size" -ge 0 ] 2> /dev/null || patch_resulting_size=""
                    fi
                    ;;
                delete)
                    patch_resulting_size=0
                    ;;
            esac
            if [ -n "$patch_resulting_size" ]; then
                CONTEXT_JSON="$(jq -n -c --arg path "$file_path" --arg operation "$patch_operation" --argjson content_length "$patch_add_bytes" --argjson resulting_content_length "$patch_resulting_size" '{file_path:$path, content_length:$content_length, resulting_content_length:$resulting_content_length, patch:true, patch_operation:$operation}')"
            else
                CONTEXT_JSON="$(jq -n -c --arg path "$file_path" --arg operation "$patch_operation" --argjson content_length "$patch_content_length" '{file_path:$path, content_length:$content_length, patch:true, patch_operation:$operation}')"
            fi
        fi
    fi
    if [ -z "$(printf '%s' "$CONTEXT_JSON" | jq -r '.file_path // ""' 2> /dev/null || true)" ]; then
        emit_response "deny" "data.file.write" "oap.missing_file_path" "File write tool did not provide a path that APort can evaluate"
    fi
    GUARDRAIL_TOOL="write"
}

map_web() {
    if aport_hook_payload_has_conflicting_web_target_aliases "$INPUT"; then
        emit_response "deny" "web.fetch" "oap.invalid_tool_arguments" "Web tool supplied conflicting URL or domain aliases"
    fi
    GUARDRAIL_TOOL="websearch"
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" web)"
}

map_codex_browser() {
    local browser_action

    if aport_hook_payload_has_conflicting_web_target_aliases "$INPUT"; then
        emit_response "deny" "web.browser" "oap.invalid_tool_arguments" "Browser tool supplied conflicting URL or domain aliases"
    fi
    if aport_hook_payload_has_conflicting_browser_action_aliases "$INPUT"; then
        emit_response "deny" "web.browser" "oap.invalid_tool_arguments" "Browser tool supplied conflicting action aliases"
    fi

    CONTEXT_JSON="$(aport_hook_browser_context_from_payload "$INPUT")"
    if [ "${APORT_GUARDRAIL_MODE:-local}" = "api" ]; then
        GUARDRAIL_TOOL="browser"
        return
    fi

    browser_action="$(printf '%s' "$CONTEXT_JSON" | jq -r '.action // ""' 2> /dev/null || true)"
    case "$browser_action" in
        navigate)
            GUARDRAIL_TOOL="browser"
            ;;
        *)
            emit_response "deny" "web.browser" "oap.interactive_browser_unsupported" "Codex browser action '$browser_action' is interactive; local APort can only authorize URL navigation metadata"
            ;;
    esac
}

map_codex_computer_use() {
    if aport_hook_payload_has_malformed_browser_action_aliases "$INPUT"; then
        emit_response "deny" "web.browser" "oap.invalid_tool_arguments" "Computer-use action aliases must be strings"
    fi
    if aport_hook_payload_has_conflicting_browser_action_aliases "$INPUT"; then
        emit_response "deny" "web.browser" "oap.invalid_tool_arguments" "Computer-use tool supplied conflicting action aliases"
    fi
    if ! aport_hook_payload_has_browser_action_evidence "$INPUT"; then
        emit_response "deny" "web.browser" "oap.missing_required_context" "Computer-use tool did not provide an explicit action that APort can evaluate"
    fi
    CONTEXT_JSON="$(aport_hook_browser_context_from_payload "$INPUT")"
    if [ "${APORT_GUARDRAIL_MODE:-local}" = "api" ]; then
        GUARDRAIL_TOOL="browser"
        return
    fi

    emit_response "deny" "web.browser" "oap.interactive_browser_unsupported" "Codex computer_use is interactive desktop/browser automation; APort cannot safely authorize it as a single web fetch"
}

map_codex_image_generation() {
    local image_context referenced_count

    if aport_hook_payload_has_conflicting_image_generation_aliases "$INPUT"; then
        emit_response "deny" "media.image.generate" "oap.invalid_tool_arguments" "Image generation tool supplied conflicting argument containers"
    fi

    image_context="$(printf '%s' "$INPUT" | jq -c --arg provider "${APORT_IMAGE_GENERATION_PROVIDER:-openai}" '
      def obj(v): if (v | type) == "object" then v elif (v | type) == "string" then (try (v | fromjson) catch {}) else {} end;
      def str_field($name; v):
        if v == null then ""
        elif (v | type) == "string" then v
        else error($name + " must be a string")
        end;
      def positive_int_field($name; v):
        if v == null then 1
        elif (v | type) == "number" and v > 0 and (v | floor) == v then v
        elif (v | type) == "string" and (v | test("^[1-9][0-9]*$")) then (v | tonumber)
        else error($name + " must be a positive integer")
        end;
      def nonnegative_int_field($name; v):
        if v == null then 0
        elif (v | type) == "number" and v >= 0 and (v | floor) == v then v
        elif (v | type) == "string" and (v | test("^[0-9]+$")) then (v | tonumber)
        else error($name + " must be a non-negative integer")
        end;
      def local_reference_count($ti):
        if (($ti | has("referenced_image_paths")) | not) or $ti.referenced_image_paths == null then 0
        elif ($ti.referenced_image_paths | type) == "array"
          and ($ti.referenced_image_paths | all(type == "string" and length > 0))
        then ($ti.referenced_image_paths | length)
        else error("referenced_image_paths must be an array of non-empty strings")
        end;
      def first_present($ti; $keys):
        reduce $keys[] as $key (null;
          if . != null then .
          elif ($ti | has($key)) and $ti[$key] != null then {key: $key, value: $ti[$key]}
          else null
          end
        );
      (obj(.tool_input) + obj(.input) + obj(.args)) as $raw_ti |
      ((obj($raw_ti.args) + obj($raw_ti.arguments)) + $raw_ti) as $ti |
      local_reference_count($ti) as $local_refs |
      nonnegative_int_field("num_last_images_to_include"; $ti.num_last_images_to_include) as $last_refs |
      (first_present($ti; ["n", "num_images", "output_count"])) as $output_count_field |
      {
        provider: $provider,
        prompt_length: (str_field("prompt"; $ti.prompt) | length),
        referenced_image_count: ($local_refs + $last_refs),
        local_referenced_image_count: $local_refs,
        output_count: positive_int_field(($output_count_field.key // "output_count"); $output_count_field.value),
        output_format: (str_field("output_format"; ($ti.output_format // $ti.format)) | if . == "" then "png" else ascii_downcase end)
      }
      + (if str_field("model"; $ti.model) != "" then {model: str_field("model"; $ti.model)} else {} end)
      + (if str_field("size"; $ti.size) != "" then {size: str_field("size"; $ti.size)} else {} end)
      + (if str_field("aspect_ratio"; $ti.aspect_ratio) != "" then {aspect_ratio: str_field("aspect_ratio"; $ti.aspect_ratio)} else {} end)
    ' 2> /dev/null || true)"
    if [ -z "$image_context" ]; then
        emit_response "deny" "media.image.generate" "oap.invalid_tool_arguments" "Image generation payload could not be parsed"
    fi
    referenced_count="$(printf '%s' "$image_context" | jq -r '.local_referenced_image_count // 0' 2> /dev/null || echo 0)"
    case "$referenced_count" in "" | *[!0-9]*) referenced_count=0 ;; esac
    if [ "$referenced_count" -gt 0 ]; then
        emit_response "deny" "media.image.generate" "oap.multi_policy_tool_unsupported" "Codex image generation with referenced local images needs both file-read and image-generation authorization; this hook cannot safely evaluate both in one decision"
    fi

    GUARDRAIL_TOOL="image.generate"
    CONTEXT_JSON="$(printf '%s' "$image_context" | jq -c 'del(.local_referenced_image_count)')"
}

map_mcp() {
    if aport_hook_payload_has_conflicting_mcp_routing_aliases "$INPUT"; then
        emit_response "deny" "mcp.tool.execute" "oap.invalid_tool_arguments" "MCP tool supplied conflicting server or tool aliases"
    fi
    GUARDRAIL_TOOL="mcp.tool"
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" mcp "$ORIGINAL_TOOL")"
    if [ "$(printf '%s' "$CONTEXT_JSON" | jq -r 'if .invalid_server == true then "true" else "false" end' 2> /dev/null || echo false)" = "true" ]; then
        emit_response "deny" "mcp.tool.execute" "oap.invalid_mcp_server" "MCP server contains ambiguous parser characters"
    fi
}

map_codex_plugin_install() {
    GUARDRAIL_TOOL="mcp.tool"
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" mcp "mcp:codex:request_plugin_install")"
}

map_session() {
    GUARDRAIL_TOOL="session.create"
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" session "$ORIGINAL_TOOL" "$FRAMEWORK")"
}

map_metadata_or_path_read() {
    local metadata_path
    metadata_path="$(printf '%s' "$INPUT" | jq -r '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def has_targets(v):
        if (v | type) == "array" then (v | map(select(type == "string" and length > 0)) | length > 0)
        elif (v | type) == "string" then (v | length > 0)
        elif v == null then false
        else true
        end;
      (obj(.tool_input) + obj(.input) + obj(.args)) as $ti |
      [
        $ti.file_path,
        $ti.path,
        $ti.dir_path,
        (if has_targets($ti.paths) then "__paths__" else null end),
        (if has_targets($ti.include) then "__include__" else null end),
        $ti.pattern,
        $ti.include_pattern
      ]
      | map(select(type == "string" and length > 0))
      | .[0] // ""
    ' 2> /dev/null || true)"
    if [ -n "$metadata_path" ]; then
        emit_response "deny" "data.file.read" "oap.metadata_enumeration_unsupported" "This hook cannot safely authorize path-scoped metadata enumeration; use an explicit file-read tool instead"
    else
        emit_response "deny" "data.file.read" "oap.missing_file_path" "Metadata tool did not provide a path that APort can evaluate"
    fi
}

has_mcp_context() {
    printf '%s' "$INPUT" | jq -e '(.mcp_context | type) == "object" and (.mcp_context | length) > 0' > /dev/null 2>&1
}

# Codex write_stdin submits keystrokes into a session started by exec_command or unified_exec. When that
# session is an interactive shell, the keystrokes ARE a new command: grouping write_stdin with the
# bookkeeping tools returned allow without ever looking at `chars`, so later shell input could bypass the
# allowlist. The characters are therefore evaluated as shell input against system.command.execute, the same
# policy that judged the command that opened the session.
#
# A non-empty chunk must end at a line boundary. A chunk that merely contains an earlier newline is still
# incomplete evidence if more non-terminated text follows it. Split fragments can bypass a blocklist if each
# piece is judged independently. Control-only chunks can also execute a command already buffered in the
# terminal. Without per-session terminal state, both cases fail closed.
#
# A line terminator is not enough when shell syntax explicitly continues the line. A trailing backslash or an
# open quote can join the next chunk into the same shell command. Without a trusted per-session shell parser
# and buffer, the only safe answer is to reject those continued chunks before policy evaluation.
aport_codex_stdin_has_shell_continuation() {
    local input="$1"
    local body tmp slash_count=0 state="" escaped=0 i ch next_ch newline cr

    newline='
'
    cr="$(printf '\r')"

    case "$input" in
        *"$newline" | *"$cr") ;;
        *) return 1 ;;
    esac

    body="$input"
    case "$body" in
        *"$newline") body="${body%"$newline"}" ;;
    esac
    case "$body" in
        *"$cr") body="${body%"$cr"}" ;;
    esac

    tmp="$body"
    while [ -n "$tmp" ] && [ "${tmp%\\}" != "$tmp" ]; do
        slash_count=$((slash_count + 1))
        tmp="${tmp%\\}"
    done
    if [ $((slash_count % 2)) -eq 1 ]; then
        return 0
    fi

    for ((i = 0; i < ${#body}; i++)); do
        ch="${body:i:1}"
        next_ch=""
        if [ $((i + 1)) -lt ${#body} ]; then
            next_ch="${body:i+1:1}"
        fi
        if [ "$escaped" -eq 1 ]; then
            escaped=0
            continue
        fi

        case "$state" in
            single)
                [ "$ch" = "'" ] && state=""
                ;;
            double)
                case "$ch" in
                    "\\")
                        if [ "$next_ch" = "$newline" ]; then
                            return 0
                        fi
                        escaped=1
                        ;;
                    '"') state="" ;;
                esac
                ;;
            *)
                case "$ch" in
                    "\\")
                        if [ "$next_ch" = "$newline" ]; then
                            return 0
                        fi
                        escaped=1
                        ;;
                    "'") state="single" ;;
                    '"') state="double" ;;
                esac
                ;;
        esac
    done

    [ -n "$state" ]
}

map_codex_write_stdin() {
    local stdin_chars stdin_command stdin_info stdin_meta stdin_state stdin_line_state stdin_blank_state stdin_sentinel newline cr
    newline='
'
    cr="$(printf '\r')"
    stdin_sentinel="APORT_STDIN_END_MARKER"
    if aport_hook_payload_has_conflicting_stdin_aliases "$INPUT"; then
        emit_response "deny" "system.command.execute" "oap.invalid_tool_arguments" "Codex write_stdin supplied conflicting input aliases"
    fi
    stdin_info="$(printf '%s' "$INPUT" | jq -c '
      def obj(v): if (v | type) == "object" then v elif (v | type) == "string" then (try (v | fromjson) catch {}) else {} end;
      def root_input_value:
        if (.input | type) != "string" then null
        elif (try ((.input | fromjson | type) == "object") catch false) then null
        else .input
        end;
      def argument_containers:
        [
          obj(.tool_input),
          obj(.input),
          obj(.args),
          obj(obj(.tool_input).args),
          obj(obj(.tool_input).arguments),
          obj(obj(.input).args),
          obj(obj(.input).arguments),
          obj(obj(.args).args),
          obj(obj(.args).arguments)
        ];
      . as $root |
      [
        $root.chars,
        root_input_value,
        $root.text,
        $root.data,
        $root.stdin,
        ($root | argument_containers[] | .chars, .input, .text, .data, .stdin)
      ]
      | map(select(type == "string"))
      | (.[0] // "") as $s |
      {
        chars: $s,
        meta: [
          (if $s == "" then "empty" else "nonempty" end),
          (if ($s | test("[\r\n]$")) then "line" else "partial" end),
          (if (($s | gsub("[ \t\r\n]"; "") | length) > 0) then "nonblank" else "blank" end)
        ]
      }
    ' 2> /dev/null || printf '{"chars":"","meta":["empty","partial","blank"]}')"
    stdin_chars="$(printf '%s' "$stdin_info" | jq -r '(.chars // "") + "APORT_STDIN_END_MARKER"' 2> /dev/null || true)"
    stdin_chars="${stdin_chars%"$stdin_sentinel"}"
    stdin_meta="$(printf '%s' "$stdin_info" | jq -r '(.meta // ["empty","partial","blank"]) | join("|")' 2> /dev/null || printf 'empty|partial|blank')"
    IFS='|' read -r stdin_state stdin_line_state stdin_blank_state <<< "$stdin_meta"
    # Nothing typed is nothing to judge; the session itself was already authorized.
    if [ "$stdin_state" = "empty" ]; then
        emit_response "allow" "" "" ""
    fi
    if [ "$stdin_line_state" != "line" ]; then
        emit_response "deny" "system.command.execute" "oap.partial_stdin_unsupported" "Codex write_stdin sent partial terminal input; APort cannot authorize split shell input without session buffering"
    fi
    if aport_codex_stdin_has_shell_continuation "$stdin_chars"; then
        emit_response "deny" "system.command.execute" "oap.partial_stdin_unsupported" "Codex write_stdin sent shell continuation syntax; APort cannot authorize split shell input without session buffering"
    fi
    if [ "$stdin_blank_state" != "nonblank" ]; then
        emit_response "deny" "system.command.execute" "oap.partial_stdin_unsupported" "Codex write_stdin sent only terminal control characters; APort cannot prove no buffered shell command will execute"
    fi
    GUARDRAIL_TOOL="bash"
    stdin_command="$stdin_chars"
    case "$stdin_command" in
        *"$newline") stdin_command="${stdin_command%"$newline"}" ;;
    esac
    case "$stdin_command" in
        *"$cr") stdin_command="${stdin_command%"$cr"}" ;;
    esac
    CONTEXT_JSON="$(jq -nc --arg command "$stdin_command" '{command: $command}')"
    if aport_is_reentrant_guardrail_command "$stdin_command" "$ROOT_DIR"; then
        emit_response "allow" "" "" ""
    fi
}

map_goose_text_editor() {
    local editor_command
    editor_command="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .input.command // .args.command // ""' 2> /dev/null || true)"
    editor_command="$(aport_hook_tool_name_normalize "$editor_command")"
    case "$editor_command" in
        view | read | open)
            map_file_read
            ;;
        create | write | edit | insert | str_replace | strreplace | undo_edit | undoedit)
            map_file_write
            ;;
        "")
            emit_response "deny" "hook.tool.map" "oap.missing_editor_command" "Goose text editor payload did not include an editor command"
            ;;
        *)
            emit_response "deny" "hook.tool.map" "oap.unknown_editor_command" "Unknown Goose text editor command: $editor_command"
            ;;
    esac
}

case "$FRAMEWORK" in
    codex)
        case "$TOOL_NORM" in
            bash | shell | exec | execcommand | exec_command | unifiedexec | unified_exec | localshell | local_shell | containerexec | container_exec | jsrepl | js_repl | codemodeexec | code_mode_exec)
                map_shell
                ;;
            applypatch | apply_patch | write | edit | multiedit | notebookedit | delete | strreplace | str_replace)
                map_file_write
                ;;
            read | readfile | read_file | viewimage | view_image | grep | grepsearch | grep_search | grepfiles | grep_files)
                map_file_read
                ;;
            webfetch | web_fetch | websearch | web_search | webrun | web_run | web.run | openurl | open_url | fetchurl | fetch_url | httprequest | http_request)
                map_web
                ;;
            browser | browse)
                map_codex_browser
                ;;
            computeruse | computer_use)
                map_codex_computer_use
                ;;
            image_gen.imagegen | image_genimagegen | imagegen | image_generate | imagegeneration | image_generation)
                map_codex_image_generation
                ;;
            glob | list | ls | lsp | listdir | list_dir)
                map_metadata_or_path_read
                ;;
            writestdin | write_stdin)
                map_codex_write_stdin
                ;;
            memories.add_ad_hoc_note)
                emit_response "deny" "hook.tool.map" "oap.unrepresentable_tool" "Codex persistent memory writes are not representable by the current APort hook policy"
                ;;
            todoread | toolsearch | tool_search | toolsearchtool | tool_search_tool | tool_search.tool_search_tool | updateplan | update_plan | requestuserinput | request_user_input | requestuserinputasync | request_user_input_async | sendmessagetouserasync | send_message_to_user_async | requestpermissions | request_permissions | wait | waitforenvironment | wait_for_environment | getcontextremaining | get_context_remaining | newcontext | new_context | clock.curr_time | clock.sleep | currtime | curr_time | sleep | getgoal | get_goal | creategoal | create_goal | updategoal | update_goal | memories.list | memories.read | memories.search | memory_read | memory_list | memory_search | skills.list | skills.read | listavailablepluginstoinstall | list_available_plugins_to_install | memoryoperators | memory_operators)
                # Session bookkeeping, plan/user prompts, provider-owned metadata, and bounded memory/skill
                # reads do not expose host file contents or perform external side effects through this hook.
                emit_response "allow" "" "" ""
                ;;
            requestplugininstall | request_plugin_install)
                map_codex_plugin_install
                ;;
            mcp__* | mcp:* | callmcptool | call_mcp_tool | readmcpresource | read_mcp_resource | readmcpresourcetool | read_mcp_resource_tool | listmcpresources | list_mcp_resources | listmcpresourcetemplates | list_mcp_resource_templates)
                map_mcp
                ;;
            agent | task | subagent | subagentstart | subagent_start | sendmessage | send_message | collaboration.sendmessage | collaboration.send_message | followuptask | followup_task | collaboration.followuptask | collaboration.followup_task | waitagent | wait_agent | collaboration.waitagent | collaboration.wait_agent | interruptagent | interrupt_agent | collaboration.interruptagent | collaboration.interrupt_agent | spawnagent | spawn_agent | collaboration.spawnagent | collaboration.spawn_agent | sendinput | send_input | collaboration.sendinput | collaboration.send_input | closeagent | close_agent | collaboration.closeagent | collaboration.close_agent | resumeagent | resume_agent | collaboration.resumeagent | collaboration.resume_agent | listagents | list_agents | collaboration.listagents | collaboration.list_agents | multi_agent_v1.spawn_agent | multi_agent_v1.send_input | multi_agent_v1.resume_agent | multi_agent_v1.wait_agent | multi_agent_v1.close_agent | collaboration.create_channel | collaboration.get_channels | collaboration.list_threads | collaboration.search_posts | collaboration.read_thread | collaboration.read_post | collaboration.subscribe | collaboration.unsubscribe | collaboration.post)
                map_session
                ;;
            "")
                emit_response "deny" "hook.tool.map" "oap.missing_tool_name" "Codex $HOOK_EVENT payload did not include tool_name"
                ;;
            *)
                # An unmapped tool denies. Codex adds tools faster than this list is updated, but a name that
                # is not listed is a name nobody has decided the capability for, and the payload cannot decide
                # it: a `url` on a payment tool is not a web fetch. An operator who has reviewed their own
                # tool surface can set APORT_CODEX_TOOL_FALLBACK=on to route unmapped tools by payload shape,
                # and even then a payload with more than one effect-bearing field denies rather than having
                # one effect picked and the rest dropped.
                case "$(codex_payload_shape "$INPUT")" in
                    shell) map_shell ;;
                    web) map_web ;;
                    write) map_file_write ;;
                    read) map_file_read ;;
                    mixed)
                        # Same code and hard-failure handling as the conflicting-alias denials above: the
                        # payload is unusable as evidence, not merely unrecognised.
                        emit_response "deny" "hook.tool.map" "oap.invalid_tool_arguments" \
                            "Codex tool $ORIGINAL_TOOL carries more than one effect (command, URL or path); APort cannot authorize it by payload shape"
                        ;;
                    *) emit_response "deny" "hook.tool.map" "oap.unknown_tool" "Unknown Codex tool: $ORIGINAL_TOOL" ;;
                esac
                ;;
        esac
        ;;
    gemini-cli)
        if has_mcp_context; then
            map_mcp
        else
            case "$TOOL_NORM" in
                run_shell_command | runshellcommand | shell | bash)
                    map_shell
                    ;;
                write_file | writefile | replace | edit | edit_file | editfile)
                    map_file_write
                    ;;
                read_file | readfile | read_many_files | readmanyfiles)
                    map_file_read
                    ;;
                list_directory | listdirectory | glob | grep_search | grepsearch)
                    map_file_read
                    ;;
                web_fetch | webfetch | google_web_search | googlewebsearch)
                    map_web
                    ;;
                mcp__* | mcp:* | mcp_* | callmcptool | call_mcp_tool)
                    map_mcp
                    ;;
                save_memory | savememory | todo_write | todowrite | write_todos | writetodos | ask_user | askuser)
                    emit_response "allow" "" "" ""
                    ;;
                "")
                    emit_response "deny" "hook.tool.map" "oap.missing_tool_name" "Gemini CLI BeforeTool payload did not include tool_name"
                    ;;
                *)
                    emit_response "deny" "hook.tool.map" "oap.unknown_tool" "Unknown Gemini CLI tool: $ORIGINAL_TOOL"
                    ;;
            esac
        fi
        ;;
    goose)
        case "$TOOL_NORM" in
            developer__shell | shell | bash | exec)
                map_shell
                ;;
            developer__text_editor | text_editor)
                map_goose_text_editor
                ;;
            developer__write | developer__edit | write | edit)
                map_file_write
                ;;
            developer__tree | developer__read | read | tree)
                map_file_read
                ;;
            developer__read_image | read_image)
                map_image_read
                ;;
            developer__fetch | webfetch | web_fetch | browser | fetch)
                map_web
                ;;
            mcp__* | mcp:* | *__*)
                map_mcp
                ;;
            "")
                emit_response "deny" "hook.tool.map" "oap.missing_tool_name" "Goose PreToolUse payload did not include tool_name"
                ;;
            *)
                emit_response "deny" "hook.tool.map" "oap.unknown_tool" "Unknown Goose tool: $ORIGINAL_TOOL"
                ;;
        esac
        ;;
esac

if [ -z "$GUARDRAIL_TOOL" ]; then
    emit_response "deny" "hook.tool.map" "oap.unknown_tool" "No APort policy mapping for tool: $ORIGINAL_TOOL"
fi

HOOK_DECISION_FILE="${APORT_DECISION_FILE:-${OPENCLAW_DECISION_FILE:-}}"
if [ -n "$HOOK_DECISION_FILE" ]; then
    HOOK_DECISION_FILE="${HOOK_DECISION_FILE%.json}-$$.json"
    export APORT_DECISION_FILE="$HOOK_DECISION_FILE"
    export OPENCLAW_DECISION_FILE="$HOOK_DECISION_FILE"
    if [ -e "$HOOK_DECISION_FILE" ] && [ ! -f "$HOOK_DECISION_FILE" ]; then
        emit_response "deny" "hook.runtime" "oap.decision_state_unavailable" "APort decision state path is not a regular file" "hard"
    fi
    if ! rm -f "$HOOK_DECISION_FILE" 2> /dev/null; then
        emit_response "deny" "hook.runtime" "oap.decision_state_unavailable" "APort decision state path could not be reset before evaluation" "hard"
    fi
fi

set +e
trap - ERR
GUARDRAIL_OUTPUT="$("$GUARDRAIL" "$GUARDRAIL_TOOL" "$CONTEXT_JSON" 2>&1)"
GUARDRAIL_EXIT=$?
set -e
trap 'emit_crash_deny "$LINENO"' ERR

if [ -n "${DEBUG_APORT:-}" ] && [ -n "$GUARDRAIL_OUTPUT" ]; then
    aport_sanitize_display_text "$GUARDRAIL_OUTPUT" >&2
    printf '\n' >&2
fi

if [ "$GUARDRAIL_EXIT" -eq 0 ]; then
    aport_append_local_session_decision "$HOOK_DECISION_FILE" "$FRAMEWORK" "$INPUT" "$ORIGINAL_TOOL" "$GUARDRAIL_TOOL" "$CONTEXT_JSON" || true
    [ -n "$HOOK_DECISION_FILE" ] && rm -f "$HOOK_DECISION_FILE" 2> /dev/null || true
    emit_response "allow" "" "" ""
fi

REASON_CODE="$(aport_hook_reason_code "$HOOK_DECISION_FILE")"
REASON_MESSAGE="$(aport_hook_reason_message "$HOOK_DECISION_FILE")"
HAS_DECISION_FILE=0
if [ -n "$HOOK_DECISION_FILE" ] && [ -f "$HOOK_DECISION_FILE" ]; then
    HAS_DECISION_FILE=1
fi
[ -z "$REASON_CODE" ] && REASON_CODE="oap.denied"
[ -z "$REASON_MESSAGE" ] && REASON_MESSAGE="$GUARDRAIL_OUTPUT"
aport_append_local_session_decision "$HOOK_DECISION_FILE" "$FRAMEWORK" "$INPUT" "$ORIGINAL_TOOL" "$GUARDRAIL_TOOL" "$CONTEXT_JSON" || true
[ -n "$HOOK_DECISION_FILE" ] && rm -f "$HOOK_DECISION_FILE" 2> /dev/null || true
if [ "$HAS_DECISION_FILE" -ne 1 ]; then
    emit_response "deny" "$GUARDRAIL_TOOL" "oap.evaluator_failed" "$REASON_MESSAGE" "hard"
fi
if aport_hook_is_hard_failure_reason "$REASON_CODE"; then
    emit_response "deny" "$GUARDRAIL_TOOL" "$REASON_CODE" "$REASON_MESSAGE" "hard"
else
    emit_response "deny" "$GUARDRAIL_TOOL" "$REASON_CODE" "$REASON_MESSAGE" "policy"
fi

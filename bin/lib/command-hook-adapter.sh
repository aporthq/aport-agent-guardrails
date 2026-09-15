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
        notice="$(aport_format_guardrail_notice warn "$policy" "$code" "$message")"
        user_warning="$(aport_hook_format_user_warning "$policy" "$code" "$message")"
        # Some hosts do not surface allow-response warnings consistently. Keep
        # stderr human-readable and sanitized while returning allow semantics.
        aport_sanitize_display_text "$user_warning" >&2
        printf '\n' >&2
        aport_hook_build_response "allow" "$notice" "$user_warning" "$FRAMEWORK"
        exit 0
    fi

    notice="$(aport_format_guardrail_notice deny "$policy" "$code" "$message")"
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
        agent | task | subagent | subagentstart | subagent_start | sendmessage | send_message | collaboration.sendmessage | collaboration.send_message | followuptask | followup_task | collaboration.followuptask | collaboration.followup_task | waitagent | wait_agent | collaboration.waitagent | collaboration.wait_agent | interruptagent | interrupt_agent | collaboration.interruptagent | collaboration.interrupt_agent | spawnagent | spawn_agent | collaboration.spawnagent | collaboration.spawn_agent | sendinput | send_input | collaboration.sendinput | collaboration.send_input | closeagent | close_agent | collaboration.closeagent | collaboration.close_agent | resumeagent | resume_agent | collaboration.resumeagent | collaboration.resume_agent | listagents | list_agents | collaboration.listagents | collaboration.list_agents)
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

map_shell() {
    GUARDRAIL_TOOL="bash"
    if aport_hook_payload_has_malformed_shell_command_aliases "$INPUT"; then
        emit_response "deny" "system.command.execute" "oap.invalid_tool_arguments" "Shell command aliases must be strings"
    fi
    if aport_hook_payload_has_conflicting_shell_command_aliases "$INPUT"; then
        emit_response "deny" "system.command.execute" "oap.invalid_tool_arguments" "Shell tool supplied conflicting command aliases"
    fi
    CONTEXT_JSON="$(aport_hook_context_from_payload "$INPUT" shell)"
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
            bash | shell | exec | execcommand | exec_command | unifiedexec | unified_exec)
                map_shell
                ;;
            applypatch | apply_patch | write | edit | multiedit | notebookedit | delete | strreplace)
                map_file_write
                ;;
            read | readfile | read_file | viewimage | view_image | grep | grepsearch | grep_search)
                map_file_read
                ;;
            webfetch | web_fetch | websearch | web_search)
                map_web
                ;;
            glob | list | ls | lsp)
                map_metadata_or_path_read
                ;;
            todoread | toolsearch)
                emit_response "allow" "" "" ""
                ;;
            mcp__* | mcp:* | callmcptool | call_mcp_tool | readmcpresourcetool | read_mcp_resource_tool)
                map_mcp
                ;;
            agent | task | subagent | subagentstart | subagent_start | sendmessage | send_message | collaboration.sendmessage | collaboration.send_message | followuptask | followup_task | collaboration.followuptask | collaboration.followup_task | waitagent | wait_agent | collaboration.waitagent | collaboration.wait_agent | interruptagent | interrupt_agent | collaboration.interruptagent | collaboration.interrupt_agent | spawnagent | spawn_agent | collaboration.spawnagent | collaboration.spawn_agent | sendinput | send_input | collaboration.sendinput | collaboration.send_input | closeagent | close_agent | collaboration.closeagent | collaboration.close_agent | resumeagent | resume_agent | collaboration.resumeagent | collaboration.resume_agent | listagents | list_agents | collaboration.listagents | collaboration.list_agents)
                map_session
                ;;
            "")
                emit_response "deny" "hook.tool.map" "oap.missing_tool_name" "Codex $HOOK_EVENT payload did not include tool_name"
                ;;
            *)
                emit_response "deny" "hook.tool.map" "oap.unknown_tool" "Unknown Codex tool: $ORIGINAL_TOOL"
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

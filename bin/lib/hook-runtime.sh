#!/usr/bin/env bash
# Shared runtime helpers for framework hooks.
# shellcheck shell=bash

APORT_HOOK_STDIN_TIMEOUT="${APORT_HOOK_STDIN_TIMEOUT:-2}"
APORT_HOOK_STDIN_MAX_BYTES="${APORT_HOOK_STDIN_MAX_BYTES:-1048576}"
APORT_HOOK_STDIN_TOO_LARGE_SENTINEL="__APORT_HOOK_INPUT_TOO_LARGE__"

aport_read_stdin_with_timeout() {
    local LC_ALL=C
    local timeout="${1:-$APORT_HOOK_STDIN_TIMEOUT}"
    local input=""
    local chunk=""
    local max_bytes="${APORT_HOOK_STDIN_MAX_BYTES:-0}"
    local chunk_size="${APORT_HOOK_STDIN_CHUNK_BYTES:-4096}"

    if [ -t 0 ]; then
        printf '{}'
        return 0
    fi

    case "$max_bytes" in
        "" | *[!0-9]*) max_bytes=0 ;;
    esac
    case "$chunk_size" in
        "" | *[!0-9]*) chunk_size=4096 ;;
    esac
    if [ "$chunk_size" -lt 1 ]; then
        chunk_size=4096
    fi
    if [ "$max_bytes" -gt 0 ] && [ "$chunk_size" -gt $((max_bytes + 1)) ]; then
        chunk_size=$((max_bytes + 1))
    fi

    # Hook payloads are expected to be a single JSON object. Read bounded chunks
    # so one huge line cannot be buffered before the size cap is enforced.
    while IFS= read -r -t "$timeout" -n "$chunk_size" chunk || [ -n "$chunk" ]; do
        input="${input}${chunk}"
        if [ "$max_bytes" -gt 0 ] && [ "${#input}" -gt "$max_bytes" ]; then
            printf '%s' "$APORT_HOOK_STDIN_TOO_LARGE_SENTINEL"
            return 0
        fi
        chunk=""
        # macOS ships Bash 3.x, whose `read -t` rejects fractional values.
        # Keep the bounded read portable; EOF returns immediately in normal hook
        # invocations, while broken pipes are capped at one second after data.
        timeout="1"
    done

    printf '%s' "$input"
}

aport_extract_session_id() {
    local default_payload='{}'
    local payload="${1:-$default_payload}"
    if ! command -v jq > /dev/null 2>&1; then
        return 0
    fi
    printf '%s' "$payload" | jq -r '
        .session_id
        // .sessionId
        // .conversation_id
        // .conversationId
        // .transcript_path
        // .cwd
        // empty
    ' 2> /dev/null | head -n 1
}

aport_is_reentrant_guardrail_command() {
    local command_text="$1"
    local root_dir="$2"
    local first_token

    [ -n "$command_text" ] || return 1
    if command -v shell_command_has_unquoted_control_operator > /dev/null 2>&1; then
        shell_command_has_unquoted_control_operator "$command_text" && return 1
    else
        # Conservative fallback for callers that source this file without the
        # validation helpers. Reentrant bypass is only safe for one simple
        # guardrail command, never for background jobs or chained commands.
        case "$command_text" in
            *$'\n'* | *\;* | *'&'* | *'|'* | *'>'* | *'<'* | *'`'* | *'$('* | *'#'*)
                return 1
                ;;
        esac
    fi
    case "$command_text" in
        *$'\n'* | *\;* | *'&'* | *'|'* | *'>'* | *'<'* | *'`'* | *'$('* | *'#'*)
            return 1
            ;;
    esac
    first_token="$(printf '%s' "$command_text" | awk '{print $1}')"
    [ -n "$first_token" ] || return 1

    case "$first_token" in
        "$root_dir/bin/aport-guardrail.sh" | \
            "$root_dir/bin/aport-guardrail-bash.sh" | \
            "$root_dir/bin/aport-guardrail-api.sh" | \
            "$root_dir/bin/aport-guardrail-v2.sh")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

aport_hook_enforcement_mode() {
    local mode="${APORT_ENFORCEMENT_MODE:-${APORT_ENFORCEMENT:-${APORT_GUARDRAIL_ENFORCEMENT:-enforce}}}"
    mode="$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    case "$mode" in
        warn | report-only | audit-only | observe | observation)
            printf 'warn'
            ;;
        *)
            printf 'enforce'
            ;;
    esac
}

aport_hook_is_warn_mode() {
    [ "$(aport_hook_enforcement_mode)" = "warn" ]
}

aport_hook_is_hard_failure_reason() {
    case "${1:-}" in
        oap.evaluator_crash | \
            oap.evaluation_error | \
            oap.evaluator_failed | \
            oap.missing_dependency | \
            oap.passport_not_found | \
            oap.passport_invalid | \
            oap.passport_suspended | \
            oap.passport_version_mismatch | \
            oap.invalid_tool_name | \
            oap.missing_command | \
            oap.missing_file_path | \
            oap.invalid_file_path | \
            oap.command_chain_unsupported | \
            oap.command_injection_detected | \
            oap.multi_path_read_unsupported | \
            oap.glob_read_unsupported | \
            oap.recursive_search_unsupported | \
            oap.metadata_enumeration_unsupported | \
            oap.context_too_large | \
            oap.input_too_large | \
            oap.invalid_json | \
            oap.invalid_tool_arguments | \
            oap.unrepresentable_tool | \
            oap.interactive_browser_unsupported | \
            oap.invalid_limit | \
            oap.unsupported_limit | \
            oap.missing_required_context | \
            oap.invalid_url | \
            oap.domain_mismatch | \
            oap.session_state_unavailable | \
            oap.decision_state_unavailable | \
            oap.rate_state_unavailable)
            return 0
            ;;
    esac
    return 1
}

aport_hook_shell_override_is_trusted() {
    local shell_path="${1:-}"
    local shell_base resolved configured_real resolved_real

    [ -z "$shell_path" ] && return 0
    case "$shell_path" in
        *[$'\001'-$'\037'$'\177']* | *[[:space:]]* | *\;* | *'&'* | *'|'* | *'>'* | *'<'* | *'`'* | *'$('* | *'#'*)
            return 1
            ;;
    esac

    shell_base="${shell_path##*/}"
    case "$shell_base" in
        sh | bash | dash) ;;
        *) return 1 ;;
    esac

    case "$shell_path" in
        */*)
            configured_real="$shell_path"
            if command -v realpath > /dev/null 2>&1; then
                configured_real="$(realpath "$shell_path" 2> /dev/null || printf '%s' "$shell_path")"
            fi
            case "$configured_real" in
                /bin/sh | /bin/bash | /bin/dash | /usr/bin/sh | /usr/bin/bash | /usr/bin/dash)
                    return 0
                    ;;
            esac
            resolved="$(command -v "$shell_base" 2> /dev/null || true)"
            [ -n "$resolved" ] || return 1
            resolved_real="$resolved"
            if command -v realpath > /dev/null 2>&1; then
                resolved_real="$(realpath "$resolved" 2> /dev/null || printf '%s' "$resolved")"
            fi
            [ "$configured_real" = "$resolved_real" ] || return 1
            ;;
    esac
    return 0
}

aport_hook_policy_reference() {
    local app_url="${APORT_APP_URL:-https://aport.io}"
    app_url="${app_url%/}"

    if [ -n "${APORT_AGENT_ID:-}" ]; then
        printf 'Review or update the hosted passport: %s/passports?details=%s' "$app_url" "$APORT_AGENT_ID"
        return 0
    fi

    if [ -n "${PASSPORT_FILE:-}" ]; then
        printf 'Review or update the local passport file: %s' "$PASSPORT_FILE"
        return 0
    fi

    printf 'Review the APort setup for this framework: %s/quickstart' "$app_url"
}

aport_hook_framework_cli_name() {
    local framework="${1:-}"
    if [ -z "$framework" ] || [ "$framework" = "unknown" ]; then
        framework="$(aport_hook_detect_framework)"
    fi
    case "$framework" in
        claude | claude-code) printf 'claude-code' ;;
        cursor) printf 'cursor' ;;
        codex) printf 'codex' ;;
        gemini | gemini-cli) printf 'gemini' ;;
        goose) printf 'goose' ;;
        openclaw) printf 'openclaw' ;;
        langchain) printf 'langchain' ;;
        crewai) printf 'crewai' ;;
        deerflow) printf 'deerflow' ;;
        n8n) printf 'n8n' ;;
        *) printf '<framework>' ;;
    esac
}

aport_hook_enforce_reference() {
    local framework="${1:-}"
    local cli_framework cli_command
    cli_framework="$(aport_hook_framework_cli_name "$framework")"
    cli_command="${APORT_CLI_COMMAND:-npx @aporthq/aport-agent-guardrails}"
    printf 'Switch this harness to blocking mode: %s mode %s --enforcement=enforce' "$cli_command" "$cli_framework"
}

aport_hook_decision_reference() {
    local app_url="${APORT_APP_URL:-https://aport.io}"
    local decision_ref audit_ref session_ref data_dir
    app_url="${app_url%/}"

    if [ -n "${APORT_AGENT_ID:-}" ]; then
        printf 'View hosted decision/audit for this passport: %s/passports?details=%s' "$app_url" "$APORT_AGENT_ID"
        return 0
    fi

    decision_ref="${DECISION_FILE:-${APORT_DECISION_FILE:-${OPENCLAW_DECISION_FILE:-}}}"
    audit_ref="${AUDIT_LOG:-${APORT_AUDIT_LOG:-${OPENCLAW_AUDIT_LOG:-}}}"
    session_ref="${APORT_SESSION_DECISIONS_FILE:-}"
    if [ -n "$audit_ref" ] || [ -n "$session_ref" ] || [ -n "$decision_ref" ]; then
        if [ -z "$audit_ref" ] || [ -z "$session_ref" ]; then
            if [ -n "$audit_ref" ]; then
                data_dir="$(dirname "$audit_ref")"
            elif [ -n "$decision_ref" ]; then
                data_dir="$(dirname "$decision_ref")"
            else
                data_dir="."
            fi
            [ -n "$audit_ref" ] || audit_ref="${data_dir}/audit.log"
            [ -n "$session_ref" ] || session_ref="${data_dir}/session-decisions.jsonl"
        fi
        printf 'View local audit artifacts: %s; %s' "$audit_ref" "$session_ref"
        return 0
    fi

    if [ -n "${PASSPORT_FILE:-}" ]; then
        printf 'View local passport and adjacent audit files near: %s' "$PASSPORT_FILE"
        return 0
    fi

    printf 'Run APort status for this framework to find the latest decision and audit log'
}

aport_hook_warn_reference_text() {
    local framework="${1:-}"
    local separator="${2:-. }"
    local evidence action

    evidence="$(aport_sanitize_display_text "$(aport_hook_decision_reference)")"
    action="$(aport_sanitize_display_text "$(aport_hook_enforce_reference "$framework")")"
    printf 'Evidence: %s%sTo fail closed: %s' "$evidence" "$separator" "$action"
}

aport_sanitize_display_text() {
    local value="${1:-}"
    value="$(printf '%s' "$value" | tr '\r\n' '  ')"
    value="$(printf '%s' "$value" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177')"
    value="$(printf '%s' "$value" | sed -E \
        -e 's/(apk|aprt)_[A-Za-z0-9_-]+/[REDACTED_APORT_KEY]/g' \
        -e 's/(Bearer|Authorization: Bearer)[[:space:]]+[A-Za-z0-9._~+\/=-]+/\1 [REDACTED]/g' \
        -e 's/github_pat_[A-Za-z0-9_]+/[REDACTED_GITHUB_TOKEN]/g' \
        -e 's/gh[pousr]_[A-Za-z0-9_]+/[REDACTED_GITHUB_TOKEN]/g' \
        -e 's/AKIA[0-9A-Z]{16}/[REDACTED_AWS_KEY]/g' \
        -e 's/(password|passwd|pwd|token|secret|api[_-]?key)=([^[:space:]]+)/\1=[REDACTED]/g' \
        -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----[^-]*-----END [A-Z ]*PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g')"
    printf '%s' "$value" | cut -c 1-320
}

aport_hash_sha256() {
    local value
    if [ "$#" -gt 0 ]; then
        value="${1:-}"
    else
        value="$(cat)"
    fi
    if command -v shasum > /dev/null 2>&1; then
        printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
        return 0
    fi
    if command -v sha256sum > /dev/null 2>&1; then
        printf '%s' "$value" | sha256sum | awk '{print $1}'
        return 0
    fi
    printf ''
}

aport_persistable_session_context() {
    local guardrail_tool="$1"
    local default_context='{}'
    local context_json="${2:-$default_context}"
    local command_hash

    if ! printf '%s' "$context_json" | jq -e . > /dev/null 2>&1; then
        printf '{}'
        return 0
    fi

    case "$guardrail_tool" in
        bash)
            command_hash="$(printf '%s' "$context_json" | jq -r '.command // "" | tostring' 2> /dev/null | aport_hash_sha256)"
            printf '%s' "$context_json" | jq -c --arg command_hash "$command_hash" '
              def keep_value(v):
                v != null and v != "" and v != [];
              {
                command_length: ((.command // "") | tostring | length),
                command_hash_sha256: (if $command_hash == "" then null else $command_hash end),
                timeout: (.timeout // null),
                timeout_seconds: (.timeout_seconds // null),
                shell: (.shell // null),
                cwd: (.cwd // null)
              }
              | with_entries(select(keep_value(.value)))
            ' 2> /dev/null || printf '{}'
            ;;
        *)
            printf '%s' "$context_json" | jq -c . 2> /dev/null || printf '{}'
            ;;
    esac
}

aport_hook_reason_code() {
    local decision_file="${1:-}"
    if [ -n "$decision_file" ] && [ -f "$decision_file" ] && command -v jq > /dev/null 2>&1; then
        jq -r '.reasons[0].code // empty' "$decision_file" 2> /dev/null | head -n 1
        return 0
    fi
}

aport_hook_reason_message() {
    local decision_file="${1:-}"
    if [ -n "$decision_file" ] && [ -f "$decision_file" ] && command -v jq > /dev/null 2>&1; then
        jq -r '.reasons[0].message // empty' "$decision_file" 2> /dev/null | head -n 1
        return 0
    fi
}

aport_format_guardrail_notice() {
    local outcome="$1"
    local policy="$2"
    local reason_code="${3:-oap.denied}"
    local reason_message="${4:-}"
    local framework="${5:-}"
    local reference warn_refs
    reference="$(aport_hook_policy_reference)"
    warn_refs="$(aport_hook_warn_reference_text "$framework" ". ")"

    reason_code="$(aport_sanitize_display_text "$reason_code")"
    reason_message="$(aport_sanitize_display_text "$reason_message")"
    reference="$(aport_sanitize_display_text "$reference")"

    if [ "$outcome" = "warn" ]; then
        if [ -n "$reason_message" ] && [ "$reason_message" != "$reason_code" ]; then
            printf 'APort warning: report-only mode allowed a tool call that policy would have denied. Policy: %s. Reason: %s. Detail: %s. %s' "$policy" "$reason_code" "$reason_message" "$warn_refs"
        else
            printf 'APort warning: report-only mode allowed a tool call that policy would have denied. Policy: %s. Reason: %s. %s' "$policy" "$reason_code" "$warn_refs"
        fi
    else
        if [ -n "$reason_message" ] && [ "$reason_message" != "$reason_code" ]; then
            printf 'APort denied this tool call. Policy: %s. Reason: %s. Detail: %s. Review: %s' "$policy" "$reason_code" "$reason_message" "$reference"
        else
            printf 'APort denied this tool call. Policy: %s. Reason: %s. Review: %s' "$policy" "$reason_code" "$reference"
        fi
    fi
}

aport_append_local_session_decision() {
    local decision_file="$1"
    local framework="$2"
    local hook_payload="$3"
    local original_tool="$4"
    local guardrail_tool="$5"
    local context_json="$6"

    [ -n "$decision_file" ] && [ -f "$decision_file" ] || return 0
    command -v jq > /dev/null 2>&1 || return 0

    local data_dir jsonl session_id now tmp persisted_context
    data_dir="$(dirname "$decision_file")"
    jsonl="${APORT_SESSION_DECISIONS_FILE:-$data_dir/session-decisions.jsonl}"
    session_id="$(aport_extract_session_id "$hook_payload")"
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tmp="$(mktemp "${data_dir}/session-decision.XXXXXX" 2> /dev/null || mktemp)"
    persisted_context="$(aport_persistable_session_context "$guardrail_tool" "$context_json")"

    if jq -c \
        --arg recorded_at "$now" \
        --arg framework "$framework" \
        --arg session_id "$session_id" \
        --arg original_tool "$original_tool" \
        --arg guardrail_tool "$guardrail_tool" \
        --argjson context "$persisted_context" \
        '{recorded_at:$recorded_at,framework:$framework,session_id:(if $session_id == "" then null else $session_id end),original_tool:$original_tool,guardrail_tool:$guardrail_tool,context:$context,decision:.}' \
        "$decision_file" > "$tmp" 2> /dev/null; then
        cat "$tmp" >> "$jsonl" 2> /dev/null || true
        chmod 600 "$jsonl" 2> /dev/null || true
    fi
    rm -f "$tmp" 2> /dev/null || true
}

aport_hook_detect_framework() {
    local config_dir="${APORT_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-}}"
    local detected

    if [ -n "${APORT_HOOK_FRAMEWORK:-}" ]; then
        printf '%s' "$APORT_HOOK_FRAMEWORK"
        return 0
    fi

    if command -v aport_hook_known_config_owner > /dev/null 2>&1; then
        detected="$(aport_hook_known_config_owner "$config_dir")"
    else
        detected=""
    fi
    if [ -n "$detected" ]; then
        printf '%s' "$detected"
        return 0
    fi

    # Fallback: check common environment variables
    if [ -n "${CURSOR_IDE:-}" ] || [ -n "${CURSOR_USER_DATA_DIR:-}" ]; then
        printf 'cursor'
    elif [ -n "${CLAUDE_CODE:-}" ] || [ "$config_dir" = "$HOME/.claude" ]; then
        printf 'claude-code'
    elif [ "$config_dir" = "$HOME/.aport/goose" ]; then
        printf 'goose'
    else
        printf 'unknown'
    fi
}

aport_hook_format_user_warning() {
    local policy="$1"
    local reason_code="${2:-oap.denied}"
    local reason_message="${3:-}"
    local framework="${4:-}"
    local warn_refs

    reason_code="$(aport_sanitize_display_text "$reason_code")"
    reason_message="$(aport_sanitize_display_text "$reason_message")"
    warn_refs="$(aport_hook_warn_reference_text "$framework" $'\n')"

    if [ -n "$reason_message" ] && [ "$reason_message" != "$reason_code" ]; then
        printf '⚠️  APort Warning: report-only mode allowed an action that policy would normally block.\nPolicy: %s | Reason: %s\nDetail: %s\n%s' "$policy" "$reason_code" "$reason_message" "$warn_refs"
    else
        printf '⚠️  APort Warning: report-only mode allowed an action that policy would normally block.\nPolicy: %s | Reason: %s\n%s' "$policy" "$reason_code" "$warn_refs"
    fi
}

aport_hook_json_escape() {
    local value="${1:-}"

    if command -v tr > /dev/null 2>&1; then
        value="$(printf '%s' "$value" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177')"
    fi

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

aport_hook_build_response_claude_code() {
    local decision="$1"
    local reason="$2"
    local user_warning="${3:-}"
    local escaped_reason escaped_warning

    if ! command -v jq > /dev/null 2>&1; then
        escaped_reason="$(aport_hook_json_escape "$reason")"
        escaped_warning="$(aport_hook_json_escape "$user_warning")"
        if [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
            printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$escaped_warning" "$escaped_reason"
        elif [ "$decision" = "allow" ]; then
            printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$escaped_reason"
        else
            printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$escaped_reason"
        fi
        return 0
    fi

    if [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
        jq -n --arg reason "$reason" --arg warning "$user_warning" --arg event "PreToolUse" \
            '{systemMessage:$warning,hookSpecificOutput:{hookEventName:$event,permissionDecision:"allow",permissionDecisionReason:$reason}}'
    elif [ "$decision" = "allow" ]; then
        jq -n --arg reason "$reason" --arg event "PreToolUse" \
            '{hookSpecificOutput:{hookEventName:$event,permissionDecision:"allow",permissionDecisionReason:$reason}}'
    else
        jq -n --arg reason "$reason" --arg event "PreToolUse" \
            '{hookSpecificOutput:{hookEventName:$event,permissionDecision:"deny",permissionDecisionReason:$reason}}'
    fi
}

aport_hook_build_response_cursor() {
    local decision="$1"
    local reason="$2"
    local user_warning="${3:-}"
    local escaped_reason escaped_warning

    # Cursor docs define warning text on deny responses; allow-response warning
    # visibility varies by host surface. Keep these fields as best-effort context
    # while audit logs remain the source of truth for report-only decisions.

    if ! command -v jq > /dev/null 2>&1; then
        escaped_reason="$(aport_hook_json_escape "$reason")"
        escaped_warning="$(aport_hook_json_escape "$user_warning")"
        if [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
            # Best effort: some Cursor surfaces may not display allow warnings.
            printf '{"permission":"allow","allowed":true,"agentMessage":"%s","agent_message":"%s","user_message":"%s","reason":"%s"}\n' "$escaped_warning" "$escaped_warning" "$escaped_warning" "$escaped_reason"
        elif [ "$decision" = "allow" ]; then
            printf '{"permission":"allow","allowed":true,"reason":"%s"}\n' "$escaped_reason"
        else
            printf '{"permission":"deny","allowed":false,"agentMessage":"%s","agent_message":"%s","user_message":"%s","reason":"%s"}\n' "$escaped_reason" "$escaped_reason" "$escaped_reason" "$escaped_reason"
        fi
        return 0
    fi

    if [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
        # Best effort: some Cursor surfaces may not display allow warnings.
        jq -n -c --arg reason "$reason" --arg warning "$user_warning" \
            '{permission:"allow",allowed:true,agentMessage:$warning,agent_message:$warning,user_message:$warning,reason:$reason}'
    elif [ "$decision" = "allow" ]; then
        jq -n -c --arg reason "$reason" \
            '{permission:"allow",allowed:true,reason:$reason}'
    else
        jq -n -c --arg reason "$reason" \
            '{permission:"deny",allowed:false,agentMessage:$reason,agent_message:$reason,user_message:$reason,reason:$reason}'
    fi
}

aport_hook_build_response_goose() {
    local decision="$1"
    local reason="$2"
    local user_warning="${3:-}"
    local escaped_reason

    if [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
        reason="$user_warning"
    fi

    if [ "$decision" = "allow" ] && [ -z "$reason" ]; then
        return 0
    fi

    if ! command -v jq > /dev/null 2>&1; then
        escaped_reason="$(aport_hook_json_escape "$reason")"
        if [ "$decision" = "allow" ]; then
            printf '{"decision":"allow","reason":"%s"}\n' "$escaped_reason"
        else
            printf '{"decision":"block","reason":"%s"}\n' "$escaped_reason"
        fi
        return 0
    fi

    if [ "$decision" = "allow" ]; then
        jq -n -c --arg reason "$reason" '{decision:"allow",reason:$reason}'
    else
        jq -n -c --arg reason "$reason" '{decision:"block",reason:$reason}'
    fi
}

aport_hook_build_response_codex() {
    local decision="$1"
    local reason="$2"
    local user_warning="${3:-}"
    local event="${APORT_CODEX_HOOK_EVENT_NAME:-PreToolUse}"
    local escaped_reason escaped_warning escaped_event

    if ! command -v jq > /dev/null 2>&1; then
        escaped_reason="$(aport_hook_json_escape "$reason")"
        escaped_warning="$(aport_hook_json_escape "$user_warning")"
        escaped_event="$(aport_hook_json_escape "$event")"
        if [ "$event" = "PermissionRequest" ] && [ "$decision" = "deny" ]; then
            printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"%s"}}}\n' "$escaped_reason"
        elif [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
            printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$escaped_warning" "$escaped_event" "$escaped_reason"
        elif [ "$decision" = "allow" ]; then
            printf '{}\n'
        else
            printf '{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$escaped_event" "$escaped_reason"
        fi
        return 0
    fi

    if [ "$event" = "PermissionRequest" ] && [ "$decision" = "deny" ]; then
        jq -n --arg reason "$reason" \
            '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"deny",message:$reason}}}'
    elif [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
        jq -n --arg event "$event" --arg reason "$reason" --arg warning "$user_warning" \
            '{systemMessage:$warning,hookSpecificOutput:{hookEventName:$event,additionalContext:$reason}}'
    elif [ "$decision" = "allow" ]; then
        jq -n '{}'
    else
        jq -n --arg event "$event" --arg reason "$reason" \
            '{hookSpecificOutput:{hookEventName:$event,permissionDecision:"deny",permissionDecisionReason:$reason}}'
    fi
}

aport_hook_build_response_gemini_cli() {
    local decision="$1"
    local reason="$2"
    local user_warning="${3:-}"
    local escaped_reason escaped_warning

    if ! command -v jq > /dev/null 2>&1; then
        escaped_reason="$(aport_hook_json_escape "$reason")"
        escaped_warning="$(aport_hook_json_escape "$user_warning")"
        if [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
            printf '{"decision":"allow","systemMessage":"%s"}\n' "$escaped_warning"
        elif [ "$decision" = "allow" ]; then
            printf '{"decision":"allow"}\n'
        else
            printf '{"decision":"deny","reason":"%s"}\n' "$escaped_reason"
        fi
        return 0
    fi

    if [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
        jq -n -c --arg warning "$user_warning" '{decision:"allow",systemMessage:$warning}'
    elif [ "$decision" = "allow" ]; then
        jq -n -c '{decision:"allow"}'
    else
        jq -n -c --arg reason "$reason" '{decision:"deny",reason:$reason}'
    fi
}

aport_hook_build_response() {
    local decision="$1"
    local reason="$2"
    local user_warning="${3:-}"
    local framework="${4:-}"

    if [ -z "$framework" ]; then
        framework="$(aport_hook_detect_framework)"
    fi

    case "$framework" in
        claude-code)
            aport_hook_build_response_claude_code "$decision" "$reason" "$user_warning"
            ;;
        cursor)
            aport_hook_build_response_cursor "$decision" "$reason" "$user_warning"
            ;;
        goose)
            aport_hook_build_response_goose "$decision" "$reason" "$user_warning"
            ;;
        codex)
            aport_hook_build_response_codex "$decision" "$reason" "$user_warning"
            ;;
        gemini-cli | gemini)
            aport_hook_build_response_gemini_cli "$decision" "$reason" "$user_warning"
            ;;
        *)
            printf 'APort hook runtime error: unsupported hook response framework: %s\n' "$framework" >&2
            return 64
            ;;
    esac
}

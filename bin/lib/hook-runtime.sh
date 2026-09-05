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
    local payload="${1:-{}}"
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
    case "$command_text" in
        *$'\n'* | *\;* | *'&&'* | *'||'* | *'|'* | *'>'* | *'<'* | *'`'* | *'$('*)
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
    local reference
    reference="$(aport_hook_policy_reference)"

    reason_code="$(aport_sanitize_display_text "$reason_code")"
    reason_message="$(aport_sanitize_display_text "$reason_message")"
    reference="$(aport_sanitize_display_text "$reference")"

    if [ "$outcome" = "warn" ]; then
        printf 'APort warning: policy would have denied this tool call. Policy: %s. Reason: %s. Review: %s' "$policy" "$reason_code" "$reference"
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

    local data_dir jsonl session_id now tmp
    data_dir="$(dirname "$decision_file")"
    jsonl="${APORT_SESSION_DECISIONS_FILE:-$data_dir/session-decisions.jsonl}"
    session_id="$(aport_extract_session_id "$hook_payload")"
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tmp="$(mktemp "${data_dir}/session-decision.XXXXXX" 2> /dev/null || mktemp)"

    if jq -c \
        --arg recorded_at "$now" \
        --arg framework "$framework" \
        --arg session_id "$session_id" \
        --arg original_tool "$original_tool" \
        --arg guardrail_tool "$guardrail_tool" \
        --argjson context "$context_json" \
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
    else
        printf 'unknown'
    fi
}

aport_hook_format_user_warning() {
    local policy="$1"
    local reason_code="${2:-oap.denied}"
    local reason_message="${3:-}"
    local reference

    reason_code="$(aport_sanitize_display_text "$reason_code")"
    reason_message="$(aport_sanitize_display_text "$reason_message")"
    reference="$(aport_sanitize_display_text "$(aport_hook_policy_reference)")"

    if [ -n "$reason_message" ] && [ "$reason_message" != "$reason_code" ]; then
        printf '⚠️  APort Warning: This action would normally be blocked.\nPolicy: %s | Reason: %s\nDetail: %s\nReview: %s' "$policy" "$reason_code" "$reason_message" "$reference"
    else
        printf '⚠️  APort Warning: This action would normally be blocked.\nPolicy: %s | Reason: %s\nReview: %s' "$policy" "$reason_code" "$reference"
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
            printf '{"permission":"allow","allowed":true,"agent_message":"%s","user_message":"%s","reason":"%s"}\n' "$escaped_warning" "$escaped_warning" "$escaped_reason"
        elif [ "$decision" = "allow" ]; then
            printf '{"permission":"allow","allowed":true,"reason":"%s"}\n' "$escaped_reason"
        else
            printf '{"permission":"deny","allowed":false,"agent_message":"%s","user_message":"%s","reason":"%s"}\n' "$escaped_reason" "$escaped_reason" "$escaped_reason"
        fi
        return 0
    fi

    if [ "$decision" = "allow" ] && [ -n "$user_warning" ]; then
        # Best effort: some Cursor surfaces may not display allow warnings.
        jq -n -c --arg reason "$reason" --arg warning "$user_warning" \
            '{permission:"allow",allowed:true,agent_message:$warning,user_message:$warning,reason:$reason}'
    elif [ "$decision" = "allow" ]; then
        jq -n -c --arg reason "$reason" \
            '{permission:"allow",allowed:true,reason:$reason}'
    else
        jq -n -c --arg reason "$reason" \
            '{permission:"deny",allowed:false,agent_message:$reason,user_message:$reason,reason:$reason}'
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
        *)
            printf 'APort hook runtime error: unsupported hook response framework: %s\n' "$framework" >&2
            return 64
            ;;
    esac
}

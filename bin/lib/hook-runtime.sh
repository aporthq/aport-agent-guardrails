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

#!/usr/bin/env bash
# Shared runtime helpers for framework hooks.
# shellcheck shell=bash

APORT_HOOK_STDIN_TIMEOUT="${APORT_HOOK_STDIN_TIMEOUT:-2}"

aport_read_stdin_with_timeout() {
    local timeout="${1:-$APORT_HOOK_STDIN_TIMEOUT}"
    local input=""
    local line=""

    if [ -t 0 ]; then
        printf '{}'
        return 0
    fi

    # Hook payloads are expected to be a single JSON object. Keep reading while
    # data is immediately available, but never let an observational hook hang.
    while IFS= read -r -t "$timeout" line || [ -n "$line" ]; do
        if [ -n "$input" ]; then
            input="${input}
${line}"
        else
            input="$line"
        fi
        line=""
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

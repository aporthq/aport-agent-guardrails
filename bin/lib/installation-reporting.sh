#!/usr/bin/env bash
# Optional metadata bridge. No tool content or reporting credential in argv/env.
aport_report_decision() {
    [ "${APORT_GUARDRAIL_MODE:-local}" = api ] || return 0
    [ "${APORT_REPORTING_DISABLED:-0}" != 1 ] || return 0
    [ -d "${APORT_CONFIG_DIR:-}/.aport-reporting" ] || compgen -G "${APORT_CONFIG_DIR:-}/aport/installation-v1-*.json" > /dev/null || return 0
    command -v node > /dev/null 2>&1 || return 0
    command -v jq > /dev/null 2>&1 || return 0
    local reporter="${BASH_SOURCE[0]%/*}/../../src/installation-reporting/cli.js"
    # Select only the opaque server decision ID before crossing the process
    # boundary. The shared serializer rejects malformed IDs and extra fields.
    if [ -n "${1:-}" ] && [ -f "$1" ] && [ ! -L "$1" ]; then
        local call_key=""
        if [ "$2" = codex ]; then call_key="$(aport_reporting_call_key)"; fi
        jq -c --arg call_key "$call_key" '{decision_id: (.decision_id // null), allow: .allow, call_key: $call_key}' "$1" 2> /dev/null \
            | APORT_HOOK_FRAMEWORK="$2" APORT_ENFORCEMENT_MODE="$(aport_hook_enforcement_mode)" \
                node "$reporter" pre > /dev/null 2>&1 || true
    fi
    return 0
}

aport_reporting_call_key() {
    command -v shasum > /dev/null 2>&1 || return 0
    local ids
    ids="$(printf '%s' "${INPUT:-{}}" | jq -c '
      ([.tool_call_id, .toolCallId, .tool_use_id, .toolUseId] | map(select(. != null)) | unique) as $calls |
      ([.session_id, .sessionId] | map(select(. != null)) | unique) as $sessions |
      if ($calls | length) == 1 and ($calls[0] | type == "string" and length > 0 and length <= 256)
        and ($sessions | length) <= 1 and (($sessions[0] // "") | type == "string" and length <= 256)
      then [$sessions[0] // "", $calls[0]] else empty end
    ' 2> /dev/null)"
    [ -n "$ids" ] || return 0
    printf '%s' "$ids" | shasum -a 256 | awk '{print $1}'
}

aport_report_post_action() {
    [ "${APORT_GUARDRAIL_MODE:-local}" = api ] || return 0
    [ "${APORT_REPORTING_DISABLED:-0}" != 1 ] || return 0
    [ -d "${APORT_CONFIG_DIR:-}/.aport-reporting" ] || return 0
    command -v node > /dev/null 2>&1 || return 0
    local key reporter="${BASH_SOURCE[0]%/*}/../../src/installation-reporting/cli.js"
    key="$(aport_reporting_call_key)"
    [ -n "$key" ] || return 0
    jq -n -c --arg key "$key" '{call_key:$key}' \
        | node "$reporter" post > /dev/null 2>&1 || true
    return 0
}

aport_reporting_setup() {
    [ -n "${APORT_INSTALLATION_HANDOFF_FILE:-}" ] || [ -d "$1/.aport-reporting" ] || compgen -G "$1/aport/installation-v1-*.json" > /dev/null || return 0
    [ "${APORT_SELECTED_GUARDRAIL_MODE:-local}" = api ] || return 0
    local reporter="${BASH_SOURCE[0]%/*}/../../src/installation-reporting/cli.js"
    APORT_CONFIG_DIR="$1" APORT_HOOK_FRAMEWORK="$2" APORT_GUARDRAIL_MODE=api \
        APORT_AGENT_ID="$3" APORT_API_URL="${APORT_SELECTED_API_URL:-https://api.aport.io}" \
        APORT_ENFORCEMENT_MODE="${APORT_SELECTED_ENFORCEMENT:-enforce}" \
        node "$reporter" setup || echo "Reporting connection unresolved; setup remains complete."
    return 0
}

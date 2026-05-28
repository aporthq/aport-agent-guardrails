#!/usr/bin/env bash
# Anonymous hosted passport issuance for quick-start installs.
# Passport contents come from the server-side framework preset selected by framework.

if ! command -v log_info > /dev/null 2>&1; then
    _quick_hosted_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
    # shellcheck source=common.sh
    source "$_quick_hosted_lib_dir/common.sh"
fi

DEFAULT_APORT_ISSUE_URL="${DEFAULT_APORT_ISSUE_URL:-https://aport.id/api/issue}"

aport_quick_hosted_git_email() {
    if command -v git > /dev/null 2>&1; then
        git config user.email 2> /dev/null || git config --global user.email 2> /dev/null || true
    fi
}

aport_quick_hosted_issue_passport() {
    local framework="$1"
    local config_dir="$2"
    local noninteractive="${APORT_NONINTERACTIVE:-${CI:-}}"
    local issue_url="${APORT_ISSUE_URL_CLI:-${APORT_ISSUE_URL:-$DEFAULT_APORT_ISSUE_URL}}"
    local email="${APORT_OWNER_EMAIL_CLI:-${APORT_OWNER_EMAIL:-${APORT_EMAIL:-}}}"

    if [[ -z "$email" && -z "$noninteractive" ]]; then
        local detected_email
        detected_email="$(aport_quick_hosted_git_email)"
        read -r -p "  Email for passport claim${detected_email:+ [$detected_email]}: " email_input
        email="${email_input:-$detected_email}"
    fi

    if [[ -z "$email" ]]; then
        log_error "Hosted quick setup requires an email. Set APORT_OWNER_EMAIL or pass --email."
        exit 1
    fi

    if ! command -v curl > /dev/null 2>&1; then
        log_error "curl is required for hosted quick setup"
        exit 1
    fi
    if ! command -v node > /dev/null 2>&1; then
        log_error "node is required for hosted quick setup"
        exit 1
    fi

    local payload response_file status body parsed agent_id api_key api_key_id
    payload="$(node -e '
const [framework, email] = process.argv.slice(1);
process.stdout.write(JSON.stringify({
  framework: [framework],
  email,
  showInGallery: false,
}));
' "$framework" "$email")"

    response_file="$(mktemp "${TMPDIR:-/tmp}/aport-issue.XXXXXX")"
    status="$(curl -sS -o "$response_file" -w "%{http_code}" \
        -X POST "$issue_url" \
        -H "Content-Type: application/json" \
        --data "$payload")" || {
        rm -f "$response_file"
        log_error "Failed to reach APort issue endpoint: $issue_url"
        exit 1
    }
    body="$(cat "$response_file")"
    rm -f "$response_file"

    if [[ ! "$status" =~ ^2 ]]; then
        log_error "APort issue endpoint failed with HTTP $status: $body"
        exit 1
    fi

    parsed="$(node -e '
try {
  const data = JSON.parse(process.argv[1] || "{}");
  if (!data.agent_id || !data.api_key) process.exit(2);
  process.stdout.write(`${data.agent_id}\t${data.api_key}\t${data.api_key_id || ""}`);
} catch {
  process.exit(2);
}
' "$body")" || {
        log_error "APort issue endpoint returned an invalid quick setup response"
        exit 1
    }

    IFS=$'\t' read -r agent_id api_key api_key_id <<< "$parsed"
    if [[ -z "$agent_id" || -z "$api_key" ]]; then
        log_error "APort issue endpoint did not return agent_id and api_key"
        exit 1
    fi

    mkdir -p "$config_dir/aport"
    export APORT_AGENT_ID="$agent_id"
    export APORT_API_KEY="$api_key"
    export APORT_SELECTED_GUARDRAIL_MODE="api"
    log_info "Created hosted passport: $agent_id${api_key_id:+ (setup key: $api_key_id)}"
}

aport_maybe_configure_hosted_passport() {
    local framework="$1"
    local config_dir="$2"
    local noninteractive="${APORT_NONINTERACTIVE:-${CI:-}}"
    local selected_mode="${APORT_GUARDRAIL_MODE_CLI:-${APORT_GUARDRAIL_MODE:-}}"

    if [[ -n "${APORT_HOSTED_AGENT_ID_CLI:-}" ]]; then
        export APORT_AGENT_ID="$APORT_HOSTED_AGENT_ID_CLI"
        return 0
    fi

    if [[ -n "${APORT_AGENT_ID:-}" ]]; then
        return 0
    fi

    if [[ "$(printf '%s' "$selected_mode" | tr '[:upper:]' '[:lower:]')" = "local" ]]; then
        return 1
    fi

    if [[ -n "$noninteractive" ]]; then
        if [[ -n "${APORT_QUICK_HOSTED_CLI:-${APORT_QUICK_HOSTED:-}}" || -n "${APORT_OWNER_EMAIL_CLI:-${APORT_OWNER_EMAIL:-${APORT_EMAIL:-}}}" ]]; then
            aport_quick_hosted_issue_passport "$framework" "$config_dir"
            return 0
        fi
        return 1
    fi

    echo ""
    echo "  Passport setup:"
    echo "    1. Create hosted APort passport now (recommended)"
    echo "    2. Use existing hosted passport ID"
    echo "    3. Create local passport file"
    echo ""
    read -r -p "  Choice [1/2/3]: " passport_choice
    passport_choice="${passport_choice:-1}"

    case "$passport_choice" in
        1)
            aport_quick_hosted_issue_passport "$framework" "$config_dir"
            return 0
            ;;
        2)
            local agent_id_input api_key_input
            read -r -p "  Enter hosted agent_id from aport.io: " agent_id_input
            if [[ ! "$agent_id_input" =~ ^ap_[a-f0-9]{32}$ ]]; then
                log_error "Invalid agent_id format. Expected ap_[32 hex characters]."
                exit 1
            fi
            export APORT_AGENT_ID="$agent_id_input"
            read -r -s -p "  APort setup API key [optional]: " api_key_input
            echo ""
            if [[ -n "$api_key_input" ]]; then
                export APORT_API_KEY="$api_key_input"
            fi
            return 0
            ;;
        3)
            return 1
            ;;
        *)
            log_error "Invalid choice: $passport_choice"
            exit 1
            ;;
    esac
}

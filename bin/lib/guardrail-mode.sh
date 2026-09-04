#!/usr/bin/env bash
# Shared guardrail mode helpers for hook-based integrations (Cursor/Claude Code).
# Stores runtime mode under <config_dir>/aport/guardrail-mode.env so hooks can
# select local vs API evaluator consistently across sessions.

DEFAULT_APORT_API_URL="${DEFAULT_APORT_API_URL:-https://api.aport.io}"

is_aport_hosted_agent_id() {
    [[ "${1:-}" =~ ^(ap|apt|agt_inst|agt_tmpl)_[A-Za-z0-9_-]+$ ]]
}

parse_guardrail_mode_args() {
    APORT_GUARDRAIL_MODE_CLI="${APORT_GUARDRAIL_MODE_CLI:-}"
    APORT_GUARDRAIL_API_URL_CLI="${APORT_GUARDRAIL_API_URL_CLI:-}"
    APORT_HOSTED_AGENT_ID_CLI="${APORT_HOSTED_AGENT_ID_CLI:-}"
    APORT_QUICK_HOSTED_CLI="${APORT_QUICK_HOSTED_CLI:-}"
    APORT_OWNER_EMAIL_CLI="${APORT_OWNER_EMAIL_CLI:-}"
    APORT_ISSUE_URL_CLI="${APORT_ISSUE_URL_CLI:-}"
    APORT_ENFORCEMENT_CLI="${APORT_ENFORCEMENT_CLI:-}"
    APORT_FRAMEWORK_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode=*)
                APORT_GUARDRAIL_MODE_CLI="${1#--mode=}"
                ;;
            --mode)
                if [[ -z "${2:-}" ]]; then
                    echo "[aport] ERROR: --mode requires a value (local|api)" >&2
                    return 1
                fi
                APORT_GUARDRAIL_MODE_CLI="$2"
                shift
                ;;
            --api-url=*)
                APORT_GUARDRAIL_API_URL_CLI="${1#--api-url=}"
                ;;
            --api-url)
                if [[ -z "${2:-}" ]]; then
                    echo "[aport] ERROR: --api-url requires a value" >&2
                    return 1
                fi
                APORT_GUARDRAIL_API_URL_CLI="$2"
                shift
                ;;
            --enforcement=*)
                APORT_ENFORCEMENT_CLI="${1#*=}"
                ;;
            --enforcement)
                if [[ -z "${2:-}" ]]; then
                    echo "[aport] ERROR: --enforcement requires a value (enforce|warn)" >&2
                    return 1
                fi
                APORT_ENFORCEMENT_CLI="$2"
                shift
                ;;
            --warn | --report-only | --audit-only)
                APORT_ENFORCEMENT_CLI="warn"
                ;;
            --block | --enforce)
                APORT_ENFORCEMENT_CLI="enforce"
                ;;
            --quick-hosted | --hosted)
                APORT_QUICK_HOSTED_CLI="1"
                ;;
            --non-interactive | --noninteractive)
                export APORT_NONINTERACTIVE=1
                ;;
            --email=* | --owner-email=*)
                APORT_OWNER_EMAIL_CLI="${1#*=}"
                ;;
            --email | --owner-email)
                if [[ -z "${2:-}" ]]; then
                    echo "[aport] ERROR: $1 requires an email value" >&2
                    return 1
                fi
                APORT_OWNER_EMAIL_CLI="$2"
                shift
                ;;
            --issue-url=*)
                APORT_ISSUE_URL_CLI="${1#*=}"
                ;;
            --issue-url)
                if [[ -z "${2:-}" ]]; then
                    echo "[aport] ERROR: --issue-url requires a value" >&2
                    return 1
                fi
                APORT_ISSUE_URL_CLI="$2"
                shift
                ;;
            ap_* | apt_* | agt_inst_* | agt_tmpl_*)
                if ! is_aport_hosted_agent_id "$1"; then
                    echo "[aport] ERROR: Invalid hosted passport ID format: $1" >&2
                    return 1
                fi
                APORT_HOSTED_AGENT_ID_CLI="$1"
                ;;
            *)
                APORT_FRAMEWORK_ARGS+=("$1")
                ;;
        esac
        shift
    done

    export APORT_GUARDRAIL_MODE_CLI APORT_GUARDRAIL_API_URL_CLI APORT_HOSTED_AGENT_ID_CLI
    export APORT_QUICK_HOSTED_CLI APORT_OWNER_EMAIL_CLI APORT_ISSUE_URL_CLI
    export APORT_ENFORCEMENT_CLI
    return 0
}

normalize_aport_enforcement() {
    local value="${1:-enforce}"
    value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    case "$value" in
        "" | block | enforce | enforced | fail-closed)
            printf 'enforce'
            ;;
        warn | report-only | audit-only | observe | observation)
            printf 'warn'
            ;;
        *)
            return 1
            ;;
    esac
}

write_env_assignment() {
    local key="$1"
    local value="$2"
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        echo "[aport] ERROR: Refusing to write multiline guardrail mode value for $key" >&2
        return 1
    fi
    printf '%s=%s\n' "$key" "$value"
}

select_guardrail_mode() {
    local framework="$1"
    local hosted_agent_id="${2:-}"
    local noninteractive="${APORT_NONINTERACTIVE:-${CI:-}}"
    local selected_mode="${APORT_GUARDRAIL_MODE_CLI:-${APORT_GUARDRAIL_MODE:-}}"

    if [[ -n "$selected_mode" ]]; then
        selected_mode="$(echo "$selected_mode" | tr '[:upper:]' '[:lower:]')"
        case "$selected_mode" in
            local | api) ;;
            *)
                echo "[aport] ERROR: Unsupported --mode value: $selected_mode (expected local|api)" >&2
                return 1
                ;;
        esac
        if [[ "$selected_mode" = "local" && -n "$hosted_agent_id" ]]; then
            echo "[aport] ERROR: --mode=local cannot be combined with a hosted passport ID." >&2
            return 1
        fi
        APORT_SELECTED_GUARDRAIL_MODE="$selected_mode"
        export APORT_SELECTED_GUARDRAIL_MODE
        return 0
    fi

    if [[ -n "$hosted_agent_id" ]]; then
        APORT_SELECTED_GUARDRAIL_MODE="api"
        export APORT_SELECTED_GUARDRAIL_MODE
        return 0
    fi

    if [[ -n "$noninteractive" ]]; then
        # Keep non-interactive deterministic and offline-friendly unless explicitly overridden.
        APORT_SELECTED_GUARDRAIL_MODE="local"
        export APORT_SELECTED_GUARDRAIL_MODE
        return 0
    fi

    echo ""
    echo "  Guardrail mode:"
    echo "    1. local  - Use local evaluator (offline, no network)"
    echo "    2. api    - Use APort API evaluator"
    echo ""
    read -r -p "  Mode [1=local, 2=api]: " mode_choice
    mode_choice="${mode_choice:-2}"
    if [[ "$mode_choice" = "2" ]]; then
        APORT_SELECTED_GUARDRAIL_MODE="api"
    else
        APORT_SELECTED_GUARDRAIL_MODE="local"
    fi
    export APORT_SELECTED_GUARDRAIL_MODE
    return 0
}

select_guardrail_api_url() {
    local mode="$1"
    local noninteractive="${APORT_NONINTERACTIVE:-${CI:-}}"
    local configured_url="${APORT_GUARDRAIL_API_URL_CLI:-${APORT_API_URL:-$DEFAULT_APORT_API_URL}}"

    APORT_SELECTED_API_URL=""
    if [[ "$mode" != "api" ]]; then
        export APORT_SELECTED_API_URL
        return 0
    fi

    if [[ -n "$noninteractive" ]]; then
        APORT_SELECTED_API_URL="$configured_url"
        export APORT_SELECTED_API_URL
        return 0
    fi

    read -r -p "  APort API URL [$configured_url]: " api_url_input
    APORT_SELECTED_API_URL="${api_url_input:-$configured_url}"
    export APORT_SELECTED_API_URL
    return 0
}

select_guardrail_enforcement() {
    local selected="${APORT_ENFORCEMENT_CLI:-${APORT_ENFORCEMENT_MODE:-${APORT_ENFORCEMENT:-${APORT_GUARDRAIL_ENFORCEMENT:-enforce}}}}"
    local normalized
    if ! normalized="$(normalize_aport_enforcement "$selected")"; then
        echo "[aport] ERROR: Unsupported --enforcement value: $selected (expected enforce|warn)" >&2
        return 1
    fi
    APORT_SELECTED_ENFORCEMENT="$normalized"
    export APORT_SELECTED_ENFORCEMENT
    return 0
}

write_guardrail_mode_file() {
    local config_dir="$1"
    local mode="$2"
    local api_url="$3"
    local hosted_agent_id="${4:-}"
    local enforcement="${5:-${APORT_SELECTED_ENFORCEMENT:-${APORT_ENFORCEMENT_MODE:-${APORT_ENFORCEMENT:-${APORT_GUARDRAIL_ENFORCEMENT:-enforce}}}}}"

    local aport_dir="$config_dir/aport"
    local mode_file="$aport_dir/guardrail-mode.env"
    mkdir -p "$aport_dir"

    local normalized_enforcement
    normalized_enforcement="$(normalize_aport_enforcement "$enforcement" 2> /dev/null || printf 'enforce')"

    {
        write_env_assignment "APORT_GUARDRAIL_MODE" "$mode"
        write_env_assignment "APORT_ENFORCEMENT_MODE" "$normalized_enforcement"
        write_env_assignment "APORT_ENFORCEMENT" "$normalized_enforcement"
        if [[ "$mode" = "api" ]]; then
            write_env_assignment "APORT_API_URL" "${api_url:-$DEFAULT_APORT_API_URL}"
        fi
        if [[ -n "$hosted_agent_id" ]]; then
            write_env_assignment "APORT_AGENT_ID" "$hosted_agent_id"
        fi
        if [[ -n "${APORT_API_KEY:-}" ]]; then
            write_env_assignment "APORT_API_KEY" "$APORT_API_KEY"
        fi
    } > "$mode_file"
    chmod 600 "$mode_file" 2> /dev/null || true
    echo "$mode_file"
}

load_guardrail_mode_for_hooks() {
    local config_dir="$1"
    local mode_file="$config_dir/aport/guardrail-mode.env"
    local line key value
    [[ -f "$mode_file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ ! "$line" =~ ^[A-Z0-9_]+= ]]; then
            echo "[aport] ERROR: Unsafe guardrail mode entry in $mode_file" >&2
            return 1
        fi

        key="${line%%=*}"
        value="${line#*=}"
        if [[ "$value" == \"*\" && "$value" == *\" ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
            value="${value:1:${#value}-2}"
        fi

        case "$key" in
            APORT_GUARDRAIL_MODE)
                case "$value" in
                    local | api) ;;
                    *)
                        echo "[aport] ERROR: Invalid APORT_GUARDRAIL_MODE in $mode_file" >&2
                        return 1
                        ;;
                esac
                ;;
            APORT_ENFORCEMENT_MODE | APORT_ENFORCEMENT | APORT_GUARDRAIL_ENFORCEMENT)
                if ! value="$(normalize_aport_enforcement "$value")"; then
                    echo "[aport] ERROR: Invalid $key in $mode_file" >&2
                    return 1
                fi
                ;;
            APORT_API_URL)
                if [[ ! "$value" =~ ^https?://[A-Za-z0-9._~:/?#@%+=,-]+$ ]]; then
                    echo "[aport] ERROR: Invalid APORT_API_URL in $mode_file" >&2
                    return 1
                fi
                ;;
            APORT_AGENT_ID)
                if ! is_aport_hosted_agent_id "$value"; then
                    echo "[aport] ERROR: Invalid APORT_AGENT_ID in $mode_file" >&2
                    return 1
                fi
                ;;
            APORT_API_KEY)
                if [[ ! "$value" =~ ^apk_[A-Za-z0-9_-]+$ ]]; then
                    echo "[aport] ERROR: Invalid APORT_API_KEY in $mode_file" >&2
                    return 1
                fi
                ;;
            *)
                echo "[aport] ERROR: Unsupported guardrail mode key $key in $mode_file" >&2
                return 1
                ;;
        esac

        export "$key=$value"
    done < "$mode_file"
}

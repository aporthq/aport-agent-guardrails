#!/usr/bin/env bash
# Shared guardrail mode helpers for hook-based integrations (Cursor/Claude Code).
# Stores runtime mode under <config_dir>/aport/guardrail-mode.env so hooks can
# select local vs API evaluator consistently across sessions.

DEFAULT_APORT_API_URL="${DEFAULT_APORT_API_URL:-https://api.aport.io}"

parse_guardrail_mode_args() {
    APORT_GUARDRAIL_MODE_CLI="${APORT_GUARDRAIL_MODE_CLI:-}"
    APORT_GUARDRAIL_API_URL_CLI="${APORT_GUARDRAIL_API_URL_CLI:-}"
    APORT_HOSTED_AGENT_ID_CLI="${APORT_HOSTED_AGENT_ID_CLI:-}"
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
            ap_[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9])
                APORT_HOSTED_AGENT_ID_CLI="$1"
                ;;
            *)
                APORT_FRAMEWORK_ARGS+=("$1")
                ;;
        esac
        shift
    done

    export APORT_GUARDRAIL_MODE_CLI APORT_GUARDRAIL_API_URL_CLI APORT_HOSTED_AGENT_ID_CLI
    return 0
}

select_guardrail_mode() {
    local framework="$1"
    local hosted_agent_id="${2:-}"
    local noninteractive="${APORT_NONINTERACTIVE:-${CI:-}}"
    local selected_mode="${APORT_GUARDRAIL_MODE_CLI:-${APORT_GUARDRAIL_MODE:-}}"

    if [[ -n "$hosted_agent_id" ]]; then
        APORT_SELECTED_GUARDRAIL_MODE="api"
        export APORT_SELECTED_GUARDRAIL_MODE
        return 0
    fi

    if [[ -n "$selected_mode" ]]; then
        selected_mode="$(echo "$selected_mode" | tr '[:upper:]' '[:lower:]')"
        case "$selected_mode" in
            local | api) ;;
            *)
                echo "[aport] ERROR: Unsupported --mode value: $selected_mode (expected local|api)" >&2
                return 1
                ;;
        esac
        APORT_SELECTED_GUARDRAIL_MODE="$selected_mode"
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

write_guardrail_mode_file() {
    local config_dir="$1"
    local mode="$2"
    local api_url="$3"
    local hosted_agent_id="${4:-}"

    local aport_dir="$config_dir/aport"
    local mode_file="$aport_dir/guardrail-mode.env"
    mkdir -p "$aport_dir"

    {
        echo "APORT_GUARDRAIL_MODE=$mode"
        if [[ "$mode" = "api" ]]; then
            echo "APORT_API_URL=${api_url:-$DEFAULT_APORT_API_URL}"
        fi
        if [[ -n "$hosted_agent_id" ]]; then
            echo "APORT_AGENT_ID=$hosted_agent_id"
        fi
    } > "$mode_file"
    chmod 600 "$mode_file" 2> /dev/null || true
    echo "$mode_file"
}

load_guardrail_mode_for_hooks() {
    local config_dir="$1"
    local mode_file="$config_dir/aport/guardrail-mode.env"
    if [[ -f "$mode_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$mode_file"
        set +a
    fi
}

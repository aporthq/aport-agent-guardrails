#!/usr/bin/env bash
# Framework hook path normalization.
# GUI tools can inherit stale legacy OPENCLAW_* variables from another framework
# session. Hooks should default to their own framework config unless the caller
# explicitly opts into an external passport path.

aport_hook_expand_path() {
    local input="$1"
    printf '%s' "${input/#\~/$HOME}"
}

aport_hook_known_config_owner() {
    local config_dir
    config_dir="$(aport_hook_expand_path "$1")"

    case "$config_dir" in
        "$HOME/.claude" | "$HOME/.claude/"*) echo "claude-code" ;;
        "$HOME/.cursor" | "$HOME/.cursor/"*) echo "cursor" ;;
        "$HOME/.openclaw" | "$HOME/.openclaw/"*) echo "openclaw" ;;
        "$HOME/.aport/langchain" | "$HOME/.aport/langchain/"*) echo "langchain" ;;
        "$HOME/.aport/crewai" | "$HOME/.aport/crewai/"*) echo "crewai" ;;
        "$HOME/.aport/deerflow" | "$HOME/.aport/deerflow/"*) echo "deerflow" ;;
        "$HOME/.n8n" | "$HOME/.n8n/"*) echo "n8n" ;;
        *) echo "" ;;
    esac
}

aport_hook_prepare_framework_paths() {
    local framework="$1"
    local framework_config_dir="${2:-}"
    local default_config_dir="$3"
    local selected_config_dir owner passport_path decision_path audit_path

    if [ -n "$framework_config_dir" ]; then
        selected_config_dir="$framework_config_dir"
    else
        selected_config_dir="${APORT_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-}}"
        owner="$(aport_hook_known_config_owner "$selected_config_dir")"
        if [ -n "$owner" ] && [ "$owner" != "$framework" ]; then
            selected_config_dir="$default_config_dir"
        fi
    fi

    selected_config_dir="${selected_config_dir:-$default_config_dir}"
    selected_config_dir="$(aport_hook_expand_path "$selected_config_dir")"
    export APORT_CONFIG_DIR="$selected_config_dir"
    export OPENCLAW_CONFIG_DIR="$selected_config_dir"

    if [ -n "${APORT_PASSPORT_FILE:-${OPENCLAW_PASSPORT_FILE:-}}" ] && [ -z "${APORT_ALLOW_EXTERNAL_PASSPORT_FILE:-}" ]; then
        passport_path="$(aport_hook_expand_path "${APORT_PASSPORT_FILE:-${OPENCLAW_PASSPORT_FILE:-}}")"
        case "$passport_path" in
            "$APORT_CONFIG_DIR"/*)
                export APORT_PASSPORT_FILE="$passport_path"
                export OPENCLAW_PASSPORT_FILE="$passport_path"
                ;;
            *)
                unset APORT_PASSPORT_FILE
                unset OPENCLAW_PASSPORT_FILE
                ;;
        esac
    fi

    if [ -n "${APORT_ALLOW_EXTERNAL_PASSPORT_FILE:-}" ] && [ -n "${APORT_PASSPORT_FILE:-${OPENCLAW_PASSPORT_FILE:-}}" ]; then
        passport_path="$(aport_hook_expand_path "${APORT_PASSPORT_FILE:-${OPENCLAW_PASSPORT_FILE:-}}")"
        export APORT_PASSPORT_FILE="$passport_path"
        export OPENCLAW_PASSPORT_FILE="$passport_path"
    fi

    if [ -n "${APORT_DECISION_FILE:-${OPENCLAW_DECISION_FILE:-}}" ]; then
        decision_path="$(aport_hook_expand_path "${APORT_DECISION_FILE:-${OPENCLAW_DECISION_FILE:-}}")"
        case "$decision_path" in
            "$APORT_CONFIG_DIR"/*)
                export APORT_DECISION_FILE="$decision_path"
                export OPENCLAW_DECISION_FILE="$decision_path"
                ;;
            *)
                unset APORT_DECISION_FILE
                unset OPENCLAW_DECISION_FILE
                ;;
        esac
    fi

    if [ -n "${APORT_AUDIT_LOG:-${OPENCLAW_AUDIT_LOG:-}}" ]; then
        audit_path="$(aport_hook_expand_path "${APORT_AUDIT_LOG:-${OPENCLAW_AUDIT_LOG:-}}")"
        case "$audit_path" in
            "$APORT_CONFIG_DIR"/*)
                export APORT_AUDIT_LOG="$audit_path"
                export OPENCLAW_AUDIT_LOG="$audit_path"
                ;;
            *)
                unset APORT_AUDIT_LOG
                unset OPENCLAW_AUDIT_LOG
                ;;
        esac
    fi
}

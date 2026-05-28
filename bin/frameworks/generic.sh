#!/usr/bin/env bash
# Generic framework setup. Works for any framework that only needs:
#   1. Config dir + passport wizard
#   2. Framework-specific "next steps" text (from next-steps.d/<framework>.txt)
#
# Frameworks with custom logic (cursor, claude-code, openclaw) keep their own scripts.
# To add a new framework: create next-steps.d/<name>.txt and add to valid_frameworks
# in bin/agent-guardrails. No new shell script needed.

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/../lib" && pwd)"
FRAMEWORKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$LIB/common.sh"
# shellcheck source=../lib/passport.sh
source "$LIB/passport.sh"
# shellcheck source=../lib/runtime.sh
source "$LIB/runtime.sh"
# shellcheck source=../lib/config.sh
source "$LIB/config.sh"
# shellcheck source=../lib/guardrail-mode.sh
source "$LIB/guardrail-mode.sh"
# shellcheck source=../lib/quick-hosted.sh
source "$LIB/quick-hosted.sh"

framework="${APORT_FRAMEWORK:?APORT_FRAMEWORK must be set by the dispatcher}"
crewai_integration_mode="${APORT_CREWAI_INTEGRATION_MODE:-compat}"
hosted_agent_id=""

parse_guardrail_mode_args "$@"
FORWARD_ARGS=()
if [[ -n "${APORT_FRAMEWORK_ARGS+x}" ]]; then
    remaining_args=("${APORT_FRAMEWORK_ARGS[@]}")
else
    remaining_args=()
fi
while [[ ${#remaining_args[@]} -gt 0 ]]; do
    arg="${remaining_args[0]}"
    remaining_args=("${remaining_args[@]:1}")
    case "$arg" in
        --integration-mode=*)
            crewai_integration_mode="${arg#--integration-mode=}"
            ;;
        --integration-mode)
            if [[ ${#remaining_args[@]} -lt 1 ]]; then
                log_error "--integration-mode requires compat or native"
                exit 1
            fi
            crewai_integration_mode="${remaining_args[0]}"
            remaining_args=("${remaining_args[@]:1}")
            ;;
        ap_* | apt_* | agt_inst_* | agt_tmpl_*)
            if ! is_aport_hosted_agent_id "$arg"; then
                log_error "Invalid hosted passport ID format: $arg"
                exit 1
            fi
            hosted_agent_id="$arg"
            ;;
        *)
            FORWARD_ARGS+=("$arg")
            ;;
    esac
done

if [[ -n "${APORT_HOSTED_AGENT_ID_CLI:-}" ]]; then
    hosted_agent_id="$APORT_HOSTED_AGENT_ID_CLI"
fi

case "$crewai_integration_mode" in
    compat | native) ;;
    *)
        log_error "Unsupported CrewAI integration mode: $crewai_integration_mode"
        exit 1
        ;;
esac

if [[ "$framework" != "crewai" && "$crewai_integration_mode" != "compat" ]]; then
    log_error "--integration-mode is only supported for CrewAI"
    exit 1
fi

resolve_next_steps_file() {
    if [[ "$framework" == "crewai" ]]; then
        if [[ "$crewai_integration_mode" == "native" ]]; then
            echo "$FRAMEWORKS_DIR/next-steps.d/crewai-native.txt"
            return
        fi
    fi
    echo "$FRAMEWORKS_DIR/next-steps.d/$framework.txt"
}

_yaml_quote() {
    local value="${1//\'/\'\'}"
    printf "'%s'" "$value"
}

_config_replace_or_append() {
    local file="$1"
    local key="$2"
    local value="$3"
    local tmpfile

    tmpfile="$(mktemp "${file}.XXXXXX")"
    awk -v key="$key" -v value="$value" '
        BEGIN { done = 0 }
        $0 ~ "^[[:space:]]*" key ":" {
            if (!done) {
                print key ": " value
                done = 1
            }
            next
        }
        { print }
        END {
            if (!done) {
                print key ": " value
            }
        }
    ' "$file" > "$tmpfile" && mv "$tmpfile" "$file"
}

_config_remove_key() {
    local file="$1"
    local key="$2"
    local tmpfile

    tmpfile="$(mktemp "${file}.XXXXXX")"
    awk -v key="$key" '$0 !~ "^[[:space:]]*" key ":" { print }' "$file" > "$tmpfile" && mv "$tmpfile" "$file"
}

persist_python_framework_config() {
    local config_file="$1"
    local selected_mode="$2"
    local selected_api_url="$3"
    local hosted_id="$4"
    local local_passport_path="$5"

    touch "$config_file"
    _config_replace_or_append "$config_file" "framework" "$(_yaml_quote "$framework")"
    _config_replace_or_append "$config_file" "mode" "$selected_mode"

    if [[ "$selected_mode" == "api" ]]; then
        _config_replace_or_append "$config_file" "api_url" "$(_yaml_quote "${selected_api_url:-$DEFAULT_APORT_API_URL}")"
        if [[ -n "${APORT_API_KEY:-}" ]]; then
            _config_replace_or_append "$config_file" "api_key" "$(_yaml_quote "$APORT_API_KEY")"
        fi
        if [[ -n "$hosted_id" ]]; then
            _config_replace_or_append "$config_file" "agent_id" "$(_yaml_quote "$hosted_id")"
            _config_remove_key "$config_file" "passport_path"
        elif [[ -n "$local_passport_path" ]]; then
            _config_replace_or_append "$config_file" "passport_path" "$(_yaml_quote "$local_passport_path")"
            _config_remove_key "$config_file" "agent_id"
        fi
    else
        if [[ -n "$local_passport_path" ]]; then
            _config_replace_or_append "$config_file" "passport_path" "$(_yaml_quote "$local_passport_path")"
        fi
        _config_remove_key "$config_file" "agent_id"
        _config_remove_key "$config_file" "api_key"
    fi

    chmod 600 "$config_file" 2> /dev/null || true
}

run_setup() {
    log_info "Setting up APort guardrails for $framework..."
    config_dir="$(write_config_template "$framework")"
    mkdir -p "$config_dir/aport"
    chmod 700 "$config_dir/aport"
    install_runtime_tree "$config_dir"
    export APORT_FRAMEWORK="$framework"
    if [[ -n "$hosted_agent_id" ]]; then
        export APORT_AGENT_ID="$hosted_agent_id"
    fi
    if [[ "$framework" == "crewai" ]]; then
        log_info "CrewAI integration mode: $crewai_integration_mode"
    fi
    if [[ -n "$hosted_agent_id" ]]; then
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    elif aport_maybe_configure_hosted_passport "$framework" "$config_dir"; then
        hosted_agent_id="$APORT_AGENT_ID"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    elif ((${#FORWARD_ARGS[@]} > 0)); then
        run_passport_wizard "${FORWARD_ARGS[@]}"
    else
        run_passport_wizard
    fi
    # Harden permissions on passport (contains policy/capabilities)
    [ -f "$config_dir/aport/passport.json" ] && chmod 600 "$config_dir/aport/passport.json"
    log_info "Local runtime installed at: $config_dir/aport/runtime"
    select_guardrail_mode "$framework" "$hosted_agent_id"
    select_guardrail_api_url "$APORT_SELECTED_GUARDRAIL_MODE"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        export APORT_API_URL="${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    mode_file="$(write_guardrail_mode_file "$config_dir" "$APORT_SELECTED_GUARDRAIL_MODE" "${APORT_SELECTED_API_URL:-}" "$hosted_agent_id")"
    local_passport_path=""
    if [[ -f "$config_dir/aport/passport.json" ]]; then
        local_passport_path="$config_dir/aport/passport.json"
    fi
    persist_python_framework_config \
        "$config_dir/config.yaml" \
        "$APORT_SELECTED_GUARDRAIL_MODE" \
        "${APORT_SELECTED_API_URL:-}" \
        "$hosted_agent_id" \
        "$local_passport_path"
    log_info "Guardrail mode: $APORT_SELECTED_GUARDRAIL_MODE"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        log_info "Guardrail API URL: ${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    log_info "Mode config: $mode_file"

    # Print framework-specific next steps from data file
    next_steps="$(resolve_next_steps_file)"
    if [ -f "$next_steps" ]; then
        echo ""
        # Substitute $config_dir in the template
        sed "s|\$config_dir|$config_dir|g" "$next_steps"
        echo ""
    else
        echo ""
        echo "  Config written to: $config_dir"
        echo "  Install: pip install aport-agent-guardrails"
        echo "  See: docs/frameworks/$framework.md"
        echo ""
    fi

    # Check if Python package is installed (skip in CI/tests)
    if [[ -z "${APORT_SKIP_ADAPTER_CHECK:-}" ]]; then
        if command -v pip &> /dev/null || command -v pip3 &> /dev/null; then
            pip_cmd="pip"
            command -v pip3 &> /dev/null && pip_cmd="pip3"
            if ! $pip_cmd show aport-agent-guardrails &> /dev/null; then
                echo "[aport] NOTE: Python package not installed. Run:" >&2
                echo "  $pip_cmd install aport-agent-guardrails" >&2
                echo "  Or: uv add aport-agent-guardrails" >&2
            fi
        fi
    fi
}

run_setup

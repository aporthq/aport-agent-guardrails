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

framework="${APORT_FRAMEWORK:?APORT_FRAMEWORK must be set by the dispatcher}"
crewai_integration_mode="${APORT_CREWAI_INTEGRATION_MODE:-compat}"

FORWARD_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --integration-mode=*)
            crewai_integration_mode="${1#--integration-mode=}"
            ;;
        --integration-mode)
            if [[ $# -lt 2 ]]; then
                log_error "--integration-mode requires compat or native"
                exit 1
            fi
            crewai_integration_mode="$2"
            shift
            ;;
        *)
            FORWARD_ARGS+=("$1")
            ;;
    esac
    shift
done

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

run_setup() {
    log_info "Setting up APort guardrails for $framework..."
    config_dir="$(write_config_template "$framework")"
    mkdir -p "$config_dir/aport"
    chmod 700 "$config_dir/aport"
    install_runtime_tree "$config_dir"
    export APORT_FRAMEWORK="$framework"
    if [[ "$framework" == "crewai" ]]; then
        log_info "CrewAI integration mode: $crewai_integration_mode"
    fi
    if ((${#FORWARD_ARGS[@]} > 0)); then
        run_passport_wizard "${FORWARD_ARGS[@]}"
    else
        run_passport_wizard
    fi
    # Harden permissions on passport (contains policy/capabilities)
    [ -f "$config_dir/aport/passport.json" ] && chmod 600 "$config_dir/aport/passport.json"
    log_info "Local runtime installed at: $config_dir/aport/runtime"

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

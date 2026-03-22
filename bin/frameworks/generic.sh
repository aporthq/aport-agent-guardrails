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
# shellcheck source=../lib/config.sh
source "$LIB/config.sh"

framework="${APORT_FRAMEWORK:?APORT_FRAMEWORK must be set by the dispatcher}"

run_setup() {
    log_info "Setting up APort guardrails for $framework..."
    config_dir="$(write_config_template "$framework")"
    mkdir -p "$config_dir/aport"
    chmod 700 "$config_dir/aport"
    export APORT_FRAMEWORK="$framework"
    run_passport_wizard "$@"
    # Harden permissions on passport (contains policy/capabilities)
    [ -f "$config_dir/aport/passport.json" ] && chmod 600 "$config_dir/aport/passport.json"

    # Print framework-specific next steps from data file
    next_steps="$FRAMEWORKS_DIR/next-steps.d/$framework.txt"
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

run_setup "$@"

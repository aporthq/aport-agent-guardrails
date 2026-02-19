#!/usr/bin/env bash
# CrewAI framework installer/setup
# Config: ~/.aport/crewai/ or .aport/config.yaml

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$LIB/common.sh"
# shellcheck source=../lib/passport.sh
source "$LIB/passport.sh"
# shellcheck source=../lib/config.sh
source "$LIB/config.sh"

run_setup() {
    log_info "Setting up APort guardrails for CrewAI..."
    config_dir="$(write_config_template crewai)"
    mkdir -p "$config_dir/aport"
    export APORT_FRAMEWORK=crewai
    run_passport_wizard "$@"
    echo ""
    echo "  Next steps (CrewAI):"
    echo "  ───────────────────"
    echo "  1. Install the Python adapter (required for runtime enforcement):"
    echo "     pip install aport-agent-guardrails-crewai"
    echo "     aport-crewai setup"
    echo "  2. Config written to: $config_dir"
    echo "  3. Register the guardrail before running your crew:"
    echo ""
    echo "     from aport_guardrails_crewai import register_aport_guardrail"
    echo "     register_aport_guardrail()"
    echo "     crew.kickoff()"
    echo ""
    echo "  Or: @with_aport_guardrail on your entry point. See: docs/frameworks/crewai.md"
    echo ""
    # Fail loudly if Python available but adapter not installed (Issue 4); skip in CI/tests
    if [[ -z "${APORT_SKIP_ADAPTER_CHECK:-}" ]]; then
        if command -v pip &> /dev/null || command -v pip3 &> /dev/null; then
            pip_cmd="pip"
            command -v pip3 &> /dev/null && pip_cmd="pip3"
            if ! $pip_cmd show aport-agent-guardrails-crewai &> /dev/null; then
                echo "[aport] ERROR: Python adapter not installed. Run the following, then use your agent:" >&2
                echo "  $pip_cmd install aport-agent-guardrails-crewai" >&2
                echo "  aport-crewai setup" >&2
                exit 1
            fi
        fi
    fi
}

run_setup "$@"

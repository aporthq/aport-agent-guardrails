#!/usr/bin/env bash
# LangChain/LangGraph framework installer/setup
# Config: ~/.aport/langchain/ or .aport/config.yaml

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$LIB/common.sh"
# shellcheck source=../lib/passport.sh
source "$LIB/passport.sh"
# shellcheck source=../lib/config.sh
source "$LIB/config.sh"

run_setup() {
    log_info "Setting up APort guardrails for LangChain..."
    config_dir="$(write_config_template langchain)"
    mkdir -p "$config_dir/aport"
    export APORT_FRAMEWORK=langchain
    run_passport_wizard "$@"
    echo ""
    echo "  Next steps (LangChain):"
    echo "  ───────────────────────"
    echo "  1. Install the Python adapter (required for runtime enforcement):"
    echo "     pip install aport-agent-guardrails-langchain"
    echo "     aport-langchain setup"
    echo "  2. Config written to: $config_dir"
    echo "  3. Add to your agent:"
    echo ""
    echo "     from aport_guardrails_langchain import APortCallback"
    echo "     agent = initialize_agent(..., callbacks=[APortCallback()])"
    echo ""
    echo "  See: docs/frameworks/langchain.md"
    echo ""
    # Fail loudly if Python available but adapter not installed (Issue 4); skip in CI/tests
    if [[ -z "${APORT_SKIP_ADAPTER_CHECK:-}" ]]; then
        if command -v pip &> /dev/null || command -v pip3 &> /dev/null; then
            pip_cmd="pip"
            command -v pip3 &> /dev/null && pip_cmd="pip3"
            if ! $pip_cmd show aport-agent-guardrails-langchain &> /dev/null; then
                echo "[aport] ERROR: Python adapter not installed. Run the following, then use your agent:" >&2
                echo "  $pip_cmd install aport-agent-guardrails-langchain" >&2
                echo "  aport-langchain setup" >&2
                exit 1
            fi
        fi
    fi
}

run_setup "$@"

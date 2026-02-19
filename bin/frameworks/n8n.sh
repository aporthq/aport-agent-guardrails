#!/usr/bin/env bash
# n8n framework installer/setup
# Custom node + credentials; config in n8n credentials store.
#
# ⚠️  n8n custom node is NOT YET AVAILABLE. This script only runs the passport wizard
#     and writes config. No APort node is installed. See docs/frameworks/n8n.md and
#     DEPLOYMENT_READINESS.md for status.

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$LIB/common.sh"
# shellcheck source=../lib/passport.sh
source "$LIB/passport.sh"
# shellcheck source=../lib/config.sh
source "$LIB/config.sh"

run_setup() {
    echo "  APort n8n support: coming soon. This installer writes config only; custom node not yet available."
    echo ""
    log_info "Setting up APort guardrails for n8n..."
    config_dir="$(write_config_template n8n)"
    mkdir -p "$config_dir/aport"
    export APORT_FRAMEWORK=n8n
    run_passport_wizard "$@"
    echo ""
    echo "  Next steps (n8n):"
    echo "  ────────────────"
    echo "  1. Install custom node to ~/.n8n/custom/ (or use HTTP Request node to APort API)."
    echo "  2. In your workflow: add APort Guardrail node before action nodes; branch on allow/deny."
    echo "  3. Store agent_id or passport in n8n credentials."
    echo ""
    echo "  See: docs/frameworks/n8n.md"
    echo ""
}

run_setup "$@"

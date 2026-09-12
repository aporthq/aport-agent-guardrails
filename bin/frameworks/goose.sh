#!/usr/bin/env bash
# Goose framework installer/setup.
# Installs an APort Goose Open Plugin and stores APort state outside the plugin.

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$LIB/common.sh"
# shellcheck source=../lib/passport.sh
source "$LIB/passport.sh"
# shellcheck source=../lib/config.sh
source "$LIB/config.sh"
# shellcheck source=../lib/framework-setup.sh
source "$LIB/framework-setup.sh"
# shellcheck source=../lib/guardrail-mode.sh
source "$LIB/guardrail-mode.sh"
# shellcheck source=../lib/runtime.sh
source "$LIB/runtime.sh"
# shellcheck source=../lib/quick-hosted.sh
source "$LIB/quick-hosted.sh"

APORT_HOOK_TIMEOUT=10

run_setup() {
    parse_guardrail_mode_args "$@"

    local plugin_scope="project"
    local forward_args=()
    for arg in ${APORT_FRAMEWORK_ARGS[@]+"${APORT_FRAMEWORK_ARGS[@]}"}; do
        case "$arg" in
            --global)
                plugin_scope="global"
                ;;
            --project)
                plugin_scope="project"
                ;;
            *)
                forward_args+=("$arg")
                ;;
        esac
    done

    export APORT_GOOSE_CONFIG_DIR="${APORT_GOOSE_CONFIG_DIR:-${APORT_CONFIG_DIR:-$HOME/.aport/goose}}"

    local plugin_dir
    if [[ -n "${APORT_GOOSE_PLUGIN_DIR:-}" ]]; then
        plugin_dir="${APORT_GOOSE_PLUGIN_DIR/#\~/$HOME}"
    elif [[ "$plugin_scope" = "global" ]]; then
        plugin_dir="$HOME/.agents/plugins/aport-guardrail"
    else
        plugin_dir="$PWD/.agents/plugins/aport-guardrail"
    fi

    warn_if_framework_command_missing "goose" "Install Goose and restart it after setup so it discovers the APort Open Plugin."
    log_info "Setting up APort guardrails for Goose..."
    config_dir="$(ensure_aport_dir_secure goose)"
    export APORT_FRAMEWORK=goose

    local hosted_agent_id=""
    if [[ -n "${APORT_HOSTED_AGENT_ID_CLI:-}" ]]; then
        hosted_agent_id="$APORT_HOSTED_AGENT_ID_CLI"
        export APORT_AGENT_ID="$hosted_agent_id"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    elif aport_maybe_configure_hosted_passport "goose" "$config_dir"; then
        hosted_agent_id="$APORT_AGENT_ID"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    else
        # shellcheck source=../lib/agentsmd.sh
        source "$LIB/agentsmd.sh"
        setup_from_agentsmd_or_wizard ${forward_args[@]+"${forward_args[@]}"}
    fi

    [ -f "$config_dir/aport/passport.json" ] && chmod 600 "$config_dir/aport/passport.json"
    [[ -z "$hosted_agent_id" && -n "${APORT_AGENT_ID:-}" ]] && hosted_agent_id="$APORT_AGENT_ID"

    select_guardrail_mode "goose" "$hosted_agent_id"
    select_guardrail_api_url "$APORT_SELECTED_GUARDRAIL_MODE"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        export APORT_API_URL="${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    select_guardrail_enforcement
    MODE_FILE="$(write_guardrail_mode_file "$config_dir" "$APORT_SELECTED_GUARDRAIL_MODE" "${APORT_SELECTED_API_URL:-}" "$hosted_agent_id" "$APORT_SELECTED_ENFORCEMENT")"

    install_runtime_tree "$config_dir"

    local hook_script
    hook_script="$(resolve_hook_script_path "${APORT_GOOSE_HOOK_SCRIPT:-$config_dir/aport/runtime/bin/aport-goose-hook.sh}" "aport-goose-hook.sh" "$LIB")"
    if [[ -f "$hook_script" ]]; then
        hook_script="$(cd "$(dirname "$hook_script")" && pwd)/$(basename "$hook_script")"
    fi

    _write_goose_plugin "$plugin_dir" "$config_dir" "$hook_script" "$APORT_SELECTED_ENFORCEMENT"

    mkdir -p "$config_dir/aport"
    : >> "$config_dir/aport/audit.log"
    chmod 600 "$config_dir/aport/audit.log" 2> /dev/null || true

    echo ""
    echo "  Next steps (Goose):"
    echo "  ───────────────────"
    echo "  1. Plugin written to: $plugin_dir"
    echo "  2. Hook script: $hook_script"
    echo "  3. APort state: $config_dir/aport"
    echo "  4. Guardrail mode: $APORT_SELECTED_GUARDRAIL_MODE"
    echo "     Enforcement: $APORT_SELECTED_ENFORCEMENT"
    [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]] && echo "     API URL: ${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    echo "  5. Mode config: $MODE_FILE"
    echo "  6. Restart Goose so it loads the APort Open Plugin."
    echo ""
}

_write_goose_plugin() {
    local plugin_dir="$1"
    local config_dir="$2"
    local hook_script="$3"
    local enforcement="$4"
    local on_failure="block"

    refuse_symlink_path "$plugin_dir"
    refuse_symlink_path "$plugin_dir/plugin.json"
    refuse_symlink_path "$plugin_dir/hooks/hooks.json"
    refuse_symlink_path "$plugin_dir/scripts/aport-goose-hook.sh"
    mkdir -p "$plugin_dir/hooks" "$plugin_dir/scripts"

    node - "$plugin_dir" "$on_failure" "$APORT_HOOK_TIMEOUT" << 'NODE'
const fs = require("node:fs");
const path = require("node:path");
const [pluginDir, onFailure, timeoutText] = process.argv.slice(2);
const timeout = Number(timeoutText || 10);
const plugin = {
  name: "aport-guardrail",
  version: "1.0.0",
  description: "APort pre-action authorization for Goose"
};
const hooks = {
  hooks: {
    PreToolUse: [
      {
        hooks: [
          {
            type: "command",
            command: "${PLUGIN_ROOT}/scripts/aport-goose-hook.sh",
            timeout,
            on_failure: onFailure
          }
        ]
      }
    ]
  }
};
fs.writeFileSync(path.join(pluginDir, "plugin.json"), `${JSON.stringify(plugin, null, 2)}\n`);
fs.writeFileSync(path.join(pluginDir, "hooks", "hooks.json"), `${JSON.stringify(hooks, null, 2)}\n`);
NODE

    local wrapper="$plugin_dir/scripts/aport-goose-hook.sh"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -euo pipefail'
        printf 'export APORT_GOOSE_CONFIG_DIR=%q\n' "$config_dir"
        printf '%s\n' 'export APORT_CONFIG_DIR="${APORT_CONFIG_DIR:-$APORT_GOOSE_CONFIG_DIR}"'
        printf 'exec %q "$@"\n' "$hook_script"
    } > "$wrapper"
    chmod 700 "$wrapper"
}

run_setup "$@"

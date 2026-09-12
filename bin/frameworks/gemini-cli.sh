#!/usr/bin/env bash
# Gemini CLI framework installer/setup.
# Writes settings.json with a BeforeTool command hook pointing at APort.

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

APORT_HOOK_MARKER="__aport_hook"
APORT_HOOK_TIMEOUT_MS=10000

shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

run_setup() {
    parse_guardrail_mode_args "$@"

    local scope="project"
    local forward_args=()
    for arg in ${APORT_FRAMEWORK_ARGS[@]+"${APORT_FRAMEWORK_ARGS[@]}"}; do
        case "$arg" in
            --global)
                scope="global"
                ;;
            --project)
                scope="project"
                ;;
            *)
                forward_args+=("$arg")
                ;;
        esac
    done

    local hook_config_dir
    if [[ "$scope" = "global" ]]; then
        hook_config_dir="${APORT_GEMINI_CLI_HOOKS_DIR:-$HOME/.gemini}"
    else
        hook_config_dir="${APORT_GEMINI_CLI_HOOKS_DIR:-$PWD/.gemini}"
    fi
    hook_config_dir="${hook_config_dir/#\~/$HOME}"
    export APORT_GEMINI_CLI_CONFIG_DIR="${APORT_CONFIG_DIR:-${APORT_GEMINI_CLI_CONFIG_DIR:-$HOME/.aport/gemini-cli}}"

    warn_if_framework_command_missing "gemini" "Install Gemini CLI first if this machine has not been onboarded yet."
    log_info "Setting up APort guardrails for Gemini CLI..."
    config_dir="$(ensure_aport_dir_secure gemini-cli)"
    export APORT_FRAMEWORK=gemini-cli

    local hosted_agent_id=""
    if [[ -n "${APORT_HOSTED_AGENT_ID_CLI:-}" ]]; then
        hosted_agent_id="$APORT_HOSTED_AGENT_ID_CLI"
        export APORT_AGENT_ID="$hosted_agent_id"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    elif aport_maybe_configure_hosted_passport "gemini-cli" "$config_dir"; then
        hosted_agent_id="$APORT_AGENT_ID"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    else
        # shellcheck source=../lib/agentsmd.sh
        source "$LIB/agentsmd.sh"
        setup_from_agentsmd_or_wizard ${forward_args[@]+"${forward_args[@]}"}
    fi

    [ -f "$config_dir/aport/passport.json" ] && chmod 600 "$config_dir/aport/passport.json"
    [[ -z "$hosted_agent_id" && -n "${APORT_AGENT_ID:-}" ]] && hosted_agent_id="$APORT_AGENT_ID"

    select_guardrail_mode "gemini-cli" "$hosted_agent_id"
    select_guardrail_api_url "$APORT_SELECTED_GUARDRAIL_MODE"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        export APORT_API_URL="${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    select_guardrail_enforcement
    MODE_FILE="$(write_guardrail_mode_file "$config_dir" "$APORT_SELECTED_GUARDRAIL_MODE" "${APORT_SELECTED_API_URL:-}" "$hosted_agent_id" "$APORT_SELECTED_ENFORCEMENT")"

    install_runtime_tree "$config_dir"

    local hook_script hook_command settings_file
    hook_script="$(resolve_hook_script_path "${APORT_GEMINI_CLI_HOOK_SCRIPT:-$config_dir/aport/runtime/bin/aport-gemini-cli-hook.sh}" "aport-gemini-cli-hook.sh" "$LIB")"
    if [[ -f "$hook_script" ]]; then
        hook_script="$(cd "$(dirname "$hook_script")" && pwd)/$(basename "$hook_script")"
    fi
    hook_command="APORT_GEMINI_CLI_CONFIG_DIR=$(shell_quote "$config_dir") $(shell_quote "$hook_script")"
    settings_file="$hook_config_dir/settings.json"
    _write_gemini_settings "$settings_file" "$hook_command"
    chmod 600 "$settings_file"

    mkdir -p "$config_dir/aport"
    : >> "$config_dir/aport/audit.log"
    chmod 600 "$config_dir/aport/audit.log" 2> /dev/null || true

    echo ""
    echo "  Next steps (Gemini CLI):"
    echo "  ────────────────────────"
    echo "  1. Settings written to: $settings_file"
    echo "  2. Hook script: $hook_script"
    echo "  3. Guardrail mode: $APORT_SELECTED_GUARDRAIL_MODE"
    echo "     Enforcement: $APORT_SELECTED_ENFORCEMENT"
    [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]] && echo "     API URL: ${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    echo "  4. Mode config: $MODE_FILE"
    echo "  5. Restart Gemini CLI so the BeforeTool hook is picked up."
    echo ""
}

_write_gemini_settings() {
    local file="$1"
    local command="$2"
    refuse_symlink_path "$file"
    mkdir -p "$(dirname "$file")"

    if [[ -f "$file" ]] && ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$file" 2> /dev/null; then
        log_error "Refusing to overwrite invalid Gemini CLI settings JSON: $file"
        exit 1
    fi

    node - "$file" "$command" "$APORT_HOOK_MARKER" "$APORT_HOOK_TIMEOUT_MS" << 'NODE'
const fs = require("node:fs");
const [file, command, marker, timeoutText] = process.argv.slice(2);
const timeout = Number(timeoutText || 10000);
const existing = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
const isAportHook = (hook) =>
  hook?.[marker] === true || /(^|\s|\/)aport-gemini-cli-hook\.sh($|\s)/.test(String(hook?.command || ""));
const aportHook = {
  type: "command",
  name: "APort Guardrail",
  command,
  [marker]: true,
  timeout,
  description: "Check APort policy before Gemini CLI tool execution"
};
const upsert = (groups = []) => {
  const kept = groups
    .map((group) => ({ ...group, hooks: Array.isArray(group.hooks) ? group.hooks.filter((hook) => !isAportHook(hook)) : [] }))
    .filter((group) => group.hooks.length > 0);
  kept.push({ matcher: ".*", hooks: [aportHook] });
  return kept;
};
existing.hooks ||= {};
existing.hooks.BeforeTool = upsert(existing.hooks.BeforeTool);
fs.writeFileSync(file, `${JSON.stringify(existing, null, 2)}\n`, { mode: 0o600 });
NODE
}

run_setup "$@"

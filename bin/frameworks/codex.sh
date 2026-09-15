#!/usr/bin/env bash
# Codex CLI framework installer/setup.
# Writes Codex hooks.json and stores APort state in ~/.aport/codex by default.

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
APORT_HOOK_TIMEOUT=10

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
    if [[ "$scope" = "project" ]]; then
        hook_config_dir="${APORT_CODEX_HOOKS_DIR:-$PWD/.codex}"
    else
        hook_config_dir="${APORT_CODEX_HOOKS_DIR:-${CODEX_HOME:-$HOME/.codex}}"
    fi
    hook_config_dir="${hook_config_dir/#\~/$HOME}"
    export APORT_CODEX_CONFIG_DIR="${APORT_CODEX_CONFIG_DIR:-${APORT_CONFIG_DIR:-$HOME/.aport/codex}}"

    warn_if_framework_command_missing "codex" "Install Codex CLI first if this machine has not been onboarded yet."
    log_info "Setting up APort guardrails for Codex..."
    config_dir="$(ensure_aport_dir_secure codex)"
    export APORT_FRAMEWORK=codex

    local hosted_agent_id=""
    if [[ -n "${APORT_HOSTED_AGENT_ID_CLI:-}" ]]; then
        hosted_agent_id="$APORT_HOSTED_AGENT_ID_CLI"
        export APORT_AGENT_ID="$hosted_agent_id"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    elif aport_maybe_configure_hosted_passport "codex" "$config_dir"; then
        hosted_agent_id="$APORT_AGENT_ID"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    else
        # shellcheck source=../lib/agentsmd.sh
        source "$LIB/agentsmd.sh"
        setup_from_agentsmd_or_wizard ${forward_args[@]+"${forward_args[@]}"}
    fi

    secure_framework_passport_file_if_present "$config_dir"
    [[ -z "$hosted_agent_id" && -n "${APORT_AGENT_ID:-}" ]] && hosted_agent_id="$APORT_AGENT_ID"

    select_guardrail_mode "codex" "$hosted_agent_id"
    select_guardrail_api_url "$APORT_SELECTED_GUARDRAIL_MODE"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        export APORT_API_URL="${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    select_guardrail_enforcement
    MODE_FILE="$(write_guardrail_mode_file "$config_dir" "$APORT_SELECTED_GUARDRAIL_MODE" "${APORT_SELECTED_API_URL:-}" "$hosted_agent_id" "$APORT_SELECTED_ENFORCEMENT")"

    install_runtime_tree "$config_dir"

    local hook_script hook_command hooks_file
    hook_script="$(resolve_hook_script_path "${APORT_CODEX_HOOK_SCRIPT:-$config_dir/aport/runtime/bin/aport-codex-hook.sh}" "aport-codex-hook.sh" "$LIB")"
    if [[ -f "$hook_script" ]]; then
        hook_script="$(cd "$(dirname "$hook_script")" && pwd)/$(basename "$hook_script")"
    fi
    hook_command="APORT_CODEX_CONFIG_DIR=$(shell_quote "$config_dir") $(shell_quote "$hook_script")"
    hooks_file="$hook_config_dir/hooks.json"
    _write_codex_hooks "$hooks_file" "$hook_command"
    chmod 600 "$hooks_file"

    mkdir -p "$config_dir/aport"
    initialize_framework_audit_log "$config_dir"

    echo ""
    echo "  Next steps (Codex):"
    echo "  ───────────────────"
    echo "  1. Hooks config written to: $hooks_file"
    echo "  2. Hook script: $hook_script"
    echo "  3. Guardrail mode: $APORT_SELECTED_GUARDRAIL_MODE"
    echo "     Enforcement: $APORT_SELECTED_ENFORCEMENT"
    [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]] && echo "     API URL: ${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    echo "  4. Mode config: $MODE_FILE"
    echo "  5. Run /hooks in Codex and trust the APort hook definition."
    echo "  6. Bash, apply_patch/file edits, MCP, and local function tools are checked before execution."
    echo ""
}

_write_codex_hooks() {
    local file="$1"
    local command="$2"
    refuse_symlink_path "$file"
    mkdir -p "$(dirname "$file")"

    if [[ -f "$file" ]] && ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$file" 2> /dev/null; then
        log_error "Refusing to overwrite invalid Codex hooks JSON: $file"
        exit 1
    fi

    node - "$file" "$command" "$APORT_HOOK_MARKER" "$APORT_HOOK_TIMEOUT" << 'NODE'
const fs = require("node:fs");
const [file, command, marker, timeoutText] = process.argv.slice(2);
const timeout = Number(timeoutText || 10);
const existing = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
const isPlainObject = (value) => value && typeof value === "object" && !Array.isArray(value);
if (!isPlainObject(existing)) {
  console.error(`[aport] ERROR: Refusing to update Codex hooks JSON with non-object root: ${file}`);
  process.exit(1);
}
if (existing.hooks != null && !isPlainObject(existing.hooks)) {
  console.error(`[aport] ERROR: Refusing to update Codex hooks JSON with non-object hooks: ${file}`);
  process.exit(1);
}
const isAportHook = (hook) =>
  hook?.[marker] === true || /(^|\s|\/)aport-codex-hook\.sh($|\s)/.test(String(hook?.command || ""));
const aportHook = {
  type: "command",
  command,
  [marker]: true,
  timeout,
  statusMessage: "Checking APort policy"
};
const upsert = (groups = [], matcher = "*") => {
  const kept = groups
    .map((group) => ({ ...group, hooks: Array.isArray(group.hooks) ? group.hooks.filter((hook) => !isAportHook(hook)) : [] }))
    .filter((group) => group.hooks.length > 0);
  kept.push({ matcher, hooks: [aportHook] });
  return kept;
};
existing.description ||= "APort pre-action authorization for Codex.";
existing.hooks ||= {};
existing.hooks.PreToolUse = upsert(existing.hooks.PreToolUse, "*");
existing.hooks.PostToolUse = upsert(existing.hooks.PostToolUse, "*");
fs.writeFileSync(file, `${JSON.stringify(existing, null, 2)}\n`, { mode: 0o600 });
NODE
}

run_setup "$@"

#!/usr/bin/env bash
# Cursor framework installer/setup.
# Runs passport wizard and writes ~/.cursor/hooks.json pointing at the APort hook script.
# Same hook script works for Cursor and VS Code/Copilot-style hook payloads.

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
# shellcheck source=../lib/quick-hosted.sh
source "$LIB/quick-hosted.sh"

APORT_HOOK_MARKER="__aport_hook"
APORT_HOOK_TIMEOUT=10

run_setup() {
    parse_guardrail_mode_args "$@"

    log_info "Setting up APort guardrails for Cursor..."
    # Passport and data live under Cursor's config dir (~/.cursor/aport/ by default).
    config_dir="$(ensure_aport_dir_secure cursor)"

    export APORT_FRAMEWORK=cursor

    local hosted_agent_id=""
    if [[ -n "${APORT_HOSTED_AGENT_ID_CLI:-}" ]]; then
        hosted_agent_id="$APORT_HOSTED_AGENT_ID_CLI"
        export APORT_AGENT_ID="$hosted_agent_id"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    elif aport_maybe_configure_hosted_passport "cursor" "$config_dir"; then
        hosted_agent_id="$APORT_AGENT_ID"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    else
        # Check AGENTS.md for enforcement config — skip wizard if already configured
        # shellcheck source=../lib/agentsmd.sh
        source "$LIB/agentsmd.sh"
        setup_from_agentsmd_or_wizard "${APORT_FRAMEWORK_ARGS[@]}"
    fi

    # Harden permissions on passport (contains policy/capabilities)
    [ -f "$config_dir/aport/passport.json" ] && chmod 600 "$config_dir/aport/passport.json"

    if [[ -z "$hosted_agent_id" && -n "${APORT_AGENT_ID:-}" ]]; then
        hosted_agent_id="$APORT_AGENT_ID"
    fi

    select_guardrail_mode "cursor" "$hosted_agent_id"
    select_guardrail_api_url "$APORT_SELECTED_GUARDRAIL_MODE"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        export APORT_API_URL="${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    select_guardrail_enforcement
    MODE_FILE="$(write_guardrail_mode_file "$config_dir" "$APORT_SELECTED_GUARDRAIL_MODE" "${APORT_SELECTED_API_URL:-}" "$hosted_agent_id" "$APORT_SELECTED_ENFORCEMENT")"

    # Resolve absolute path to hook script (works from repo or npx package)
    HOOK_SCRIPT="$(resolve_hook_script_path "${APORT_CURSOR_HOOK_SCRIPT:-}" "aport-cursor-hook.sh" "$LIB")"
    if [ ! -f "$HOOK_SCRIPT" ]; then
        log_warn "Hook script not found at $HOOK_SCRIPT; hooks.json will reference it (create the file for hooks to work)."
    else
        HOOK_SCRIPT="$(cd "$(dirname "$HOOK_SCRIPT")" && pwd)/$(basename "$HOOK_SCRIPT")"
    fi

    # Write Cursor hooks config: beforeShellExecution and preToolUse run the same script
    CURSOR_HOOKS_DIR="${CURSOR_HOOKS_DIR:-$HOME/.cursor}"
    CURSOR_HOOKS_FILE="$CURSOR_HOOKS_DIR/hooks.json"
    mkdir -p "$CURSOR_HOOKS_DIR"

    # Merge with existing hooks.json if present; otherwise create new.
    if [ -f "$CURSOR_HOOKS_FILE" ]; then
        if ! command -v jq &> /dev/null; then
            log_error "Cannot merge existing Cursor hooks without jq: $CURSOR_HOOKS_FILE"
            exit 1
        fi
        if ! jq -e . "$CURSOR_HOOKS_FILE" > /dev/null 2>&1; then
            log_error "Refusing to overwrite invalid Cursor hooks JSON: $CURSOR_HOOKS_FILE"
            exit 1
        fi
        # Add APort hook to all supported lifecycle events.
        # Replace marker-owned or legacy APort entries, preserve non-APort hooks.
        NEW_HOOKS=$(jq -c --arg cmd "$HOOK_SCRIPT" --arg marker "$APORT_HOOK_MARKER" --argjson timeout "$APORT_HOOK_TIMEOUT" '
        def aport_hook($cmd; $marker; $timeout):
          { "command": $cmd, ($marker): true, "timeout": $timeout, "failClosed": true };
        def is_aport_cursor_hook:
          (.[$marker] == true) or (((.command // "") | tostring) | test("(^|/)aport-cursor-hook\\.sh($|[[:space:]])"));
        def upsert_hook:
          (. // []) | map(select(is_aport_cursor_hook | not)) | . + [aport_hook($cmd; $marker; $timeout)];
        .version = (.version // 1) |
        .hooks = (.hooks // {}) |
        .hooks.beforeShellExecution = ((.hooks.beforeShellExecution // []) | upsert_hook) |
        .hooks.preToolUse = ((.hooks.preToolUse // []) | upsert_hook) |
        .hooks.beforeMCPExecution = ((.hooks.beforeMCPExecution // []) | upsert_hook) |
        .hooks.beforeReadFile = ((.hooks.beforeReadFile // []) | upsert_hook) |
        .hooks.subagentStart = ((.hooks.subagentStart // []) | upsert_hook)
      ' "$CURSOR_HOOKS_FILE")
        cp "$CURSOR_HOOKS_FILE" "${CURSOR_HOOKS_FILE}.bak"
        echo "$NEW_HOOKS" > "$CURSOR_HOOKS_FILE"
    else
        _write_cursor_hooks_file "$CURSOR_HOOKS_FILE" "$HOOK_SCRIPT"
    fi
    chmod 600 "$CURSOR_HOOKS_FILE"

    echo ""
    echo "  Next steps (Cursor):"
    echo "  ────────────────────"
    echo "  1. Hooks config written to: $CURSOR_HOOKS_FILE"
    echo "  2. Hook script: $HOOK_SCRIPT"
    echo "  3. Guardrail mode: $APORT_SELECTED_GUARDRAIL_MODE"
    echo "     Enforcement: $APORT_SELECTED_ENFORCEMENT"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        echo "     API URL: ${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    echo "  4. Mode config: $MODE_FILE"
    echo "  5. Restart Cursor (or reload window) so hooks are picked up."
    echo "  6. Shell commands and tool use will be checked by APort policy (exit 2 = block)."
    echo ""
    echo "  For other frameworks like Claude Code, use the dedicated integration: docs/frameworks"
    echo ""
}

_write_cursor_hooks_file() {
    local file="$1"
    local cmd="$2"
    if command -v jq &> /dev/null; then
        jq -n -c --arg cmd "$cmd" --arg marker "$APORT_HOOK_MARKER" --argjson timeout "$APORT_HOOK_TIMEOUT" '{
      version: 1,
      hooks: {
        beforeShellExecution: [{ command: $cmd, ($marker): true, timeout: $timeout, failClosed: true }],
        preToolUse: [{ command: $cmd, ($marker): true, timeout: $timeout, failClosed: true }],
        beforeMCPExecution: [{ command: $cmd, ($marker): true, timeout: $timeout, failClosed: true }],
        beforeReadFile: [{ command: $cmd, ($marker): true, timeout: $timeout, failClosed: true }],
        subagentStart: [{ command: $cmd, ($marker): true, timeout: $timeout, failClosed: true }]
      }
    }' > "$file"
    else
        local escaped_cmd
        escaped_cmd="$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        cat > "$file" << EOF
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [{"command": "${escaped_cmd}", "__aport_hook": true, "timeout": 10, "failClosed": true}],
    "preToolUse": [{"command": "${escaped_cmd}", "__aport_hook": true, "timeout": 10, "failClosed": true}],
    "beforeMCPExecution": [{"command": "${escaped_cmd}", "__aport_hook": true, "timeout": 10, "failClosed": true}],
    "beforeReadFile": [{"command": "${escaped_cmd}", "__aport_hook": true, "timeout": 10, "failClosed": true}],
    "subagentStart": [{"command": "${escaped_cmd}", "__aport_hook": true, "timeout": 10, "failClosed": true}]
  }
}
EOF
    fi
}

run_setup "$@"

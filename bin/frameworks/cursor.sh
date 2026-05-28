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
    MODE_FILE="$(write_guardrail_mode_file "$config_dir" "$APORT_SELECTED_GUARDRAIL_MODE" "${APORT_SELECTED_API_URL:-}" "$hosted_agent_id")"

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

    # Merge with existing hooks.json if present; otherwise create new
    if [ -f "$CURSOR_HOOKS_FILE" ] && command -v jq &> /dev/null; then
        EXISTING=$(cat "$CURSOR_HOOKS_FILE")
        if echo "$EXISTING" | jq -e '.hooks' &> /dev/null; then
            # Add APort hook to all supported lifecycle events.
            # Replace stale APort entries (old npx paths), preserve non-APort hooks.
            NEW_HOOKS=$(echo "$EXISTING" | jq -c --arg cmd "$HOOK_SCRIPT" '
        def is_aport_cmd:
          (.command? // "") | test("aport-(cursor-hook|claude-code-hook)\\.sh$");
        def upsert_hook:
          map(select((.command != $cmd) and (is_aport_cmd | not))) | . + [{ "command": $cmd }];
        .hooks.beforeShellExecution = ((.hooks.beforeShellExecution // []) | upsert_hook) |
        .hooks.preToolUse = ((.hooks.preToolUse // []) | upsert_hook) |
        .hooks.beforeMCPExecution = ((.hooks.beforeMCPExecution // []) | upsert_hook) |
        .hooks.subagentStart = ((.hooks.subagentStart // []) | upsert_hook)
      ')
            [ -f "$CURSOR_HOOKS_FILE" ] && cp "$CURSOR_HOOKS_FILE" "${CURSOR_HOOKS_FILE}.bak"
            echo "$NEW_HOOKS" > "$CURSOR_HOOKS_FILE"
        else
            _write_cursor_hooks_file "$CURSOR_HOOKS_FILE" "$HOOK_SCRIPT"
        fi
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
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        echo "     API URL: ${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    echo "  4. Mode config: $MODE_FILE"
    echo "  5. Restart Cursor (or reload window) so hooks are picked up."
    echo "  6. Shell commands and tool use will be checked by APort policy (exit 2 = block)."
    echo ""
    echo "  Same script works for VS Code + Copilot. For Claude Code use the dedicated integration: docs/frameworks/claude-code.md"
    echo ""
}

_write_cursor_hooks_file() {
    local file="$1"
    local cmd="$2"
    if command -v jq &> /dev/null; then
        jq -n -c --arg cmd "$cmd" '{
      version: 1,
      hooks: {
        beforeShellExecution: [{ command: $cmd }],
        preToolUse: [{ command: $cmd }],
        beforeMCPExecution: [{ command: $cmd }],
        subagentStart: [{ command: $cmd }]
      }
    }' > "$file"
    else
        local escaped_cmd
        escaped_cmd="$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        cat > "$file" << EOF
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [{"command": "${escaped_cmd}"}],
    "preToolUse": [{"command": "${escaped_cmd}"}],
    "beforeMCPExecution": [{"command": "${escaped_cmd}"}],
    "subagentStart": [{"command": "${escaped_cmd}"}]
  }
}
EOF
    fi
}

run_setup "$@"

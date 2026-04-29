#!/usr/bin/env bash
# Claude Code framework installer/setup.
# Runs passport wizard and writes ~/.claude/settings.json with PreToolUse hook
# pointing at aport-claude-code-hook.sh. Format is Claude Code official schema

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

run_setup() {
    parse_guardrail_mode_args "$@"

    log_info "Setting up APort guardrails for Claude Code..."
    config_dir="$(ensure_aport_dir_secure claude-code)"

    export APORT_FRAMEWORK=claude-code

    local hosted_agent_id=""
    if [[ -n "${APORT_HOSTED_AGENT_ID_CLI:-}" ]]; then
        hosted_agent_id="$APORT_HOSTED_AGENT_ID_CLI"
        export APORT_AGENT_ID="$hosted_agent_id"
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

    select_guardrail_mode "claude-code" "$hosted_agent_id"
    select_guardrail_api_url "$APORT_SELECTED_GUARDRAIL_MODE"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        export APORT_API_URL="${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    MODE_FILE="$(write_guardrail_mode_file "$config_dir" "$APORT_SELECTED_GUARDRAIL_MODE" "${APORT_SELECTED_API_URL:-}" "$hosted_agent_id")"

    # Resolve absolute path to hook script (works from repo or npx package)
    HOOK_SCRIPT="$(resolve_hook_script_path "${APORT_CLAUDE_CODE_HOOK_SCRIPT:-}" "aport-claude-code-hook.sh" "$LIB")"
    if [ ! -f "$HOOK_SCRIPT" ]; then
        log_warn "Hook script not found at $HOOK_SCRIPT; settings.json will reference it (create the file for hooks to work)."
    else
        HOOK_SCRIPT="$(cd "$(dirname "$HOOK_SCRIPT")" && pwd)/$(basename "$HOOK_SCRIPT")"
    fi

    CLAUDE_DIR="${APORT_CLAUDE_CODE_CONFIG_DIR:-$HOME/.claude}"
    CLAUDE_DIR="${CLAUDE_DIR/#\~/$HOME}"
    SETTINGS_FILE="$CLAUDE_DIR/settings.json"
    mkdir -p "$CLAUDE_DIR"

    _write_claude_settings "$SETTINGS_FILE" "$HOOK_SCRIPT"
    chmod 600 "$SETTINGS_FILE"

    echo ""
    echo "  Next steps (Claude Code):"
    echo "  ─────────────────────────"
    echo "  1. Settings written to: $SETTINGS_FILE"
    echo "  2. Hook script: $HOOK_SCRIPT"
    echo "  3. Guardrail mode: $APORT_SELECTED_GUARDRAIL_MODE"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        echo "     API URL: ${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    echo "  4. Mode config: $MODE_FILE"
    echo "  5. Restart Claude Code so the PreToolUse hook is picked up."
    echo "  6. Tool use will be checked by APort policy (exit 2 = block)."
    echo ""
    echo "  Audit log: $config_dir/aport/audit.log"
    echo ""
    echo "  Note: claude --dangerously-skip-permissions bypasses ALL hooks including APort."
    echo "  See: docs/frameworks/claude-code.md"
    echo ""
}

# Write ~/.claude/settings.json in Claude Code official format (PreToolUse, matcher "*").
# Merges with existing settings.json without clobbering other settings.
_write_claude_settings() {
    local file="$1"
    local cmd="$2"

    if [ -f "$file" ] && command -v jq &> /dev/null; then
        if jq -e '.hooks' "$file" &> /dev/null; then
            # Merge: replace stale APort hook entries (old npx paths), preserve non-APort hooks
            local tmpfile
            tmpfile="$(mktemp "${file}.XXXXXX")"
            jq -c --arg cmd "$cmd" '
                (.hooks.PreToolUse // []) as $p |
                .hooks.PreToolUse = ($p | map(select(
                    ((.hooks[0].command != $cmd) and (((.hooks[0].command // "") | test("aport-(cursor-hook|claude-code-hook)\\.sh$")) | not))
                )) | . + [{"matcher":"*","hooks":[{"type":"command","command":$cmd}]}])
            ' "$file" > "$tmpfile" && mv "$tmpfile" "$file"
            return
        fi
    fi

    # Write fresh settings (Claude Code format: hooks.PreToolUse, matcher "*")
    if command -v jq &> /dev/null; then
        jq -n --arg cmd "$cmd" '{
            hooks: {
                PreToolUse: [{"matcher":"*","hooks":[{"type":"command","command":$cmd}]}]
            }
        }' > "$file"
    else
        # Escape special JSON characters in cmd path (quotes, backslashes)
        local escaped_cmd
        escaped_cmd="$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        cat > "$file" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${escaped_cmd}"
          }
        ]
      }
    ]
  }
}
EOF
    fi
}

run_setup "$@"

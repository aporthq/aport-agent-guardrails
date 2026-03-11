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

run_setup() {
    log_info "Setting up APort guardrails for Claude Code..."
    config_dir="$(get_config_dir claude-code)"
    config_dir="${config_dir/#\~/$HOME}"
    mkdir -p "$config_dir/aport"
    chmod 700 "$config_dir/aport"

    export APORT_FRAMEWORK=claude-code
    run_passport_wizard "$@"

    # Harden permissions on passport (contains policy/capabilities)
    [ -f "$config_dir/aport/passport.json" ] && chmod 600 "$config_dir/aport/passport.json"

    # Resolve absolute path to hook script (works from repo or npx package)
    HOOK_SCRIPT="${APORT_CLAUDE_CODE_HOOK_SCRIPT:-}"
    if [ -z "$HOOK_SCRIPT" ]; then
        ROOT_FOR_HOOK="$(cd "$LIB/../.." && pwd)"
        HOOK_SCRIPT="$ROOT_FOR_HOOK/bin/aport-claude-code-hook.sh"
    fi
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
    echo "  3. Restart Claude Code so the PreToolUse hook is picked up."
    echo "  4. Tool use will be checked by APort policy (exit 2 = block)."
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
            # Merge: add APort to PreToolUse array, dedup by command
            local tmpfile
            tmpfile="$(mktemp "${file}.XXXXXX")"
            jq -c --arg cmd "$cmd" '
                (.hooks.PreToolUse // []) as $p |
                .hooks.PreToolUse = ($p | map(select(
                    (.hooks[0].command != $cmd)
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

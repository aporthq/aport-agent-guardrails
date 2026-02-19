#!/usr/bin/env bash
# Cursor (and optional Copilot/Claude Code) framework installer/setup.
# Runs passport wizard and writes ~/.cursor/hooks.json pointing at the APort hook script.
# Same hook script works for Cursor, VS Code + Copilot, and Claude Code.

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$LIB/common.sh"
# shellcheck source=../lib/passport.sh
source "$LIB/passport.sh"
# shellcheck source=../lib/config.sh
source "$LIB/config.sh"

run_setup() {
    log_info "Setting up APort guardrails for Cursor..."
    # Passport and data live under Cursor's config dir (~/.cursor/aport/ by default).
    config_dir="$(get_config_dir cursor)"
    mkdir -p "$config_dir/aport"

    export APORT_FRAMEWORK=cursor
    run_passport_wizard "$@"

    # Resolve absolute path to hook script (works from repo or npx package)
    HOOK_SCRIPT="${APORT_CURSOR_HOOK_SCRIPT:-}"
    if [ -z "$HOOK_SCRIPT" ]; then
        ROOT_FOR_HOOK="$(cd "$LIB/../.." && pwd)"
        HOOK_SCRIPT="$ROOT_FOR_HOOK/bin/aport-cursor-hook.sh"
    fi
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
            # Add APort hook to beforeShellExecution and preToolUse (avoid duplicate)
            NEW_HOOKS=$(echo "$EXISTING" | jq -c --arg cmd "$HOOK_SCRIPT" '
        (.hooks.beforeShellExecution // []) as $b |
        (.hooks.preToolUse // []) as $p |
        .hooks.beforeShellExecution = ($b | map(select(.command != $cmd)) | . + [{ "command": $cmd }]) |
        .hooks.preToolUse = ($p | map(select(.command != $cmd)) | . + [{ "command": $cmd }])
      ')
            echo "$NEW_HOOKS" > "$CURSOR_HOOKS_FILE"
        else
            _write_cursor_hooks_file "$CURSOR_HOOKS_FILE" "$HOOK_SCRIPT"
        fi
    else
        _write_cursor_hooks_file "$CURSOR_HOOKS_FILE" "$HOOK_SCRIPT"
    fi

    echo ""
    echo "  Next steps (Cursor):"
    echo "  ────────────────────"
    echo "  1. Hooks config written to: $CURSOR_HOOKS_FILE"
    echo "  2. Hook script: $HOOK_SCRIPT"
    echo "  3. Restart Cursor (or reload window) so hooks are picked up."
    echo "  4. Shell commands and tool use will be checked by APort policy (exit 2 = block)."
    echo ""
    echo "  Same script works for VS Code + Copilot and Claude Code — see: docs/frameworks/cursor.md"
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
        preToolUse: [{ command: $cmd }]
      }
    }' > "$file"
    else
        cat > "$file" << EOF
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [{"command": "$cmd"}],
    "preToolUse": [{"command": "$cmd"}]
  }
}
EOF
    fi
}

run_setup "$@"

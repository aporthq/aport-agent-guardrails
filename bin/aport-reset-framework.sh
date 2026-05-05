#!/usr/bin/env bash

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/lib" && pwd)"
# shellcheck source=./lib/common.sh
source "$LIB/common.sh"
# shellcheck source=./lib/config.sh
source "$LIB/config.sh"

framework="${1:-}"
shift || true

if [[ -z "$framework" ]]; then
    log_error "Usage: agent-guardrails reset <framework> [--yes]"
    exit 1
fi

yes_mode="${APORT_NONINTERACTIVE:-${CI:-}}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes | -y)
            yes_mode=1
            ;;
        *)
            log_error "Unknown reset option: $1"
            exit 1
            ;;
    esac
    shift
done

framework="$(echo "$framework" | tr '[:upper:]' '[:lower:]')"
config_dir="$(get_config_dir "$framework")"
config_dir="${config_dir/#\~/$HOME}"

confirm_reset() {
    if [[ -n "$yes_mode" ]]; then
        return 0
    fi

    echo ""
    echo "  Reset APort for $framework"
    echo "  ──────────────────────────"
    echo "  This removes APort-owned local config and hook/plugin wiring for this framework."
    echo "  Other framework settings are preserved when possible."
    echo ""

    local answer
    read -r -p "  Continue? [y/N]: " answer
    case "$answer" in
        y | Y | yes | YES) ;;
        *)
            echo "  Reset cancelled."
            exit 0
            ;;
    esac
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.bak"
    fi
}

remove_dir_if_exists() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
        echo "  ✅ Removed $dir"
    fi
}

remove_file_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        rm -f "$file"
        echo "  ✅ Removed $file"
    fi
}

cleanup_claude_settings() {
    local settings_file="$1"
    if [[ ! -f "$settings_file" ]]; then
        return 0
    fi
    if ! command -v jq &> /dev/null; then
        log_warn "jq not found; leaving Claude settings intact at $settings_file"
        return 0
    fi

    local tmpfile
    tmpfile="$(mktemp "${settings_file}.XXXXXX")"
    if jq '
        if (.hooks.PreToolUse? // null) == null then
            .
        else
            .hooks.PreToolUse = (
                (.hooks.PreToolUse // [])
                | map(
                    if (.hooks? // null) == null then
                        .
                    else
                        .hooks = (
                            (.hooks // [])
                            | map(select((((.command // "") | test("aport-(cursor-hook|claude-code-hook)\\.sh$")) | not)))
                        )
                    end
                )
                | map(select(((.hooks? // []) | length) > 0))
            )
            | if ((.hooks.PreToolUse // []) | length) == 0 then del(.hooks.PreToolUse) else . end
            | if ((.hooks // {}) | keys | length) == 0 then del(.hooks) else . end
        end
    ' "$settings_file" > "$tmpfile"; then
        backup_file "$settings_file"
        mv "$tmpfile" "$settings_file"
        echo "  ✅ Removed APort Claude Code hook entries from $settings_file"
    else
        rm -f "$tmpfile"
        log_warn "Failed to clean Claude settings at $settings_file"
    fi
}

cleanup_cursor_hooks() {
    local hooks_file="$1"
    if [[ ! -f "$hooks_file" ]]; then
        return 0
    fi
    if ! command -v jq &> /dev/null; then
        log_warn "jq not found; leaving Cursor hooks intact at $hooks_file"
        return 0
    fi

    local tmpfile
    tmpfile="$(mktemp "${hooks_file}.XXXXXX")"
    if jq '
        def strip_aport_hooks:
            (. // []) | map(select((((.command // "") | test("aport-(cursor-hook|claude-code-hook)\\.sh$")) | not)));
        .hooks.beforeShellExecution = ((.hooks.beforeShellExecution // []) | strip_aport_hooks) |
        .hooks.preToolUse = ((.hooks.preToolUse // []) | strip_aport_hooks) |
        .hooks.beforeMCPExecution = ((.hooks.beforeMCPExecution // []) | strip_aport_hooks) |
        .hooks.subagentStart = ((.hooks.subagentStart // []) | strip_aport_hooks) |
        if ((.hooks.beforeShellExecution // []) | length) == 0 then del(.hooks.beforeShellExecution) else . end |
        if ((.hooks.preToolUse // []) | length) == 0 then del(.hooks.preToolUse) else . end |
        if ((.hooks.beforeMCPExecution // []) | length) == 0 then del(.hooks.beforeMCPExecution) else . end |
        if ((.hooks.subagentStart // []) | length) == 0 then del(.hooks.subagentStart) else . end |
        if ((.hooks // {}) | keys | length) == 0 then del(.hooks) else . end
    ' "$hooks_file" > "$tmpfile"; then
        backup_file "$hooks_file"
        mv "$tmpfile" "$hooks_file"
        echo "  ✅ Removed APort Cursor hook entries from $hooks_file"
    else
        rm -f "$tmpfile"
        log_warn "Failed to clean Cursor hooks at $hooks_file"
    fi
}

cleanup_openclaw_json() {
    local openclaw_json="$1"
    if [[ ! -f "$openclaw_json" ]]; then
        return 0
    fi
    if ! command -v jq &> /dev/null; then
        log_warn "jq not found; leaving OpenClaw JSON config intact at $openclaw_json"
        return 0
    fi

    local tmpfile
    tmpfile="$(mktemp "${openclaw_json}.XXXXXX")"
    if jq '
        .plugins = (.plugins // {}) |
        .plugins.entries = ((.plugins.entries // {}) | del(.["openclaw-aport"])) |
        .plugins.installs = ((.plugins.installs // {}) | del(.["openclaw-aport"])) |
        .plugins.load = (.plugins.load // {}) |
        .plugins.load.paths = ((.plugins.load.paths // []) | map(select((type == "string" and contains("/openclaw-aport")) | not))) |
        if ((.plugins.entries // {}) | keys | length) == 0 then del(.plugins.entries) else . end |
        if ((.plugins.installs // {}) | keys | length) == 0 then del(.plugins.installs) else . end |
        if ((.plugins.load.paths // []) | length) == 0 then del(.plugins.load.paths) else . end |
        if ((.plugins.load // {}) | keys | length) == 0 then del(.plugins.load) else . end |
        if ((.plugins // {}) | keys | length) == 0 then del(.plugins) else . end
    ' "$openclaw_json" > "$tmpfile"; then
        backup_file "$openclaw_json"
        mv "$tmpfile" "$openclaw_json"
        echo "  ✅ Removed APort OpenClaw entries from $openclaw_json"
    else
        rm -f "$tmpfile"
        log_warn "Failed to clean OpenClaw JSON config at $openclaw_json"
    fi
}

cleanup_python_framework() {
    local config_dir="$1"
    remove_dir_if_exists "$config_dir/aport"
    remove_file_if_exists "$config_dir/config.yaml"
}

cleanup_n8n() {
    local config_dir="$1"
    remove_dir_if_exists "$config_dir/aport"
}

cleanup_claude() {
    local settings_file="$config_dir/settings.json"
    remove_dir_if_exists "$config_dir/aport"
    cleanup_claude_settings "$settings_file"
}

cleanup_cursor() {
    local hooks_file="$config_dir/hooks.json"
    remove_dir_if_exists "$config_dir/aport"
    cleanup_cursor_hooks "$hooks_file"
}

cleanup_openclaw() {
    local openclaw_json="$config_dir/openclaw.json"
    remove_dir_if_exists "$config_dir/aport"
    remove_dir_if_exists "$config_dir/extensions/openclaw-aport"
    remove_dir_if_exists "$config_dir/skills/aport-guardrail"
    remove_file_if_exists "$config_dir/.aport-repo"
    remove_file_if_exists "$config_dir/.skills/aport-guardrail.sh"
    remove_file_if_exists "$config_dir/.skills/aport-guardrail-bash.sh"
    remove_file_if_exists "$config_dir/.skills/aport-guardrail-api.sh"
    remove_file_if_exists "$config_dir/.skills/aport-guardrail-v2.sh"
    remove_file_if_exists "$config_dir/.skills/aport-create-passport.sh"
    remove_file_if_exists "$config_dir/.skills/aport-status.sh"
    cleanup_openclaw_json "$openclaw_json"
    if [[ -f "$config_dir/config.yaml" ]]; then
        log_warn "OpenClaw config.yaml may still contain APort plugin config. Review $config_dir/config.yaml if you need a completely pristine OpenClaw config."
    fi
}

confirm_reset

echo "[aport] Resetting framework: $framework" >&2

case "$framework" in
    claude-code)
        cleanup_claude
        ;;
    cursor)
        cleanup_cursor
        ;;
    openclaw)
        cleanup_openclaw
        ;;
    langchain | crewai | deerflow)
        cleanup_python_framework "$config_dir"
        ;;
    n8n)
        cleanup_n8n "$config_dir"
        ;;
    *)
        log_error "Unsupported framework reset: $framework"
        exit 1
        ;;
esac

echo ""
echo "  Reset complete for $framework."
echo "  Re-run the setup command when you want a fresh install."
echo ""

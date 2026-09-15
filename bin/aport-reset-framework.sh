#!/usr/bin/env bash

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/lib" && pwd)"
# shellcheck source=./lib/common.sh
source "$LIB/common.sh"
# shellcheck source=./lib/config.sh
source "$LIB/config.sh"
# shellcheck source=./lib/framework-setup.sh
source "$LIB/framework-setup.sh"

APORT_HOOK_MARKER="__aport_hook"

framework="${1:-}"
shift || true

if [[ -z "$framework" ]]; then
    log_error "Usage: agent-guardrails reset <framework> [--yes]"
    exit 1
fi

yes_mode="${APORT_NONINTERACTIVE:-${CI:-}}"
reset_scope="auto"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes | -y)
            yes_mode=1
            ;;
        --project)
            reset_scope="project"
            ;;
        --global)
            reset_scope="global"
            ;;
        *)
            log_error "Unknown reset option: $1"
            exit 1
            ;;
    esac
    shift
done

framework="$(echo "$framework" | tr '[:upper:]' '[:lower:]')"
case "$framework" in
    claude) framework="claude-code" ;;
    gemini) framework="gemini-cli" ;;
esac

has_project_aport_codex_config() {
    local dir="$PWD/.codex"
    [[ -d "$dir/aport" ]] || [[ -f "$dir/hooks.json" ]] || return 1
    [[ -f "$dir/aport/guardrail-mode.env" ]] && return 0
    [[ -f "$dir/hooks.json" ]] && grep -Eq '__aport_hook|aport-codex-hook\.sh' "$dir/hooks.json" 2> /dev/null
}

has_project_aport_gemini_config() {
    local dir="$PWD/.gemini"
    [[ -d "$dir/aport" ]] || [[ -f "$dir/settings.json" ]] || return 1
    [[ -f "$dir/aport/guardrail-mode.env" ]] && return 0
    [[ -f "$dir/settings.json" ]] && grep -Eq '__aport_hook|aport-gemini-cli-hook\.sh' "$dir/settings.json" 2> /dev/null
}

framework_specific_config_dir_override() {
    case "$framework" in
        openclaw)
            printf '%s' "${APORT_OPENCLAW_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-}}"
            ;;
        cursor)
            printf '%s' "${APORT_CURSOR_CONFIG_DIR:-}"
            ;;
        claude-code)
            printf '%s' "${APORT_CLAUDE_CODE_CONFIG_DIR:-}"
            ;;
        codex)
            printf '%s' "${APORT_CODEX_CONFIG_DIR:-}"
            ;;
        gemini-cli)
            printf '%s' "${APORT_GEMINI_CLI_CONFIG_DIR:-}"
            ;;
        goose)
            printf '%s' "${APORT_GOOSE_CONFIG_DIR:-}"
            ;;
        langchain)
            printf '%s' "${APORT_LANGCHAIN_CONFIG_DIR:-}"
            ;;
        crewai)
            printf '%s' "${APORT_CREWAI_CONFIG_DIR:-}"
            ;;
        deerflow)
            printf '%s' "${APORT_DEERFLOW_CONFIG_DIR:-}"
            ;;
        n8n)
            printf '%s' "${APORT_N8N_CONFIG_DIR:-}"
            ;;
        *)
            printf ''
            ;;
    esac
}

resolve_reset_config_dir() {
    local framework_override
    framework_override="$(framework_specific_config_dir_override)"
    if [[ -n "$framework_override" ]]; then
        printf '%s' "${framework_override/#\~/$HOME}"
        return 0
    fi

    if [[ -n "${APORT_CONFIG_DIR:-}" ]]; then
        printf '%s' "${APORT_CONFIG_DIR/#\~/$HOME}"
        return 0
    fi

    case "$framework" in
        codex)
            get_config_dir "$framework"
            return 0
            ;;
        gemini-cli)
            get_config_dir "$framework"
            return 0
            ;;
    esac

    get_config_dir "$framework"
}

resolve_codex_hook_config_dir() {
    local codex_home="${CODEX_HOME:-$HOME/.codex}"
    codex_home="${codex_home/#\~/$HOME}"
    if [[ -n "${APORT_CODEX_HOOKS_DIR:-}" ]]; then
        printf '%s' "${APORT_CODEX_HOOKS_DIR/#\~/$HOME}"
    elif [[ "$reset_scope" = "project" ]]; then
        printf '%s/.codex' "$PWD"
    elif [[ "$reset_scope" = "global" ]]; then
        printf '%s' "$codex_home"
    elif [[ -n "${APORT_CODEX_CONFIG_DIR:-}" && -f "${APORT_CODEX_CONFIG_DIR/#\~/$HOME}/hooks.json" ]]; then
        printf '%s' "${APORT_CODEX_CONFIG_DIR/#\~/$HOME}"
    elif has_project_aport_codex_config; then
        printf '%s/.codex' "$PWD"
    else
        printf '%s' "$codex_home"
    fi
}

resolve_gemini_hook_config_dir() {
    if [[ -n "${APORT_GEMINI_CLI_HOOKS_DIR:-}" ]]; then
        printf '%s' "${APORT_GEMINI_CLI_HOOKS_DIR/#\~/$HOME}"
    elif [[ "$reset_scope" = "project" ]]; then
        printf '%s/.gemini' "$PWD"
    elif [[ "$reset_scope" = "global" ]]; then
        printf '%s/.gemini' "$HOME"
    elif [[ -n "${APORT_GEMINI_CLI_CONFIG_DIR:-}" && -f "${APORT_GEMINI_CLI_CONFIG_DIR/#\~/$HOME}/settings.json" ]]; then
        printf '%s' "${APORT_GEMINI_CLI_CONFIG_DIR/#\~/$HOME}"
    elif has_project_aport_gemini_config; then
        printf '%s/.gemini' "$PWD"
    else
        printf '%s/.gemini' "$HOME"
    fi
}

config_dir="$(resolve_reset_config_dir)"
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
        refuse_symlink_path "$file" || return 1
        refuse_symlink_path "${file}.bak" || return 1
        cp "$file" "${file}.bak" || return 1
    fi
}

remove_dir_if_exists() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        refuse_symlink_path "$dir"
        rm -rf "$dir"
        echo "  ✅ Removed $dir"
    fi
}

remove_file_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        refuse_symlink_path "$file"
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
        log_error "jq not found; cannot safely remove Claude Code hook entries from $settings_file"
        return 1
    fi

    local tmpfile
    tmpfile="$(mktemp "${settings_file}.XXXXXX")"
    if ! jq -e . "$settings_file" > /dev/null 2>&1; then
        log_error "Invalid Claude settings JSON; cannot safely remove hook entries from $settings_file"
        return 1
    fi

    if jq --arg marker "$APORT_HOOK_MARKER" '
        def is_aport_claude_hook:
            (.[$marker] == true) or (((.command // "") | tostring) | test("(^|/)aport-claude-code-hook\\.sh($|[[:space:]])"));
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
                            | map(select(is_aport_claude_hook | not))
                        )
                    end
                )
                | map(select(((.hooks? // []) | length) > 0))
            )
            | if ((.hooks.PreToolUse // []) | length) == 0 then del(.hooks.PreToolUse) else . end
            | if ((.hooks // {}) | keys | length) == 0 then del(.hooks) else . end
        end
    ' "$settings_file" > "$tmpfile"; then
        if ! backup_file "$settings_file"; then
            rm -f "$tmpfile"
            return 1
        fi
        mv "$tmpfile" "$settings_file"
        echo "  ✅ Removed APort Claude Code hook entries from $settings_file"
    else
        rm -f "$tmpfile"
        log_error "Failed to clean Claude settings at $settings_file"
        return 1
    fi
}

cleanup_cursor_hooks() {
    local hooks_file="$1"
    if [[ ! -f "$hooks_file" ]]; then
        return 0
    fi
    if ! command -v jq &> /dev/null; then
        log_error "jq not found; cannot safely remove Cursor hook entries from $hooks_file"
        return 1
    fi

    local tmpfile
    tmpfile="$(mktemp "${hooks_file}.XXXXXX")"
    if ! jq -e . "$hooks_file" > /dev/null 2>&1; then
        log_error "Invalid Cursor hooks JSON; cannot safely remove hook entries from $hooks_file"
        return 1
    fi

    if jq --arg marker "$APORT_HOOK_MARKER" '
        def is_aport_cursor_hook:
            (.[$marker] == true) or (((.command // "") | tostring) | test("(^|/)aport-cursor-hook\\.sh($|[[:space:]])"));
        def strip_aport_hooks:
            (. // []) | map(select(is_aport_cursor_hook | not));
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
        if ! backup_file "$hooks_file"; then
            rm -f "$tmpfile"
            return 1
        fi
        mv "$tmpfile" "$hooks_file"
        echo "  ✅ Removed APort Cursor hook entries from $hooks_file"
    else
        rm -f "$tmpfile"
        log_error "Failed to clean Cursor hooks at $hooks_file"
        return 1
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
    cleanup_claude_settings "$settings_file"
    remove_dir_if_exists "$config_dir/aport"
}

cleanup_cursor() {
    local hooks_file="$config_dir/hooks.json"
    cleanup_cursor_hooks "$hooks_file"
    remove_dir_if_exists "$config_dir/aport"
}

cleanup_codex_hooks() {
    local hooks_file="${1:-$config_dir/hooks.json}"
    [[ -f "$hooks_file" ]] || return 0
    refuse_symlink_path "$hooks_file"
    if ! command -v jq &> /dev/null; then
        log_error "jq not found; cannot safely remove Codex hook entries from $hooks_file"
        return 1
    fi
    if ! jq -e . "$hooks_file" > /dev/null 2>&1; then
        log_error "Invalid Codex hooks JSON; cannot safely remove hook entries from $hooks_file"
        return 1
    fi

    local tmpfile
    tmpfile="$(mktemp "${hooks_file}.XXXXXX")"
    if jq --arg marker "$APORT_HOOK_MARKER" '
        def is_aport_codex_hook:
            (.[$marker] == true) or (((.command // "") | tostring) | test("(^|/)aport-codex-hook\\.sh($|[[:space:]])"));
        def strip_groups:
            (. // [])
            | map(.hooks = ((.hooks // []) | map(select(is_aport_codex_hook | not))))
            | map(select(((.hooks // []) | length) > 0));
        .hooks.PreToolUse = ((.hooks.PreToolUse // []) | strip_groups) |
        .hooks.PostToolUse = ((.hooks.PostToolUse // []) | strip_groups) |
        .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) | strip_groups) |
        if ((.hooks.PreToolUse // []) | length) == 0 then del(.hooks.PreToolUse) else . end |
        if ((.hooks.PostToolUse // []) | length) == 0 then del(.hooks.PostToolUse) else . end |
        if ((.hooks.PermissionRequest // []) | length) == 0 then del(.hooks.PermissionRequest) else . end |
        if ((.hooks // {}) | keys | length) == 0 then del(.hooks) else . end
    ' "$hooks_file" > "$tmpfile"; then
        if ! backup_file "$hooks_file"; then
            rm -f "$tmpfile"
            return 1
        fi
        mv "$tmpfile" "$hooks_file"
        echo "  ✅ Removed APort Codex hook entries from $hooks_file"
    else
        rm -f "$tmpfile"
        log_error "Failed to clean Codex hooks at $hooks_file"
        return 1
    fi
}

cleanup_gemini_settings() {
    local settings_file="${1:-$config_dir/settings.json}"
    [[ -f "$settings_file" ]] || return 0
    refuse_symlink_path "$settings_file"
    if ! command -v jq &> /dev/null; then
        log_error "jq not found; cannot safely remove Gemini CLI hook entries from $settings_file"
        return 1
    fi
    if ! jq -e . "$settings_file" > /dev/null 2>&1; then
        log_error "Invalid Gemini CLI settings JSON; cannot safely remove hook entries from $settings_file"
        return 1
    fi

    local tmpfile
    tmpfile="$(mktemp "${settings_file}.XXXXXX")"
    if jq --arg marker "$APORT_HOOK_MARKER" '
        def is_aport_gemini_hook:
            (.[$marker] == true) or (((.command // "") | tostring) | test("(^|/)aport-gemini-cli-hook\\.sh($|[[:space:]])"));
        def strip_groups:
            (. // [])
            | map(.hooks = ((.hooks // []) | map(select(is_aport_gemini_hook | not))))
            | map(select(((.hooks // []) | length) > 0));
        .hooks.BeforeTool = ((.hooks.BeforeTool // []) | strip_groups) |
        if ((.hooks.BeforeTool // []) | length) == 0 then del(.hooks.BeforeTool) else . end |
        if ((.hooks // {}) | keys | length) == 0 then del(.hooks) else . end
    ' "$settings_file" > "$tmpfile"; then
        if ! backup_file "$settings_file"; then
            rm -f "$tmpfile"
            return 1
        fi
        mv "$tmpfile" "$settings_file"
        echo "  ✅ Removed APort Gemini CLI hook entries from $settings_file"
    else
        rm -f "$tmpfile"
        log_error "Failed to clean Gemini CLI settings at $settings_file"
        return 1
    fi
}

cleanup_goose() {
    local project_plugin_dir="$PWD/.agents/plugins/aport-guardrail"
    local global_plugin_dir="$HOME/.agents/plugins/aport-guardrail"
    local custom_plugin_dir="${APORT_GOOSE_PLUGIN_DIR:-}"
    custom_plugin_dir="${custom_plugin_dir/#\~/$HOME}"
    local selected_scope="$reset_scope"

    is_aport_goose_plugin() {
        local plugin_dir="$1"
        [[ -f "$plugin_dir/plugin.json" ]] || return 1
        if command -v jq > /dev/null 2>&1; then
            jq -e '.name == "aport-guardrail"' "$plugin_dir/plugin.json" > /dev/null 2>&1
            return $?
        fi
        grep -Eq '"name"[[:space:]]*:[[:space:]]*"aport-guardrail"' "$plugin_dir/plugin.json" 2> /dev/null
    }

    remove_goose_plugin_if_aport() {
        local plugin_dir="$1"
        [[ -d "$plugin_dir" ]] || return 0
        if is_aport_goose_plugin "$plugin_dir"; then
            remove_dir_if_exists "$plugin_dir"
        fi
    }

    goose_plugin_exists_after_cleanup() {
        is_aport_goose_plugin "$project_plugin_dir" && return 0
        is_aport_goose_plugin "$global_plugin_dir" && return 0
        if [[ -n "$custom_plugin_dir" && "$custom_plugin_dir" != "$project_plugin_dir" && "$custom_plugin_dir" != "$global_plugin_dir" ]]; then
            is_aport_goose_plugin "$custom_plugin_dir" && return 0
        fi
        return 1
    }

    cleanup_goose_state_if_unreferenced() {
        if [[ "$selected_scope" = "project" || "$selected_scope" = "global" || "$selected_scope" = "custom" ]] || goose_plugin_exists_after_cleanup; then
            echo "  ✅ Preserved shared APort Goose state at $config_dir/aport"
        else
            remove_dir_if_exists "$config_dir/aport"
        fi
    }

    remove_selected_goose_plugin() {
        local fallback_plugin_dir="$1"
        if [[ -n "$custom_plugin_dir" ]]; then
            remove_goose_plugin_if_aport "$custom_plugin_dir"
        else
            remove_goose_plugin_if_aport "$fallback_plugin_dir"
        fi
    }

    if [[ "$selected_scope" = "auto" ]]; then
        if [[ -n "$custom_plugin_dir" ]]; then
            selected_scope="custom"
        elif is_aport_goose_plugin "$project_plugin_dir"; then
            selected_scope="project"
        else
            selected_scope="global"
        fi
    fi

    case "$selected_scope" in
        project)
            remove_selected_goose_plugin "$project_plugin_dir"
            cleanup_goose_state_if_unreferenced
            ;;
        global)
            remove_selected_goose_plugin "$global_plugin_dir"
            cleanup_goose_state_if_unreferenced
            ;;
        custom)
            remove_goose_plugin_if_aport "$custom_plugin_dir"
            cleanup_goose_state_if_unreferenced
            ;;
    esac
}

command_hook_selected_config_exists() {
    local framework_name="$1"
    local hook_config_dir="$2"
    local config_name

    case "$framework_name" in
        Codex)
            config_name="hooks.json"
            ;;
        "Gemini CLI")
            config_name="settings.json"
            ;;
        *)
            return 1
            ;;
    esac

    [[ -f "$hook_config_dir/$config_name" ]]
}

command_hook_config_file_name() {
    local framework_name="$1"
    case "$framework_name" in
        Codex)
            printf 'hooks.json'
            ;;
        "Gemini CLI")
            printf 'settings.json'
            ;;
        *)
            return 1
            ;;
    esac
}

command_hook_config_references_state_dir() {
    local file="$1"
    local state_dir="$2"

    [[ -f "$file" ]] || return 1
    command -v jq > /dev/null 2>&1 || return 1
    jq -e --arg state "$state_dir" '
      def unescape_shell_single_quotes:
        gsub("'\\''"; "'");
      [
        .. | objects | .command? |
        select(type == "string" and ((contains($state)) or ((unescape_shell_single_quotes) | contains($state))))
      ] | length > 0
    ' "$file" > /dev/null 2>&1
}

command_hook_file_references_state_dir() {
    local file="$1"
    local state_dir="$2"

    [[ -f "$file" ]] || return 1
    if command_hook_config_references_state_dir "$file" "$state_dir"; then
        return 0
    fi
    grep -F -- "$state_dir" "$file" > /dev/null 2>&1 && return 0
    sed "s/'\\\\''/'/g" "$file" 2> /dev/null | grep -F -- "$state_dir" > /dev/null 2>&1
}

preserve_command_hook_state_if_referenced() {
    local framework_name="$1"
    local state_dir="$2"
    local label="${3:-shared}"

    if command_hook_any_state_has_remaining_reference "$state_dir"; then
        echo "  ✅ Preserved ${label} APort $framework_name state at $state_dir/aport"
        return 0
    fi
    return 1
}

command_hook_any_state_has_remaining_reference() {
    local shared_state_dir="$1"
    local candidate_file
    local candidate_files=()

    candidate_files+=("$PWD/.codex/hooks.json" "$HOME/.codex/hooks.json")
    candidate_files+=("$PWD/.gemini/settings.json" "$HOME/.gemini/settings.json")
    candidate_files+=("$PWD/.claude/settings.json" "$HOME/.claude/settings.json")
    candidate_files+=("$PWD/.cursor/hooks.json" "$HOME/.cursor/hooks.json")
    candidate_files+=("$PWD/.agents/plugins/aport-guardrail/scripts/aport-goose-hook.sh")
    candidate_files+=("$HOME/.agents/plugins/aport-guardrail/scripts/aport-goose-hook.sh")
    [[ -n "${CODEX_HOME:-}" ]] && candidate_files+=("${CODEX_HOME/#\~/$HOME}/hooks.json")
    [[ -n "${APORT_CODEX_HOOKS_DIR:-}" ]] && candidate_files+=("${APORT_CODEX_HOOKS_DIR/#\~/$HOME}/hooks.json")
    [[ -n "${APORT_GEMINI_CLI_HOOKS_DIR:-}" ]] && candidate_files+=("${APORT_GEMINI_CLI_HOOKS_DIR/#\~/$HOME}/settings.json")
    [[ -n "${APORT_CLAUDE_CODE_CONFIG_DIR:-}" ]] && candidate_files+=("${APORT_CLAUDE_CODE_CONFIG_DIR/#\~/$HOME}/settings.json")
    [[ -n "${APORT_CURSOR_CONFIG_DIR:-}" ]] && candidate_files+=("${APORT_CURSOR_CONFIG_DIR/#\~/$HOME}/hooks.json")
    [[ -n "${APORT_GOOSE_PLUGIN_DIR:-}" ]] && candidate_files+=("${APORT_GOOSE_PLUGIN_DIR/#\~/$HOME}/scripts/aport-goose-hook.sh")

    for candidate_file in "${candidate_files[@]}"; do
        [[ -n "$candidate_file" ]] || continue
        if command_hook_file_references_state_dir "$candidate_file" "$shared_state_dir"; then
            return 0
        fi
    done

    return 1
}

cleanup_command_hook_state() {
    local framework_name="$1"
    local hook_config_dir="$2"
    local project_config_dir="$3"
    local shared_state_dir="$4"

    if preserve_command_hook_state_if_referenced "$framework_name" "$shared_state_dir" "shared"; then
        return 0
    fi
    if [[ "$reset_scope" != "global" && "$hook_config_dir" = "$project_config_dir" ]]; then
        if ! preserve_command_hook_state_if_referenced "$framework_name" "$project_config_dir" "project-local"; then
            remove_dir_if_exists "$project_config_dir/aport"
        fi
    fi
    if [[ "$shared_state_dir" != "$project_config_dir" && ("$hook_config_dir" = "$project_config_dir" || "$reset_scope" = "project") ]]; then
        echo "  ✅ Preserved shared APort $framework_name state at $shared_state_dir/aport"
        return 0
    fi
    if [[ -n "${APORT_CONFIG_DIR:-}" && "$shared_state_dir" != "$project_config_dir" && "$shared_state_dir" != "$hook_config_dir" ]] \
        && command_hook_selected_config_exists "$framework_name" "$hook_config_dir"; then
        echo "  ✅ Preserved explicitly shared APort $framework_name state at $shared_state_dir/aport"
        return 0
    fi
    if [[ -z "${APORT_CONFIG_DIR:-}" && "$shared_state_dir" != "$project_config_dir" && "$shared_state_dir" != "$hook_config_dir" && "$hook_config_dir" != "$project_config_dir" && "$reset_scope" != "project" ]]; then
        echo "  ✅ Preserved shared APort $framework_name state at $shared_state_dir/aport"
        return 0
    fi
    if [[ "$reset_scope" = "global" && "$shared_state_dir" = "$hook_config_dir" && "$project_config_dir" != "$hook_config_dir" ]]; then
        echo "  ✅ Preserved shared APort $framework_name state at $shared_state_dir/aport"
        return 0
    fi
    if [[ "$reset_scope" = "global" && "$shared_state_dir" != "$hook_config_dir" ]]; then
        echo "  ✅ Preserved shared APort $framework_name state at $shared_state_dir/aport"
        return 0
    fi
    remove_dir_if_exists "$shared_state_dir/aport"
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
    codex)
        codex_hook_dir="$(resolve_codex_hook_config_dir)"
        cleanup_codex_hooks "$codex_hook_dir/hooks.json"
        cleanup_command_hook_state "Codex" "$codex_hook_dir" "$PWD/.codex" "$config_dir"
        ;;
    gemini-cli)
        gemini_hook_dir="$(resolve_gemini_hook_config_dir)"
        cleanup_gemini_settings "$gemini_hook_dir/settings.json"
        cleanup_command_hook_state "Gemini CLI" "$gemini_hook_dir" "$PWD/.gemini" "$config_dir"
        ;;
    goose)
        cleanup_goose
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

#!/usr/bin/env bash
# Shared setup helpers for framework installers.

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]:-.}")/common.sh"

ensure_aport_dir_secure() {
    local framework="$1"
    local config_dir
    config_dir="$(get_config_dir "$framework")"
    config_dir="${config_dir/#\~/$HOME}"
    mkdir -p "$config_dir/aport"
    chmod 700 "$config_dir/aport"
    echo "$config_dir"
}

resolve_hook_script_path() {
    local env_override="$1"
    local hook_filename="$2"
    local lib_dir="$3"
    local hook_script

    hook_script="${env_override:-}"
    if [ -z "$hook_script" ]; then
        local root_for_hook
        root_for_hook="$(cd "$lib_dir/../.." && pwd)"
        hook_script="$root_for_hook/bin/$hook_filename"
    fi

    if [ -f "$hook_script" ]; then
        hook_script="$(cd "$(dirname "$hook_script")" && pwd)/$(basename "$hook_script")"
    fi

    echo "$hook_script"
}

warn_if_framework_command_missing() {
    local command_name="$1"
    local install_hint="$2"

    if command -v "$command_name" > /dev/null 2>&1; then
        return 0
    fi

    log_warn "$command_name CLI was not found on PATH. APort setup will still write hook/config files, but the guardrail only runs after the host is installed and restarted. $install_hint"
}

refuse_symlink_path() {
    local path="${1/#\~/$HOME}"
    [[ "$path" = /* ]] || path="$PWD/$path"
    local anchor=""
    local pwd_anchor="${PWD%/}"
    local home_anchor="${HOME%/}"
    local current="$path"

    case "$path" in
        "$pwd_anchor" | "$pwd_anchor"/*)
            anchor="$pwd_anchor"
            ;;
        "$home_anchor" | "$home_anchor"/*)
            anchor="$home_anchor"
            ;;
    esac

    while [[ -n "$current" && "$current" != "." && "$current" != "/" ]]; do
        [[ -n "$anchor" && "$current" = "$anchor" ]] && break
        [[ "$(dirname "$current")" = "/" ]] && break
        if [[ -L "$current" ]]; then
            log_error "Refusing to write through symlink: $current"
            return 1
        fi
        current="$(dirname "$current")"
    done
}

export -f ensure_aport_dir_secure resolve_hook_script_path warn_if_framework_command_missing refuse_symlink_path

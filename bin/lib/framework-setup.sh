#!/usr/bin/env bash
# Shared setup helpers for framework installers.

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]:-.}")/common.sh"

ensure_aport_dir_secure() {
    local framework="$1"
    local config_dir
    config_dir="$(get_config_dir "$framework")"
    config_dir="${config_dir/#\~/$HOME}"
    refuse_symlink_path "$config_dir" || return 1
    refuse_symlink_path "$config_dir/aport" || return 1
    mkdir -p "$config_dir/aport" || return 1
    chmod 700 "$config_dir/aport" || return 1
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

initialize_framework_audit_log() {
    local config_dir="${1/#\~/$HOME}"
    local audit_log="$config_dir/aport/audit.log"

    refuse_symlink_path "$audit_log" || return 1
    : >> "$audit_log" || return 1
    chmod 600 "$audit_log" 2> /dev/null || true
}

secure_framework_passport_file_if_present() {
    local config_dir="${1/#\~/$HOME}"
    local passport_file="$config_dir/aport/passport.json"

    [[ -e "$passport_file" ]] || return 0
    refuse_symlink_path "$passport_file" || return 1
    if [[ ! -f "$passport_file" ]]; then
        log_error "Refusing to use non-file passport path: $passport_file"
        return 1
    fi
    chmod 600 "$passport_file" || return 1
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

export -f ensure_aport_dir_secure resolve_hook_script_path initialize_framework_audit_log secure_framework_passport_file_if_present warn_if_framework_command_missing refuse_symlink_path

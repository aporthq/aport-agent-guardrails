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

export -f ensure_aport_dir_secure resolve_hook_script_path

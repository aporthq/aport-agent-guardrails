#!/usr/bin/env bash
# Runtime asset installation for local APort evaluation.
# Installs a self-contained shell runtime under <config_dir>/aport/runtime
# from the repo/npm package sources in bin/, external/, and src/.

set -euo pipefail

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]:-.}")/common.sh"

MANIFEST_FILE="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)/runtime-manifest.txt"

_runtime_refuse_existing_symlink() {
    local path="$1"
    local anchor="${2:-}"
    local current="$path"

    while [[ -n "$current" && "$current" != "." && "$current" != "/" ]]; do
        [[ -n "$anchor" && "$current" = "$anchor" ]] && break
        if [[ -L "$current" ]]; then
            log_error "Refusing to install APort runtime through symlink: $current"
            exit 1
        fi
        current="$(dirname "$current")"
    done
}

_runtime_refuse_descendant_symlink() {
    local runtime_dir="$1"
    local path="$2"
    local current="$path"

    while [[ "$current" = "$runtime_dir"/* && "$current" != "$runtime_dir" ]]; do
        if [[ -L "$current" ]]; then
            log_error "Refusing to install APort runtime through symlink: $current"
            exit 1
        fi
        current="$(dirname "$current")"
    done
}

_runtime_copy_file() {
    local runtime_dir="$1"
    local rel_path="$2"
    local src="$ROOT_DIR/$rel_path"
    local dest="$runtime_dir/$rel_path"

    if [[ ! -f "$src" ]]; then
        log_error "Runtime source missing: $src"
        exit 1
    fi

    _runtime_refuse_descendant_symlink "$runtime_dir" "$dest"
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    chmod +x "$dest" 2> /dev/null || true
}

_runtime_copy_tree() {
    local runtime_dir="$1"
    local rel_path="$2"
    local src="$ROOT_DIR/$rel_path"
    local dest="$runtime_dir/$rel_path"

    if [[ ! -d "$src" ]]; then
        log_error "Runtime source directory missing: $src"
        exit 1
    fi

    _runtime_refuse_descendant_symlink "$runtime_dir" "$dest"
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -R "$src" "$dest"
}

install_runtime_tree() {
    local config_dir="$1"
    local runtime_dir="$config_dir/aport/runtime"
    local kind=""
    local rel_path=""

    _runtime_refuse_existing_symlink "$config_dir/aport" "$config_dir"
    _runtime_refuse_existing_symlink "$runtime_dir" "$config_dir"
    mkdir -p "$runtime_dir"

    if [[ ! -f "$MANIFEST_FILE" ]]; then
        log_error "Runtime manifest missing: $MANIFEST_FILE"
        exit 1
    fi

    while read -r kind rel_path; do
        [[ -z "$kind" ]] && continue
        [[ "$kind" == \#* ]] && continue
        case "$kind" in
            file)
                _runtime_copy_file "$runtime_dir" "$rel_path"
                ;;
            tree)
                _runtime_copy_tree "$runtime_dir" "$rel_path"
                ;;
            mkdir)
                _runtime_refuse_descendant_symlink "$runtime_dir" "$runtime_dir/$rel_path"
                mkdir -p "$runtime_dir/$rel_path"
                ;;
            *)
                log_error "Unsupported runtime manifest entry: $kind $rel_path"
                exit 1
                ;;
        esac
    done < "$MANIFEST_FILE"

    chmod -R u+rwX "$runtime_dir" 2> /dev/null || true
}

export -f install_runtime_tree

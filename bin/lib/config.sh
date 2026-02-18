#!/usr/bin/env bash
# Config file management (shared across frameworks)
# Read/write config, env vars, credential paths.

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]:-.}")/common.sh"

# Default config locations per framework (where that framework stores data; can be overridden by env).
# Default passport path = get_config_dir/aport/passport.json. Keep in sync with packages/core default-passport-paths.json.
get_config_dir() {
  local framework="${1:-}"
  case "$framework" in
    openclaw) echo "${APORT_OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}" ;;
    langchain) echo "${APORT_LANGCHAIN_CONFIG_DIR:-$HOME/.aport/langchain}" ;;
    crewai)    echo "${APORT_CREWAI_CONFIG_DIR:-$HOME/.aport/crewai}" ;;
    n8n)      echo "${APORT_N8N_CONFIG_DIR:-$HOME/.n8n}" ;;
    cursor)   echo "${APORT_CURSOR_CONFIG_DIR:-$HOME/.cursor}" ;;
    *)        echo "${APORT_CONFIG_DIR:-$HOME/.aport}" ;;
  esac
}

# Default passport path per framework (config_dir/aport/passport.json). Used by wizard and evaluator.
get_default_passport_path() {
  local framework="${1:-}"
  local config_dir
  config_dir="$(get_config_dir "$framework")"
  config_dir="${config_dir/#\~/$HOME}"
  echo "${config_dir}/aport/passport.json"
}

write_config_template() {
  local framework="$1"
  local dest_dir
  dest_dir="$(get_config_dir "$framework")"
  mkdir -p "$dest_dir"
  log_info "Config directory: $dest_dir"
  local lib_dir templates_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
  templates_dir="$lib_dir/templates"
  if [[ -f "$templates_dir/config.yaml" ]]; then
    cp "$templates_dir/config.yaml" "$dest_dir/config.yaml" 2>/dev/null || true
  fi
  echo "$dest_dir"
}

export -f get_config_dir get_default_passport_path write_config_template

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
        # OpenClaw is the one framework whose location has aliases. bin/openclaw writes the passport under
        # $OPENCLAW_HOME or $OPENCLAW_STATE_DIR and exports OPENCLAW_CONFIG_DIR for the runtime, and
        # aport-set-mode/aport-reset read the same aliases. Resolving only APORT_OPENCLAW_CONFIG_DIR here
        # meant the passport-reuse scanner looked in ~/.openclaw on a machine using an OpenClaw alias, found
        # nothing, and offered to mint a duplicate of a passport that was already on the device. Same
        # precedence the other commands use, with OpenClaw's aliases last so APort-specific overrides win.
        openclaw) echo "${APORT_OPENCLAW_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-${OPENCLAW_STATE_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}}}}" ;;
        langchain) echo "${APORT_LANGCHAIN_CONFIG_DIR:-$HOME/.aport/langchain}" ;;
        crewai) echo "${APORT_CREWAI_CONFIG_DIR:-$HOME/.aport/crewai}" ;;
        n8n) echo "${APORT_N8N_CONFIG_DIR:-$HOME/.n8n}" ;;
        cursor) echo "${APORT_CURSOR_CONFIG_DIR:-$HOME/.cursor}" ;;
        claude-code | claude) echo "${APORT_CLAUDE_CODE_CONFIG_DIR:-$HOME/.claude}" ;;
        deerflow) echo "${APORT_DEERFLOW_CONFIG_DIR:-$HOME/.aport/deerflow}" ;;
        goose) echo "${APORT_GOOSE_CONFIG_DIR:-$HOME/.aport/goose}" ;;
        codex) echo "${APORT_CODEX_CONFIG_DIR:-$HOME/.aport/codex}" ;;
        gemini-cli | gemini) echo "${APORT_GEMINI_CLI_CONFIG_DIR:-$HOME/.aport/gemini-cli}" ;;
        opencode) echo "${APORT_OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}" ;;
        *) echo "${APORT_CONFIG_DIR:-$HOME/.aport}" ;;
    esac
}

# Default passport path per framework (config_dir/aport/passport.json). Used by wizard and evaluator.
# The frameworks the installers know. One list: the dispatcher, set-mode and passport reuse all read it.
APORT_SUPPORTED_FRAMEWORKS=(openclaw langchain crewai cursor claude-code codex gemini-cli goose deerflow n8n opencode)

# Frameworks the dispatcher accepts but whose setup intentionally exits because no enforcement hook exists yet
# (bin/frameworks/<name>.sh explains why). They belong in APORT_SUPPORTED_FRAMEWORKS so `agent-guardrails
# opencode` gets that explanation instead of "unknown framework", but they must stay out of anything that
# implies a working installation: switching an opencode install to enforce mode would report protection that
# is not there. aport_framework_is_gated is the single check; do not restate the list elsewhere.
APORT_GATED_FRAMEWORKS=(opencode)

aport_framework_is_gated() {
    local candidate="${1:-}" gated
    for gated in "${APORT_GATED_FRAMEWORKS[@]}"; do
        [[ "$candidate" == "$gated" ]] && return 0
    done
    return 1
}

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
    if [[ -f "$templates_dir/config.yaml" ]] && [[ ! -f "$dest_dir/config.yaml" ]]; then
        cp "$templates_dir/config.yaml" "$dest_dir/config.yaml" 2> /dev/null || true
    fi
    echo "$dest_dir"
}

export -f get_config_dir get_default_passport_path write_config_template

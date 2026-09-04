#!/usr/bin/env bash
# Update APort guardrail mode/enforcement without recreating passports or hooks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
LIB="$SCRIPT_DIR/lib"

# shellcheck source=lib/common.sh
source "$LIB/common.sh"
# shellcheck source=lib/config.sh
source "$LIB/config.sh"
# shellcheck source=lib/guardrail-mode.sh
source "$LIB/guardrail-mode.sh"

SUPPORTED_FRAMEWORKS=(openclaw langchain crewai cursor claude-code deerflow n8n)

usage() {
    cat << 'EOF'
Usage:
  aport-agent-guardrails mode <framework> [--mode=local|api] [--enforcement=enforce|warn]

Examples:
  aport-agent-guardrails mode claude-code --enforcement=warn
  aport-agent-guardrails mode cursor --enforcement=enforce
  aport-agent-guardrails mode langchain --mode=api --api-url=https://api.aport.io

This command updates APort config only. It does not create a passport, mint an API key,
or reinstall framework hooks.
EOF
}

framework="${1:-}"
if [[ -z "$framework" || "$framework" == "--help" || "$framework" == "-h" ]]; then
    usage
    exit 0
fi
shift
framework="$(printf '%s' "$framework" | tr '[:upper:]' '[:lower:]')"

is_supported=false
for supported in "${SUPPORTED_FRAMEWORKS[@]}"; do
    if [[ "$framework" == "$supported" ]]; then
        is_supported=true
        break
    fi
done
if [[ "$is_supported" != true ]]; then
    log_error "Unsupported framework: $framework"
    echo "Supported: ${SUPPORTED_FRAMEWORKS[*]}" >&2
    exit 1
fi

parse_guardrail_mode_args "$@"

config_dir="$(get_config_dir "$framework")"
config_dir="${config_dir/#\~/$HOME}"
mkdir -p "$config_dir/aport"
chmod 700 "$config_dir/aport" 2> /dev/null || true

mode_file="$config_dir/aport/guardrail-mode.env"
if [[ -f "$mode_file" ]]; then
    load_guardrail_mode_for_hooks "$config_dir"
fi

read_yaml_scalar() {
    local file="$1"
    local key="$2"
    [[ -f "$file" ]] || return 0
    awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key ":" {
            sub("^[[:space:]]*" key ":[[:space:]]*", "")
            gsub(/^["'\'' ]+|["'\'' ]+$/, "")
            print
            exit
        }
    ' "$file"
}

existing_config_mode=""
existing_config_agent_id=""
existing_config_api_url=""
if [[ "$framework" == "openclaw" ]]; then
    openclaw_json="$config_dir/openclaw.json"
    if [[ -f "$openclaw_json" && "$(command -v jq || true)" ]]; then
        existing_config_mode="$(jq -r '.plugins.entries["openclaw-aport"].config.mode // empty' "$openclaw_json" 2> /dev/null || true)"
        existing_config_agent_id="$(jq -r '.plugins.entries["openclaw-aport"].config.agentId // empty' "$openclaw_json" 2> /dev/null || true)"
        existing_config_api_url="$(jq -r '.plugins.entries["openclaw-aport"].config.apiUrl // empty' "$openclaw_json" 2> /dev/null || true)"
    fi
    if [[ -z "$existing_config_mode" || -z "$existing_config_agent_id" || -z "$existing_config_api_url" ]]; then
        openclaw_yaml="$config_dir/config.yaml"
        [[ -z "$existing_config_mode" ]] && existing_config_mode="$(read_yaml_scalar "$openclaw_yaml" "mode" || true)"
        [[ -z "$existing_config_agent_id" ]] && existing_config_agent_id="$(read_yaml_scalar "$openclaw_yaml" "agentId" || true)"
        [[ -z "$existing_config_api_url" ]] && existing_config_api_url="$(read_yaml_scalar "$openclaw_yaml" "apiUrl" || true)"
    fi
elif [[ "$framework" == "langchain" || "$framework" == "crewai" || "$framework" == "deerflow" || "$framework" == "n8n" ]]; then
    generic_config="$config_dir/config.yaml"
    existing_config_mode="$(read_yaml_scalar "$generic_config" "mode" || true)"
    existing_config_agent_id="$(read_yaml_scalar "$generic_config" "agent_id" || true)"
    existing_config_api_url="$(read_yaml_scalar "$generic_config" "api_url" || true)"
fi

existing_mode="${APORT_GUARDRAIL_MODE:-${existing_config_mode:-local}}"
selected_mode="${APORT_GUARDRAIL_MODE_CLI:-$existing_mode}"
selected_mode="$(printf '%s' "$selected_mode" | tr '[:upper:]' '[:lower:]')"
case "$selected_mode" in
    local | api) ;;
    *)
        log_error "Unsupported --mode value: $selected_mode (expected local|api)"
        exit 1
        ;;
esac

existing_agent_id="${APORT_HOSTED_AGENT_ID_CLI:-${APORT_AGENT_ID:-$existing_config_agent_id}}"
selected_api_url="${APORT_GUARDRAIL_API_URL_CLI:-${APORT_API_URL:-${existing_config_api_url:-$DEFAULT_APORT_API_URL}}}"
selected_enforcement_input="${APORT_ENFORCEMENT_CLI:-${APORT_ENFORCEMENT_MODE:-${APORT_ENFORCEMENT:-${APORT_GUARDRAIL_ENFORCEMENT:-enforce}}}}"
if ! selected_enforcement="$(normalize_aport_enforcement "$selected_enforcement_input")"; then
    log_error "Unsupported --enforcement value: $selected_enforcement_input (expected enforce|warn)"
    exit 1
fi

write_guardrail_mode_file "$config_dir" "$selected_mode" "$selected_api_url" "$existing_agent_id" "$selected_enforcement" > /dev/null

yaml_quote() {
    local value="${1//\'/\'\'}"
    printf "'%s'" "$value"
}

config_replace_or_append() {
    local file="$1"
    local key="$2"
    local value="$3"
    local tmpfile
    tmpfile="$(mktemp "${file}.XXXXXX")"
    awk -v key="$key" -v value="$value" '
        BEGIN { done = 0 }
        $0 ~ "^[[:space:]]*" key ":" {
            if (!done) {
                print key ": " value
                done = 1
            }
            next
        }
        { print }
        END {
            if (!done) {
                print key ": " value
            }
        }
    ' "$file" > "$tmpfile" && mv "$tmpfile" "$file"
}

update_generic_config() {
    local file="$config_dir/config.yaml"
    [[ -f "$file" ]] || return 0
    config_replace_or_append "$file" "mode" "$selected_mode"
    config_replace_or_append "$file" "enforcement_mode" "$(yaml_quote "$selected_enforcement")"
    if [[ "$selected_mode" == "api" ]]; then
        config_replace_or_append "$file" "api_url" "$(yaml_quote "$selected_api_url")"
        if [[ -n "$existing_agent_id" ]]; then
            config_replace_or_append "$file" "agent_id" "$(yaml_quote "$existing_agent_id")"
        fi
    fi
    chmod 600 "$file" 2> /dev/null || true
}

update_openclaw_json() {
    local file="$config_dir/openclaw.json"
    [[ -f "$file" ]] || return 0
    command -v jq > /dev/null 2>&1 || return 0

    local tmpfile
    tmpfile="$(mktemp "${file}.XXXXXX")"
    jq \
        --arg mode "$selected_mode" \
        --arg api_url "$selected_api_url" \
        --arg agent_id "$existing_agent_id" \
        --arg enforcement "$selected_enforcement" '
        if (.plugins.entries["openclaw-aport"]? == null) then
          .
        else
        .plugins = (.plugins // {}) |
        .plugins.entries = (.plugins.entries // {}) |
        .plugins.entries["openclaw-aport"].enabled = true |
        .plugins.entries["openclaw-aport"].config = (.plugins.entries["openclaw-aport"].config // {}) |
        .plugins.entries["openclaw-aport"].config.mode = $mode |
        .plugins.entries["openclaw-aport"].config.enforcementMode = $enforcement |
        (if $mode == "api" then .plugins.entries["openclaw-aport"].config.apiUrl = $api_url else . end) |
        (if $agent_id != "" then .plugins.entries["openclaw-aport"].config.agentId = $agent_id else . end)
        end
    ' "$file" > "$tmpfile" && mv "$tmpfile" "$file"
    chmod 600 "$file" 2> /dev/null || true
}

update_openclaw_yaml() {
    local file="$config_dir/config.yaml"
    [[ -f "$file" ]] || return 0
    command -v node > /dev/null 2>&1 || return 0

    APORT_SET_MODE_VALUE="$selected_mode" \
        APORT_SET_API_URL="$selected_api_url" \
        APORT_SET_AGENT_ID="$existing_agent_id" \
        APORT_SET_ENFORCEMENT="$selected_enforcement" \
        node - "$file" << 'NODE'
const fs = require("node:fs");
const file = process.argv[2];
const input = fs.readFileSync(file, "utf8");
const lines = input.split(/\n/);
const start = lines.findIndex((line) => /^\s*openclaw-aport:\s*$/.test(line));
if (start < 0) process.exit(0);
const indent = (lines[start].match(/^\s*/) || [""])[0];
let end = start + 1;
for (; end < lines.length; end += 1) {
  const line = lines[end];
  if (!line.trim()) continue;
  const currentIndent = (line.match(/^\s*/) || [""])[0].length;
  if (currentIndent <= indent.length) break;
}
const q = (value) => JSON.stringify(String(value || ""));
const configIndent = `${indent}    `;
function upsert(key, value) {
  const pattern = new RegExp(`^${configIndent}${key}:\\s*`);
  const replacement = `${configIndent}${key}: ${value}`;
  for (let i = start + 1; i < end; i += 1) {
    if (pattern.test(lines[i])) {
      lines[i] = replacement;
      return;
    }
  }
  lines.splice(end, 0, replacement);
  end += 1;
}
const mode = process.env.APORT_SET_MODE_VALUE || "local";
upsert("mode", q(mode));
upsert("enforcementMode", q(process.env.APORT_SET_ENFORCEMENT || "enforce"));
if (mode === "api") upsert("apiUrl", q(process.env.APORT_SET_API_URL || "https://api.aport.io"));
if (process.env.APORT_SET_AGENT_ID) upsert("agentId", q(process.env.APORT_SET_AGENT_ID));
fs.writeFileSync(file, lines.join("\n"), "utf8");
NODE
    chmod 600 "$file" 2> /dev/null || true
}

case "$framework" in
    openclaw)
        update_openclaw_json
        update_openclaw_yaml
        ;;
    langchain | crewai | deerflow | n8n)
        update_generic_config
        ;;
esac

log_info "Updated APort guardrail settings for $framework"
echo "  Config dir:  $config_dir"
echo "  Mode:        $selected_mode"
echo "  Enforcement: $selected_enforcement"
if [[ "$selected_mode" == "api" ]]; then
    echo "  API URL:     $selected_api_url"
fi
if [[ -n "$existing_agent_id" ]]; then
    echo "  Passport:    $existing_agent_id"
fi
echo "  Mode file:   $mode_file"

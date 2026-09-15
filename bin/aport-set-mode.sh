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

SUPPORTED_FRAMEWORKS=(openclaw langchain crewai cursor claude-code codex gemini-cli goose deerflow n8n)

usage() {
    cat << 'EOF'
Usage:
  aport-agent-guardrails mode <framework> [--mode=local|api] [--enforcement=enforce|warn]

Examples:
  aport-agent-guardrails mode claude-code --enforcement=warn
  aport-agent-guardrails mode codex --enforcement=warn
  aport-agent-guardrails mode gemini --mode=api --api-url=https://api.aport.io
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
case "$framework" in
    claude) framework="claude-code" ;;
    gemini) framework="gemini-cli" ;;
esac

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
if [[ "${#APORT_FRAMEWORK_ARGS[@]}" -gt 0 ]]; then
    if [[ "${#APORT_FRAMEWORK_ARGS[@]}" -eq 1 && ("${APORT_FRAMEWORK_ARGS[0]}" == "--help" || "${APORT_FRAMEWORK_ARGS[0]}" == "-h") ]]; then
        usage
        exit 0
    fi
    log_error "Unexpected argument for mode command: ${APORT_FRAMEWORK_ARGS[0]}"
    echo "Run: aport-agent-guardrails mode $framework --help" >&2
    exit 1
fi

has_explicit_config_dir_override() {
    [[ -n "${APORT_CONFIG_DIR:-}" ]] && return 0

    case "$framework" in
        openclaw)
            [[ -n "${APORT_OPENCLAW_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-}}" ]]
            ;;
        cursor)
            [[ -n "${APORT_CURSOR_CONFIG_DIR:-}" ]]
            ;;
        claude-code)
            [[ -n "${APORT_CLAUDE_CODE_CONFIG_DIR:-}" ]]
            ;;
        codex)
            [[ -n "${APORT_CODEX_CONFIG_DIR:-}" ]]
            ;;
        gemini-cli)
            [[ -n "${APORT_GEMINI_CLI_CONFIG_DIR:-}" ]]
            ;;
        goose)
            [[ -n "${APORT_GOOSE_CONFIG_DIR:-}" ]]
            ;;
        langchain)
            [[ -n "${APORT_LANGCHAIN_CONFIG_DIR:-}" ]]
            ;;
        crewai)
            [[ -n "${APORT_CREWAI_CONFIG_DIR:-}" ]]
            ;;
        deerflow)
            [[ -n "${APORT_DEERFLOW_CONFIG_DIR:-}" ]]
            ;;
        n8n)
            [[ -n "${APORT_N8N_CONFIG_DIR:-}" ]]
            ;;
        *)
            return 1
            ;;
    esac
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

read_hook_config_dir_from_file() {
    local file="$1"
    local env_name="$2"
    local hook_name="${3:-}"
    [[ -f "$file" ]] || return 0
    command -v node > /dev/null 2>&1 || return 0
    node - "$file" "$env_name" "$hook_name" << 'NODE'
const fs = require("node:fs");
const [file, envName, hookName] = process.argv.slice(2);
const input = fs.readFileSync(file, "utf8");

const commands = [];
const visit = (value) => {
  if (!value) return;
  if (typeof value === "string") return;
  if (Array.isArray(value)) {
    for (const item of value) visit(item);
    return;
  }
  if (typeof value !== "object") return;
  if (typeof value.command === "string" && value.command.includes(hookName)) {
    commands.push(value.command);
  }
  for (const child of Object.values(value)) visit(child);
};
try {
  visit(JSON.parse(input));
} catch {
  for (const line of input.split(/\r?\n/)) {
    if (!hookName || line.includes(hookName) || line.includes(`${envName}=`)) {
      commands.push(line);
    }
  }
}

const readAssignment = (command) => {
  const needle = `${envName}=`;
  const start = command.indexOf(needle);
  if (start < 0) return "";
  const rest = command.slice(start + needle.length);
  let value = "";
  let quote = "";
  for (let i = 0; i < rest.length; i += 1) {
    const ch = rest[i];
    if (quote === "'") {
      if (ch === "'") quote = "";
      else value += ch;
      continue;
    }
    if (quote === '"') {
      if (ch === '"') {
        quote = "";
      } else if (ch === "\\" && i + 1 < rest.length) {
        value += rest[i + 1];
        i += 1;
      } else {
        value += ch;
      }
      continue;
    }
    if (/\s/.test(ch)) break;
    if (ch === "'" || ch === '"') {
      quote = ch;
      continue;
    }
    if (ch === "\\" && i + 1 < rest.length) {
      value += rest[i + 1];
      i += 1;
      continue;
    }
    value += ch;
  }
  return quote ? "" : value;
};

for (const command of commands) {
  const value = readAssignment(command);
  if (value) {
    process.stdout.write(value);
    process.exit(0);
  }
}
NODE
}

read_command_hook_config_dir() {
    read_hook_config_dir_from_file "$1" "$2" "$3"
}

resolve_command_hook_state_dir() {
    local env_name="$1"
    local hook_name="$2"
    local project_file="$3"
    local global_file="$4"
    local state_dir

    state_dir="$(read_command_hook_config_dir "$project_file" "$env_name" "$hook_name")"
    if [[ -n "$state_dir" ]]; then
        printf '%s' "${state_dir/#\~/$HOME}"
        return 0
    fi
    state_dir="$(read_command_hook_config_dir "$global_file" "$env_name" "$hook_name")"
    if [[ -n "$state_dir" ]]; then
        printf '%s' "${state_dir/#\~/$HOME}"
        return 0
    fi
    return 1
}

resolve_goose_plugin_state_dir() {
    local state_dir
    local custom_plugin_dir="${APORT_GOOSE_PLUGIN_DIR:-}"
    local plugin_scripts=()

    if [[ -n "$custom_plugin_dir" ]]; then
        plugin_scripts+=("${custom_plugin_dir/#\~/$HOME}/scripts/aport-goose-hook.sh")
    fi
    plugin_scripts+=("$PWD/.agents/plugins/aport-guardrail/scripts/aport-goose-hook.sh")
    plugin_scripts+=("$HOME/.agents/plugins/aport-guardrail/scripts/aport-goose-hook.sh")

    for wrapper in "${plugin_scripts[@]}"; do
        state_dir="$(read_hook_config_dir_from_file "$wrapper" "APORT_GOOSE_CONFIG_DIR")"
        if [[ -n "$state_dir" ]]; then
            printf '%s' "${state_dir/#\~/$HOME}"
            return 0
        fi
    done

    return 1
}

resolve_set_mode_config_dir() {
    local framework_override
    framework_override="$(framework_specific_config_dir_override)"
    if [[ -n "$framework_override" ]]; then
        printf '%s' "$framework_override"
        return 0
    fi

    if [[ -n "${APORT_CONFIG_DIR:-}" ]]; then
        printf '%s' "$APORT_CONFIG_DIR"
        return 0
    fi

    case "$framework" in
        codex)
            if [[ -n "${APORT_CODEX_HOOKS_DIR:-}" ]] && config_from_hook="$(read_command_hook_config_dir "${APORT_CODEX_HOOKS_DIR/#\~/$HOME}/hooks.json" "APORT_CODEX_CONFIG_DIR" "aport-codex-hook.sh")" && [[ -n "$config_from_hook" ]]; then
                printf '%s' "${config_from_hook/#\~/$HOME}"
                return 0
            fi
            local codex_home="${CODEX_HOME:-$HOME/.codex}"
            codex_home="${codex_home/#\~/$HOME}"
            if config_from_hook="$(resolve_command_hook_state_dir "APORT_CODEX_CONFIG_DIR" "aport-codex-hook.sh" "$PWD/.codex/hooks.json" "$codex_home/hooks.json" "$HOME/.codex/hooks.json")"; then
                printf '%s' "$config_from_hook"
                return 0
            fi
            ;;
        gemini-cli)
            if [[ -n "${APORT_GEMINI_CLI_HOOKS_DIR:-}" ]] && config_from_hook="$(read_command_hook_config_dir "${APORT_GEMINI_CLI_HOOKS_DIR/#\~/$HOME}/settings.json" "APORT_GEMINI_CLI_CONFIG_DIR" "aport-gemini-cli-hook.sh")" && [[ -n "$config_from_hook" ]]; then
                printf '%s' "${config_from_hook/#\~/$HOME}"
                return 0
            fi
            if config_from_hook="$(resolve_command_hook_state_dir "APORT_GEMINI_CLI_CONFIG_DIR" "aport-gemini-cli-hook.sh" "$PWD/.gemini/settings.json" "$HOME/.gemini/settings.json")"; then
                printf '%s' "$config_from_hook"
                return 0
            fi
            ;;
        goose)
            if config_from_hook="$(resolve_goose_plugin_state_dir)"; then
                printf '%s' "$config_from_hook"
                return 0
            fi
            ;;
        langchain | crewai | deerflow | n8n)
            if ! has_explicit_config_dir_override && [[ -f "$PWD/.aport/config.yaml" ]]; then
                printf '%s/.aport' "$PWD"
                return 0
            fi
            ;;
    esac

    get_config_dir "$framework"
}

config_dir="$(resolve_set_mode_config_dir)"
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

require_node() {
    local purpose="${1:-update APort config}"
    if ! command -v node > /dev/null 2>&1; then
        log_error "Node.js is required to $purpose."
        exit 1
    fi
}

read_openclaw_json_config_value() {
    local file="$1"
    local key="$2"
    [[ -f "$file" ]] || return 0
    require_node "read OpenClaw JSON config"
    node - "$file" "$key" << 'NODE'
const fs = require("node:fs");
const [file, key] = process.argv.slice(2);
try {
  const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
  const value = cfg?.plugins?.entries?.["openclaw-aport"]?.config?.[key];
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    process.stdout.write(String(value));
  }
} catch {
  process.exit(0);
}
NODE
}

read_openclaw_yaml_config_value() {
    local file="$1"
    local key="$2"
    [[ -f "$file" ]] || return 0
    require_node "read OpenClaw YAML config"
    node - "$file" "$key" << 'NODE'
const fs = require("node:fs");
const [file, key] = process.argv.slice(2);
const input = fs.readFileSync(file, "utf8");
const lines = input.split(/\n/);
const start = lines.findIndex((line) => /^\s*openclaw-aport:\s*$/.test(line));
if (start < 0) process.exit(0);
const pluginIndent = (lines[start].match(/^\s*/) || [""])[0].length;
let end = start + 1;
for (; end < lines.length; end += 1) {
  const line = lines[end];
  if (!line.trim()) continue;
  const currentIndent = (line.match(/^\s*/) || [""])[0].length;
  if (currentIndent <= pluginIndent) break;
}
let configIndent = -1;
let configLine = -1;
for (let i = start + 1; i < end; i += 1) {
  if (/^\s*config:\s*$/.test(lines[i])) {
    configIndent = (lines[i].match(/^\s*/) || [""])[0].length;
    configLine = i;
    break;
  }
}
if (configIndent < 0) process.exit(0);
const keyPattern = new RegExp(`^\\s*${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}:\\s*(.*)$`);
for (let i = configLine + 1; i < end; i += 1) {
  const line = lines[i];
  if (!line.trim()) continue;
  const indent = (line.match(/^\s*/) || [""])[0].length;
  if (indent <= configIndent) break;
  const match = line.match(keyPattern);
  if (!match) continue;
  const raw = String(match[1] || "").trim();
  if ((raw.startsWith('"') && raw.endsWith('"')) || (raw.startsWith("'") && raw.endsWith("'"))) {
    process.stdout.write(raw.slice(1, -1));
  } else {
    process.stdout.write(raw);
  }
  break;
}
NODE
}

expand_user_path() {
    local value="$1"
    printf '%s' "${value/#\~/$HOME}"
}

validate_local_passport_file() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    require_node "validate the local passport file"
    node - "$file" << 'NODE'
const fs = require("node:fs");
const file = process.argv[2];
try {
  const passport = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!passport || typeof passport !== "object" || Array.isArray(passport)) process.exit(1);
  if (!passport.agent_id && !passport.passport_id && !passport.id) process.exit(1);
} catch {
  process.exit(1);
}
NODE
}

existing_config_mode=""
existing_config_agent_id=""
existing_config_api_url=""
existing_config_api_key=""
existing_config_passport_file=""
existing_config_enforcement=""
if [[ "$framework" == "openclaw" ]]; then
    openclaw_json="$config_dir/openclaw.json"
    existing_config_mode="$(read_openclaw_json_config_value "$openclaw_json" "mode" || true)"
    existing_config_agent_id="$(read_openclaw_json_config_value "$openclaw_json" "agentId" || true)"
    existing_config_api_url="$(read_openclaw_json_config_value "$openclaw_json" "apiUrl" || true)"
    existing_config_api_key="$(read_openclaw_json_config_value "$openclaw_json" "apiKey" || true)"
    existing_config_passport_file="$(read_openclaw_json_config_value "$openclaw_json" "passportFile" || true)"
    existing_config_enforcement="$(read_openclaw_json_config_value "$openclaw_json" "enforcementMode" || true)"
    if [[ -z "$existing_config_mode" || -z "$existing_config_agent_id" || -z "$existing_config_api_url" || -z "$existing_config_api_key" || -z "$existing_config_passport_file" || -z "$existing_config_enforcement" ]]; then
        openclaw_yaml="$config_dir/config.yaml"
        [[ -z "$existing_config_mode" ]] && existing_config_mode="$(read_openclaw_yaml_config_value "$openclaw_yaml" "mode" || true)"
        [[ -z "$existing_config_agent_id" ]] && existing_config_agent_id="$(read_openclaw_yaml_config_value "$openclaw_yaml" "agentId" || true)"
        [[ -z "$existing_config_api_url" ]] && existing_config_api_url="$(read_openclaw_yaml_config_value "$openclaw_yaml" "apiUrl" || true)"
        [[ -z "$existing_config_api_key" ]] && existing_config_api_key="$(read_openclaw_yaml_config_value "$openclaw_yaml" "apiKey" || true)"
        [[ -z "$existing_config_passport_file" ]] && existing_config_passport_file="$(read_openclaw_yaml_config_value "$openclaw_yaml" "passportFile" || true)"
        [[ -z "$existing_config_enforcement" ]] && existing_config_enforcement="$(read_openclaw_yaml_config_value "$openclaw_yaml" "enforcementMode" || true)"
    fi
elif [[ "$framework" == "langchain" || "$framework" == "crewai" || "$framework" == "deerflow" || "$framework" == "n8n" ]]; then
    generic_config="$config_dir/config.yaml"
    existing_config_mode="$(read_yaml_scalar "$generic_config" "mode" || true)"
    existing_config_agent_id="$(read_yaml_scalar "$generic_config" "agent_id" || true)"
    existing_config_api_url="$(read_yaml_scalar "$generic_config" "api_url" || true)"
    existing_config_passport_file="$(read_yaml_scalar "$generic_config" "passport_path" || true)"
    existing_config_enforcement="$(read_yaml_scalar "$generic_config" "enforcement_mode" || true)"
    [[ -z "$existing_config_enforcement" ]] && existing_config_enforcement="$(read_yaml_scalar "$generic_config" "enforcementMode" || true)"
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
selected_api_key="${APORT_API_KEY:-$existing_config_api_key}"
selected_enforcement_input="${APORT_ENFORCEMENT_CLI:-${APORT_ENFORCEMENT_MODE:-${APORT_ENFORCEMENT:-${APORT_GUARDRAIL_ENFORCEMENT:-${existing_config_enforcement:-enforce}}}}}"
if ! selected_enforcement="$(normalize_aport_enforcement "$selected_enforcement_input")"; then
    log_error "Unsupported --enforcement value: $selected_enforcement_input (expected enforce|warn)"
    exit 1
fi

default_passport_file="$config_dir/aport/passport.json"
local_passport_file="$(expand_user_path "${existing_config_passport_file:-$default_passport_file}")"
guardrail_script="$SCRIPT_DIR/aport-guardrail-bash.sh"

if [[ "$selected_mode" == "local" ]]; then
    if [[ -n "${APORT_HOSTED_AGENT_ID_CLI:-}" ]]; then
        log_error "--mode=local cannot be combined with a hosted passport ID."
        exit 1
    fi
    if ! validate_local_passport_file "$local_passport_file"; then
        log_error "Cannot switch $framework to local mode because no valid local passport exists at $local_passport_file."
        echo "Create a local passport first, or use --mode=api for the existing hosted passport." >&2
        exit 1
    fi
    existing_agent_id=""
    selected_api_url=""
    selected_api_key=""
fi

if [[ "$selected_mode" == "api" && -n "$selected_api_key" ]]; then
    export APORT_API_KEY="$selected_api_key"
fi

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

config_delete_key() {
    local file="$1"
    local key="$2"
    local tmpfile
    tmpfile="$(mktemp "${file}.XXXXXX")"
    awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key ":" { next }
        { print }
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
    else
        config_replace_or_append "$file" "passport_path" "$(yaml_quote "$local_passport_file")"
        config_delete_key "$file" "agent_id"
        config_delete_key "$file" "api_url"
    fi
    chmod 600 "$file" 2> /dev/null || true
}

update_openclaw_json() {
    local file="$config_dir/openclaw.json"
    [[ -f "$file" ]] || return 0
    require_node "update OpenClaw JSON config"

    local tmpfile
    tmpfile="$(mktemp "${file}.XXXXXX")"
    APORT_SET_MODE_VALUE="$selected_mode" \
        APORT_SET_API_URL="$selected_api_url" \
        APORT_SET_AGENT_ID="$existing_agent_id" \
        APORT_SET_API_KEY="$selected_api_key" \
        APORT_SET_ENFORCEMENT="$selected_enforcement" \
        APORT_SET_PASSPORT_FILE="$local_passport_file" \
        APORT_SET_GUARDRAIL_SCRIPT="$guardrail_script" \
        node - "$file" "$tmpfile" << 'NODE'
const fs = require("node:fs");
const [file, tmpfile] = process.argv.slice(2);
const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
const entry = cfg?.plugins?.entries?.["openclaw-aport"];
if (entry) {
  entry.enabled = true;
  const config = entry.config && typeof entry.config === "object" && !Array.isArray(entry.config)
    ? entry.config
    : {};
  entry.config = config;
  const mode = process.env.APORT_SET_MODE_VALUE || "local";
  config.mode = mode;
  config.enforcementMode = process.env.APORT_SET_ENFORCEMENT || "enforce";
  if (mode === "api") {
    config.apiUrl = process.env.APORT_SET_API_URL || "https://api.aport.io";
    if (process.env.APORT_SET_AGENT_ID) {
      config.agentId = process.env.APORT_SET_AGENT_ID;
      delete config.passportFile;
      delete config.guardrailScript;
    } else {
      delete config.agentId;
      config.passportFile = process.env.APORT_SET_PASSPORT_FILE;
      config.guardrailScript = process.env.APORT_SET_GUARDRAIL_SCRIPT;
    }
    if (process.env.APORT_SET_API_KEY) config.apiKey = process.env.APORT_SET_API_KEY;
  } else {
    config.passportFile = process.env.APORT_SET_PASSPORT_FILE;
    config.guardrailScript = process.env.APORT_SET_GUARDRAIL_SCRIPT;
    delete config.agentId;
    delete config.apiKey;
    delete config.apiUrl;
  }
}
fs.writeFileSync(tmpfile, `${JSON.stringify(cfg, null, 2)}\n`, "utf8");
NODE
    mv "$tmpfile" "$file"
    chmod 600 "$file" 2> /dev/null || true
}

update_openclaw_yaml() {
    local file="$config_dir/config.yaml"
    [[ -f "$file" ]] || return 0
    require_node "update OpenClaw YAML config"

    APORT_SET_MODE_VALUE="$selected_mode" \
        APORT_SET_API_URL="$selected_api_url" \
        APORT_SET_AGENT_ID="$existing_agent_id" \
        APORT_SET_API_KEY="$selected_api_key" \
        APORT_SET_ENFORCEMENT="$selected_enforcement" \
        APORT_SET_PASSPORT_FILE="$local_passport_file" \
        APORT_SET_GUARDRAIL_SCRIPT="$guardrail_script" \
        node - "$file" << 'NODE'
const fs = require("node:fs");
const file = process.argv[2];
const input = fs.readFileSync(file, "utf8");
const lines = input.split(/\n/);
const start = lines.findIndex((line) => /^\s*openclaw-aport:\s*$/.test(line));
if (start < 0) process.exit(0);
const indent = (lines[start].match(/^\s*/) || [""])[0];
const pluginIndentLength = indent.length;
let end = start + 1;
for (; end < lines.length; end += 1) {
  const line = lines[end];
  if (!line.trim()) continue;
  const currentIndent = (line.match(/^\s*/) || [""])[0].length;
  if (currentIndent <= pluginIndentLength) break;
}
let configIndex = lines.findIndex((line, index) => index > start && index < end && /^\s*config:\s*$/.test(line));
function inferIndentUnit() {
  for (let i = start + 1; i < end; i += 1) {
    if (!lines[i].trim()) continue;
    const currentIndent = (lines[i].match(/^\s*/) || [""])[0].length;
    if (currentIndent > pluginIndentLength) return currentIndent - pluginIndentLength;
  }
  return 2;
}
if (configIndex < 0) {
  const unit = inferIndentUnit();
  lines.splice(end, 0, `${indent}${" ".repeat(unit)}config:`);
  configIndex = end;
  end += 1;
}
const configIndent = (lines[configIndex].match(/^\s*/) || [""])[0];
const configIndentLength = configIndent.length;
let childIndent = "";
for (let i = configIndex + 1; i < end; i += 1) {
  if (!lines[i].trim()) continue;
  const currentIndent = (lines[i].match(/^\s*/) || [""])[0];
  if (currentIndent.length > configIndentLength) {
    childIndent = currentIndent;
    break;
  }
  if (currentIndent.length <= configIndentLength) break;
}
if (!childIndent) {
  const unit = Math.max(2, configIndentLength - pluginIndentLength || inferIndentUnit());
  childIndent = `${configIndent}${" ".repeat(unit)}`;
}
const q = (value) => JSON.stringify(String(value || ""));
const escapedIndent = childIndent.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
function upsert(key, value) {
  const pattern = new RegExp(`^${escapedIndent}${key}:\\s*`);
  const replacement = `${childIndent}${key}: ${value}`;
  for (let i = configIndex + 1; i < end; i += 1) {
    const currentIndent = (lines[i].match(/^\s*/) || [""])[0].length;
    if (lines[i].trim() && currentIndent <= configIndentLength) break;
    if (pattern.test(lines[i])) {
      lines[i] = replacement;
      return;
    }
  }
  lines.splice(end, 0, replacement);
  end += 1;
}
function remove(key) {
  const pattern = new RegExp(`^${escapedIndent}${key}:\\s*`);
  for (let i = end - 1; i > configIndex; i -= 1) {
    if (pattern.test(lines[i])) {
      lines.splice(i, 1);
      end -= 1;
    }
  }
}
const mode = process.env.APORT_SET_MODE_VALUE || "local";
upsert("mode", q(mode));
upsert("enforcementMode", q(process.env.APORT_SET_ENFORCEMENT || "enforce"));
if (mode === "api") {
  upsert("apiUrl", q(process.env.APORT_SET_API_URL || "https://api.aport.io"));
  if (process.env.APORT_SET_AGENT_ID) {
    upsert("agentId", q(process.env.APORT_SET_AGENT_ID));
    remove("passportFile");
    remove("guardrailScript");
  } else {
    remove("agentId");
    upsert("passportFile", q(process.env.APORT_SET_PASSPORT_FILE));
    upsert("guardrailScript", q(process.env.APORT_SET_GUARDRAIL_SCRIPT));
  }
  if (process.env.APORT_SET_API_KEY) upsert("apiKey", q(process.env.APORT_SET_API_KEY));
} else {
  upsert("passportFile", q(process.env.APORT_SET_PASSPORT_FILE));
  upsert("guardrailScript", q(process.env.APORT_SET_GUARDRAIL_SCRIPT));
  remove("agentId");
  remove("apiKey");
  remove("apiUrl");
}
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

write_guardrail_mode_file "$config_dir" "$selected_mode" "$selected_api_url" "$existing_agent_id" "$selected_enforcement" > /dev/null

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

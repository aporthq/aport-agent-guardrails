#!/bin/bash
# Resolve APort data paths: prefer config_dir/aport/, fallback to config_dir (legacy).
# MUST be sourced by any script that reads/writes passport, decision, or audit:
#   - aport-guardrail-bash.sh
#   - aport-guardrail-api.sh
#   - aport-status.sh
# (aport-create-passport.sh uses --output; wrappers set env so children get resolved paths.)
# Sets: OPENCLAW_PASSPORT_FILE, OPENCLAW_DECISION_FILE, OPENCLAW_AUDIT_LOG
# and PASSPORT_FILE, DECISION_FILE, AUDIT_LOG. Passport status (active|suspended|revoked) is source of truth for suspend; no separate file.
# Caller must ensure APORT_DATA_DIR exists before writing (e.g. mkdir -p "$(dirname "$AUDIT_LOG")").

resolve_aport_paths() {
    local config_dir
    local passport_path
    local data_dir

    # 1) Explicit path set and file exists → use it (plugin or wrapper)
    if [ -n "${OPENCLAW_PASSPORT_FILE:-}" ] && [ -f "$OPENCLAW_PASSPORT_FILE" ]; then
        data_dir="$(dirname "$OPENCLAW_PASSPORT_FILE")"
        passport_path="$OPENCLAW_PASSPORT_FILE"
    # 2) Explicit path set but file missing → legacy: try parent dir (e.g. .../openclaw/passport.json)
    elif [ -n "${OPENCLAW_PASSPORT_FILE:-}" ]; then
        config_dir="$(cd "$(dirname "$OPENCLAW_PASSPORT_FILE")/.." 2>/dev/null && pwd)"
        if [ -f "${config_dir}/passport.json" ]; then
            passport_path="${config_dir}/passport.json"
            data_dir="$config_dir"
        else
            passport_path="$OPENCLAW_PASSPORT_FILE"
            data_dir="$(dirname "$OPENCLAW_PASSPORT_FILE")"
        fi
    # 3) No env → probe framework-specific default paths (where each framework stores data), then OpenClaw legacy
    else
        config_dir=""
        for candidate in "$HOME/.cursor" "$HOME/.openclaw" "$HOME/.aport/langchain" "$HOME/.aport/crewai" "$HOME/.n8n"; do
            if [ -f "${candidate}/aport/passport.json" ]; then
                config_dir="$candidate"
                break
            fi
        done
        if [ -z "$config_dir" ]; then
            config_dir="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
        fi
        config_dir="${config_dir/#\~/$HOME}"
        if [ -f "${config_dir}/aport/passport.json" ]; then
            passport_path="${config_dir}/aport/passport.json"
            data_dir="${config_dir}/aport"
        elif [ -f "${config_dir}/passport.json" ]; then
            passport_path="${config_dir}/passport.json"
            data_dir="$config_dir"
        else
            passport_path="${config_dir}/aport/passport.json"
            data_dir="${config_dir}/aport"
        fi
    fi

    export OPENCLAW_PASSPORT_FILE="$passport_path"
    # Preserve explicitly set decision path (e.g. tests set OPENCLAW_DECISION_FILE); otherwise use data_dir
    if [ -n "${OPENCLAW_DECISION_FILE:-}" ]; then
        export OPENCLAW_DECISION_FILE="$OPENCLAW_DECISION_FILE"
    else
        export OPENCLAW_DECISION_FILE="${data_dir}/decision.json"
    fi
    export OPENCLAW_AUDIT_LOG="${data_dir}/audit.log"

    PASSPORT_FILE="$OPENCLAW_PASSPORT_FILE"
    DECISION_FILE="$OPENCLAW_DECISION_FILE"
    AUDIT_LOG="$OPENCLAW_AUDIT_LOG"
}

# When sourced, resolve immediately so callers just use the vars
resolve_aport_paths

#!/bin/bash
# Resolve APort data paths: prefer config_dir/aport/, fallback to config_dir (legacy).
# MUST be sourced by any script that reads/writes passport, decision, audit, or kill-switch:
#   - aport-guardrail-bash.sh
#   - aport-guardrail-api.sh
#   - aport-status.sh
# (aport-create-passport.sh uses --output; wrappers set env so children get resolved paths.)
# Sets: OPENCLAW_PASSPORT_FILE, OPENCLAW_DECISION_FILE, OPENCLAW_AUDIT_LOG, OPENCLAW_KILL_SWITCH
# and PASSPORT_FILE, DECISION_FILE, AUDIT_LOG, KILL_SWITCH for script use.
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
    # 3) No env → try aport then legacy
    else
        config_dir="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
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
    export OPENCLAW_DECISION_FILE="${data_dir}/decision.json"
    export OPENCLAW_AUDIT_LOG="${data_dir}/audit.log"
    export OPENCLAW_KILL_SWITCH="${data_dir}/kill-switch"

    PASSPORT_FILE="$OPENCLAW_PASSPORT_FILE"
    DECISION_FILE="$OPENCLAW_DECISION_FILE"
    AUDIT_LOG="$OPENCLAW_AUDIT_LOG"
    KILL_SWITCH="$OPENCLAW_KILL_SWITCH"
}

# When sourced, resolve immediately so callers just use the vars
resolve_aport_paths

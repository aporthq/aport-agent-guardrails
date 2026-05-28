#!/bin/bash
# Resolve APort data paths: prefer config_dir/aport/, fallback to config_dir (legacy).
# MUST be sourced by any script that reads/writes passport, decision, or audit:
#   - aport-guardrail-bash.sh
#   - aport-guardrail-api.sh
#   - aport-status.sh
# (aport-create-passport.sh uses --output; wrappers set env so children get resolved paths.)
# Sets canonical APORT_* path variables plus legacy OPENCLAW_* aliases for compatibility.
# Also sets PASSPORT_FILE, DECISION_FILE, AUDIT_LOG. Passport status (active|suspended|revoked)
# is source of truth for suspend; no separate file.
# Caller must ensure APORT_DATA_DIR exists before writing (e.g. mkdir -p "$(dirname "$AUDIT_LOG")").

resolve_aport_paths() {
    local config_dir
    local passport_path
    local data_dir
    local explicit_passport="${APORT_PASSPORT_FILE:-${OPENCLAW_PASSPORT_FILE:-}}"
    local explicit_decision="${APORT_DECISION_FILE:-${OPENCLAW_DECISION_FILE:-}}"
    local explicit_audit="${APORT_AUDIT_LOG:-${OPENCLAW_AUDIT_LOG:-}}"
    local explicit_config="${APORT_CONFIG_DIR:-${OPENCLAW_CONFIG_DIR:-}}"

    # Source validation if available (for validate_passport_path)
    local _resolve_script_dir
    _resolve_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$_resolve_script_dir/lib/validation.sh" ]; then
        # shellcheck source=lib/validation.sh
        . "$_resolve_script_dir/lib/validation.sh" 2> /dev/null || true
    elif [ -f "$_resolve_script_dir/../bin/lib/validation.sh" ]; then
        . "$_resolve_script_dir/../bin/lib/validation.sh" 2> /dev/null || true
    fi

    [ -n "$explicit_passport" ] && explicit_passport="${explicit_passport/#\~/$HOME}"
    [ -n "$explicit_decision" ] && explicit_decision="${explicit_decision/#\~/$HOME}"
    [ -n "$explicit_audit" ] && explicit_audit="${explicit_audit/#\~/$HOME}"
    [ -n "$explicit_config" ] && explicit_config="${explicit_config/#\~/$HOME}"

    # 0) AGENTS.md enforcement block (repo-scoped, highest priority after explicit env)
    #    Only checked when no explicit passport env var is set.
    if [ -z "$explicit_passport" ]; then
        local _agentsmd_lib="$_resolve_script_dir/lib/agentsmd.sh"
        [ ! -f "$_agentsmd_lib" ] && _agentsmd_lib="$_resolve_script_dir/../bin/lib/agentsmd.sh"
        if [ -f "$_agentsmd_lib" ]; then
            # shellcheck source=lib/agentsmd.sh
            . "$_agentsmd_lib"
            if resolve_agentsmd_enforcement 2> /dev/null; then
                if [ -n "$AGENTSMD_AGENT_ID" ]; then
                    export APORT_AGENT_ID="$AGENTSMD_AGENT_ID"
                fi
                if [ -n "$AGENTSMD_PASSPORT" ] && [ -f "$AGENTSMD_PASSPORT" ]; then
                    passport_path="$AGENTSMD_PASSPORT"
                    data_dir="$(dirname "$AGENTSMD_PASSPORT")"
                    explicit_decision="${explicit_decision:-${data_dir}/decision.json}"
                    explicit_audit="${explicit_audit:-${data_dir}/audit.log}"

                    export APORT_PASSPORT_FILE="$passport_path"
                    export OPENCLAW_PASSPORT_FILE="$passport_path"
                    export APORT_DECISION_FILE="$explicit_decision"
                    export OPENCLAW_DECISION_FILE="$explicit_decision"
                    export APORT_AUDIT_LOG="$explicit_audit"
                    export OPENCLAW_AUDIT_LOG="$explicit_audit"

                    PASSPORT_FILE="$passport_path"
                    DECISION_FILE="$explicit_decision"
                    AUDIT_LOG="$explicit_audit"
                    return 0
                fi
            fi
        fi
    fi

    # 1) Explicit path set and file exists -> use it (plugin or wrapper)
    if [ -n "$explicit_passport" ] && [ -f "$explicit_passport" ]; then
        # Validate env-provided path if validator is available
        if type validate_explicit_passport_path &> /dev/null; then
            if ! validate_explicit_passport_path "$explicit_passport"; then
                echo "[aport] WARN: APORT_PASSPORT_FILE path failed validation: $explicit_passport" >&2
            fi
        fi
        data_dir="$(dirname "$explicit_passport")"
        passport_path="$explicit_passport"
    # 2) Explicit path set but file missing -> legacy: try parent dir (e.g. .../openclaw/passport.json)
    elif [ -n "$explicit_passport" ]; then
        config_dir="$(cd "$(dirname "$explicit_passport")/.." 2> /dev/null && pwd)"
        if [ -f "${config_dir}/passport.json" ]; then
            passport_path="${config_dir}/passport.json"
            data_dir="$config_dir"
        else
            passport_path="$explicit_passport"
            data_dir="$(dirname "$explicit_passport")"
        fi
    # 3) Probe framework paths, or honor APORT_CONFIG_DIR / OPENCLAW_CONFIG_DIR set by framework hooks.
    else
        if [ -n "$explicit_config" ]; then
            config_dir="$explicit_config"
        else
            config_dir=""
            for candidate in "$HOME/.claude" "$HOME/.cursor" "$HOME/.openclaw" "$HOME/.aport/langchain" "$HOME/.aport/crewai" "$HOME/.aport/deerflow" "$HOME/.n8n"; do
                if [ -f "${candidate}/aport/passport.json" ]; then
                    config_dir="$candidate"
                    break
                fi
            done
            if [ -z "$config_dir" ]; then
                config_dir="$HOME/.openclaw"
            fi
        fi
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

    export APORT_PASSPORT_FILE="$passport_path"
    export OPENCLAW_PASSPORT_FILE="$passport_path"

    # Preserve explicitly set decision/audit paths (e.g. tests); otherwise use data_dir.
    if [ -n "$explicit_decision" ]; then
        export APORT_DECISION_FILE="$explicit_decision"
    else
        export APORT_DECISION_FILE="${data_dir}/decision.json"
    fi
    export OPENCLAW_DECISION_FILE="$APORT_DECISION_FILE"

    if [ -n "$explicit_audit" ]; then
        export APORT_AUDIT_LOG="$explicit_audit"
    else
        export APORT_AUDIT_LOG="${data_dir}/audit.log"
    fi
    export OPENCLAW_AUDIT_LOG="$APORT_AUDIT_LOG"

    PASSPORT_FILE="$APORT_PASSPORT_FILE"
    DECISION_FILE="$APORT_DECISION_FILE"
    AUDIT_LOG="$APORT_AUDIT_LOG"
}

# When sourced, resolve immediately so callers just use the vars.
resolve_aport_paths

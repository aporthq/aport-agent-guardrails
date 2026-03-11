#!/usr/bin/env bash
# Command allowlisting helpers (shared across frameworks)
# Used by evaluator / policy to check allowed_commands vs blocked patterns.

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]:-.}")/common.sh"

# Stub: command allowlist checking is implemented directly in aport-guardrail-bash.sh
# (safe_prefix_match + blocked_patterns). This file is kept for backward compatibility
# but callers MUST NOT rely on this function for security enforcement.
check_command_allowed() {
    local command_line="$1"
    local allowed_list="${2:-*}"
    [[ -z "$command_line" ]] && return 1
    # SECURITY: Not implemented here — use aport-guardrail-bash.sh for actual enforcement
    echo "[aport] WARN: check_command_allowed is a stub; use aport-guardrail-bash.sh" >&2
    return 1
}

export -f check_command_allowed

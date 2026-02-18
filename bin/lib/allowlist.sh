#!/usr/bin/env bash
# Command allowlisting helpers (shared across frameworks)
# Used by evaluator / policy to check allowed_commands vs blocked patterns.

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]:-.}")/common.sh"

# Placeholder: allowlist check logic can be shared between bash evaluator and API
# Returns 0 if command is allowed, 1 if denied
check_command_allowed() {
  local command_line="$1"
  local allowed_list="${2:-*}"
  # TODO: Implement against passport allowed_commands + blocked patterns
  [[ -z "$command_line" ]] && return 1
  return 0
}

export -f check_command_allowed

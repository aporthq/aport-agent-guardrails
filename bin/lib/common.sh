#!/usr/bin/env bash
# Shared bash functions for APort agent-guardrails (multi-framework)
# Used by passport wizard, config helpers, and framework installers.

set -euo pipefail

# Resolve script directory and project root
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)}"
# Project root: bin/lib -> repo root
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)}"

# Log helpers
log_info()  { echo "[aport] $*" >&2; }
log_warn()  { echo "[aport] WARN: $*" >&2; }
log_error() { echo "[aport] ERROR: $*" >&2; }

# Check required commands
require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: $cmd"
    exit 1
  fi
}

# Export for subshells
export SCRIPT_DIR ROOT_DIR
export -f log_info log_warn log_error require_cmd

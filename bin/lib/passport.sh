#!/usr/bin/env bash
# Passport creation wizard logic (shared across frameworks)
# OAP v1.0 format; used by bin/aport-create-passport.sh and framework installers.

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]:-.}")/common.sh"

# Placeholder: full wizard logic can be refactored from aport-create-passport.sh
run_passport_wizard() {
  log_info "Running passport wizard (shared)..."
  # Delegate to existing script if present
  if [[ -x "$ROOT_DIR/bin/aport-create-passport.sh" ]]; then
    "$ROOT_DIR/bin/aport-create-passport.sh" "$@"
  else
    log_warn "bin/aport-create-passport.sh not found; wizard stub only."
  fi
}

export -f run_passport_wizard

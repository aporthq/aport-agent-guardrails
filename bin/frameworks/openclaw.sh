#!/usr/bin/env bash
# OpenClaw framework: delegate to full installer so passport wizard, config,
# plugin, and next steps all run identically (single source of truth in bin/openclaw).
# Pass-through: all arguments ($@) are passed to bin/openclaw (e.g. agent_id for
# hosted passport, or any future flags/openclaw options). Non-interactive use
# (e.g. agent_id only) is unchanged when invoked via agent-guardrails openclaw <agent_id>.

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]:-.}")/../lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
OPENCLAW_BIN="$SCRIPT_DIR/../openclaw"

if [[ ! -x "$OPENCLAW_BIN" ]]; then
  log_error "OpenClaw installer not found: $OPENCLAW_BIN"
  exit 1
fi

exec "$OPENCLAW_BIN" "$@"

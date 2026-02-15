#!/bin/bash
# Backward-compat wrapper: runs API evaluator (agent_id or passport).
# Prefer: bin/aport-guardrail-api.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/aport-guardrail-api.sh" "$@"

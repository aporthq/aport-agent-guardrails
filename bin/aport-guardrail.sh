#!/bin/bash
# Backward-compat wrapper: runs built-in bash evaluator (no API).
# Prefer: bin/aport-guardrail-bash.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/aport-guardrail-bash.sh" "$@"

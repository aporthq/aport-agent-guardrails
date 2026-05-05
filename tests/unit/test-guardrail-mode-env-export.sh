#!/bin/bash
# Unit test: guardrail mode loaded from disk must be exported so child guardrail
# processes receive hosted-mode settings like APORT_AGENT_ID.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "$0")/../setup.sh"
source "$REPO_ROOT/bin/lib/guardrail-mode.sh"

mkdir -p "$TEST_DIR/aport"
MODE_FILE="$TEST_DIR/aport/guardrail-mode.env"

cat > "$MODE_FILE" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_API_URL=https://api.aport.io
APORT_AGENT_ID=ap_04c65c1dd7224160b36b756960e2cc48
EOF

unset APORT_GUARDRAIL_MODE APORT_API_URL APORT_AGENT_ID 2> /dev/null || true

load_guardrail_mode_for_hooks "$TEST_DIR"

[ "$APORT_GUARDRAIL_MODE" = "api" ] || {
    echo "FAIL: expected APORT_GUARDRAIL_MODE=api in current shell, got '${APORT_GUARDRAIL_MODE:-}'" >&2
    exit 1
}

[ "$APORT_API_URL" = "https://api.aport.io" ] || {
    echo "FAIL: expected APORT_API_URL in current shell, got '${APORT_API_URL:-}'" >&2
    exit 1
}

[ "$APORT_AGENT_ID" = "ap_04c65c1dd7224160b36b756960e2cc48" ] || {
    echo "FAIL: expected APORT_AGENT_ID in current shell, got '${APORT_AGENT_ID:-}'" >&2
    exit 1
}

bash -c '
    [ "${APORT_GUARDRAIL_MODE:-}" = "api" ] &&
    [ "${APORT_API_URL:-}" = "https://api.aport.io" ] &&
    [ "${APORT_AGENT_ID:-}" = "ap_04c65c1dd7224160b36b756960e2cc48" ]
' || {
    echo "FAIL: hosted guardrail mode variables were not exported to child process" >&2
    exit 1
}

echo "OK test-guardrail-mode-env-export.sh"

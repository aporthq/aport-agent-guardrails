#!/bin/bash
# Integration test: run agent-guardrails --framework=deerflow and assert config/mode file exists.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
CONFIG_DIR="$TEST_DIR/.aport/deerflow"
rm -rf "$CONFIG_DIR"
mkdir -p "$(dirname "$CONFIG_DIR")"

echo ""
echo "  Integration — DeerFlow setup (agent-guardrails --framework=deerflow)"
echo "  Config dir: $CONFIG_DIR"
echo ""

export APORT_DEERFLOW_CONFIG_DIR="$CONFIG_DIR"
export APORT_NONINTERACTIVE="${APORT_NONINTERACTIVE:-1}"
export APORT_SKIP_ADAPTER_CHECK=1
"$DISPATCHER" --framework=deerflow --mode=api --api-url="https://api.aport.io" 2>&1 | tee "$TEST_DIR/deerflow-setup.log" || true

if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "FAIL: expected config dir $CONFIG_DIR" >&2
    exit 1
fi
echo "  ✅ config dir exists"

if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
    echo "FAIL: expected config.yaml at $CONFIG_DIR/config.yaml" >&2
    exit 1
fi
echo "  ✅ config.yaml exists"
grep -q "^mode: api$" "$CONFIG_DIR/config.yaml" || {
    echo "FAIL: expected mode: api in $CONFIG_DIR/config.yaml" >&2
    cat "$CONFIG_DIR/config.yaml" >&2
    exit 1
}
echo "  ✅ config.yaml persisted api mode"

MODE_FILE="$CONFIG_DIR/aport/guardrail-mode.env"
if [[ ! -f "$MODE_FILE" ]]; then
    echo "FAIL: expected mode file at $MODE_FILE" >&2
    exit 1
fi
grep -q '^APORT_GUARDRAIL_MODE=api$' "$MODE_FILE" || {
    echo "FAIL: expected api mode in $MODE_FILE" >&2
    cat "$MODE_FILE" >&2
    exit 1
}
grep -q '^APORT_API_URL=https://api.aport.io$' "$MODE_FILE" || {
    echo "FAIL: expected API URL in $MODE_FILE" >&2
    cat "$MODE_FILE" >&2
    exit 1
}
echo "  ✅ guardrail mode config saved (api)"

echo ""
echo "  DeerFlow setup integration test passed."
echo ""

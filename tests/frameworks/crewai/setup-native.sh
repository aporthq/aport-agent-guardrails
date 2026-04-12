#!/bin/bash
# Integration test: run agent-guardrails --framework=crewai --integration-mode=native
# and assert native-provider next steps are printed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
CONFIG_DIR="$TEST_DIR/.aport/crewai-native"
rm -rf "$CONFIG_DIR"
mkdir -p "$(dirname "$CONFIG_DIR")"

echo ""
echo "  Integration — CrewAI native setup (agent-guardrails --framework=crewai --integration-mode=native)"
echo "  Config dir: $CONFIG_DIR"
echo ""

export APORT_CREWAI_CONFIG_DIR="$CONFIG_DIR"
export APORT_NONINTERACTIVE="${APORT_NONINTERACTIVE:-1}"
export APORT_SKIP_ADAPTER_CHECK=1
"$DISPATCHER" --framework=crewai --integration-mode=native 2>&1 | tee "$TEST_DIR/crewai-native-setup.log" || true

if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
    echo "FAIL: expected config.yaml in native setup" >&2
    exit 1
fi

if ! grep -q "OAPGuardrailProvider" "$TEST_DIR/crewai-native-setup.log"; then
    echo "FAIL: expected native provider instructions in output" >&2
    exit 1
fi

if ! grep -q "enable_guardrail" "$TEST_DIR/crewai-native-setup.log"; then
    echo "FAIL: expected enable_guardrail instructions in output" >&2
    exit 1
fi

echo "  ✅ native CrewAI mode prints provider instructions"
echo ""

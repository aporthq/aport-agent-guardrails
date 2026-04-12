#!/bin/bash
# Integration test: run agent-guardrails --framework=crewai and assert config,
# passport runtime, and config dir exist. Uses APORT_CREWAI_CONFIG_DIR so we
# don't touch ~/.aport.
# Usage: ./setup.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
CONFIG_DIR="$TEST_DIR/.aport/crewai"
rm -rf "$CONFIG_DIR"
mkdir -p "$(dirname "$CONFIG_DIR")"

echo ""
echo "  Integration — CrewAI setup (agent-guardrails --framework=crewai)"
echo "  Config dir: $CONFIG_DIR"
echo ""

export APORT_CREWAI_CONFIG_DIR="$CONFIG_DIR"
export APORT_NONINTERACTIVE="${APORT_NONINTERACTIVE:-1}"
export APORT_SKIP_ADAPTER_CHECK=1
"$DISPATCHER" --framework=crewai 2>&1 | tee "$TEST_DIR/crewai-setup.log" || true

if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "FAIL: expected config dir $CONFIG_DIR" >&2
    exit 1
fi
echo "  ✅ config dir exists"

if [[ -f "$CONFIG_DIR/config.yaml" ]]; then
    echo "  ✅ config.yaml exists"
else
    echo "  ⚠️  config.yaml not found (template copy optional)"
fi

if grep -q "aport-agent-guardrails-crewai" "$TEST_DIR/crewai-setup.log" && grep -q "register_aport_guardrail" "$TEST_DIR/crewai-setup.log"; then
    echo "  ✅ default CrewAI mode is released compatibility mode"
else
    echo "FAIL: expected released CrewAI compatibility instructions in setup output" >&2
    exit 1
fi

if [[ -f "$CONFIG_DIR/aport/passport.json" ]]; then
    echo "  ✅ passport created"
else
    echo "FAIL: expected passport at $CONFIG_DIR/aport/passport.json" >&2
    exit 1
fi

if [[ -x "$CONFIG_DIR/aport/runtime/bin/aport-guardrail.sh" ]]; then
    echo "  ✅ local runtime installed"
else
    echo "FAIL: expected local runtime at $CONFIG_DIR/aport/runtime/bin/aport-guardrail.sh" >&2
    exit 1
fi

if [[ -f "$CONFIG_DIR/aport/runtime/external/aport-spec/oap/passport-schema.json" ]]; then
    echo "  ✅ spec assets installed"
else
    echo "FAIL: expected spec asset in runtime bundle" >&2
    exit 1
fi

echo ""
echo "  CrewAI setup integration test passed."
echo ""

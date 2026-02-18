#!/bin/bash
# Integration test: run agent-guardrails --framework=openclaw in temp dir and assert config files exist.
# Uses hosted agent_id and piped defaults so run is non-interactive.
# Usage: ./setup.sh
#   Optional: APORT_TEST_OPENCLAW_AGENT_ID=ap_xxx
#   Optional: APORT_TEST_DIR for temp dir

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2>/dev/null || echo "$REPO_ROOT/tests/output")}"
CONFIG_DIR="$TEST_DIR/.openclaw-integration"
rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

AGENT_ID="${APORT_TEST_OPENCLAW_AGENT_ID:-ap_8955f5450cd542fe8f67bbbf07c3e103}"

echo ""
echo "  Integration — OpenClaw setup (agent-guardrails --framework=openclaw)"
echo "  Config dir: $CONFIG_DIR"
echo ""

export OPENCLAW_HOME="$CONFIG_DIR"
# Run dispatcher with --framework=openclaw and agent_id; pipe newlines for any prompts from openclaw
printf '\n\n\n\n' | "$DISPATCHER" --framework=openclaw "$AGENT_ID" 2>&1 | tee "$TEST_DIR/openclaw-setup.log" || true

# Assert config files exist (same as test-openclaw-hosted-flow)
if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
  echo "FAIL: expected $CONFIG_DIR/config.yaml" >&2
  exit 1
fi
echo "  ✅ config.yaml exists"

if ! grep -q "agentId:" "$CONFIG_DIR/config.yaml"; then
  echo "FAIL: config.yaml should contain agentId" >&2
  cat "$CONFIG_DIR/config.yaml" >&2
  exit 1
fi
echo "  ✅ config has agentId"

echo ""
echo "  OpenClaw setup integration test passed."
echo ""

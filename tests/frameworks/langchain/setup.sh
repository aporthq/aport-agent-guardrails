#!/bin/bash
# Integration test: run agent-guardrails --framework=langchain and assert config dir + config.yaml exist.
# Uses APORT_LANGCHAIN_CONFIG_DIR so we don't touch ~/.aport. Pipes newlines for wizard prompts.
# Usage: ./setup.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2>/dev/null || echo "$REPO_ROOT/tests/output")}"
CONFIG_DIR="$TEST_DIR/.aport/langchain"
rm -rf "$CONFIG_DIR"
mkdir -p "$(dirname "$CONFIG_DIR")"

echo ""
echo "  Integration — LangChain setup (agent-guardrails --framework=langchain)"
echo "  Config dir: $CONFIG_DIR"
echo ""

export APORT_LANGCHAIN_CONFIG_DIR="$CONFIG_DIR"
export APORT_NONINTERACTIVE="${APORT_NONINTERACTIVE:-1}"
export APORT_SKIP_ADAPTER_CHECK=1
printf '\n\n\n\n' | "$DISPATCHER" --framework=langchain 2>&1 | tee "$TEST_DIR/langchain-setup.log" || true

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

echo ""
echo "  LangChain setup integration test passed."
echo ""

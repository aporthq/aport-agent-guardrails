#!/bin/bash
# Test OpenClaw setup with hosted passport (agent_id): CLI accepts agent_id, skips wizard, writes agentId to config, no local passport file.
# See: agent-passport/_plan/execution/openclaw/HOSTED_PASSPORT_CLI_FIX.md
#
# Usage: ./test-openclaw-hosted-flow.sh
#   Optional: APORT_TEST_OPENCLAW_AGENT_ID=ap_xxx (default: ap_8955f5450cd542fe8f67bbbf07c3e103)
#   Optional: OPENCLAW_HOME or test dir for config (isolated from ~/.openclaw)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2>/dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"
CONFIG_DIR="$TEST_DIR/.openclaw-hosted-test"
rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

# Use a valid agent_id format (same as remote passport API test)
AGENT_ID="${APORT_TEST_OPENCLAW_AGENT_ID:-ap_8955f5450cd542fe8f67bbbf07c3e103}"

echo ""
echo "  OpenClaw hosted passport flow (agent_id arg)"
echo "  Config dir: $CONFIG_DIR"
echo "  Agent ID: $AGENT_ID"
echo ""

# 1. Invalid agent_id must exit with error
echo "  Invalid agent_id: must exit non-zero..."
if ( "$REPO_ROOT/bin/openclaw" invalid_id 2>/dev/null ); then
    echo "FAIL: openclaw invalid_id should exit 1" >&2
    exit 1
fi
if ! "$REPO_ROOT/bin/openclaw" invalid_id 2>&1 | grep -q "Invalid agent_id format"; then
    echo "FAIL: expected 'Invalid agent_id format' message" >&2
    exit 1
fi
echo "  ✅ Invalid agent_id rejected"

# 2. Valid agent_id: run setup with piped defaults (config dir, API URL, strict mode, continue without openclaw)
#    We pipe newlines to accept defaults. Order: config dir (we pass our CONFIG_DIR via env), then if openclaw missing "Continue? Y", API URL, strict mode.
export OPENCLAW_HOME="$CONFIG_DIR"
# Pass multiple newlines for: config dir Enter, Continue anyway Y, API URL Enter, strict mode N
printf '\n\n\n\n' | "$REPO_ROOT/bin/openclaw" "$AGENT_ID" 2>&1 | tee "$TEST_DIR/openclaw-hosted.log" || true
# Script may exit 0 or 1 (e.g. if openclaw not installed); we only care that config was written

if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
    echo "FAIL: expected $CONFIG_DIR/config.yaml (hosted setup)" >&2
    exit 1
fi
echo "  ✅ config.yaml created"

if ! grep -q "agentId:" "$CONFIG_DIR/config.yaml"; then
    echo "FAIL: config.yaml should contain agentId (hosted passport)" >&2
    cat "$CONFIG_DIR/config.yaml" >&2
    exit 1
fi
echo "  ✅ config has agentId"

if grep -q "passportFile:.*passport.json" "$CONFIG_DIR/config.yaml" 2>/dev/null; then
    # Hosted config should not set passportFile (API fetches by agent_id)
    echo "FAIL: hosted config should not set passportFile" >&2
    exit 1
fi
echo "  ✅ config does not set passportFile (hosted)"

if [ -f "$CONFIG_DIR/passport.json" ]; then
    echo "FAIL: hosted flow must not create local passport.json" >&2
    exit 1
fi
echo "  ✅ No local passport.json (hosted)"

echo ""
echo "  OpenClaw hosted passport flow tests passed."
exit 0

#!/bin/bash
# Test remote (hosted) passport with API mode: use agent_id only, no passport file.
# The API fetches the passport from the registry by agent_id.
#
# Usage: ./test-remote-passport-api.sh
#   Optional: APORT_TEST_REMOTE_AGENT_ID=ap_xxx  (default: ap_8955f5450cd542fe8f67bbbf07c3e103)
#   Optional: APORT_API_URL=http://localhost:8787 (default; or https://api.aport.io for cloud)
#   Optional: APORT_API_KEY=... (if API requires auth)
#
# Skip: set APORT_SKIP_REMOTE_PASSPORT_TEST=1 to skip (e.g. in CI without a real passport).
#
# Verification flow (same as other API tests):
#   1. Test calls bin/aport-guardrail-api.sh with tool name (e.g. system.command.execute) and context JSON.
#   2. Script maps tool → policy pack ID (system.command.execute → system.command.execute.v1), then runs src/evaluator.js.
#   3. Evaluator (with APORT_AGENT_ID set) POSTs to:
#        ${APORT_API_URL}/api/verify/policy/system.command.execute.v1
#      with body: { "context": { "agent_id": "<APORT_AGENT_ID>", "command": "ls" } }.
#   4. API fetches passport from registry by agent_id, evaluates policy, returns allow/deny.

set -e

source "$(dirname "$0")/setup.sh"

# Remote passport (hosted) to test — create one at https://aport.io/builder/create
REMOTE_AGENT_ID="${APORT_TEST_REMOTE_AGENT_ID:-ap_8955f5450cd542fe8f67bbbf07c3e103}"

if [ -n "$APORT_SKIP_REMOTE_PASSPORT_TEST" ]; then
    echo "  Skipping remote passport API test (APORT_SKIP_REMOTE_PASSPORT_TEST is set)"
    exit 0
fi

# Use API mode with agent_id only (no local passport file)
export APORT_AGENT_ID="$REMOTE_AGENT_ID"
export APORT_API_URL="${APORT_API_URL:-http://localhost:8787}"
# Point passport file to non-existent so we truly use agent_id path; script allows this when APORT_AGENT_ID is set
export OPENCLAW_PASSPORT_FILE="$TEST_DIR/nonexistent-passport-remote.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/decision-remote.json"
rm -f "$OPENCLAW_PASSPORT_FILE" "$OPENCLAW_DECISION_FILE"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GUARDRAIL_API="$SCRIPT_DIR/bin/aport-guardrail-api.sh"

echo ""
echo "  Remote passport API test (agent_id only, no passport file)"
echo "  Agent ID: $REMOTE_AGENT_ID"
echo "  API: $APORT_API_URL"
echo ""

# Probe API reachability (agent-passport exposes GET /api/status, not /health)
if ! curl -sf --connect-timeout 5 "${APORT_API_URL%/}/api/status" >/dev/null 2>&1; then
    echo "  Skipping: API unreachable at $APORT_API_URL (set APORT_SKIP_REMOTE_PASSPORT_TEST=1 to suppress)"
    exit 0
fi

echo "  Test 1: ALLOW — safe command (e.g. ls)"
if "$GUARDRAIL_API" system.command.execute '{"command":"ls"}'; then
    echo "  ✅ Test 1 passed: Command allowed"
else
    echo "  ❌ Test 1 failed: Expected ALLOW for command 'ls'"
    [ -f "$OPENCLAW_DECISION_FILE" ] && jq -r '.reasons[0].message // .' "$OPENCLAW_DECISION_FILE"
    exit 1
fi

echo ""
echo "  Test 2: DENY — blocked pattern (rm -rf)"
if ! "$GUARDRAIL_API" system.command.execute '{"command":"rm -rf /"}'; then
    echo "  ✅ Test 2 passed: Blocked pattern denied"
else
    echo "  ❌ Test 2 failed: Expected DENY for 'rm -rf /'"
    [ -f "$OPENCLAW_DECISION_FILE" ] && jq -r '.reasons[0].message // .' "$OPENCLAW_DECISION_FILE"
    exit 1
fi

rm -f "$OPENCLAW_DECISION_FILE"
echo ""
echo "  ✅ All remote passport API tests passed!"

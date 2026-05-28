#!/bin/bash
# Test guardrail allow/deny via API evaluator (live) or local bash (CI/offline).
# APORT_SKIP_REMOTE_PASSPORT_TEST=1 uses the local bash evaluator.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export APORT_API_URL="${APORT_API_URL:-https://api.aport.io}"
unset APORT_AGENT_ID 2> /dev/null || true

PASSPORT_FILE="${APORT_TEST_PASSPORT_FILE:-/tmp/test-passport-api.json}"
DECISION_FILE="${APORT_TEST_DECISION_FILE:-/tmp/test-decision-api.json}"
export OPENCLAW_PASSPORT_FILE="$PASSPORT_FILE"
export OPENCLAW_DECISION_FILE="$DECISION_FILE"

GUARDRAIL="$SCRIPT_DIR/bin/aport-guardrail-v2.sh"
GUARDRAIL_MODE="api"

if [ -n "${APORT_SKIP_REMOTE_PASSPORT_TEST:-}" ]; then
    GUARDRAIL="$SCRIPT_DIR/bin/aport-guardrail-bash.sh"
    GUARDRAIL_MODE="local bash"
elif ! curl -sf --connect-timeout 5 "${APORT_API_URL%/}/api/status" > /dev/null 2>&1; then
    echo "  SKIP: API unreachable at $APORT_API_URL (set APORT_SKIP_REMOTE_PASSPORT_TEST=1 for local bash)"
    exit 0
fi

trap 'rm -f "$PASSPORT_FILE" "$DECISION_FILE"' EXIT

echo ""
echo "  API evaluator test (mode: $GUARDRAIL_MODE)"
echo "  Endpoint: $APORT_API_URL"
echo ""

cat > "$PASSPORT_FILE" << 'EOF'
{
  "spec_version": "oap/1.0",
  "passport_id": "passport-test-api",
  "owner_id": "user-test",
  "agent_id": "agent-test-api",
  "status": "active",
  "assurance_level": "L0",
  "capabilities": [
    {
      "id": "system.command.execute",
      "description": "Execute system commands"
    }
  ],
  "limits": {
    "system.command.execute": {
      "allowed_commands": ["ls", "pwd", "echo"],
      "blocked_patterns": ["rm -rf", "sudo"],
      "max_execution_time": 300
    }
  },
  "issued_at": "2026-02-14T00:00:00Z",
  "expires_at": "2027-02-14T00:00:00Z"
}
EOF

echo "  Test 1: Allow - command in allowlist"
if "$GUARDRAIL" system.command.execute '{"command":"ls"}'; then
    echo "  ✅ Allow: ls"
else
    echo "  ❌ Test 1 failed" >&2
    exit 1
fi

echo "  Test 2: Deny - command not in allowlist"
if ! "$GUARDRAIL" system.command.execute '{"command":"cat /etc/passwd"}'; then
    echo "  ✅ Deny: cat /etc/passwd"
else
    echo "  ❌ Test 2 failed" >&2
    exit 1
fi

echo "  Test 3: Deny - blocked pattern"
if ! "$GUARDRAIL" system.command.execute '{"command":"rm -rf /"}'; then
    echo "  ✅ Deny: rm -rf /"
else
    echo "  ❌ Test 3 failed" >&2
    exit 1
fi

echo ""
echo "  OK test-api-evaluator.sh"

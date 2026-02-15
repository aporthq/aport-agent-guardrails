#!/bin/bash
# Test the API-powered evaluator (default: https://api.aport.io)

set -e

echo "Testing API-powered evaluator..."

# Use local agent-passport when available; override with APORT_API_URL to test cloud or other instance
export APORT_API_URL="${APORT_API_URL:-https://api.aport.io}"
echo "Using API endpoint: $APORT_API_URL"

# Create test passport
export OPENCLAW_PASSPORT_FILE="/tmp/test-passport-api.json"
export OPENCLAW_DECISION_FILE="/tmp/test-decision-api.json"

# Create a minimal test passport
cat > "$OPENCLAW_PASSPORT_FILE" <<'EOF'
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
    "allowed_commands": ["ls", "pwd", "echo"],
    "blocked_patterns": ["rm -rf", "sudo"],
    "max_execution_time": 300
  },
  "issued_at": "2026-02-14T00:00:00Z",
  "expires_at": "2027-02-14T00:00:00Z"
}
EOF

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ""
echo "Test 1: Allow - system command in allowed list"
if "$SCRIPT_DIR/bin/aport-guardrail-v2.sh" system.command.execute '{"command":"ls"}'; then
    echo "✅ Test 1 passed: Command allowed"
    cat "$OPENCLAW_DECISION_FILE" | jq -r '.reasons[0].message'
else
    echo "❌ Test 1 failed: Command should be allowed"
    cat "$OPENCLAW_DECISION_FILE" | jq -r '.reasons[0].message'
    exit 1
fi

echo ""
echo "Test 2: Deny - system command not in allowed list"
if ! "$SCRIPT_DIR/bin/aport-guardrail-v2.sh" system.command.execute '{"command":"cat /etc/passwd"}'; then
    echo "✅ Test 2 passed: Command denied"
    cat "$OPENCLAW_DECISION_FILE" | jq -r '.reasons[0].message'
else
    echo "❌ Test 2 failed: Command should be denied"
    cat "$OPENCLAW_DECISION_FILE" | jq -r '.reasons[0].message'
    exit 1
fi

echo ""
echo "Test 3: Deny - blocked pattern"
if ! "$SCRIPT_DIR/bin/aport-guardrail-v2.sh" system.command.execute '{"command":"rm -rf /"}'; then
    echo "✅ Test 3 passed: Blocked pattern denied"
    cat "$OPENCLAW_DECISION_FILE" | jq -r '.reasons[0].message'
else
    echo "❌ Test 3 failed: Blocked pattern should be denied"
    cat "$OPENCLAW_DECISION_FILE" | jq -r '.reasons[0].message'
    exit 1
fi

# Cleanup
rm -f "$OPENCLAW_PASSPORT_FILE" "$OPENCLAW_DECISION_FILE"

echo ""
echo "✅ All API evaluator tests passed!"

#!/bin/bash
# Test surgical patterns for system.command.execute
# Verify that legitimate commands with metacharacters are allowed
# while dangerous operations are blocked

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_NAME="surgical-patterns"

echo "🧪 Testing: $TEST_NAME"
echo "================================"

# Setup
PASSPORT_FILE="/tmp/test-passport-surgical.json"
DECISION_FILE="/tmp/test-decision-surgical.json"
export OPENCLAW_PASSPORT_FILE="$PASSPORT_FILE"
export OPENCLAW_DECISION_FILE="$DECISION_FILE"

# Create test passport with command execution capability
cat > "$PASSPORT_FILE" << 'EOF'
{
  "spec_version": "oap/1.0",
  "passport_id": "ap_test_surgical",
  "owner_id": "org_test",
  "owner_type": "organization",
  "kind": "agent",
  "status": "active",
  "assurance_level": "L0",
  "never_expires": true,
  "capabilities": [
    {"id": "system.command.execute"}
  ],
  "limits": {
    "system.command.execute": {
      "allowed_commands": ["*"],
      "max_execution_time": 300,
      "blocked_patterns": []
    }
  }
}
EOF

# Test 1: Allow legitimate command chaining (&&)
echo
echo "Test 1: Allow 'git status && git diff' (legitimate chaining)"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" exec.run '{"command":"git status && git diff"}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed git status && git diff"
else
    echo "❌ FAIL: Should allow legitimate command chaining"
    cat "$DECISION_FILE"
    exit 1
fi

# Test 2: Allow legitimate piping (|)
echo
echo "Test 2: Allow 'ls | grep test' (legitimate piping)"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" exec.run '{"command":"ls | grep test"}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed ls | grep test"
else
    echo "❌ FAIL: Should allow legitimate piping"
    cat "$DECISION_FILE"
    exit 1
fi

# Test 3: Allow legitimate command sequencing (;)
echo
echo "Test 3: Allow 'cd /tmp; ls' (legitimate sequencing)"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" exec.run '{"command":"cd /tmp; ls"}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed cd /tmp; ls"
else
    echo "❌ FAIL: Should allow legitimate sequencing"
    cat "$DECISION_FILE"
    exit 1
fi

# Test 4: Allow legitimate OR chaining (||)
echo
echo "Test 4: Allow 'command || echo failed' (legitimate OR)"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" exec.run '{"command":"test -f file.txt || echo not found"}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed test || echo"
else
    echo "❌ FAIL: Should allow legitimate OR chaining"
    cat "$DECISION_FILE"
    exit 1
fi

# Test 5: Allow legitimate backgrounding (&)
echo
echo "Test 5: Allow 'npm start &' (legitimate backgrounding)"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" exec.run '{"command":"npm start &"}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed npm start &"
else
    echo "❌ FAIL: Should allow legitimate backgrounding"
    cat "$DECISION_FILE"
    exit 1
fi

# Test 6: Block destructive operation (rm -rf /)
echo
echo "Test 6: Block 'rm -rf /' (dangerous operation)"
if "$SCRIPT_DIR/bin/aport-guardrail-bash.sh" exec.run '{"command":"rm -rf /"}' > "$DECISION_FILE" 2>&1; then
    ALLOW=$(jq -r '.allow' "$DECISION_FILE")
    if [ "$ALLOW" = "false" ]; then
        echo "✅ PASS: Blocked rm -rf /"
    else
        echo "❌ FAIL: Should block rm -rf /"
        cat "$DECISION_FILE"
        exit 1
    fi
else
    echo "✅ PASS: Blocked rm -rf / (exit code 1)"
fi

# Test 7: Allow safe rm operation
echo
echo "Test 7: Allow 'rm /tmp/test.txt' (safe removal)"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" exec.run '{"command":"rm /tmp/test.txt"}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed safe rm"
else
    echo "❌ FAIL: Should allow safe rm"
    cat "$DECISION_FILE"
    exit 1
fi

# Cleanup
rm -f "$PASSPORT_FILE" "$DECISION_FILE"

echo
echo "================================"
echo "✅ All surgical pattern tests passed!"
echo "   Legitimate commands: ALLOWED ✅"
echo "   Dangerous operations: BLOCKED ❌"
echo

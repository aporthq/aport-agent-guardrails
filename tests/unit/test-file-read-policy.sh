#!/bin/bash
# Test file read policy evaluation (data.file.read.v1)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_NAME="file-read-policy"

echo "🧪 Testing: $TEST_NAME"
echo "================================"

# Setup
PASSPORT_FILE="/tmp/test-passport-file-read.json"
DECISION_FILE="/tmp/test-decision-file-read.json"
export OPENCLAW_PASSPORT_FILE="$PASSPORT_FILE"
export OPENCLAW_DECISION_FILE="$DECISION_FILE"

# Create test passport with file read capability
cat > "$PASSPORT_FILE" << 'EOF'
{
  "spec_version": "oap/1.0",
  "passport_id": "ap_test_file_read",
  "owner_id": "org_test",
  "owner_type": "organization",
  "kind": "agent",
  "status": "active",
  "assurance_level": "L0",
  "never_expires": true,
  "capabilities": [
    {"id": "data.file.read"}
  ],
  "limits": {
    "data.file.read": {
      "allowed_paths": ["/tmp/", "/Users/uchi/Downloads/projects/"],
      "blocked_patterns": ["**/.ssh/**", "**/.env", "**/id_rsa*", "**/credentials.json"]
    }
  }
}
EOF

# Test 1: Allowed path (/tmp/test.txt)
echo
echo "Test 1: Allow read from /tmp/test.txt"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" read '{"file_path":"/tmp/test.txt"}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed /tmp/test.txt"
else
    echo "❌ FAIL: Should allow /tmp/test.txt"
    cat "$DECISION_FILE"
    exit 1
fi

# Test 2: Denied path (not in allowlist)
echo
echo "Test 2: Deny read from /etc/passwd"
if "$SCRIPT_DIR/bin/aport-guardrail-bash.sh" read '{"file_path":"/etc/passwd"}' > "$DECISION_FILE" 2>&1; then
    ALLOW=$(jq -r '.allow' "$DECISION_FILE")
    if [ "$ALLOW" = "false" ]; then
        echo "✅ PASS: Denied /etc/passwd"
    else
        echo "❌ FAIL: Should deny /etc/passwd"
        cat "$DECISION_FILE"
        exit 1
    fi
else
    echo "✅ PASS: Denied /etc/passwd (exit code 1)"
fi

# Test 3: Blocked pattern (SSH key)
echo
echo "Test 3: Deny read from ~/.ssh/id_rsa"
if "$SCRIPT_DIR/bin/aport-guardrail-bash.sh" read '{"file_path":"/home/user/.ssh/id_rsa"}' > "$DECISION_FILE" 2>&1; then
    ALLOW=$(jq -r '.allow' "$DECISION_FILE")
    if [ "$ALLOW" = "false" ]; then
        echo "✅ PASS: Denied SSH key"
    else
        echo "❌ FAIL: Should deny SSH key"
        cat "$DECISION_FILE"
        exit 1
    fi
else
    echo "✅ PASS: Denied SSH key (exit code 1)"
fi

# Test 4: Blocked pattern (.env file)
echo
echo "Test 4: Deny read from project/.env"
if "$SCRIPT_DIR/bin/aport-guardrail-bash.sh" read '{"file_path":"/tmp/project/.env"}' > "$DECISION_FILE" 2>&1; then
    ALLOW=$(jq -r '.allow' "$DECISION_FILE")
    if [ "$ALLOW" = "false" ]; then
        echo "✅ PASS: Denied .env file"
    else
        echo "❌ FAIL: Should deny .env file"
        cat "$DECISION_FILE"
        exit 1
    fi
else
    echo "✅ PASS: Denied .env file (exit code 1)"
fi

# Test 5: Allowed path with deeper nesting
echo
echo "Test 5: Allow read from /Users/uchi/Downloads/projects/test.md"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" read '{"file_path":"/Users/uchi/Downloads/projects/test.md"}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed nested project file"
else
    echo "❌ FAIL: Should allow nested project file"
    cat "$DECISION_FILE"
    exit 1
fi

# Cleanup
rm -f "$PASSPORT_FILE" "$DECISION_FILE"

echo
echo "================================"
echo "✅ All file read tests passed!"
echo

#!/bin/bash
# Test file write policy evaluation (data.file.write.v1)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_NAME="file-write-policy"

echo "🧪 Testing: $TEST_NAME"
echo "================================"

# Setup
PASSPORT_FILE="/tmp/test-passport-file-write.json"
DECISION_FILE="/tmp/test-decision-file-write.json"
export OPENCLAW_PASSPORT_FILE="$PASSPORT_FILE"
export OPENCLAW_DECISION_FILE="$DECISION_FILE"

# Create test passport with file write capability
cat > "$PASSPORT_FILE" << 'EOF'
{
  "spec_version": "oap/1.0",
  "passport_id": "ap_test_file_write",
  "owner_id": "org_test",
  "owner_type": "organization",
  "kind": "agent",
  "status": "active",
  "assurance_level": "L0",
  "never_expires": true,
  "capabilities": [
    {"id": "data.file.write"}
  ],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["/tmp/", "/Users/uchi/Downloads/projects/"],
      "blocked_paths": ["/etc/", "/bin/", "/usr/bin/", "/System/"],
      "allowed_extensions": [".txt", ".md", ".json", ".log"]
    }
  }
}
EOF

# Test 1: Allowed path and extension
echo
echo "Test 1: Allow write to /tmp/test.txt"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" write '{"file_path":"/tmp/test.txt","content_length":100}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed /tmp/test.txt"
else
    echo "❌ FAIL: Should allow /tmp/test.txt"
    cat "$DECISION_FILE"
    exit 1
fi

# Test 2: Denied path (system directory)
echo
echo "Test 2: Deny write to /etc/hosts"
if "$SCRIPT_DIR/bin/aport-guardrail-bash.sh" write '{"file_path":"/etc/hosts"}' > "$DECISION_FILE" 2>&1; then
    ALLOW=$(jq -r '.allow' "$DECISION_FILE")
    if [ "$ALLOW" = "false" ]; then
        echo "✅ PASS: Denied /etc/hosts"
    else
        echo "❌ FAIL: Should deny /etc/hosts"
        cat "$DECISION_FILE"
        exit 1
    fi
else
    echo "✅ PASS: Denied /etc/hosts (exit code 1)"
fi

# Test 3: Denied path (/bin directory)
echo
echo "Test 3: Deny write to /bin/malicious"
if "$SCRIPT_DIR/bin/aport-guardrail-bash.sh" write '{"file_path":"/bin/malicious"}' > "$DECISION_FILE" 2>&1; then
    ALLOW=$(jq -r '.allow' "$DECISION_FILE")
    if [ "$ALLOW" = "false" ]; then
        echo "✅ PASS: Denied /bin/malicious"
    else
        echo "❌ FAIL: Should deny /bin/malicious"
        cat "$DECISION_FILE"
        exit 1
    fi
else
    echo "✅ PASS: Denied /bin/malicious (exit code 1)"
fi

# Test 4: Denied extension
echo
echo "Test 4: Deny write to /tmp/script.sh (disallowed extension)"
if "$SCRIPT_DIR/bin/aport-guardrail-bash.sh" write '{"file_path":"/tmp/script.sh"}' > "$DECISION_FILE" 2>&1; then
    ALLOW=$(jq -r '.allow' "$DECISION_FILE")
    if [ "$ALLOW" = "false" ]; then
        echo "✅ PASS: Denied .sh extension"
    else
        echo "❌ FAIL: Should deny .sh extension"
        cat "$DECISION_FILE"
        exit 1
    fi
else
    echo "✅ PASS: Denied .sh extension (exit code 1)"
fi

# Test 5: Allowed path with allowed extension
echo
echo "Test 5: Allow write to /Users/uchi/Downloads/projects/notes.md"
"$SCRIPT_DIR/bin/aport-guardrail-bash.sh" write '{"file_path":"/Users/uchi/Downloads/projects/notes.md"}' > "$DECISION_FILE" 2>&1
ALLOW=$(jq -r '.allow' "$DECISION_FILE")
if [ "$ALLOW" = "true" ]; then
    echo "✅ PASS: Allowed project .md file"
else
    echo "❌ FAIL: Should allow project .md file"
    cat "$DECISION_FILE"
    exit 1
fi

# Cleanup
rm -f "$PASSPORT_FILE" "$DECISION_FILE"

echo
echo "================================"
echo "✅ All file write tests passed!"
echo

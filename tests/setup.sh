#!/bin/bash
# Test setup: isolated env for OAP v1 tests (no ~/.openclaw pollution)
# Source this from test scripts:  source "$(dirname "$0")/setup.sh"

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2>/dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"

export OPENCLAW_PASSPORT_FILE="$TEST_DIR/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/decision.json"
export OPENCLAW_AUDIT_LOG="$TEST_DIR/audit.log"
export OPENCLAW_KILL_SWITCH="$TEST_DIR/kill-switch"

GUARDRAIL="$REPO_ROOT/bin/aport-guardrail.sh"
STATUS_SCRIPT="$REPO_ROOT/bin/aport-status.sh"
FIXTURE_PASSPORT="$REPO_ROOT/tests/fixtures/passport.oap-v1.json"

# Ensure scripts are executable
chmod +x "$REPO_ROOT/bin/"*.sh 2>/dev/null || true

# Copy fixture passport into test dir so guardrail finds it
cp "$FIXTURE_PASSPORT" "$OPENCLAW_PASSPORT_FILE"

# Remove kill switch if present (clean state)
rm -f "$OPENCLAW_KILL_SWITCH"

# Assert helper: exit 1 with message if condition fails
assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="${3:-expected $expected, got $actual}"
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $msg" >&2
        exit 1
    fi
}

assert_json_has() {
    local file="$1"
    local key="$2"
    local msg="${3:-$file should have key $key}"
    if ! jq -e ".$key" "$file" >/dev/null 2>&1; then
        echo "FAIL: $msg" >&2
        exit 1
    fi
}

assert_json_eq() {
    local file="$1"
    local key="$2"
    local expected="$3"
    local msg="${4:-$key}"
    local actual
    actual=$(jq -r ".$key" "$file")
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $msg (expected $expected, got $actual)" >&2
        exit 1
    fi
}

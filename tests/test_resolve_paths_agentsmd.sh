#!/bin/bash
# Integration test: AGENTS.md passport resolution in aport-resolve-paths.sh
# Verifies that AGENTS.md is checked first in the resolution chain.
# Run: bash tests/test_resolve_paths_agentsmd.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ $name"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $name"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
    fi
}

# --- Test 1: AGENTS.md passport resolved by aport-resolve-paths ---
echo "Test 1: AGENTS.md passport resolved by resolve_aport_paths"
t="$TMPDIR_BASE/t1"
mkdir -p "$t/.aport"
echo '{"spec_version":"oap/1.0","status":"active"}' > "$t/.aport/passport.json"
cat > "$t/AGENTS.md" << 'EOF'
---
enforcement:
  engine: aport
  passport: ./.aport/passport.json
---
EOF

# Clear env to ensure clean state
unset APORT_PASSPORT_FILE APORT_DECISION_FILE APORT_AUDIT_LOG 2> /dev/null || true
unset OPENCLAW_PASSPORT_FILE OPENCLAW_DECISION_FILE OPENCLAW_AUDIT_LOG 2> /dev/null || true
unset PASSPORT_FILE DECISION_FILE AUDIT_LOG 2> /dev/null || true
(
    cd "$t"
    source "$SCRIPT_DIR/bin/aport-resolve-paths.sh"
    [ "$PASSPORT_FILE" = "$t/.aport/passport.json" ] || {
        echo "  ✗ PASSPORT_FILE=$PASSPORT_FILE"
        exit 1
    }
    echo "  ✓ PASSPORT_FILE resolved from AGENTS.md"
)
PASS=$((PASS + 1))

# --- Test 2: APORT_PASSPORT_FILE overrides AGENTS.md ---
echo "Test 2: Explicit canonical env var overrides AGENTS.md"
t="$TMPDIR_BASE/t2"
mkdir -p "$t/.aport"
echo '{"spec_version":"oap/1.0","status":"active"}' > "$t/.aport/passport.json"
mkdir -p "$t/override"
echo '{"spec_version":"oap/1.0","status":"active"}' > "$t/override/passport.json"
cat > "$t/AGENTS.md" << 'EOF'
---
enforcement:
  engine: aport
  passport: ./.aport/passport.json
---
EOF

(
    cd "$t"
    export APORT_PASSPORT_FILE="$t/override/passport.json"
    unset APORT_DECISION_FILE APORT_AUDIT_LOG OPENCLAW_PASSPORT_FILE OPENCLAW_DECISION_FILE OPENCLAW_AUDIT_LOG 2> /dev/null || true
    source "$SCRIPT_DIR/bin/aport-resolve-paths.sh"
    [ "$PASSPORT_FILE" = "$t/override/passport.json" ] || {
        echo "  ✗ Override failed: PASSPORT_FILE=$PASSPORT_FILE"
        exit 1
    }
    [ "$OPENCLAW_PASSPORT_FILE" = "$APORT_PASSPORT_FILE" ] || {
        echo "  ✗ Legacy alias not synced: OPENCLAW_PASSPORT_FILE=$OPENCLAW_PASSPORT_FILE"
        exit 1
    }
    echo "  ✓ Explicit env var takes precedence over AGENTS.md"
)
PASS=$((PASS + 1))

# --- Test 3: AGENTS.md agent_id sets APORT_AGENT_ID ---
echo "Test 3: AGENTS.md agent_id sets APORT_AGENT_ID"
t="$TMPDIR_BASE/t3"
mkdir -p "$t"
cat > "$t/AGENTS.md" << 'EOF'
---
enforcement:
  engine: aport
  agent_id: ap_test1234
---
EOF

(
    cd "$t"
    unset APORT_PASSPORT_FILE APORT_DECISION_FILE APORT_AUDIT_LOG 2> /dev/null || true
    unset OPENCLAW_PASSPORT_FILE OPENCLAW_DECISION_FILE OPENCLAW_AUDIT_LOG APORT_AGENT_ID 2> /dev/null || true
    source "$SCRIPT_DIR/bin/aport-resolve-paths.sh"
    [ "$APORT_AGENT_ID" = "ap_test1234" ] || {
        echo "  ✗ APORT_AGENT_ID=$APORT_AGENT_ID"
        exit 1
    }
    echo "  ✓ APORT_AGENT_ID set from AGENTS.md"
)
PASS=$((PASS + 1))

# --- Test 4: No AGENTS.md falls through to default resolution ---
echo "Test 4: No AGENTS.md falls through to default"
t="$TMPDIR_BASE/t4"
mkdir -p "$t"
(
    cd "$t"
    unset APORT_PASSPORT_FILE APORT_DECISION_FILE APORT_AUDIT_LOG APORT_CONFIG_DIR 2> /dev/null || true
    unset OPENCLAW_PASSPORT_FILE OPENCLAW_DECISION_FILE OPENCLAW_AUDIT_LOG OPENCLAW_CONFIG_DIR APORT_AGENT_ID 2> /dev/null || true
    source "$SCRIPT_DIR/bin/aport-resolve-paths.sh"
    # Should fall through to default path probe — no AGENTS.md, no error
    echo "  ✓ No AGENTS.md — fell through to default resolution"
)
PASS=$((PASS + 1))

# --- Test 5: APORT_CONFIG_DIR anchors hosted/API framework paths ---
echo "Test 5: APORT_CONFIG_DIR anchors paths without passport.json"
t="$TMPDIR_BASE/t5"
mkdir -p "$t/.cursor"
(
    cd "$t"
    export APORT_CONFIG_DIR="$t/.cursor"
    unset APORT_PASSPORT_FILE APORT_DECISION_FILE APORT_AUDIT_LOG 2> /dev/null || true
    unset OPENCLAW_PASSPORT_FILE OPENCLAW_DECISION_FILE OPENCLAW_AUDIT_LOG OPENCLAW_CONFIG_DIR 2> /dev/null || true
    source "$SCRIPT_DIR/bin/aport-resolve-paths.sh"
    [ "$APORT_PASSPORT_FILE" = "$t/.cursor/aport/passport.json" ] || {
        echo "  ✗ APORT_CONFIG_DIR path failed: APORT_PASSPORT_FILE=$APORT_PASSPORT_FILE"
        exit 1
    }
    [ "$OPENCLAW_PASSPORT_FILE" = "$APORT_PASSPORT_FILE" ] || {
        echo "  ✗ Legacy passport alias not synced"
        exit 1
    }
    echo "  ✓ APORT_CONFIG_DIR anchors framework paths"
)
PASS=$((PASS + 1))

# --- Results ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1

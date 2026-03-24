#!/bin/bash
# Tests for bin/lib/agentsmd.sh — AGENTS.md enforcement block parser.
# Run: bash tests/test_agentsmd.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/bin/lib/agentsmd.sh"

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
        echo "  ✗ $name: expected='$expected' actual='$actual'"
    fi
}

run_in_dir() {
    # Run resolve_agentsmd_enforcement in the given dir without subshell
    pushd "$1" > /dev/null
    resolve_agentsmd_enforcement 2> /dev/null
    local rc=$?
    popd > /dev/null
    return $rc
}

# --- Test 1: Local passport ---
echo "Test 1: AGENTS.md with local passport"
t="$TMPDIR_BASE/t1" && mkdir -p "$t"
cat > "$t/AGENTS.md" << 'EOF'
---
enforcement:
  engine: aport
  passport: ./.aport/passport.json
---

# Instructions
EOF
run_in_dir "$t"
assert_eq "engine" "aport" "$AGENTSMD_ENGINE"
assert_eq "passport" "$t/.aport/passport.json" "$AGENTSMD_PASSPORT"
assert_eq "agent_id empty" "" "$AGENTSMD_AGENT_ID"

# --- Test 2: Hosted agent_id ---
echo "Test 2: AGENTS.md with hosted agent_id"
t="$TMPDIR_BASE/t2" && mkdir -p "$t"
cat > "$t/AGENTS.md" << 'EOF'
---
enforcement:
  engine: aport
  agent_id: ap_fa2f6d53abcdef1234567890abcdef12
---
EOF
run_in_dir "$t"
assert_eq "engine" "aport" "$AGENTSMD_ENGINE"
assert_eq "passport empty" "" "$AGENTSMD_PASSPORT"
assert_eq "agent_id" "ap_fa2f6d53abcdef1234567890abcdef12" "$AGENTSMD_AGENT_ID"

# --- Test 3: Both passport and agent_id ---
echo "Test 3: Both passport and agent_id"
t="$TMPDIR_BASE/t3" && mkdir -p "$t"
cat > "$t/AGENTS.md" << 'EOF'
---
enforcement:
  engine: aport
  passport: ./.aport/passport.json
  agent_id: ap_abc123
---
EOF
run_in_dir "$t"
assert_eq "engine" "aport" "$AGENTSMD_ENGINE"
assert_eq "passport" "$t/.aport/passport.json" "$AGENTSMD_PASSPORT"
assert_eq "agent_id" "ap_abc123" "$AGENTSMD_AGENT_ID"

# --- Test 4: No enforcement block ---
echo "Test 4: No enforcement block"
t="$TMPDIR_BASE/t4" && mkdir -p "$t"
cat > "$t/AGENTS.md" << 'EOF'
---
version: 1.0
---

# Instructions
EOF
if run_in_dir "$t"; then
    FAIL=$((FAIL + 1))
    echo "  ✗ should return 1"
else
    PASS=$((PASS + 1))
    echo "  ✓ returns 1"
fi

# --- Test 5: No AGENTS.md ---
echo "Test 5: No AGENTS.md"
t="$TMPDIR_BASE/t5" && mkdir -p "$t"
if run_in_dir "$t"; then
    FAIL=$((FAIL + 1))
    echo "  ✗ should return 1"
else
    PASS=$((PASS + 1))
    echo "  ✓ returns 1"
fi

# --- Test 6: No frontmatter ---
echo "Test 6: No frontmatter"
t="$TMPDIR_BASE/t6" && mkdir -p "$t"
cat > "$t/AGENTS.md" << 'EOF'
# Just instructions, no frontmatter.
EOF
if run_in_dir "$t"; then
    FAIL=$((FAIL + 1))
    echo "  ✗ should return 1"
else
    PASS=$((PASS + 1))
    echo "  ✓ returns 1"
fi

# --- Test 7: .agents.md (dotfile variant) ---
echo "Test 7: .agents.md dotfile"
t="$TMPDIR_BASE/t7" && mkdir -p "$t"
cat > "$t/.agents.md" << 'EOF'
---
enforcement:
  engine: aport
  agent_id: ap_lowercase_variant
---
EOF
run_in_dir "$t"
assert_eq "agent_id" "ap_lowercase_variant" "$AGENTSMD_AGENT_ID"

# --- Test 8: Walk up directories ---
echo "Test 8: Walk up to parent"
t="$TMPDIR_BASE/t8" && mkdir -p "$t/src/components"
cat > "$t/AGENTS.md" << 'EOF'
---
enforcement:
  engine: aport
  passport: ./.aport/passport.json
---
EOF
run_in_dir "$t/src/components"
assert_eq "engine" "aport" "$AGENTSMD_ENGINE"
assert_eq "passport" "$t/.aport/passport.json" "$AGENTSMD_PASSPORT"
assert_eq "dir" "$t" "$AGENTSMD_DIR"

# --- Test 9: Inline comments stripped ---
echo "Test 9: Inline comments"
t="$TMPDIR_BASE/t9" && mkdir -p "$t"
cat > "$t/AGENTS.md" << 'EOF'
---
enforcement:
  engine: aport  # the engine
  agent_id: ap_test123  # hosted mode
---
EOF
run_in_dir "$t"
assert_eq "engine" "aport" "$AGENTSMD_ENGINE"
assert_eq "agent_id" "ap_test123" "$AGENTSMD_AGENT_ID"

# --- Test 10: Mixed frontmatter ---
echo "Test 10: Enforcement alongside other frontmatter"
t="$TMPDIR_BASE/t10" && mkdir -p "$t"
cat > "$t/AGENTS.md" << 'EOF'
---
version: 1.0
permissions:
  files:
    read: allow
    delete: deny
enforcement:
  engine: aport
  passport: ./policy/passport.json
other:
  key: value
---
EOF
run_in_dir "$t"
assert_eq "engine" "aport" "$AGENTSMD_ENGINE"
assert_eq "passport" "$t/policy/passport.json" "$AGENTSMD_PASSPORT"

# --- Results ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1

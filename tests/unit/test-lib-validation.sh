#!/bin/bash
# Unit tests for bin/lib/validation.sh passport path handling.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$REPO_ROOT/bin/lib"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.claude" "$HOME/.cursor" "$HOME/.n8n"

# shellcheck source=../../bin/lib/validation.sh
source "$LIB_DIR/validation.sh"

echo ""
echo "  Unit — bin/lib/validation.sh"
echo "  Test dir: $TEST_DIR"
echo ""

validate_explicit_passport_path "/tmp/custom-passports/aport/passport.json"
echo "  ✅ explicit path allows non-default /tmp location"

if validate_passport_path "/tmp/custom-passports/aport/passport.json"; then
    echo "FAIL: discovered path should reject untrusted /tmp location" >&2
    exit 1
fi
echo "  ✅ discovered path rejects untrusted /tmp location"

validate_passport_path "$HOME/.claude/aport/passport.json"
validate_passport_path "$HOME/.cursor/aport/passport.json"
validate_passport_path "$HOME/.n8n/aport/passport.json"
echo "  ✅ discovered path accepts known framework dirs"

if validate_explicit_passport_path "../secrets/passport.json"; then
    echo "FAIL: explicit path should reject traversal" >&2
    exit 1
fi
echo "  ✅ explicit path rejects traversal"

echo ""
echo "  All validation.sh tests passed."
echo ""

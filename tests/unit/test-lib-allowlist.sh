#!/bin/bash
# Unit tests for bin/lib/allowlist.sh: check_command_allowed.
# Usage: ./test-lib-allowlist.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$REPO_ROOT/bin/lib"

# shellcheck source=../../bin/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=../../bin/lib/allowlist.sh
source "$LIB_DIR/allowlist.sh"

echo ""
echo "  Unit — bin/lib/allowlist.sh"
echo ""

# check_command_allowed: empty command -> return 1
if check_command_allowed "" 2> /dev/null; then
    echo "FAIL: check_command_allowed '' should return 1" >&2
    exit 1
fi
echo "  ✅ check_command_allowed '' -> 1"

# check_command_allowed: non-empty -> return 1 (stub denies by default; real enforcement in aport-guardrail-bash.sh)
if check_command_allowed "ls -la" 2> /dev/null; then
    echo "FAIL: check_command_allowed 'ls -la' should return 1 (stub)" >&2
    exit 1
fi
echo "  ✅ check_command_allowed 'ls -la' -> 1 (stub denies)"

if check_command_allowed "bash" 2> /dev/null; then
    echo "FAIL: check_command_allowed 'bash' should return 1 (stub)" >&2
    exit 1
fi
echo "  ✅ check_command_allowed 'bash' -> 1 (stub denies)"

echo ""
echo "  All allowlist.sh tests passed."
echo ""

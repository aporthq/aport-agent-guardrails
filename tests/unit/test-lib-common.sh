#!/bin/bash
# Unit tests for bin/lib/common.sh: log helpers, require_cmd.
# Usage: ./test-lib-common.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$REPO_ROOT/bin/lib"

# shellcheck source=../../bin/lib/common.sh
source "$LIB_DIR/common.sh"

assert_eq() {
    local actual="$1" expected="$2" msg="${3:-}"
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $msg (expected '$expected', got '$actual')" >&2
        exit 1
    fi
}

echo ""
echo "  Unit — bin/lib/common.sh"
echo ""

# log_info goes to stderr and contains [aport]
out=$(log_info "hello" 2>&1)
assert_eq "$out" "[aport] hello" "log_info format"
echo "  ✅ log_info format"

# log_warn contains WARN
out=$(log_warn "w" 2>&1)
[[ "$out" == *"WARN"* ]] && [[ "$out" == *"w"* ]] || {
    echo "FAIL: log_warn" >&2
    exit 1
}
echo "  ✅ log_warn"

# log_error contains ERROR
out=$(log_error "e" 2>&1)
[[ "$out" == *"ERROR"* ]] && [[ "$out" == *"e"* ]] || {
    echo "FAIL: log_error" >&2
    exit 1
}
echo "  ✅ log_error"

# require_cmd: existing command succeeds
require_cmd "bash"
echo "  ✅ require_cmd bash"

# require_cmd: nonexistent command exits 1 and prints ERROR
exitcode=0
out=$(require_cmd "__nonexistent_cmd_$$" 2>&1) || exitcode=$?
[[ "$exitcode" -ne 0 ]] || {
    echo "FAIL: require_cmd should exit non-zero" >&2
    exit 1
}
[[ "$out" == *"ERROR"* ]] && [[ "$out" == *"not found"* ]] || {
    echo "FAIL: require_cmd error message" >&2
    exit 1
}
echo "  ✅ require_cmd nonexistent -> exit 1 and ERROR"

echo ""
echo "  All common.sh tests passed."
echo ""

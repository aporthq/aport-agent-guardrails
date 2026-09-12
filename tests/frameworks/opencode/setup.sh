#!/bin/bash
# opencode remains gated until an installed-version plugin smoke test is available.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output/opencode")}"

set +e
APORT_NONINTERACTIVE=1 "$DISPATCHER" opencode > "$TEST_DIR/opencode-setup.log" 2>&1
status=$?
set -e

[[ "$status" -ne 0 ]] || {
    echo "FAIL: opencode setup should be gated until smoke-tested" >&2
    exit 1
}
grep -q 'planned but not enabled' "$TEST_DIR/opencode-setup.log" || {
    echo "FAIL: opencode setup should explain the gating reason" >&2
    cat "$TEST_DIR/opencode-setup.log" >&2
    exit 1
}

echo "  ✅ opencode gated setup test passed"

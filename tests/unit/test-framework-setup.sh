#!/bin/bash
# Unit tests for shared framework setup helpers.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
trap 'rm -rf "$TEST_DIR"' EXIT

# shellcheck source=../../bin/lib/framework-setup.sh
source "$REPO_ROOT/bin/lib/framework-setup.sh"

out="$(PATH="$TEST_DIR/no-runtime" warn_if_safe_audit_writer_missing 2>&1)"
if [[ "$out" != *"APort audit entries require python3 or node"* || "$out" != *"oap.missing_dependency"* ]]; then
    echo "FAIL: missing safe audit writer warning should name python3/node and oap.missing_dependency" >&2
    printf '%s\n' "$out" >&2
    exit 1
fi

if command -v python3 > /dev/null 2>&1 || command -v node > /dev/null 2>&1; then
    out="$(warn_if_safe_audit_writer_missing 2>&1)"
    [ -z "$out" ] || {
        echo "FAIL: safe audit writer warning should stay quiet when python3 or node exists" >&2
        printf '%s\n' "$out" >&2
        exit 1
    }
fi

echo "PASS: framework setup helpers"

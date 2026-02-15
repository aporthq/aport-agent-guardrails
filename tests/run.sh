#!/bin/bash
# Run all OAP v1 tests. Exit 1 if any test fails.
# Usage: ./run.sh   or   bash tests/run.sh

set -e

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0
RUN=0

for t in "$TESTS_DIR"/test-*.sh; do
    [ -f "$t" ] || continue
    RUN=$((RUN + 1))
    name=$(basename "$t")
    if bash "$t"; then
        echo "  OK $name"
    else
        echo "  FAIL $name"
        FAILED=$((FAILED + 1))
    fi
done

if [ "$RUN" -eq 0 ]; then
    echo "No test scripts found in $TESTS_DIR"
    exit 1
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All $RUN tests passed."
    exit 0
else
    echo "$FAILED of $RUN tests failed."
    exit 1
fi

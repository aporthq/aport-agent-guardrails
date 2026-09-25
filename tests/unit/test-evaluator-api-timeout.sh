#!/bin/bash
# Unit test: APORT_API_TIMEOUT parsing never throws inside the evaluator.
set -e
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$TESTS_DIR/../.."
node "$TESTS_DIR/test-evaluator-api-timeout.cjs"

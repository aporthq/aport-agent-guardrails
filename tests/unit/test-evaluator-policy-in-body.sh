#!/bin/bash
# Unit test: Node evaluator policyInBody → IN_BODY path and body.policy
set -e
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
cd "$ROOT"
node "$TESTS_DIR/test-evaluator-policy-in-body.cjs"

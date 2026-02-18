#!/bin/bash
# Run full test suite: unit (bin/lib, dispatcher, detection), OAP/guardrail tests, integration (OpenClaw setup).
# Exit 1 if any test fails.
# Usage: ./run.sh   or   bash tests/run.sh

set -e

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0
RUN=0

run_one() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  RUN=$((RUN + 1))
  local name=$(basename "$path")
  if bash "$path"; then
    echo "  OK $name"
  else
    echo "  FAIL $name"
    FAILED=$((FAILED + 1))
  fi
}

echo ""
echo "  — Unit (bin/lib, detect, dispatcher) —"
for t in "$TESTS_DIR/unit"/test-*.sh; do
  run_one "$t"
done

echo ""
echo "  — OAP / guardrail / passport —"
for t in "$TESTS_DIR"/test-*.sh; do
  run_one "$t"
done

echo ""
echo "  — Integration (frameworks) —"
run_one "$TESTS_DIR/frameworks/openclaw/setup.sh"
run_one "$TESTS_DIR/frameworks/langchain/setup.sh"
run_one "$TESTS_DIR/frameworks/crewai/setup.sh"
run_one "$TESTS_DIR/frameworks/n8n/setup.sh"
run_one "$TESTS_DIR/frameworks/cursor/setup.sh"

# Node integration test (setup.test.mjs)
if [[ -f "$TESTS_DIR/frameworks/openclaw/setup.test.mjs" ]]; then
  RUN=$((RUN + 1))
  if node "$TESTS_DIR/frameworks/openclaw/setup.test.mjs" 2>/dev/null; then
    echo "  OK setup.test.mjs"
  else
    echo "  FAIL setup.test.mjs"
    FAILED=$((FAILED + 1))
  fi
fi

echo ""
if [[ "$RUN" -eq 0 ]]; then
  echo "No test scripts found."
  exit 1
fi
if [[ "$FAILED" -eq 0 ]]; then
  echo "All $RUN tests passed."
  exit 0
else
  echo "$FAILED of $RUN tests failed."
  exit 1
fi

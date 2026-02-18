#!/bin/bash
# Integration test: run agent-guardrails --framework=cursor and assert hooks.json written.
# Uses CURSOR_HOOKS_DIR so we don't touch ~/.cursor. Non-interactive.
# Usage: ./setup.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2>/dev/null || echo "$REPO_ROOT/tests/output")}"
CURSOR_DIR="$TEST_DIR/.cursor"
rm -rf "$CURSOR_DIR"
mkdir -p "$CURSOR_DIR"

echo ""
echo "  Integration — Cursor setup (agent-guardrails --framework=cursor)"
echo "  Hooks dir: $CURSOR_DIR"
echo ""

export CURSOR_HOOKS_DIR="$CURSOR_DIR"
export APORT_NONINTERACTIVE="${APORT_NONINTERACTIVE:-1}"
# Pass --output and --non-interactive so wizard writes to test dir and does not abort
PASSPORT_PATH="$TEST_DIR/aport/passport.json"
mkdir -p "$(dirname "$PASSPORT_PATH")"
"$DISPATCHER" --framework=cursor --output "$PASSPORT_PATH" --non-interactive 2>&1 | tee "$TEST_DIR/cursor-setup.log" || true

if [[ ! -f "$CURSOR_DIR/hooks.json" ]]; then
  echo "FAIL: expected hooks.json at $CURSOR_DIR/hooks.json" >&2
  exit 1
fi
echo "  ✅ hooks.json exists"

# Assert it contains our hook command (path to aport-cursor-hook.sh)
if command -v jq &>/dev/null; then
  HOOK_CMD=$(jq -r '.hooks.beforeShellExecution[0].command // empty' "$CURSOR_DIR/hooks.json")
  if [[ -z "$HOOK_CMD" ]]; then
    HOOK_CMD=$(jq -r '.hooks.preToolUse[0].command // empty' "$CURSOR_DIR/hooks.json")
  fi
  if [[ -z "$HOOK_CMD" ]]; then
    echo "FAIL: hooks.json should have beforeShellExecution or preToolUse with command" >&2
    exit 1
  fi
  if [[ "$HOOK_CMD" != *"aport-cursor-hook"* ]]; then
    echo "FAIL: hook command should reference aport-cursor-hook script, got: $HOOK_CMD" >&2
    exit 1
  fi
  echo "  ✅ hooks.json references APort hook script"
fi

echo ""
echo "  Cursor setup integration test passed."
echo ""

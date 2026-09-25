#!/bin/bash
# Integration test: run agent-guardrails --framework=cursor and assert hooks.json written.
# Uses CURSOR_HOOKS_DIR so we don't touch ~/.cursor. Non-interactive.
# Usage: ./setup.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
CURSOR_DIR="$TEST_DIR/.cursor"
rm -rf "$CURSOR_DIR"
mkdir -p "$CURSOR_DIR"

# Seed existing hooks.json with a stale APort path + a user custom hook.
cat > "$CURSOR_DIR/hooks.json" << EOF
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      {"command":"/Users/uchi/.npm/_npx/stale/node_modules/@aporthq/aport-agent-guardrails/bin/aport-cursor-hook.sh","__aport_hook":true,"timeout":10},
      {"command":"/opt/custom/aport-cursor-hook.sh"},
      {"command":"/usr/local/bin/custom-before-shell-hook.sh"}
    ],
    "preToolUse": [
      {"command":"/Users/uchi/.npm/_npx/stale/node_modules/@aporthq/aport-agent-guardrails/bin/aport-cursor-hook.sh","__aport_hook":true,"timeout":10}
    ]
  }
}
EOF

echo ""
echo "  Integration — Cursor setup (agent-guardrails --framework=cursor)"
echo "  Hooks dir: $CURSOR_DIR"
echo ""

export CURSOR_HOOKS_DIR="$CURSOR_DIR"
export APORT_CURSOR_CONFIG_DIR="$CURSOR_DIR"
export APORT_NONINTERACTIVE="${APORT_NONINTERACTIVE:-1}"
# Pass --output and --non-interactive so wizard writes to test dir and does not abort
PASSPORT_PATH="$TEST_DIR/aport/passport.json"
mkdir -p "$(dirname "$PASSPORT_PATH")"
"$DISPATCHER" --framework=cursor --output "$PASSPORT_PATH" --non-interactive --mode=api --api-url="https://api.aport.io" 2>&1 | tee "$TEST_DIR/cursor-setup.log" || true

if [[ ! -f "$CURSOR_DIR/hooks.json" ]]; then
    echo "FAIL: expected hooks.json at $CURSOR_DIR/hooks.json" >&2
    exit 1
fi
echo "  ✅ hooks.json exists"

# Assert it contains our hook command (path to aport-cursor-hook.sh)
if command -v jq &> /dev/null; then
    HOOK_CMD=$(jq -r '.hooks.beforeShellExecution[]?.command // empty' "$CURSOR_DIR/hooks.json" | grep "aport-cursor-hook" | head -n 1)
    if [[ -z "$HOOK_CMD" ]]; then
        HOOK_CMD=$(jq -r '.hooks.preToolUse[]?.command // empty' "$CURSOR_DIR/hooks.json" | grep "aport-cursor-hook" | head -n 1)
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

    if [[ "$HOOK_CMD" != *"$CURSOR_DIR/aport/runtime/bin/aport-cursor-hook.sh"* ]]; then
        echo "FAIL: Cursor hook should point to stable APort runtime, got: $HOOK_CMD" >&2
        exit 1
    fi
    [[ -x "$CURSOR_DIR/aport/runtime/bin/aport-cursor-hook.sh" ]] || {
        echo "FAIL: expected stable Cursor runtime hook at $CURSOR_DIR/aport/runtime/bin/aport-cursor-hook.sh" >&2
        exit 1
    }
    echo "  ✅ hooks.json uses stable APort runtime hook"

    MARKER_COUNT=$(jq -r '[
        .hooks.beforeShellExecution[]?,
        .hooks.preToolUse[]?,
        .hooks.beforeMCPExecution[]?,
        .hooks.beforeReadFile[]?,
        .hooks.subagentStart[]?
    ] | map(select(.__aport_hook == true and .timeout == 30 and .failClosed == true)) | length' "$CURSOR_DIR/hooks.json")
    if [[ "$MARKER_COUNT" -ne 5 ]]; then
        echo "FAIL: expected one marker-owned APort hook with timeout=30 (evaluator bound 15 s + 15 s margin) and failClosed=true for each supported Cursor event" >&2
        jq -c '.hooks' "$CURSOR_DIR/hooks.json" >&2
        exit 1
    fi
    echo "  ✅ marker-owned APort hooks with timeout=30"

    # Stale marker-owned npx APort cursor hook path should be replaced
    STALE_COUNT=$(jq -r '[
        .hooks.beforeShellExecution[]?,
        .hooks.preToolUse[]?,
        .hooks.beforeMCPExecution[]?,
        .hooks.beforeReadFile[]?,
        .hooks.subagentStart[]?
    ] | map(select(.__aport_hook == true) | .command // "") | map(select(test("aport-cursor-hook\\.sh$") and test("/\\.npm/_npx/"))) | length' "$CURSOR_DIR/hooks.json")
    if [[ "$STALE_COUNT" -ne 0 ]]; then
        echo "FAIL: stale npx APort cursor hook entries should be removed" >&2
        jq -c '.hooks' "$CURSOR_DIR/hooks.json" >&2
        exit 1
    fi
    echo "  ✅ stale npx APort cursor hook entries removed"

    LEGACY_UNMARKED_COUNT=$(jq -r '[
        .hooks.beforeShellExecution[]?,
        .hooks.preToolUse[]?,
        .hooks.beforeMCPExecution[]?,
        .hooks.beforeReadFile[]?,
        .hooks.subagentStart[]?
    ] | map(select(.command == "/opt/custom/aport-cursor-hook.sh")) | length' "$CURSOR_DIR/hooks.json")
    if [[ "$LEGACY_UNMARKED_COUNT" -ne 0 ]]; then
        echo "FAIL: legacy unmarked APort cursor hook entries should be removed" >&2
        jq -c '.hooks' "$CURSOR_DIR/hooks.json" >&2
        exit 1
    fi
    echo "  ✅ legacy unmarked APort cursor hook entries removed"

    # User custom hooks must be preserved
    CUSTOM_COUNT=$(jq -r '[.hooks.beforeShellExecution[]? | select(.command == "/usr/local/bin/custom-before-shell-hook.sh")] | length' "$CURSOR_DIR/hooks.json")
    if [[ "$CUSTOM_COUNT" -ne 1 ]]; then
        echo "FAIL: custom hooks should be preserved during merge" >&2
        jq -c '.hooks.beforeShellExecution' "$CURSOR_DIR/hooks.json" >&2
        exit 1
    fi
    echo "  ✅ custom hooks preserved"

    # beforeTabFileRead is opt-in: a default install must not register it.
    TAB_DEFAULT_COUNT=$(jq -r '[.hooks.beforeTabFileRead[]? | select(.__aport_hook == true)] | length' "$CURSOR_DIR/hooks.json")
    if [[ "$TAB_DEFAULT_COUNT" -ne 0 ]]; then
        echo "FAIL: default install must not register beforeTabFileRead" >&2
        jq -c '.hooks' "$CURSOR_DIR/hooks.json" >&2
        exit 1
    fi
    echo "  ✅ beforeTabFileRead not registered by default"

    # Opt-in re-run merges a marker-owned beforeTabFileRead entry into the existing file.
    APORT_CURSOR_TAB_READ_HOOK=1 "$DISPATCHER" --framework=cursor --output "$PASSPORT_PATH" --non-interactive --mode=api --api-url="https://api.aport.io" > "$TEST_DIR/cursor-setup-tab.log" 2>&1 || true
    TAB_OPTIN_COUNT=$(jq -r '[.hooks.beforeTabFileRead[]? | select(.__aport_hook == true and .timeout == 30 and .failClosed == true and (.command | endswith("/aport/runtime/bin/aport-cursor-hook.sh")))] | length' "$CURSOR_DIR/hooks.json")
    if [[ "$TAB_OPTIN_COUNT" -ne 1 ]]; then
        echo "FAIL: APORT_CURSOR_TAB_READ_HOOK=1 should register one marker-owned beforeTabFileRead hook" >&2
        jq -c '.hooks' "$CURSOR_DIR/hooks.json" >&2
        cat "$TEST_DIR/cursor-setup-tab.log" >&2
        exit 1
    fi
    OTHER_COUNT=$(jq -r '[
        .hooks.beforeShellExecution[]?,
        .hooks.preToolUse[]?,
        .hooks.beforeMCPExecution[]?,
        .hooks.beforeReadFile[]?,
        .hooks.subagentStart[]?
    ] | map(select(.__aport_hook == true)) | length' "$CURSOR_DIR/hooks.json")
    if [[ "$OTHER_COUNT" -ne 5 ]]; then
        echo "FAIL: opt-in re-run must keep exactly one APort entry per default event" >&2
        jq -c '.hooks' "$CURSOR_DIR/hooks.json" >&2
        exit 1
    fi
    grep -q 'beforeTabFileRead is registered' "$TEST_DIR/cursor-setup-tab.log" || {
        echo "FAIL: opt-in install should report beforeTabFileRead registration" >&2
        cat "$TEST_DIR/cursor-setup-tab.log" >&2
        exit 1
    }
    echo "  ✅ APORT_CURSOR_TAB_READ_HOOK=1 registers beforeTabFileRead"

    # A later run without the opt-in removes the APort entry and drops the empty key,
    # while a user's own beforeTabFileRead hook survives.
    jq '.hooks.beforeTabFileRead += [{"command":"/usr/local/bin/custom-tab-hook.sh"}]' "$CURSOR_DIR/hooks.json" > "$CURSOR_DIR/hooks.json.tmp" \
        && mv "$CURSOR_DIR/hooks.json.tmp" "$CURSOR_DIR/hooks.json"
    "$DISPATCHER" --framework=cursor --output "$PASSPORT_PATH" --non-interactive --mode=api --api-url="https://api.aport.io" > "$TEST_DIR/cursor-setup-notab.log" 2>&1 || true
    TAB_AFTER_COUNT=$(jq -r '[.hooks.beforeTabFileRead[]? | select(.__aport_hook == true)] | length' "$CURSOR_DIR/hooks.json")
    TAB_CUSTOM_COUNT=$(jq -r '[.hooks.beforeTabFileRead[]? | select(.command == "/usr/local/bin/custom-tab-hook.sh")] | length' "$CURSOR_DIR/hooks.json")
    if [[ "$TAB_AFTER_COUNT" -ne 0 || "$TAB_CUSTOM_COUNT" -ne 1 ]]; then
        echo "FAIL: re-install without opt-in should remove only the APort beforeTabFileRead entry" >&2
        jq -c '.hooks' "$CURSOR_DIR/hooks.json" >&2
        exit 1
    fi
    echo "  ✅ re-install without opt-in removes APort beforeTabFileRead entry only"

    rm -f "$CURSOR_DIR/hooks.json"
    APORT_CURSOR_TAB_READ_HOOK=1 "$DISPATCHER" --framework=cursor --output "$PASSPORT_PATH" --non-interactive --mode=api --api-url="https://api.aport.io" > "$TEST_DIR/cursor-setup-fresh-tab.log" 2>&1 || true
    FRESH_KEYS=$(jq -r '.hooks | keys | sort | join(",")' "$CURSOR_DIR/hooks.json")
    if [[ "$FRESH_KEYS" != "beforeMCPExecution,beforeReadFile,beforeShellExecution,beforeTabFileRead,preToolUse,subagentStart" ]]; then
        echo "FAIL: fresh opt-in install should write six permission hooks, got: $FRESH_KEYS" >&2
        exit 1
    fi
    jq -e '.version == 1' "$CURSOR_DIR/hooks.json" > /dev/null || {
        echo "FAIL: hooks.json must keep version 1" >&2
        exit 1
    }
    echo "  ✅ fresh opt-in install writes all six permission hooks"
fi

MODE_FILE="$CURSOR_DIR/aport/guardrail-mode.env"
if [[ ! -f "$MODE_FILE" ]]; then
    echo "FAIL: expected mode file at $MODE_FILE" >&2
    exit 1
fi
grep -q '^APORT_GUARDRAIL_MODE=api$' "$MODE_FILE" || {
    echo "FAIL: expected api mode in $MODE_FILE" >&2
    cat "$MODE_FILE" >&2
    exit 1
}
grep -q '^APORT_API_URL=https://api.aport.io$' "$MODE_FILE" || {
    echo "FAIL: expected API URL in $MODE_FILE" >&2
    cat "$MODE_FILE" >&2
    exit 1
}
echo "  ✅ guardrail mode config saved (api)"

echo ""
echo "  Cursor setup integration test passed."
echo ""

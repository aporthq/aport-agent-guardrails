#!/bin/bash
# Integration test: run agent-guardrails --framework=claude-code and assert settings.json written.
# Uses APORT_CLAUDE_CODE_CONFIG_DIR so we don't touch ~/.claude. Non-interactive.
# Usage: ./setup.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
CLAUDE_DIR="$TEST_DIR/.claude"
rm -rf "$CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR"

# Seed existing settings.json with stale APort hook path + a user custom hook.
cat > "$CLAUDE_DIR/settings.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/uchi/.npm/_npx/stale/node_modules/@aporthq/aport-agent-guardrails/bin/aport-claude-code-hook.sh",
            "__aport_hook": true,
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "Bash(*)",
        "hooks": [
          {
            "type": "command",
            "command": "/opt/custom/aport-claude-code-hook.sh"
          },
          {
            "type": "command",
            "command": "/usr/local/bin/custom-claude-hook.sh"
          }
        ]
      }
    ]
  }
}
EOF

# Ensure framework script is executable (e.g. when running tests without make test)
chmod +x "$REPO_ROOT/bin/frameworks/claude-code.sh" 2> /dev/null || true

echo ""
echo "  Integration — Claude Code setup (agent-guardrails --framework=claude-code)"
echo "  Config dir: $CLAUDE_DIR"
echo ""

export APORT_CLAUDE_CODE_CONFIG_DIR="$CLAUDE_DIR"
export APORT_NONINTERACTIVE="${APORT_NONINTERACTIVE:-1}"
PASSPORT_PATH="$CLAUDE_DIR/aport/passport.json"
mkdir -p "$(dirname "$PASSPORT_PATH")"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$PASSPORT_PATH" 2> /dev/null || true

"$DISPATCHER" --framework=claude-code --output "$PASSPORT_PATH" --non-interactive --mode=api --api-url="https://api.aport.io" 2>&1 | tee "$TEST_DIR/claude-code-setup.log" || true

if [[ ! -f "$CLAUDE_DIR/settings.json" ]]; then
    echo "FAIL: expected settings.json at $CLAUDE_DIR/settings.json" >&2
    exit 1
fi
echo "  ✅ settings.json exists"

# Assert it contains PreToolUse and APort hook command (aport-claude-code-hook.sh)
if command -v jq &> /dev/null; then
    PRETOOL=$(jq -r '.hooks.PreToolUse // empty' "$CLAUDE_DIR/settings.json")
    if [[ -z "$PRETOOL" ]] || [[ "$PRETOOL" == "null" ]]; then
        echo "FAIL: settings.json should have hooks.PreToolUse" >&2
        exit 1
    fi
    HOOK_CMD=$(jq -r '.hooks.PreToolUse[]?.hooks[]?.command // empty' "$CLAUDE_DIR/settings.json" | grep "aport-claude-code-hook" | head -n 1)
    if [[ -z "$HOOK_CMD" ]]; then
        HOOK_CMD=$(jq -r '.hooks.PreToolUse[]?.command // empty' "$CLAUDE_DIR/settings.json" | grep "aport-claude-code-hook" | head -n 1)
    fi
    if [[ "$HOOK_CMD" != *"aport-claude-code-hook"* ]]; then
        echo "FAIL: hook command should reference aport-claude-code-hook script, got: $HOOK_CMD" >&2
        exit 1
    fi
    echo "  ✅ settings.json references APort Claude Code hook script"

    if [[ "$HOOK_CMD" != *"$CLAUDE_DIR/aport/runtime/bin/aport-claude-code-hook.sh"* ]]; then
        echo "FAIL: Claude Code hook should point to stable APort runtime, got: $HOOK_CMD" >&2
        exit 1
    fi
    [[ -x "$CLAUDE_DIR/aport/runtime/bin/aport-claude-code-hook.sh" ]] || {
        echo "FAIL: expected stable Claude Code runtime hook at $CLAUDE_DIR/aport/runtime/bin/aport-claude-code-hook.sh" >&2
        exit 1
    }
    echo "  ✅ settings.json uses stable APort runtime hook"

    # timeout=30: a PreToolUse command hook that hits its timeout does not block in
    # Claude Code, so the registered value must exceed the evaluator's 15s API timeout.
    MARKER_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true and .timeout == 30)] | length' "$CLAUDE_DIR/settings.json")
    if [[ "$MARKER_COUNT" -ne 1 ]]; then
        echo "FAIL: expected exactly one marker-owned APort hook with timeout=30" >&2
        jq -c '.hooks.PreToolUse' "$CLAUDE_DIR/settings.json" >&2
        exit 1
    fi
    echo "  ✅ marker-owned APort hook with timeout=30"

    # The hook timeout follows the evaluator bound plus a 15 s margin, so raising APORT_API_TIMEOUT cannot
    # reintroduce the fail-open that a fixed 30 s would.
    DERIVED_DIR="$TEST_DIR/claude-derived-timeout"
    mkdir -p "$DERIVED_DIR/aport"
    cp "$CLAUDE_DIR/aport/passport.json" "$DERIVED_DIR/aport/passport.json"
    APORT_API_TIMEOUT=45 APORT_CLAUDE_CODE_CONFIG_DIR="$DERIVED_DIR" \
        "$REPO_ROOT/bin/agent-guardrails" --framework=claude-code --output "$DERIVED_DIR/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/claude-derived.out" 2>&1 || {
        echo "FAIL: Claude Code setup with APORT_API_TIMEOUT=45 failed" >&2
        cat "$TEST_DIR/claude-derived.out" >&2
        exit 1
    }
    DERIVED_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true and .timeout == 60)] | length' "$DERIVED_DIR/settings.json")
    if [[ "$DERIVED_COUNT" -ne 1 ]]; then
        echo "FAIL: APORT_API_TIMEOUT=45 should install a 60 s hook timeout" >&2
        jq -c '.hooks.PreToolUse' "$DERIVED_DIR/settings.json" >&2
        exit 1
    fi
    echo "  ✅ hook timeout follows APORT_API_TIMEOUT plus the margin"

    # Stale marker-owned npx APort Claude hook path should be replaced
    STALE_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true) | .command // ""] | map(select(test("aport-claude-code-hook\\.sh$") and test("/\\.npm/_npx/"))) | length' "$CLAUDE_DIR/settings.json")
    if [[ "$STALE_COUNT" -ne 0 ]]; then
        echo "FAIL: stale npx APort Claude hook entries should be removed" >&2
        jq -c '.hooks.PreToolUse' "$CLAUDE_DIR/settings.json" >&2
        exit 1
    fi
    echo "  ✅ stale npx APort Claude hook entries removed"

    LEGACY_UNMARKED_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command == "/opt/custom/aport-claude-code-hook.sh")] | length' "$CLAUDE_DIR/settings.json")
    if [[ "$LEGACY_UNMARKED_COUNT" -ne 0 ]]; then
        echo "FAIL: legacy unmarked APort Claude hook entries should be removed" >&2
        jq -c '.hooks.PreToolUse' "$CLAUDE_DIR/settings.json" >&2
        exit 1
    fi
    echo "  ✅ legacy unmarked APort Claude hook entries removed"

    # User custom hook must be preserved
    CUSTOM_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command == "/usr/local/bin/custom-claude-hook.sh")] | length' "$CLAUDE_DIR/settings.json")
    if [[ "$CUSTOM_COUNT" -ne 1 ]]; then
        echo "FAIL: custom Claude hooks should be preserved during merge" >&2
        jq -c '.hooks.PreToolUse' "$CLAUDE_DIR/settings.json" >&2
        exit 1
    fi
    echo "  ✅ custom Claude hooks preserved"
fi

MODE_FILE="$CLAUDE_DIR/aport/guardrail-mode.env"
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

SYMLINK_CONFIG_DIR="$TEST_DIR/.claude-runtime-symlink"
SYMLINK_OUTSIDE_DIR="$TEST_DIR/runtime-symlink-outside"
rm -rf "$SYMLINK_CONFIG_DIR" "$SYMLINK_OUTSIDE_DIR"
mkdir -p "$SYMLINK_CONFIG_DIR/aport" "$SYMLINK_OUTSIDE_DIR"
ln -s "$SYMLINK_OUTSIDE_DIR" "$SYMLINK_CONFIG_DIR/aport/runtime"

echo "  Test: setup refuses symlinked runtime target..."
set +e
APORT_CLAUDE_CODE_CONFIG_DIR="$SYMLINK_CONFIG_DIR" APORT_NONINTERACTIVE=1 \
    "$DISPATCHER" --framework=claude-code --output "$SYMLINK_CONFIG_DIR/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/claude-code-symlink-runtime.log" 2>&1
SYMLINK_EXIT=$?
set -e
if [[ "$SYMLINK_EXIT" -eq 0 ]]; then
    echo "FAIL: expected setup to reject symlinked runtime target" >&2
    cat "$TEST_DIR/claude-code-symlink-runtime.log" >&2
    exit 1
fi
if [[ -e "$SYMLINK_OUTSIDE_DIR/bin/aport-claude-code-hook.sh" ]]; then
    echo "FAIL: setup wrote runtime files through symlink" >&2
    find "$SYMLINK_OUTSIDE_DIR" -maxdepth 3 -type f >&2
    exit 1
fi
grep -q 'Refusing to install APort runtime through symlink' "$TEST_DIR/claude-code-symlink-runtime.log" || {
    echo "FAIL: expected symlink refusal diagnostic" >&2
    cat "$TEST_DIR/claude-code-symlink-runtime.log" >&2
    exit 1
}
echo "  ✅ setup refuses symlinked runtime target"

echo ""
echo "  Claude Code setup integration test passed."
echo ""

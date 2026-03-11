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

"$DISPATCHER" --framework=claude-code --output "$PASSPORT_PATH" --non-interactive 2>&1 | tee "$TEST_DIR/claude-code-setup.log" || true

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
    HOOK_CMD=$(jq -r '.hooks.PreToolUse[0].hooks[0].command // empty' "$CLAUDE_DIR/settings.json")
    if [[ -z "$HOOK_CMD" ]]; then
        HOOK_CMD=$(jq -r '.hooks.PreToolUse[0].command // empty' "$CLAUDE_DIR/settings.json")
    fi
    if [[ "$HOOK_CMD" != *"aport-claude-code-hook"* ]]; then
        echo "FAIL: hook command should reference aport-claude-code-hook script, got: $HOOK_CMD" >&2
        exit 1
    fi
    echo "  ✅ settings.json references APort Claude Code hook script"
fi

echo ""
echo "  Claude Code setup integration test passed."
echo ""

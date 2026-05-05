#!/bin/bash

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"

echo ""
echo "  Unit/Integration — framework reset"
echo "  Dispatcher: $DISPATCHER"
echo ""

CLAUDE_DIR="$TEST_DIR/.claude"
mkdir -p "$CLAUDE_DIR/aport"

cat > "$CLAUDE_DIR/settings.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/tmp/aport-claude-code-hook.sh"
          }
        ]
      },
      {
        "matcher": "Bash(*)",
        "hooks": [
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

touch "$CLAUDE_DIR/aport/passport.json"

echo "  Test: reset claude-code removes APort hook/config and preserves custom hooks..."
APORT_CLAUDE_CODE_CONFIG_DIR="$CLAUDE_DIR" "$DISPATCHER" reset claude-code --yes > "$TEST_DIR/reset-1.txt" 2>&1

if [[ -d "$CLAUDE_DIR/aport" ]]; then
    echo "FAIL: expected $CLAUDE_DIR/aport to be removed" >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "FAIL: jq is required for reset test" >&2
    exit 1
fi

APORT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select((.command // "") | test("aport-(cursor-hook|claude-code-hook)\\.sh$"))] | length' "$CLAUDE_DIR/settings.json")
if [[ "$APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected APort Claude hook entries to be removed" >&2
    cat "$CLAUDE_DIR/settings.json" >&2
    exit 1
fi

CUSTOM_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command == "/usr/local/bin/custom-claude-hook.sh")] | length' "$CLAUDE_DIR/settings.json")
if [[ "$CUSTOM_COUNT" -ne 1 ]]; then
    echo "FAIL: expected custom Claude hook to be preserved" >&2
    cat "$CLAUDE_DIR/settings.json" >&2
    exit 1
fi

echo "  ✅ reset claude-code cleans APort hook/config and preserves custom hooks"

mkdir -p "$CLAUDE_DIR/aport"
cat > "$CLAUDE_DIR/settings.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/tmp/aport-claude-code-hook.sh"
          }
        ]
      }
    ]
  }
}
EOF
touch "$CLAUDE_DIR/aport/passport.json"

echo "  Test: claude-code reset positional form works..."
APORT_CLAUDE_CODE_CONFIG_DIR="$CLAUDE_DIR" "$DISPATCHER" claude-code reset --yes > "$TEST_DIR/reset-2.txt" 2>&1

if [[ -d "$CLAUDE_DIR/aport" ]]; then
    echo "FAIL: expected positional reset to remove $CLAUDE_DIR/aport" >&2
    exit 1
fi

echo "  ✅ claude-code reset positional form works"

echo ""
echo "  Framework reset tests passed."
echo ""

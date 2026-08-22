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
            "command": "/tmp/aport-claude-code-hook.sh",
            "__aport_hook": true,
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "Write(*)",
        "hooks": [
          {
            "type": "command",
            "command": "/opt/custom/aport-claude-code-hook.sh"
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

APORT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CLAUDE_DIR/settings.json")
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

UNMARKED_LOOKALIKE_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command == "/opt/custom/aport-claude-code-hook.sh")] | length' "$CLAUDE_DIR/settings.json")
if [[ "$UNMARKED_LOOKALIKE_COUNT" -ne 0 ]]; then
    echo "FAIL: expected legacy unmarked APort hook-like command to be removed" >&2
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
            "command": "/tmp/aport-claude-code-hook.sh",
            "__aport_hook": true,
            "timeout": 10
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

CURSOR_DIR="$TEST_DIR/.cursor"
mkdir -p "$CURSOR_DIR/aport"
cat > "$CURSOR_DIR/hooks.json" << 'EOF'
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      {"command":"/tmp/aport-cursor-hook.sh","__aport_hook":true,"timeout":10},
      {"command":"/opt/custom/aport-cursor-hook.sh"},
      {"command":"/usr/local/bin/custom-before-shell-hook.sh"}
    ],
    "preToolUse": [
      {"command":"/tmp/aport-cursor-hook.sh","__aport_hook":true,"timeout":10}
    ]
  }
}
EOF
touch "$CURSOR_DIR/aport/passport.json"

echo "  Test: reset cursor removes APort hooks and preserves custom hooks..."
APORT_CURSOR_CONFIG_DIR="$CURSOR_DIR" "$DISPATCHER" reset cursor --yes > "$TEST_DIR/reset-3.txt" 2>&1

if [[ -d "$CURSOR_DIR/aport" ]]; then
    echo "FAIL: expected $CURSOR_DIR/aport to be removed" >&2
    exit 1
fi

CURSOR_APORT_COUNT=$(jq -r '[
    .hooks.beforeShellExecution[]?,
    .hooks.preToolUse[]?,
    .hooks.beforeMCPExecution[]?,
    .hooks.subagentStart[]?
] | map(select(.__aport_hook == true)) | length' "$CURSOR_DIR/hooks.json")
if [[ "$CURSOR_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected marker-owned Cursor hook entries to be removed" >&2
    cat "$CURSOR_DIR/hooks.json" >&2
    exit 1
fi

CURSOR_UNMARKED_COUNT=$(jq -r '[.hooks.beforeShellExecution[]? | select(.command == "/opt/custom/aport-cursor-hook.sh")] | length' "$CURSOR_DIR/hooks.json")
if [[ "$CURSOR_UNMARKED_COUNT" -ne 0 ]]; then
    echo "FAIL: expected legacy unmarked Cursor APort hook-like command to be removed" >&2
    cat "$CURSOR_DIR/hooks.json" >&2
    exit 1
fi

CURSOR_CUSTOM_COUNT=$(jq -r '[.hooks.beforeShellExecution[]? | select(.command == "/usr/local/bin/custom-before-shell-hook.sh")] | length' "$CURSOR_DIR/hooks.json")
if [[ "$CURSOR_CUSTOM_COUNT" -ne 1 ]]; then
    echo "FAIL: expected custom Cursor hook to be preserved" >&2
    cat "$CURSOR_DIR/hooks.json" >&2
    exit 1
fi

echo "  ✅ reset cursor cleans APort hooks and preserves custom hooks"

echo ""
echo "  Framework reset tests passed."
echo ""

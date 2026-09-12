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

CLAUDE_INVALID_DIR="$TEST_DIR/claude-invalid-reset"
mkdir -p "$CLAUDE_INVALID_DIR/aport"
printf '{"hooks":' > "$CLAUDE_INVALID_DIR/settings.json"
touch "$CLAUDE_INVALID_DIR/aport/passport.json"

echo "  Test: reset claude-code preserves runtime when hook cleanup fails..."
set +e
APORT_CLAUDE_CODE_CONFIG_DIR="$CLAUDE_INVALID_DIR" "$DISPATCHER" reset claude-code --yes > "$TEST_DIR/reset-claude-invalid-json.txt" 2>&1
CLAUDE_INVALID_EXIT=$?
set -e
if [[ "$CLAUDE_INVALID_EXIT" -eq 0 ]]; then
    echo "FAIL: reset claude-code should fail when settings JSON is invalid" >&2
    cat "$TEST_DIR/reset-claude-invalid-json.txt" >&2
    exit 1
fi
if [[ ! -f "$CLAUDE_INVALID_DIR/aport/passport.json" ]]; then
    echo "FAIL: reset claude-code removed runtime before hook cleanup succeeded" >&2
    exit 1
fi
grep -q "cannot safely remove hook entries" "$TEST_DIR/reset-claude-invalid-json.txt" || {
    echo "FAIL: expected Claude cleanup failure message" >&2
    cat "$TEST_DIR/reset-claude-invalid-json.txt" >&2
    exit 1
}

echo "  ✅ reset claude-code preserves runtime on cleanup failure"

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

CURSOR_INVALID_DIR="$TEST_DIR/cursor-invalid-reset"
mkdir -p "$CURSOR_INVALID_DIR/aport"
printf '{"hooks":' > "$CURSOR_INVALID_DIR/hooks.json"
touch "$CURSOR_INVALID_DIR/aport/passport.json"

echo "  Test: reset cursor preserves runtime when hook cleanup fails..."
set +e
APORT_CURSOR_CONFIG_DIR="$CURSOR_INVALID_DIR" "$DISPATCHER" reset cursor --yes > "$TEST_DIR/reset-cursor-invalid-json.txt" 2>&1
CURSOR_INVALID_EXIT=$?
set -e
if [[ "$CURSOR_INVALID_EXIT" -eq 0 ]]; then
    echo "FAIL: reset cursor should fail when hooks JSON is invalid" >&2
    cat "$TEST_DIR/reset-cursor-invalid-json.txt" >&2
    exit 1
fi
if [[ ! -f "$CURSOR_INVALID_DIR/aport/passport.json" ]]; then
    echo "FAIL: reset cursor removed runtime before hook cleanup succeeded" >&2
    exit 1
fi
grep -q "cannot safely remove hook entries" "$TEST_DIR/reset-cursor-invalid-json.txt" || {
    echo "FAIL: expected Cursor cleanup failure message" >&2
    cat "$TEST_DIR/reset-cursor-invalid-json.txt" >&2
    exit 1
}

echo "  ✅ reset cursor preserves runtime on cleanup failure"

CODEX_DIR="$TEST_DIR/.codex"
mkdir -p "$CODEX_DIR/aport"
cat > "$CODEX_DIR/hooks.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-codex-hook.sh","__aport_hook":true},
          {"type":"command","command":"/usr/local/bin/custom-codex-hook.sh"}
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
touch "$CODEX_DIR/aport/passport.json"

echo "  Test: reset codex removes APort hooks and preserves custom hooks..."
APORT_CODEX_CONFIG_DIR="$CODEX_DIR" "$DISPATCHER" reset codex --yes > "$TEST_DIR/reset-codex.txt" 2>&1

if [[ -d "$CODEX_DIR/aport" ]]; then
    echo "FAIL: expected $CODEX_DIR/aport to be removed" >&2
    exit 1
fi
CODEX_APORT_COUNT=$(jq -r '[
    .hooks.PreToolUse[]?.hooks[]?,
    .hooks.PostToolUse[]?.hooks[]?,
    .hooks.PermissionRequest[]?.hooks[]?
] | map(select(.__aport_hook == true)) | length' "$CODEX_DIR/hooks.json")
if [[ "$CODEX_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected marker-owned Codex hook entries to be removed" >&2
    cat "$CODEX_DIR/hooks.json" >&2
    exit 1
fi
CODEX_CUSTOM_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command == "/usr/local/bin/custom-codex-hook.sh")] | length' "$CODEX_DIR/hooks.json")
if [[ "$CODEX_CUSTOM_COUNT" -ne 1 ]]; then
    echo "FAIL: expected custom Codex hook to be preserved" >&2
    cat "$CODEX_DIR/hooks.json" >&2
    exit 1
fi

echo "  ✅ reset codex cleans APort hooks and preserves custom hooks"

CODEX_PROJECT_DIR="$TEST_DIR/codex-project-default"
CODEX_PROJECT_HOOKS="$CODEX_PROJECT_DIR/.codex"
CODEX_STATE_DIR="$TEST_DIR/codex-home/.aport/codex"
mkdir -p "$CODEX_PROJECT_HOOKS" "$CODEX_STATE_DIR/aport"
cat > "$CODEX_PROJECT_HOOKS/hooks.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
touch "$CODEX_STATE_DIR/aport/passport.json"

echo "  Test: reset codex cleans project hook and preserves shared state without env override..."
(
    cd "$CODEX_PROJECT_DIR"
    HOME="$TEST_DIR/codex-home" "$DISPATCHER" reset codex --yes > "$TEST_DIR/reset-codex-project.txt" 2>&1
)
if [[ ! -d "$CODEX_STATE_DIR/aport" ]]; then
    echo "FAIL: expected shared Codex state to be preserved for other project hooks" >&2
    exit 1
fi
CODEX_PROJECT_APORT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_PROJECT_HOOKS/hooks.json")
if [[ "$CODEX_PROJECT_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected project-local Codex hook entries to be removed" >&2
    cat "$CODEX_PROJECT_HOOKS/hooks.json" >&2
    exit 1
fi

echo "  ✅ reset codex cleans project-local hooks and preserves shared state"

CODEX_CUSTOM_DIR="$TEST_DIR/codex-custom-project"
CODEX_CUSTOM_HOOKS="$TEST_DIR/codex-custom-hooks"
CODEX_CUSTOM_STATE="$TEST_DIR/codex-custom-home/.aport/codex"
mkdir -p "$CODEX_CUSTOM_DIR" "$CODEX_CUSTOM_HOOKS" "$CODEX_CUSTOM_STATE/aport"
cat > "$CODEX_CUSTOM_HOOKS/hooks.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
touch "$CODEX_CUSTOM_STATE/aport/passport.json"

echo "  Test: reset codex honors explicit project hooks directory override..."
(
    cd "$CODEX_CUSTOM_DIR"
    HOME="$TEST_DIR/codex-custom-home" APORT_CODEX_HOOKS_DIR="$CODEX_CUSTOM_HOOKS" "$DISPATCHER" reset codex --project --yes > "$TEST_DIR/reset-codex-custom-hooks.txt" 2>&1
)
CODEX_CUSTOM_APORT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_CUSTOM_HOOKS/hooks.json")
if [[ "$CODEX_CUSTOM_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected custom Codex hooks directory to be cleaned" >&2
    cat "$CODEX_CUSTOM_HOOKS/hooks.json" >&2
    exit 1
fi
if [[ ! -d "$CODEX_CUSTOM_STATE/aport" ]]; then
    echo "FAIL: expected custom Codex reset to preserve shared state" >&2
    exit 1
fi

echo "  ✅ reset codex honors explicit hook directory override"

CODEX_OVERRIDE_PROJECT="$TEST_DIR/codex-config-override-project"
CODEX_OVERRIDE_HOME="$TEST_DIR/codex-config-override-home"
CODEX_OVERRIDE_STATE="$TEST_DIR/codex-config-override-state"
CODEX_OVERRIDE_DEFAULT_STATE="$CODEX_OVERRIDE_HOME/.aport/codex"
mkdir -p "$CODEX_OVERRIDE_PROJECT" "$CODEX_OVERRIDE_STATE/aport" "$CODEX_OVERRIDE_DEFAULT_STATE/aport"
touch "$CODEX_OVERRIDE_STATE/aport/passport.json" "$CODEX_OVERRIDE_DEFAULT_STATE/aport/passport.json"

echo "  Test: reset codex honors generic APORT_CONFIG_DIR for state cleanup..."
(
    cd "$CODEX_OVERRIDE_PROJECT"
    HOME="$CODEX_OVERRIDE_HOME" APORT_CONFIG_DIR="$CODEX_OVERRIDE_STATE" "$DISPATCHER" reset codex --yes > "$TEST_DIR/reset-codex-config-override.txt" 2>&1
)
if [[ -d "$CODEX_OVERRIDE_STATE/aport" ]]; then
    echo "FAIL: expected generic APORT_CONFIG_DIR state to be removed" >&2
    cat "$TEST_DIR/reset-codex-config-override.txt" >&2
    exit 1
fi
if [[ ! -d "$CODEX_OVERRIDE_DEFAULT_STATE/aport" ]]; then
    echo "FAIL: expected default Codex state to remain untouched when APORT_CONFIG_DIR is set" >&2
    exit 1
fi

echo "  ✅ reset codex honors generic APORT_CONFIG_DIR"

CODEX_BACKUP_PROJECT="$TEST_DIR/codex-backup-project"
CODEX_BACKUP_HOME="$TEST_DIR/codex-backup-home"
CODEX_BACKUP_HOOKS="$CODEX_BACKUP_PROJECT/.codex"
CODEX_BACKUP_VICTIM="$TEST_DIR/codex-backup-victim.txt"
mkdir -p "$CODEX_BACKUP_HOOKS" "$CODEX_BACKUP_HOME"
cat > "$CODEX_BACKUP_HOOKS/hooks.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
printf 'do not overwrite\n' > "$CODEX_BACKUP_VICTIM"
ln -s "$CODEX_BACKUP_VICTIM" "$CODEX_BACKUP_HOOKS/hooks.json.bak"

echo "  Test: reset codex refuses symlinked backup targets..."
set +e
(
    cd "$CODEX_BACKUP_PROJECT"
    HOME="$CODEX_BACKUP_HOME" "$DISPATCHER" reset codex --project --yes > "$TEST_DIR/reset-codex-backup-symlink.txt" 2>&1
)
CODEX_BACKUP_EXIT=$?
set -e
if [[ "$CODEX_BACKUP_EXIT" -eq 0 ]]; then
    echo "FAIL: reset codex should reject symlinked backup targets" >&2
    cat "$TEST_DIR/reset-codex-backup-symlink.txt" >&2
    exit 1
fi
if [[ "$(cat "$CODEX_BACKUP_VICTIM")" != "do not overwrite" ]]; then
    echo "FAIL: reset codex overwrote symlinked backup target" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/reset-codex-backup-symlink.txt" || {
    echo "FAIL: expected backup symlink refusal in codex reset output" >&2
    cat "$TEST_DIR/reset-codex-backup-symlink.txt" >&2
    exit 1
}

echo "  ✅ reset codex refuses symlinked backup targets"

CODEX_SYMLINK_PROJECT="$TEST_DIR/codex-symlink-project"
CODEX_SYMLINK_TARGET="$TEST_DIR/codex-symlink-target"
CODEX_SYMLINK_HOME="$TEST_DIR/codex-symlink-home"
mkdir -p "$CODEX_SYMLINK_PROJECT" "$CODEX_SYMLINK_TARGET/aport" "$CODEX_SYMLINK_HOME"
ln -s "$CODEX_SYMLINK_TARGET" "$CODEX_SYMLINK_PROJECT/.codex"
touch "$CODEX_SYMLINK_TARGET/aport/passport.json"

echo "  Test: reset codex refuses symlinked project config paths..."
set +e
(
    cd "$CODEX_SYMLINK_PROJECT"
    HOME="$CODEX_SYMLINK_HOME" "$DISPATCHER" reset codex --project --yes > "$TEST_DIR/reset-codex-symlink.txt" 2>&1
)
CODEX_SYMLINK_EXIT=$?
set -e
if [[ "$CODEX_SYMLINK_EXIT" -eq 0 ]]; then
    echo "FAIL: reset codex should reject symlinked project paths" >&2
    cat "$TEST_DIR/reset-codex-symlink.txt" >&2
    exit 1
fi
if [[ ! -f "$CODEX_SYMLINK_TARGET/aport/passport.json" ]]; then
    echo "FAIL: reset codex followed a symlink and removed target state" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/reset-codex-symlink.txt" || {
    echo "FAIL: expected symlink refusal in codex reset output" >&2
    cat "$TEST_DIR/reset-codex-symlink.txt" >&2
    exit 1
}

echo "  ✅ reset codex refuses symlinked project paths"

CODEX_GLOBAL_HOME="$TEST_DIR/codex-global-home"
CODEX_GLOBAL_PROJECT="$TEST_DIR/codex-global-project"
CODEX_GLOBAL_HOOKS="$CODEX_GLOBAL_HOME/.codex"
CODEX_GLOBAL_PROJECT_HOOKS="$CODEX_GLOBAL_PROJECT/.codex"
CODEX_GLOBAL_STATE="$CODEX_GLOBAL_HOME/.aport/codex/aport"
mkdir -p "$CODEX_GLOBAL_HOOKS" "$CODEX_GLOBAL_PROJECT_HOOKS" "$CODEX_GLOBAL_STATE"
for hooks_file in "$CODEX_GLOBAL_HOOKS/hooks.json" "$CODEX_GLOBAL_PROJECT_HOOKS/hooks.json"; do
    cat > "$hooks_file" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
done
touch "$CODEX_GLOBAL_STATE/passport.json"

echo "  Test: reset codex --global preserves shared state for project hooks..."
(
    cd "$CODEX_GLOBAL_PROJECT"
    HOME="$CODEX_GLOBAL_HOME" "$DISPATCHER" reset codex --global --yes > "$TEST_DIR/reset-codex-global.txt" 2>&1
)
CODEX_GLOBAL_APORT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_GLOBAL_HOOKS/hooks.json")
if [[ "$CODEX_GLOBAL_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected global Codex hooks to be cleaned" >&2
    cat "$CODEX_GLOBAL_HOOKS/hooks.json" >&2
    exit 1
fi
CODEX_REMAINING_PROJECT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_GLOBAL_PROJECT_HOOKS/hooks.json")
if [[ "$CODEX_REMAINING_PROJECT_COUNT" -ne 1 ]]; then
    echo "FAIL: expected project Codex hook to be preserved by --global" >&2
    cat "$CODEX_GLOBAL_PROJECT_HOOKS/hooks.json" >&2
    exit 1
fi
if [[ ! -d "$CODEX_GLOBAL_STATE" ]]; then
    echo "FAIL: expected shared Codex state to be preserved by --global" >&2
    exit 1
fi

echo "  ✅ reset codex --global preserves shared state for project hooks"

CODEX_INVALID_HOME="$TEST_DIR/codex-invalid-home"
CODEX_INVALID_PROJECT="$TEST_DIR/codex-invalid-project"
CODEX_INVALID_HOOKS="$CODEX_INVALID_HOME/.codex"
CODEX_INVALID_STATE="$CODEX_INVALID_HOME/.aport/codex/aport"
mkdir -p "$CODEX_INVALID_PROJECT" "$CODEX_INVALID_HOOKS" "$CODEX_INVALID_STATE"
printf '{"hooks":' > "$CODEX_INVALID_HOOKS/hooks.json"
touch "$CODEX_INVALID_STATE/passport.json"

echo "  Test: reset codex stops before state cleanup when hook cleanup fails..."
set +e
(
    cd "$CODEX_INVALID_PROJECT"
    HOME="$CODEX_INVALID_HOME" "$DISPATCHER" reset codex --global --yes > "$TEST_DIR/reset-codex-invalid-json.txt" 2>&1
)
CODEX_INVALID_EXIT=$?
set -e
if [[ "$CODEX_INVALID_EXIT" -eq 0 ]]; then
    echo "FAIL: reset codex should fail when hook cleanup cannot run" >&2
    cat "$TEST_DIR/reset-codex-invalid-json.txt" >&2
    exit 1
fi
if [[ ! -d "$CODEX_INVALID_STATE" ]]; then
    echo "FAIL: reset codex removed shared state after hook cleanup failed" >&2
    exit 1
fi
grep -q "cannot safely remove hook entries" "$TEST_DIR/reset-codex-invalid-json.txt" || {
    echo "FAIL: expected cleanup failure message in codex reset output" >&2
    cat "$TEST_DIR/reset-codex-invalid-json.txt" >&2
    exit 1
}

echo "  ✅ reset codex preserves state when hook cleanup fails"

GEMINI_DIR="$TEST_DIR/.gemini"
mkdir -p "$GEMINI_DIR/aport"
cat > "$GEMINI_DIR/settings.json" << 'EOF'
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": ".*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-gemini-cli-hook.sh","__aport_hook":true},
          {"type":"command","command":"/usr/local/bin/custom-gemini-hook.sh"}
        ]
      }
    ]
  }
}
EOF
touch "$GEMINI_DIR/aport/passport.json"

echo "  Test: reset gemini removes APort hooks and preserves custom hooks..."
APORT_GEMINI_CLI_CONFIG_DIR="$GEMINI_DIR" "$DISPATCHER" reset gemini --yes > "$TEST_DIR/reset-gemini.txt" 2>&1

if [[ -d "$GEMINI_DIR/aport" ]]; then
    echo "FAIL: expected $GEMINI_DIR/aport to be removed" >&2
    exit 1
fi
GEMINI_APORT_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_DIR/settings.json")
if [[ "$GEMINI_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected marker-owned Gemini CLI hook entries to be removed" >&2
    cat "$GEMINI_DIR/settings.json" >&2
    exit 1
fi
GEMINI_CUSTOM_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.command == "/usr/local/bin/custom-gemini-hook.sh")] | length' "$GEMINI_DIR/settings.json")
if [[ "$GEMINI_CUSTOM_COUNT" -ne 1 ]]; then
    echo "FAIL: expected custom Gemini CLI hook to be preserved" >&2
    cat "$GEMINI_DIR/settings.json" >&2
    exit 1
fi

echo "  ✅ reset gemini cleans APort hooks and preserves custom hooks"

GEMINI_PROJECT_DIR="$TEST_DIR/gemini-project-default"
GEMINI_PROJECT_HOOKS="$GEMINI_PROJECT_DIR/.gemini"
GEMINI_STATE_DIR="$TEST_DIR/gemini-home/.aport/gemini-cli"
mkdir -p "$GEMINI_PROJECT_HOOKS" "$GEMINI_STATE_DIR/aport"
cat > "$GEMINI_PROJECT_HOOKS/settings.json" << 'EOF'
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": ".*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-gemini-cli-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
touch "$GEMINI_STATE_DIR/aport/passport.json"

echo "  Test: reset gemini cleans project hook and preserves shared state without env override..."
(
    cd "$GEMINI_PROJECT_DIR"
    HOME="$TEST_DIR/gemini-home" "$DISPATCHER" reset gemini --yes > "$TEST_DIR/reset-gemini-project.txt" 2>&1
)
if [[ ! -d "$GEMINI_STATE_DIR/aport" ]]; then
    echo "FAIL: expected shared Gemini state to be preserved for other project hooks" >&2
    exit 1
fi
GEMINI_PROJECT_APORT_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_PROJECT_HOOKS/settings.json")
if [[ "$GEMINI_PROJECT_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected project-local Gemini hook entries to be removed" >&2
    cat "$GEMINI_PROJECT_HOOKS/settings.json" >&2
    exit 1
fi

echo "  ✅ reset gemini cleans project-local hooks and preserves shared state"

GEMINI_CUSTOM_DIR="$TEST_DIR/gemini-custom-project"
GEMINI_CUSTOM_HOOKS="$TEST_DIR/gemini-custom-hooks"
GEMINI_CUSTOM_STATE="$TEST_DIR/gemini-custom-home/.aport/gemini-cli"
mkdir -p "$GEMINI_CUSTOM_DIR" "$GEMINI_CUSTOM_HOOKS" "$GEMINI_CUSTOM_STATE/aport"
cat > "$GEMINI_CUSTOM_HOOKS/settings.json" << 'EOF'
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": ".*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-gemini-cli-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
touch "$GEMINI_CUSTOM_STATE/aport/passport.json"

echo "  Test: reset gemini honors explicit project hooks directory override..."
(
    cd "$GEMINI_CUSTOM_DIR"
    HOME="$TEST_DIR/gemini-custom-home" APORT_GEMINI_CLI_HOOKS_DIR="$GEMINI_CUSTOM_HOOKS" "$DISPATCHER" reset gemini --project --yes > "$TEST_DIR/reset-gemini-custom-hooks.txt" 2>&1
)
GEMINI_CUSTOM_APORT_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_CUSTOM_HOOKS/settings.json")
if [[ "$GEMINI_CUSTOM_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected custom Gemini hooks directory to be cleaned" >&2
    cat "$GEMINI_CUSTOM_HOOKS/settings.json" >&2
    exit 1
fi
if [[ ! -d "$GEMINI_CUSTOM_STATE/aport" ]]; then
    echo "FAIL: expected custom Gemini reset to preserve shared state" >&2
    exit 1
fi

echo "  ✅ reset gemini honors explicit hook directory override"

GEMINI_BACKUP_PROJECT="$TEST_DIR/gemini-backup-project"
GEMINI_BACKUP_HOME="$TEST_DIR/gemini-backup-home"
GEMINI_BACKUP_HOOKS="$GEMINI_BACKUP_PROJECT/.gemini"
GEMINI_BACKUP_VICTIM="$TEST_DIR/gemini-backup-victim.txt"
mkdir -p "$GEMINI_BACKUP_HOOKS" "$GEMINI_BACKUP_HOME"
cat > "$GEMINI_BACKUP_HOOKS/settings.json" << 'EOF'
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": ".*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-gemini-cli-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
printf 'do not overwrite\n' > "$GEMINI_BACKUP_VICTIM"
ln -s "$GEMINI_BACKUP_VICTIM" "$GEMINI_BACKUP_HOOKS/settings.json.bak"

echo "  Test: reset gemini refuses symlinked backup targets..."
set +e
(
    cd "$GEMINI_BACKUP_PROJECT"
    HOME="$GEMINI_BACKUP_HOME" "$DISPATCHER" reset gemini --project --yes > "$TEST_DIR/reset-gemini-backup-symlink.txt" 2>&1
)
GEMINI_BACKUP_EXIT=$?
set -e
if [[ "$GEMINI_BACKUP_EXIT" -eq 0 ]]; then
    echo "FAIL: reset gemini should reject symlinked backup targets" >&2
    cat "$TEST_DIR/reset-gemini-backup-symlink.txt" >&2
    exit 1
fi
if [[ "$(cat "$GEMINI_BACKUP_VICTIM")" != "do not overwrite" ]]; then
    echo "FAIL: reset gemini overwrote symlinked backup target" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/reset-gemini-backup-symlink.txt" || {
    echo "FAIL: expected backup symlink refusal in gemini reset output" >&2
    cat "$TEST_DIR/reset-gemini-backup-symlink.txt" >&2
    exit 1
}

echo "  ✅ reset gemini refuses symlinked backup targets"

GEMINI_SYMLINK_PROJECT="$TEST_DIR/gemini-symlink-project"
GEMINI_SYMLINK_TARGET="$TEST_DIR/gemini-symlink-target"
GEMINI_SYMLINK_HOME="$TEST_DIR/gemini-symlink-home"
mkdir -p "$GEMINI_SYMLINK_PROJECT" "$GEMINI_SYMLINK_TARGET/aport" "$GEMINI_SYMLINK_HOME"
ln -s "$GEMINI_SYMLINK_TARGET" "$GEMINI_SYMLINK_PROJECT/.gemini"
touch "$GEMINI_SYMLINK_TARGET/aport/passport.json"

echo "  Test: reset gemini refuses symlinked project config paths..."
set +e
(
    cd "$GEMINI_SYMLINK_PROJECT"
    HOME="$GEMINI_SYMLINK_HOME" "$DISPATCHER" reset gemini --project --yes > "$TEST_DIR/reset-gemini-symlink.txt" 2>&1
)
GEMINI_SYMLINK_EXIT=$?
set -e
if [[ "$GEMINI_SYMLINK_EXIT" -eq 0 ]]; then
    echo "FAIL: reset gemini should reject symlinked project paths" >&2
    cat "$TEST_DIR/reset-gemini-symlink.txt" >&2
    exit 1
fi
if [[ ! -f "$GEMINI_SYMLINK_TARGET/aport/passport.json" ]]; then
    echo "FAIL: reset gemini followed a symlink and removed target state" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/reset-gemini-symlink.txt" || {
    echo "FAIL: expected symlink refusal in gemini reset output" >&2
    cat "$TEST_DIR/reset-gemini-symlink.txt" >&2
    exit 1
}

echo "  ✅ reset gemini refuses symlinked project paths"

GEMINI_GLOBAL_HOME="$TEST_DIR/gemini-global-home"
GEMINI_GLOBAL_PROJECT="$TEST_DIR/gemini-global-project"
GEMINI_GLOBAL_HOOKS="$GEMINI_GLOBAL_HOME/.gemini"
GEMINI_GLOBAL_PROJECT_HOOKS="$GEMINI_GLOBAL_PROJECT/.gemini"
GEMINI_GLOBAL_STATE="$GEMINI_GLOBAL_HOME/.aport/gemini-cli/aport"
mkdir -p "$GEMINI_GLOBAL_HOOKS" "$GEMINI_GLOBAL_PROJECT_HOOKS" "$GEMINI_GLOBAL_STATE"
for settings_file in "$GEMINI_GLOBAL_HOOKS/settings.json" "$GEMINI_GLOBAL_PROJECT_HOOKS/settings.json"; do
    cat > "$settings_file" << 'EOF'
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": ".*",
        "hooks": [
          {"type":"command","command":"/tmp/aport-gemini-cli-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
done
touch "$GEMINI_GLOBAL_STATE/passport.json"

echo "  Test: reset gemini --global preserves shared state for project hooks..."
(
    cd "$GEMINI_GLOBAL_PROJECT"
    HOME="$GEMINI_GLOBAL_HOME" "$DISPATCHER" reset gemini --global --yes > "$TEST_DIR/reset-gemini-global.txt" 2>&1
)
GEMINI_GLOBAL_APORT_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_GLOBAL_HOOKS/settings.json")
if [[ "$GEMINI_GLOBAL_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected global Gemini hooks to be cleaned" >&2
    cat "$GEMINI_GLOBAL_HOOKS/settings.json" >&2
    exit 1
fi
GEMINI_REMAINING_PROJECT_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_GLOBAL_PROJECT_HOOKS/settings.json")
if [[ "$GEMINI_REMAINING_PROJECT_COUNT" -ne 1 ]]; then
    echo "FAIL: expected project Gemini hook to be preserved by --global" >&2
    cat "$GEMINI_GLOBAL_PROJECT_HOOKS/settings.json" >&2
    exit 1
fi
if [[ ! -d "$GEMINI_GLOBAL_STATE" ]]; then
    echo "FAIL: expected shared Gemini state to be preserved by --global" >&2
    exit 1
fi

echo "  ✅ reset gemini --global preserves shared state for project hooks"

GEMINI_INVALID_HOME="$TEST_DIR/gemini-invalid-home"
GEMINI_INVALID_PROJECT="$TEST_DIR/gemini-invalid-project"
GEMINI_INVALID_HOOKS="$GEMINI_INVALID_HOME/.gemini"
GEMINI_INVALID_STATE="$GEMINI_INVALID_HOME/.aport/gemini-cli/aport"
mkdir -p "$GEMINI_INVALID_PROJECT" "$GEMINI_INVALID_HOOKS" "$GEMINI_INVALID_STATE"
printf '{"hooks":' > "$GEMINI_INVALID_HOOKS/settings.json"
touch "$GEMINI_INVALID_STATE/passport.json"

echo "  Test: reset gemini stops before state cleanup when hook cleanup fails..."
set +e
(
    cd "$GEMINI_INVALID_PROJECT"
    HOME="$GEMINI_INVALID_HOME" "$DISPATCHER" reset gemini --global --yes > "$TEST_DIR/reset-gemini-invalid-json.txt" 2>&1
)
GEMINI_INVALID_EXIT=$?
set -e
if [[ "$GEMINI_INVALID_EXIT" -eq 0 ]]; then
    echo "FAIL: reset gemini should fail when hook cleanup cannot run" >&2
    cat "$TEST_DIR/reset-gemini-invalid-json.txt" >&2
    exit 1
fi
if [[ ! -d "$GEMINI_INVALID_STATE" ]]; then
    echo "FAIL: reset gemini removed shared state after hook cleanup failed" >&2
    exit 1
fi
grep -q "cannot safely remove hook entries" "$TEST_DIR/reset-gemini-invalid-json.txt" || {
    echo "FAIL: expected cleanup failure message in gemini reset output" >&2
    cat "$TEST_DIR/reset-gemini-invalid-json.txt" >&2
    exit 1
}

echo "  ✅ reset gemini preserves state when hook cleanup fails"

GOOSE_HOME="$TEST_DIR/goose-home"
GOOSE_PROJECT="$TEST_DIR/goose-project"
GOOSE_CONFIG_DIR="$GOOSE_HOME/.aport/goose"
GOOSE_PLUGIN_DIR="$GOOSE_PROJECT/.agents/plugins/aport-guardrail"
mkdir -p "$GOOSE_CONFIG_DIR/aport" "$GOOSE_PLUGIN_DIR"
cat > "$GOOSE_PLUGIN_DIR/plugin.json" << 'EOF'
{"name":"aport-guardrail","version":"1.0.0"}
EOF
touch "$GOOSE_CONFIG_DIR/aport/passport.json"

echo "  Test: reset goose removes APort plugin and state..."
(
    cd "$GOOSE_PROJECT"
    HOME="$GOOSE_HOME" APORT_GOOSE_CONFIG_DIR="$GOOSE_CONFIG_DIR" "$DISPATCHER" reset goose --yes > "$TEST_DIR/reset-goose.txt" 2>&1
)

if [[ ! -d "$GOOSE_CONFIG_DIR/aport" ]]; then
    echo "FAIL: expected shared Goose state to be preserved for project-local reset" >&2
    exit 1
fi
if [[ -d "$GOOSE_PLUGIN_DIR" ]]; then
    echo "FAIL: expected APort Goose plugin dir to be removed" >&2
    find "$GOOSE_PLUGIN_DIR" -maxdepth 2 -type f >&2
    exit 1
fi

echo "  ✅ reset goose removes project plugin and preserves shared state"

GOOSE_SCOPE_HOME="$TEST_DIR/goose-scope-home"
GOOSE_SCOPE_PROJECT="$TEST_DIR/goose-scope-project"
GOOSE_SCOPE_PROJECT_PLUGIN="$GOOSE_SCOPE_PROJECT/.agents/plugins/aport-guardrail"
GOOSE_SCOPE_GLOBAL_PLUGIN="$GOOSE_SCOPE_HOME/.agents/plugins/aport-guardrail"
GOOSE_SCOPE_STATE="$GOOSE_SCOPE_HOME/.aport/goose/aport"
mkdir -p "$GOOSE_SCOPE_PROJECT_PLUGIN" "$GOOSE_SCOPE_GLOBAL_PLUGIN" "$GOOSE_SCOPE_STATE"
printf '{"name":"aport-guardrail","version":"1.0.0"}\n' > "$GOOSE_SCOPE_PROJECT_PLUGIN/plugin.json"
printf '{"name":"aport-guardrail","version":"1.0.0"}\n' > "$GOOSE_SCOPE_GLOBAL_PLUGIN/plugin.json"
touch "$GOOSE_SCOPE_STATE/passport.json"

echo "  Test: reset goose --project preserves global plugin and shared state..."
(
    cd "$GOOSE_SCOPE_PROJECT"
    HOME="$GOOSE_SCOPE_HOME" "$DISPATCHER" reset goose --project --yes > "$TEST_DIR/reset-goose-project-scope.txt" 2>&1
)
if [[ -d "$GOOSE_SCOPE_PROJECT_PLUGIN" ]]; then
    echo "FAIL: expected project Goose plugin to be removed" >&2
    exit 1
fi
if [[ ! -d "$GOOSE_SCOPE_GLOBAL_PLUGIN" ]]; then
    echo "FAIL: expected global Goose plugin to be preserved by --project" >&2
    exit 1
fi
if [[ ! -d "$GOOSE_SCOPE_STATE" ]]; then
    echo "FAIL: expected shared Goose state to be preserved by --project" >&2
    exit 1
fi

echo "  ✅ reset goose --project preserves global plugin and shared state"

mkdir -p "$GOOSE_SCOPE_PROJECT_PLUGIN"
printf '{"name":"aport-guardrail","version":"1.0.0"}\n' > "$GOOSE_SCOPE_PROJECT_PLUGIN/plugin.json"

echo "  Test: reset goose --global preserves project plugin and shared state..."
(
    cd "$GOOSE_SCOPE_PROJECT"
    HOME="$GOOSE_SCOPE_HOME" "$DISPATCHER" reset goose --global --yes > "$TEST_DIR/reset-goose-global-scope.txt" 2>&1
)
if [[ ! -d "$GOOSE_SCOPE_PROJECT_PLUGIN" ]]; then
    echo "FAIL: expected project Goose plugin to be preserved by --global" >&2
    exit 1
fi
if [[ -d "$GOOSE_SCOPE_GLOBAL_PLUGIN" ]]; then
    echo "FAIL: expected global Goose plugin to be removed by --global" >&2
    exit 1
fi
if [[ ! -d "$GOOSE_SCOPE_STATE" ]]; then
    echo "FAIL: expected shared Goose state to be preserved by --global" >&2
    exit 1
fi

echo "  ✅ reset goose --global preserves project plugin and shared state"

GOOSE_CUSTOM_HOME="$TEST_DIR/goose-custom-home"
GOOSE_CUSTOM_PROJECT="$TEST_DIR/goose-custom-project"
GOOSE_CUSTOM_PLUGIN="$TEST_DIR/goose-custom-plugin"
GOOSE_CUSTOM_STATE="$GOOSE_CUSTOM_HOME/.aport/goose/aport"
mkdir -p "$GOOSE_CUSTOM_PROJECT" "$GOOSE_CUSTOM_PLUGIN" "$GOOSE_CUSTOM_STATE"
printf '{"name":"aport-guardrail","version":"1.0.0"}\n' > "$GOOSE_CUSTOM_PLUGIN/plugin.json"
touch "$GOOSE_CUSTOM_STATE/passport.json"

echo "  Test: reset goose --project honors explicit plugin directory override..."
(
    cd "$GOOSE_CUSTOM_PROJECT"
    HOME="$GOOSE_CUSTOM_HOME" APORT_GOOSE_PLUGIN_DIR="$GOOSE_CUSTOM_PLUGIN" "$DISPATCHER" reset goose --project --yes > "$TEST_DIR/reset-goose-custom-plugin.txt" 2>&1
)
if [[ -d "$GOOSE_CUSTOM_PLUGIN" ]]; then
    echo "FAIL: expected custom Goose plugin directory to be removed" >&2
    exit 1
fi
if [[ ! -d "$GOOSE_CUSTOM_STATE" ]]; then
    echo "FAIL: expected explicit project reset to preserve shared Goose state" >&2
    exit 1
fi

echo "  ✅ reset goose honors explicit plugin directory override"

GOOSE_SHARED_CUSTOM_HOME="$TEST_DIR/goose-shared-custom-home"
GOOSE_SHARED_CUSTOM_PROJECT="$TEST_DIR/goose-shared-custom-project"
GOOSE_SHARED_CUSTOM_STATE="$TEST_DIR/goose-shared-custom-state"
GOOSE_SHARED_CUSTOM_PROJECT_PLUGIN="$GOOSE_SHARED_CUSTOM_PROJECT/.agents/plugins/aport-guardrail"
GOOSE_SHARED_CUSTOM_GLOBAL_PLUGIN="$GOOSE_SHARED_CUSTOM_HOME/.agents/plugins/aport-guardrail"
mkdir -p "$GOOSE_SHARED_CUSTOM_PROJECT_PLUGIN" "$GOOSE_SHARED_CUSTOM_GLOBAL_PLUGIN" "$GOOSE_SHARED_CUSTOM_STATE/aport"
printf '{"name":"aport-guardrail","version":"1.0.0"}\n' > "$GOOSE_SHARED_CUSTOM_PROJECT_PLUGIN/plugin.json"
printf '{"name":"aport-guardrail","version":"1.0.0"}\n' > "$GOOSE_SHARED_CUSTOM_GLOBAL_PLUGIN/plugin.json"
touch "$GOOSE_SHARED_CUSTOM_STATE/aport/passport.json"

echo "  Test: reset goose --project preserves custom state used by another plugin scope..."
(
    cd "$GOOSE_SHARED_CUSTOM_PROJECT"
    HOME="$GOOSE_SHARED_CUSTOM_HOME" APORT_GOOSE_CONFIG_DIR="$GOOSE_SHARED_CUSTOM_STATE" "$DISPATCHER" reset goose --project --yes > "$TEST_DIR/reset-goose-shared-custom-state.txt" 2>&1
)
if [[ -d "$GOOSE_SHARED_CUSTOM_PROJECT_PLUGIN" ]]; then
    echo "FAIL: expected project Goose plugin to be removed" >&2
    exit 1
fi
if [[ ! -d "$GOOSE_SHARED_CUSTOM_GLOBAL_PLUGIN" ]]; then
    echo "FAIL: expected global Goose plugin to remain" >&2
    exit 1
fi
if [[ ! -f "$GOOSE_SHARED_CUSTOM_STATE/aport/passport.json" ]]; then
    echo "FAIL: expected custom Goose state to remain while global plugin exists" >&2
    exit 1
fi

echo "  ✅ reset goose preserves shared custom state"

GOOSE_SYMLINK_PROJECT="$TEST_DIR/goose-symlink-project"
GOOSE_SYMLINK_TARGET="$TEST_DIR/goose-symlink-target"
GOOSE_SYMLINK_HOME="$TEST_DIR/goose-symlink-home"
mkdir -p "$GOOSE_SYMLINK_PROJECT" "$GOOSE_SYMLINK_TARGET/plugins/aport-guardrail" "$GOOSE_SYMLINK_HOME"
ln -s "$GOOSE_SYMLINK_TARGET" "$GOOSE_SYMLINK_PROJECT/.agents"
printf '{"name":"aport-guardrail","version":"1.0.0"}\n' > "$GOOSE_SYMLINK_TARGET/plugins/aport-guardrail/plugin.json"

echo "  Test: reset goose refuses symlinked project plugin paths..."
set +e
(
    cd "$GOOSE_SYMLINK_PROJECT"
    HOME="$GOOSE_SYMLINK_HOME" "$DISPATCHER" reset goose --project --yes > "$TEST_DIR/reset-goose-symlink.txt" 2>&1
)
GOOSE_SYMLINK_EXIT=$?
set -e
if [[ "$GOOSE_SYMLINK_EXIT" -eq 0 ]]; then
    echo "FAIL: reset goose should reject symlinked project plugin paths" >&2
    cat "$TEST_DIR/reset-goose-symlink.txt" >&2
    exit 1
fi
if [[ ! -f "$GOOSE_SYMLINK_TARGET/plugins/aport-guardrail/plugin.json" ]]; then
    echo "FAIL: reset goose followed a symlink and removed target plugin" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/reset-goose-symlink.txt" || {
    echo "FAIL: expected symlink refusal in goose reset output" >&2
    cat "$TEST_DIR/reset-goose-symlink.txt" >&2
    exit 1
}

echo "  ✅ reset goose refuses symlinked project plugin paths"

echo ""
echo "  Framework reset tests passed."
echo ""

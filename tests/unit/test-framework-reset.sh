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
    ],
    "beforeReadFile": [
      {"command":"/tmp/aport-cursor-hook.sh","__aport_hook":true,"timeout":10,"failClosed":true}
    ],
    "beforeTabFileRead": [
      {"command":"/tmp/aport-cursor-hook.sh","__aport_hook":true,"timeout":10,"failClosed":true}
    ],
    "afterFileEdit": [
      {"command":"/usr/local/bin/custom-after-edit.sh"}
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

# Every event, including beforeReadFile and beforeTabFileRead: an entry left behind would point at the removed
# script with failClosed and block reads.
CURSOR_APORT_COUNT=$(jq -r '[.hooks // {} | .[] | .[]? | select(.__aport_hook == true)] | length' "$CURSOR_DIR/hooks.json")
if [[ "$CURSOR_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected marker-owned Cursor hook entries to be removed from every event" >&2
    cat "$CURSOR_DIR/hooks.json" >&2
    exit 1
fi
jq -e '(.hooks | has("beforeReadFile") | not) and (.hooks | has("beforeTabFileRead") | not) and (.hooks.afterFileEdit | length == 1)' "$CURSOR_DIR/hooks.json" > /dev/null || {
    echo "FAIL: emptied events must be dropped and a custom event must survive reset" >&2
    cat "$CURSOR_DIR/hooks.json" >&2
    exit 1
}

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

CURSOR_SPECIFIC_OVERRIDE_DIR="$TEST_DIR/cursor-specific-override"
CURSOR_GENERIC_OVERRIDE_DIR="$TEST_DIR/cursor-generic-override"
mkdir -p "$CURSOR_SPECIFIC_OVERRIDE_DIR/aport" "$CURSOR_GENERIC_OVERRIDE_DIR/aport"
cat > "$CURSOR_SPECIFIC_OVERRIDE_DIR/hooks.json" << 'EOF'
{
  "hooks": {
    "preToolUse": [
      {"command":"/tmp/aport-cursor-hook.sh","__aport_hook":true,"timeout":10}
    ]
  }
}
EOF
touch "$CURSOR_SPECIFIC_OVERRIDE_DIR/aport/passport.json" "$CURSOR_GENERIC_OVERRIDE_DIR/aport/passport.json"

echo "  Test: reset cursor prefers framework-specific config over generic APORT_CONFIG_DIR..."
APORT_CONFIG_DIR="$CURSOR_GENERIC_OVERRIDE_DIR" APORT_CURSOR_CONFIG_DIR="$CURSOR_SPECIFIC_OVERRIDE_DIR" "$DISPATCHER" reset cursor --yes > "$TEST_DIR/reset-cursor-specific-over-generic.txt" 2>&1
if [[ -d "$CURSOR_SPECIFIC_OVERRIDE_DIR/aport" ]]; then
    echo "FAIL: expected framework-specific Cursor state to be removed" >&2
    cat "$TEST_DIR/reset-cursor-specific-over-generic.txt" >&2
    exit 1
fi
if [[ ! -f "$CURSOR_GENERIC_OVERRIDE_DIR/aport/passport.json" ]]; then
    echo "FAIL: reset cursor removed generic APORT_CONFIG_DIR instead of framework-specific state" >&2
    cat "$TEST_DIR/reset-cursor-specific-over-generic.txt" >&2
    exit 1
fi
CURSOR_SPECIFIC_OVERRIDE_COUNT=$(jq -r '[.hooks.preToolUse[]? | select(.__aport_hook == true)] | length' "$CURSOR_SPECIFIC_OVERRIDE_DIR/hooks.json")
if [[ "$CURSOR_SPECIFIC_OVERRIDE_COUNT" -ne 0 ]]; then
    echo "FAIL: expected framework-specific Cursor hook entries to be removed" >&2
    cat "$CURSOR_SPECIFIC_OVERRIDE_DIR/hooks.json" >&2
    exit 1
fi

echo "  ✅ reset cursor prefers framework-specific config over generic APORT_CONFIG_DIR"

CURSOR_SPLIT_STATE_DIR="$TEST_DIR/cursor-split-state"
CURSOR_SPLIT_HOOKS_DIR="$TEST_DIR/cursor-split-hooks"
mkdir -p "$CURSOR_SPLIT_STATE_DIR/aport" "$CURSOR_SPLIT_HOOKS_DIR"
cat > "$CURSOR_SPLIT_HOOKS_DIR/hooks.json" << EOF
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {"command":"$CURSOR_SPLIT_STATE_DIR/aport/runtime/bin/aport-cursor-hook.sh","__aport_hook":true,"timeout":30,"failClosed":true},
      {"command":"/usr/local/bin/custom-cursor-hook.sh"}
    ]
  }
}
EOF
touch "$CURSOR_SPLIT_STATE_DIR/aport/passport.json"

echo "  Test: reset cursor honors CURSOR_HOOKS_DIR when state is split..."
APORT_CURSOR_CONFIG_DIR="$CURSOR_SPLIT_STATE_DIR" CURSOR_HOOKS_DIR="$CURSOR_SPLIT_HOOKS_DIR" "$DISPATCHER" reset cursor --yes > "$TEST_DIR/reset-cursor-split-hooks.txt" 2>&1
if [[ -d "$CURSOR_SPLIT_STATE_DIR/aport" ]]; then
    echo "FAIL: expected split Cursor state to be removed after hooks cleanup" >&2
    cat "$TEST_DIR/reset-cursor-split-hooks.txt" >&2
    exit 1
fi
CURSOR_SPLIT_APORT_COUNT=$(jq -r '[.hooks.preToolUse[]? | select(.__aport_hook == true)] | length' "$CURSOR_SPLIT_HOOKS_DIR/hooks.json")
if [[ "$CURSOR_SPLIT_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: reset cursor should remove APort hook entries from CURSOR_HOOKS_DIR" >&2
    cat "$CURSOR_SPLIT_HOOKS_DIR/hooks.json" >&2
    exit 1
fi
CURSOR_SPLIT_CUSTOM_COUNT=$(jq -r '[.hooks.preToolUse[]? | select(.command == "/usr/local/bin/custom-cursor-hook.sh")] | length' "$CURSOR_SPLIT_HOOKS_DIR/hooks.json")
if [[ "$CURSOR_SPLIT_CUSTOM_COUNT" -ne 1 ]]; then
    echo "FAIL: reset cursor should preserve custom hooks in CURSOR_HOOKS_DIR" >&2
    cat "$CURSOR_SPLIT_HOOKS_DIR/hooks.json" >&2
    exit 1
fi

echo "  ✅ reset cursor honors CURSOR_HOOKS_DIR when state is split"

OPENCLAW_STATE_RESET_DIR="$TEST_DIR/openclaw-state-reset"
OPENCLAW_HOME_RESET_DIR="$TEST_DIR/openclaw-home-reset"
mkdir -p "$OPENCLAW_STATE_RESET_DIR/aport" "$OPENCLAW_HOME_RESET_DIR/aport"
cat > "$OPENCLAW_STATE_RESET_DIR/openclaw.json" << 'EOF'
{
  "plugins": {
    "entries": {
      "openclaw-aport": {
        "enabled": true,
        "config": {"mode": "api", "agentId": "ap_state_existing"}
      },
      "custom-plugin": {
        "enabled": true
      }
    }
  }
}
EOF
touch "$OPENCLAW_STATE_RESET_DIR/aport/passport.json" "$OPENCLAW_HOME_RESET_DIR/aport/passport.json"

echo "  Test: reset openclaw honors OPENCLAW_STATE_DIR..."
OPENCLAW_STATE_DIR="$OPENCLAW_STATE_RESET_DIR" OPENCLAW_HOME="$OPENCLAW_HOME_RESET_DIR" "$DISPATCHER" reset openclaw --yes > "$TEST_DIR/reset-openclaw-state-dir.txt" 2>&1
if [[ -d "$OPENCLAW_STATE_RESET_DIR/aport" ]]; then
    echo "FAIL: expected OpenClaw state dir APort runtime to be removed" >&2
    cat "$TEST_DIR/reset-openclaw-state-dir.txt" >&2
    exit 1
fi
if [[ ! -f "$OPENCLAW_HOME_RESET_DIR/aport/passport.json" ]]; then
    echo "FAIL: reset openclaw removed OPENCLAW_HOME instead of OPENCLAW_STATE_DIR" >&2
    cat "$TEST_DIR/reset-openclaw-state-dir.txt" >&2
    exit 1
fi
jq -e '(.plugins.entries | has("openclaw-aport") | not) and (.plugins.entries["custom-plugin"].enabled == true)' "$OPENCLAW_STATE_RESET_DIR/openclaw.json" > /dev/null || {
    echo "FAIL: reset openclaw should clean only APort plugin entries from OPENCLAW_STATE_DIR" >&2
    cat "$OPENCLAW_STATE_RESET_DIR/openclaw.json" >&2
    exit 1
}

echo "  ✅ reset openclaw honors OPENCLAW_STATE_DIR"

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

CODEX_GLOBAL_UNRELATED="$TEST_DIR/codex-global-unrelated"
CODEX_GLOBAL_HOME="$TEST_DIR/codex-global-home"
CODEX_GLOBAL_STATE="$CODEX_GLOBAL_HOME/.aport/codex"
CODEX_GLOBAL_OTHER_PROJECT="$TEST_DIR/codex-global-other-project/.codex"
mkdir -p "$CODEX_GLOBAL_UNRELATED" "$CODEX_GLOBAL_HOME/.codex" "$CODEX_GLOBAL_STATE/aport" "$CODEX_GLOBAL_OTHER_PROJECT"
cat > "$CODEX_GLOBAL_HOME/.codex/hooks.json" << 'EOF'
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
cat > "$CODEX_GLOBAL_OTHER_PROJECT/hooks.json" << 'EOF'
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
touch "$CODEX_GLOBAL_STATE/aport/passport.json"

echo "  Test: reset codex from unrelated directory preserves global shared state..."
(
    cd "$CODEX_GLOBAL_UNRELATED"
    HOME="$CODEX_GLOBAL_HOME" "$DISPATCHER" reset codex --yes > "$TEST_DIR/reset-codex-global-unrelated.txt" 2>&1
)
if [[ ! -f "$CODEX_GLOBAL_STATE/aport/passport.json" ]]; then
    echo "FAIL: expected auto-global Codex reset to preserve shared state" >&2
    cat "$TEST_DIR/reset-codex-global-unrelated.txt" >&2
    exit 1
fi
CODEX_GLOBAL_APORT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_GLOBAL_HOME/.codex/hooks.json")
if [[ "$CODEX_GLOBAL_APORT_COUNT" -ne 0 ]]; then
    echo "FAIL: expected global Codex hook entries to be removed" >&2
    cat "$CODEX_GLOBAL_HOME/.codex/hooks.json" >&2
    exit 1
fi

echo "  ✅ reset codex auto-global cleanup preserves shared state"

CODEX_HOME_RESET_UNRELATED="$TEST_DIR/codex-home-reset-unrelated"
CODEX_HOME_RESET_HOME="$TEST_DIR/codex-home-reset-home"
CODEX_HOME_RESET_CODEX_HOME="$TEST_DIR/codex-home-reset-codex-home"
CODEX_HOME_RESET_STATE="$CODEX_HOME_RESET_HOME/.aport/codex"
mkdir -p "$CODEX_HOME_RESET_UNRELATED" "$CODEX_HOME_RESET_CODEX_HOME" "$CODEX_HOME_RESET_STATE/aport"
cat > "$CODEX_HOME_RESET_CODEX_HOME/hooks.json" << 'EOF'
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
touch "$CODEX_HOME_RESET_STATE/aport/passport.json"

echo "  Test: reset codex --global honors CODEX_HOME..."
(
    cd "$CODEX_HOME_RESET_UNRELATED"
    HOME="$CODEX_HOME_RESET_HOME" CODEX_HOME="$CODEX_HOME_RESET_CODEX_HOME" "$DISPATCHER" reset codex --global --yes > "$TEST_DIR/reset-codex-codex-home.txt" 2>&1
)
CODEX_HOME_RESET_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_HOME_RESET_CODEX_HOME/hooks.json")
if [[ "$CODEX_HOME_RESET_COUNT" -ne 0 ]]; then
    echo "FAIL: reset codex --global should remove APort hooks from CODEX_HOME" >&2
    cat "$CODEX_HOME_RESET_CODEX_HOME/hooks.json" >&2
    exit 1
fi
[[ ! -e "$CODEX_HOME_RESET_HOME/.codex/hooks.json" ]] || {
    echo "FAIL: reset codex --global should not create or mutate HOME/.codex when CODEX_HOME is active" >&2
    cat "$CODEX_HOME_RESET_HOME/.codex/hooks.json" >&2
    exit 1
}

echo "  ✅ reset codex --global honors CODEX_HOME"

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

CODEX_SHARED_PROJECT="$TEST_DIR/codex-shared-project"
CODEX_SHARED_HOME="$TEST_DIR/codex-shared-home"
CODEX_SHARED_STATE="$TEST_DIR/codex-shared-state"
CODEX_SHARED_HOOKS_A="$TEST_DIR/codex-shared-hooks-a"
CODEX_SHARED_HOOKS_B="$TEST_DIR/codex-shared-hooks-b"
mkdir -p "$CODEX_SHARED_PROJECT" "$CODEX_SHARED_HOME" "$CODEX_SHARED_STATE/aport/runtime/bin" "$CODEX_SHARED_HOOKS_A" "$CODEX_SHARED_HOOKS_B"
touch "$CODEX_SHARED_STATE/aport/marker"
for hooks_dir in "$CODEX_SHARED_HOOKS_A" "$CODEX_SHARED_HOOKS_B"; do
    cat > "$hooks_dir/hooks.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"$CODEX_SHARED_STATE/aport/runtime/bin/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
done

echo "  Test: reset codex preserves explicit shared state still referenced elsewhere..."
(
    cd "$CODEX_SHARED_PROJECT"
    HOME="$CODEX_SHARED_HOME" APORT_CONFIG_DIR="$CODEX_SHARED_STATE" APORT_CODEX_HOOKS_DIR="$CODEX_SHARED_HOOKS_A" "$DISPATCHER" reset codex --yes > "$TEST_DIR/reset-codex-shared-state.txt" 2>&1
)
CODEX_SHARED_A_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_SHARED_HOOKS_A/hooks.json")
CODEX_SHARED_B_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_SHARED_HOOKS_B/hooks.json")
if [[ "$CODEX_SHARED_A_COUNT" -ne 0 || "$CODEX_SHARED_B_COUNT" -ne 1 ]]; then
    echo "FAIL: expected selected Codex hook cleaned and other shared hook preserved" >&2
    cat "$CODEX_SHARED_HOOKS_A/hooks.json" >&2
    cat "$CODEX_SHARED_HOOKS_B/hooks.json" >&2
    exit 1
fi
if [[ ! -f "$CODEX_SHARED_STATE/aport/marker" ]]; then
    echo "FAIL: reset codex removed explicitly shared state still referenced by another install" >&2
    cat "$TEST_DIR/reset-codex-shared-state.txt" >&2
    exit 1
fi

echo "  ✅ reset codex preserves explicit shared state still referenced elsewhere"

CODEX_CUSTOM_AND_PROJECT="$TEST_DIR/codex-custom-and-project"
CODEX_CUSTOM_AND_PROJECT_HOME="$TEST_DIR/codex-custom-and-project-home"
CODEX_CUSTOM_AND_PROJECT_STATE="$TEST_DIR/codex-custom-and-project-state"
CODEX_CUSTOM_AND_PROJECT_HOOKS="$TEST_DIR/codex-custom-and-project-hooks"
mkdir -p "$CODEX_CUSTOM_AND_PROJECT/.codex/aport" "$CODEX_CUSTOM_AND_PROJECT_HOME" "$CODEX_CUSTOM_AND_PROJECT_STATE/aport" "$CODEX_CUSTOM_AND_PROJECT_HOOKS"
touch "$CODEX_CUSTOM_AND_PROJECT/.codex/aport/passport.json" "$CODEX_CUSTOM_AND_PROJECT_STATE/aport/passport.json"
cat > "$CODEX_CUSTOM_AND_PROJECT/.codex/hooks.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"/legacy/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cp "$CODEX_CUSTOM_AND_PROJECT/.codex/hooks.json" "$CODEX_CUSTOM_AND_PROJECT_HOOKS/hooks.json"

echo "  Test: reset codex custom hook preserves project state and hooks..."
(
    cd "$CODEX_CUSTOM_AND_PROJECT"
    HOME="$CODEX_CUSTOM_AND_PROJECT_HOME" APORT_CONFIG_DIR="$CODEX_CUSTOM_AND_PROJECT_STATE" APORT_CODEX_HOOKS_DIR="$CODEX_CUSTOM_AND_PROJECT_HOOKS" "$DISPATCHER" reset codex --yes > "$TEST_DIR/reset-codex-custom-preserve-project.txt" 2>&1
)
CODEX_CUSTOM_AND_PROJECT_CUSTOM_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_CUSTOM_AND_PROJECT_HOOKS/hooks.json")
CODEX_CUSTOM_AND_PROJECT_PROJECT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_CUSTOM_AND_PROJECT/.codex/hooks.json")
if [[ "$CODEX_CUSTOM_AND_PROJECT_CUSTOM_COUNT" -ne 0 || "$CODEX_CUSTOM_AND_PROJECT_PROJECT_COUNT" -ne 1 ]]; then
    echo "FAIL: expected selected custom Codex hook cleaned and project hook preserved" >&2
    cat "$CODEX_CUSTOM_AND_PROJECT_HOOKS/hooks.json" >&2
    cat "$CODEX_CUSTOM_AND_PROJECT/.codex/hooks.json" >&2
    exit 1
fi
if [[ ! -f "$CODEX_CUSTOM_AND_PROJECT/.codex/aport/passport.json" ]]; then
    echo "FAIL: reset codex custom hook deleted unrelated project-local state" >&2
    cat "$TEST_DIR/reset-codex-custom-preserve-project.txt" >&2
    exit 1
fi

echo "  ✅ reset codex custom hook preserves project state and hooks"

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

CODEX_COLOCATED_PROJECT="$TEST_DIR/codex-colocated-project"
CODEX_COLOCATED_HOME="$TEST_DIR/codex-colocated-home"
CODEX_COLOCATED_GLOBAL="$CODEX_COLOCATED_HOME/.codex"
CODEX_COLOCATED_PROJECT_CONFIG="$CODEX_COLOCATED_PROJECT/.codex"
mkdir -p "$CODEX_COLOCATED_GLOBAL/aport/runtime/bin" "$CODEX_COLOCATED_PROJECT_CONFIG"
touch "$CODEX_COLOCATED_GLOBAL/aport/passport.json"
cat > "$CODEX_COLOCATED_GLOBAL/hooks.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"$CODEX_COLOCATED_GLOBAL/aport/runtime/bin/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cat > "$CODEX_COLOCATED_PROJECT_CONFIG/hooks.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"$CODEX_COLOCATED_GLOBAL/aport/runtime/bin/aport-codex-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF

echo "  Test: reset codex --global preserves co-located state used by project hooks..."
(
    cd "$CODEX_COLOCATED_PROJECT"
    HOME="$CODEX_COLOCATED_HOME" APORT_CONFIG_DIR="$CODEX_COLOCATED_GLOBAL" "$DISPATCHER" reset codex --global --yes > "$TEST_DIR/reset-codex-colocated-global.txt" 2>&1
)
CODEX_COLOCATED_GLOBAL_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_COLOCATED_GLOBAL/hooks.json")
CODEX_COLOCATED_PROJECT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_COLOCATED_PROJECT_CONFIG/hooks.json")
if [[ "$CODEX_COLOCATED_GLOBAL_COUNT" -ne 0 || "$CODEX_COLOCATED_PROJECT_COUNT" -ne 1 ]]; then
    echo "FAIL: expected global Codex hook cleaned and project hook preserved" >&2
    cat "$CODEX_COLOCATED_GLOBAL/hooks.json" >&2
    cat "$CODEX_COLOCATED_PROJECT_CONFIG/hooks.json" >&2
    exit 1
fi
if [[ ! -f "$CODEX_COLOCATED_GLOBAL/aport/passport.json" ]]; then
    echo "FAIL: reset codex --global deleted state still referenced by project hook" >&2
    cat "$TEST_DIR/reset-codex-colocated-global.txt" >&2
    exit 1
fi

echo "  ✅ reset codex --global preserves co-located state used by project hooks"

CODEX_CROSS_HOME="$TEST_DIR/codex-cross-home"
CODEX_CROSS_GLOBAL="$CODEX_CROSS_HOME/.codex"
CODEX_CROSS_PROJECT_A="$TEST_DIR/codex-cross-project-a"
CODEX_CROSS_PROJECT_B="$TEST_DIR/codex-cross-project-b"
mkdir -p "$CODEX_CROSS_GLOBAL/aport/runtime/bin" "$CODEX_CROSS_PROJECT_A/.codex" "$CODEX_CROSS_PROJECT_B"
touch "$CODEX_CROSS_GLOBAL/aport/passport.json" "$CODEX_CROSS_GLOBAL/aport/runtime/bin/marker"
cat > "$CODEX_CROSS_GLOBAL/hooks.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"APORT_CODEX_CONFIG_DIR='$CODEX_CROSS_GLOBAL' '$CODEX_CROSS_GLOBAL/aport/runtime/bin/aport-codex-hook.sh'","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cp "$CODEX_CROSS_GLOBAL/hooks.json" "$CODEX_CROSS_PROJECT_A/.codex/hooks.json"

echo "  Test: reset codex --global preserves state referenced by another project..."
(
    cd "$CODEX_CROSS_PROJECT_B"
    HOME="$CODEX_CROSS_HOME" APORT_CODEX_CONFIG_DIR="$CODEX_CROSS_GLOBAL" "$DISPATCHER" reset codex --global --yes > "$TEST_DIR/reset-codex-cross-project.txt" 2>&1
)
CODEX_CROSS_GLOBAL_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_CROSS_GLOBAL/hooks.json")
CODEX_CROSS_PROJECT_A_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_CROSS_PROJECT_A/.codex/hooks.json")
if [[ "$CODEX_CROSS_GLOBAL_COUNT" -ne 0 || "$CODEX_CROSS_PROJECT_A_COUNT" -ne 1 ]]; then
    echo "FAIL: expected global Codex hook cleaned and unrelated project hook preserved" >&2
    cat "$CODEX_CROSS_GLOBAL/hooks.json" >&2
    cat "$CODEX_CROSS_PROJECT_A/.codex/hooks.json" >&2
    exit 1
fi
if [[ ! -f "$CODEX_CROSS_GLOBAL/aport/runtime/bin/marker" || ! -f "$CODEX_CROSS_GLOBAL/aport/passport.json" ]]; then
    echo "FAIL: reset codex --global deleted state still referenced by another project" >&2
    cat "$TEST_DIR/reset-codex-cross-project.txt" >&2
    exit 1
fi

echo "  ✅ reset codex --global preserves state referenced by another project"

CODEX_PROJECT_SHARED_PROJECT="$TEST_DIR/codex-project-shared-project"
CODEX_PROJECT_SHARED_HOME="$TEST_DIR/codex-project-shared-home"
CODEX_PROJECT_SHARED_PROJECT_CONFIG="$CODEX_PROJECT_SHARED_PROJECT/.codex"
CODEX_PROJECT_SHARED_GLOBAL_CONFIG="$CODEX_PROJECT_SHARED_HOME/.codex"
mkdir -p "$CODEX_PROJECT_SHARED_PROJECT_CONFIG/aport/runtime/bin" "$CODEX_PROJECT_SHARED_GLOBAL_CONFIG"
touch "$CODEX_PROJECT_SHARED_PROJECT_CONFIG/aport/passport.json"
cat > "$CODEX_PROJECT_SHARED_PROJECT_CONFIG/hooks.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"APORT_CODEX_CONFIG_DIR='$CODEX_PROJECT_SHARED_PROJECT_CONFIG' '$CODEX_PROJECT_SHARED_PROJECT_CONFIG/aport/runtime/bin/aport-codex-hook.sh'","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cp "$CODEX_PROJECT_SHARED_PROJECT_CONFIG/hooks.json" "$CODEX_PROJECT_SHARED_GLOBAL_CONFIG/hooks.json"

echo "  Test: reset codex --project preserves project state still used by global hooks..."
(
    cd "$CODEX_PROJECT_SHARED_PROJECT"
    HOME="$CODEX_PROJECT_SHARED_HOME" APORT_CODEX_CONFIG_DIR="$CODEX_PROJECT_SHARED_PROJECT_CONFIG" "$DISPATCHER" reset codex --project --yes > "$TEST_DIR/reset-codex-project-shared-global.txt" 2>&1
)
CODEX_PROJECT_SHARED_PROJECT_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_PROJECT_SHARED_PROJECT_CONFIG/hooks.json")
CODEX_PROJECT_SHARED_GLOBAL_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_PROJECT_SHARED_GLOBAL_CONFIG/hooks.json")
if [[ "$CODEX_PROJECT_SHARED_PROJECT_COUNT" -ne 0 || "$CODEX_PROJECT_SHARED_GLOBAL_COUNT" -ne 1 ]]; then
    echo "FAIL: expected project Codex hook cleaned and global hook preserved" >&2
    cat "$CODEX_PROJECT_SHARED_PROJECT_CONFIG/hooks.json" >&2
    cat "$CODEX_PROJECT_SHARED_GLOBAL_CONFIG/hooks.json" >&2
    exit 1
fi
if [[ ! -f "$CODEX_PROJECT_SHARED_PROJECT_CONFIG/aport/passport.json" ]]; then
    echo "FAIL: reset codex --project deleted state still referenced by global hook" >&2
    cat "$TEST_DIR/reset-codex-project-shared-global.txt" >&2
    exit 1
fi

echo "  ✅ reset codex --project preserves project state used by global hooks"

CODEX_GEMINI_SHARED_PROJECT="$TEST_DIR/codex-gemini-shared-project"
CODEX_GEMINI_SHARED_HOME="$TEST_DIR/codex-gemini-shared-home"
CODEX_GEMINI_SHARED_CODEX="$CODEX_GEMINI_SHARED_PROJECT/.codex"
CODEX_GEMINI_SHARED_GEMINI="$CODEX_GEMINI_SHARED_PROJECT/.gemini"
mkdir -p "$CODEX_GEMINI_SHARED_CODEX/aport/runtime/bin" "$CODEX_GEMINI_SHARED_GEMINI" "$CODEX_GEMINI_SHARED_HOME"
touch "$CODEX_GEMINI_SHARED_CODEX/aport/passport.json"
cat > "$CODEX_GEMINI_SHARED_CODEX/hooks.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"APORT_CODEX_CONFIG_DIR='$CODEX_GEMINI_SHARED_CODEX' '$CODEX_GEMINI_SHARED_CODEX/aport/runtime/bin/aport-codex-hook.sh'","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cat > "$CODEX_GEMINI_SHARED_GEMINI/settings.json" << EOF
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"APORT_GEMINI_CLI_CONFIG_DIR='$CODEX_GEMINI_SHARED_CODEX' '$CODEX_GEMINI_SHARED_CODEX/aport/runtime/bin/aport-gemini-cli-hook.sh'","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF

echo "  Test: reset codex preserves shared state still used by Gemini..."
(
    cd "$CODEX_GEMINI_SHARED_PROJECT"
    HOME="$CODEX_GEMINI_SHARED_HOME" APORT_CODEX_CONFIG_DIR="$CODEX_GEMINI_SHARED_CODEX" "$DISPATCHER" reset codex --project --yes > "$TEST_DIR/reset-codex-preserve-gemini-shared.txt" 2>&1
)
CODEX_GEMINI_CODEX_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_GEMINI_SHARED_CODEX/hooks.json")
CODEX_GEMINI_GEMINI_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_GEMINI_SHARED_GEMINI/settings.json")
if [[ "$CODEX_GEMINI_CODEX_COUNT" -ne 0 || "$CODEX_GEMINI_GEMINI_COUNT" -ne 1 ]]; then
    echo "FAIL: expected Codex hook cleaned and Gemini hook preserved" >&2
    cat "$CODEX_GEMINI_SHARED_CODEX/hooks.json" >&2
    cat "$CODEX_GEMINI_SHARED_GEMINI/settings.json" >&2
    exit 1
fi
if [[ ! -f "$CODEX_GEMINI_SHARED_CODEX/aport/passport.json" ]]; then
    echo "FAIL: reset codex deleted state still referenced by Gemini" >&2
    cat "$TEST_DIR/reset-codex-preserve-gemini-shared.txt" >&2
    exit 1
fi

echo "  ✅ reset codex preserves shared state still used by Gemini"

CODEX_GEMINI_PROJECT_LOCAL="$TEST_DIR/codex-gemini-project-local"
CODEX_GEMINI_PROJECT_LOCAL_HOME="$TEST_DIR/codex-gemini-project-local-home"
mkdir -p "$CODEX_GEMINI_PROJECT_LOCAL/.codex/aport/runtime/bin" "$CODEX_GEMINI_PROJECT_LOCAL/.gemini" "$CODEX_GEMINI_PROJECT_LOCAL_HOME"
touch "$CODEX_GEMINI_PROJECT_LOCAL/.codex/aport/passport.json"
cat > "$CODEX_GEMINI_PROJECT_LOCAL/.codex/hooks.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"APORT_CODEX_CONFIG_DIR='$CODEX_GEMINI_PROJECT_LOCAL/.codex' '$CODEX_GEMINI_PROJECT_LOCAL/.codex/aport/runtime/bin/aport-codex-hook.sh'","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cat > "$CODEX_GEMINI_PROJECT_LOCAL/.gemini/settings.json" << EOF
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"APORT_GEMINI_CLI_CONFIG_DIR='$CODEX_GEMINI_PROJECT_LOCAL/.codex' '$CODEX_GEMINI_PROJECT_LOCAL/.codex/aport/runtime/bin/aport-gemini-cli-hook.sh'","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF

echo "  Test: reset codex preserves project-local state still used by Gemini..."
(
    cd "$CODEX_GEMINI_PROJECT_LOCAL"
    HOME="$CODEX_GEMINI_PROJECT_LOCAL_HOME" "$DISPATCHER" reset codex --project --yes > "$TEST_DIR/reset-codex-project-local-preserve-gemini.txt" 2>&1
)
CODEX_GEMINI_PROJECT_LOCAL_CODEX_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_GEMINI_PROJECT_LOCAL/.codex/hooks.json")
CODEX_GEMINI_PROJECT_LOCAL_GEMINI_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_GEMINI_PROJECT_LOCAL/.gemini/settings.json")
if [[ "$CODEX_GEMINI_PROJECT_LOCAL_CODEX_COUNT" -ne 0 || "$CODEX_GEMINI_PROJECT_LOCAL_GEMINI_COUNT" -ne 1 ]]; then
    echo "FAIL: expected project Codex hook cleaned and Gemini hook preserved" >&2
    cat "$CODEX_GEMINI_PROJECT_LOCAL/.codex/hooks.json" >&2
    cat "$CODEX_GEMINI_PROJECT_LOCAL/.gemini/settings.json" >&2
    exit 1
fi
if [[ ! -f "$CODEX_GEMINI_PROJECT_LOCAL/.codex/aport/passport.json" ]]; then
    echo "FAIL: reset codex deleted project-local state still referenced by Gemini" >&2
    cat "$TEST_DIR/reset-codex-project-local-preserve-gemini.txt" >&2
    exit 1
fi

echo "  ✅ reset codex preserves project-local state still used by Gemini"

CODEX_GOOSE_PROJECT_LOCAL="$TEST_DIR/codex-goose-project-local"
CODEX_GOOSE_PROJECT_LOCAL_HOME="$TEST_DIR/codex-goose-project-local-home"
CODEX_GOOSE_PLUGIN="$CODEX_GOOSE_PROJECT_LOCAL_HOME/.agents/plugins/aport-guardrail"
mkdir -p "$CODEX_GOOSE_PROJECT_LOCAL/.codex/aport/runtime/bin" "$CODEX_GOOSE_PROJECT_LOCAL_HOME" "$CODEX_GOOSE_PLUGIN/scripts"
touch "$CODEX_GOOSE_PROJECT_LOCAL/.codex/aport/passport.json"
touch "$CODEX_GOOSE_PROJECT_LOCAL/.codex/aport/runtime/bin/aport-goose-hook.sh"
cat > "$CODEX_GOOSE_PROJECT_LOCAL/.codex/hooks.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"APORT_CODEX_CONFIG_DIR='$CODEX_GOOSE_PROJECT_LOCAL/.codex' '$CODEX_GOOSE_PROJECT_LOCAL/.codex/aport/runtime/bin/aport-codex-hook.sh'","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cat > "$CODEX_GOOSE_PLUGIN/plugin.json" << 'EOF'
{"name":"aport-guardrail","version":"1.0.0"}
EOF
cat > "$CODEX_GOOSE_PLUGIN/scripts/aport-goose-hook.sh" << EOF
#!/bin/bash
export APORT_GOOSE_CONFIG_DIR="$CODEX_GOOSE_PROJECT_LOCAL/.codex"
export APORT_CONFIG_DIR="\${APORT_CONFIG_DIR:-\$APORT_GOOSE_CONFIG_DIR}"
exec "$CODEX_GOOSE_PROJECT_LOCAL/.codex/aport/runtime/bin/aport-goose-hook.sh" "\$@"
EOF
chmod +x "$CODEX_GOOSE_PLUGIN/scripts/aport-goose-hook.sh"

echo "  Test: reset codex preserves project-local state still used by Goose..."
(
    cd "$CODEX_GOOSE_PROJECT_LOCAL"
    HOME="$CODEX_GOOSE_PROJECT_LOCAL_HOME" "$DISPATCHER" reset codex --project --yes > "$TEST_DIR/reset-codex-project-local-preserve-goose.txt" 2>&1
)
CODEX_GOOSE_PROJECT_LOCAL_CODEX_COUNT=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true)] | length' "$CODEX_GOOSE_PROJECT_LOCAL/.codex/hooks.json")
if [[ "$CODEX_GOOSE_PROJECT_LOCAL_CODEX_COUNT" -ne 0 ]]; then
    echo "FAIL: expected project Codex hook cleaned" >&2
    cat "$CODEX_GOOSE_PROJECT_LOCAL/.codex/hooks.json" >&2
    exit 1
fi
if [[ ! -f "$CODEX_GOOSE_PROJECT_LOCAL/.codex/aport/passport.json" ]]; then
    echo "FAIL: reset codex deleted project-local state still referenced by Goose" >&2
    cat "$TEST_DIR/reset-codex-project-local-preserve-goose.txt" >&2
    exit 1
fi
if [[ ! -x "$CODEX_GOOSE_PLUGIN/scripts/aport-goose-hook.sh" ]]; then
    echo "FAIL: reset codex removed Goose wrapper" >&2
    exit 1
fi

echo "  ✅ reset codex preserves project-local state still used by Goose"

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

GEMINI_SHARED_PROJECT="$TEST_DIR/gemini-shared-project"
GEMINI_SHARED_HOME="$TEST_DIR/gemini-shared-home"
GEMINI_SHARED_STATE="$TEST_DIR/gemini-shared-state"
GEMINI_SHARED_HOOKS_A="$TEST_DIR/gemini-shared-hooks-a"
GEMINI_SHARED_HOOKS_B="$TEST_DIR/gemini-shared-hooks-b"
mkdir -p "$GEMINI_SHARED_PROJECT" "$GEMINI_SHARED_HOME" "$GEMINI_SHARED_STATE/aport/runtime/bin" "$GEMINI_SHARED_HOOKS_A" "$GEMINI_SHARED_HOOKS_B"
touch "$GEMINI_SHARED_STATE/aport/marker"
for hooks_dir in "$GEMINI_SHARED_HOOKS_A" "$GEMINI_SHARED_HOOKS_B"; do
    cat > "$hooks_dir/settings.json" << EOF
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"$GEMINI_SHARED_STATE/aport/runtime/bin/aport-gemini-cli-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
done

echo "  Test: reset gemini preserves explicit shared state still referenced elsewhere..."
(
    cd "$GEMINI_SHARED_PROJECT"
    HOME="$GEMINI_SHARED_HOME" APORT_CONFIG_DIR="$GEMINI_SHARED_STATE" APORT_GEMINI_CLI_HOOKS_DIR="$GEMINI_SHARED_HOOKS_A" "$DISPATCHER" reset gemini-cli --yes > "$TEST_DIR/reset-gemini-shared-state.txt" 2>&1
)
GEMINI_SHARED_A_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_SHARED_HOOKS_A/settings.json")
GEMINI_SHARED_B_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_SHARED_HOOKS_B/settings.json")
if [[ "$GEMINI_SHARED_A_COUNT" -ne 0 || "$GEMINI_SHARED_B_COUNT" -ne 1 ]]; then
    echo "FAIL: expected selected Gemini hook cleaned and other shared hook preserved" >&2
    cat "$GEMINI_SHARED_HOOKS_A/settings.json" >&2
    cat "$GEMINI_SHARED_HOOKS_B/settings.json" >&2
    exit 1
fi
if [[ ! -f "$GEMINI_SHARED_STATE/aport/marker" ]]; then
    echo "FAIL: reset gemini removed explicitly shared state still referenced by another install" >&2
    cat "$TEST_DIR/reset-gemini-shared-state.txt" >&2
    exit 1
fi

echo "  ✅ reset gemini preserves explicit shared state still referenced elsewhere"

GEMINI_CUSTOM_AND_PROJECT="$TEST_DIR/gemini-custom-and-project"
GEMINI_CUSTOM_AND_PROJECT_HOME="$TEST_DIR/gemini-custom-and-project-home"
GEMINI_CUSTOM_AND_PROJECT_STATE="$TEST_DIR/gemini-custom-and-project-state"
GEMINI_CUSTOM_AND_PROJECT_HOOKS="$TEST_DIR/gemini-custom-and-project-hooks"
mkdir -p "$GEMINI_CUSTOM_AND_PROJECT/.gemini/aport" "$GEMINI_CUSTOM_AND_PROJECT_HOME" "$GEMINI_CUSTOM_AND_PROJECT_STATE/aport" "$GEMINI_CUSTOM_AND_PROJECT_HOOKS"
touch "$GEMINI_CUSTOM_AND_PROJECT/.gemini/aport/passport.json" "$GEMINI_CUSTOM_AND_PROJECT_STATE/aport/passport.json"
cat > "$GEMINI_CUSTOM_AND_PROJECT/.gemini/settings.json" << 'EOF'
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"/legacy/aport-gemini-cli-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cp "$GEMINI_CUSTOM_AND_PROJECT/.gemini/settings.json" "$GEMINI_CUSTOM_AND_PROJECT_HOOKS/settings.json"

echo "  Test: reset gemini custom hook preserves project state and hooks..."
(
    cd "$GEMINI_CUSTOM_AND_PROJECT"
    HOME="$GEMINI_CUSTOM_AND_PROJECT_HOME" APORT_CONFIG_DIR="$GEMINI_CUSTOM_AND_PROJECT_STATE" APORT_GEMINI_CLI_HOOKS_DIR="$GEMINI_CUSTOM_AND_PROJECT_HOOKS" "$DISPATCHER" reset gemini-cli --yes > "$TEST_DIR/reset-gemini-custom-preserve-project.txt" 2>&1
)
GEMINI_CUSTOM_AND_PROJECT_CUSTOM_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_CUSTOM_AND_PROJECT_HOOKS/settings.json")
GEMINI_CUSTOM_AND_PROJECT_PROJECT_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_CUSTOM_AND_PROJECT/.gemini/settings.json")
if [[ "$GEMINI_CUSTOM_AND_PROJECT_CUSTOM_COUNT" -ne 0 || "$GEMINI_CUSTOM_AND_PROJECT_PROJECT_COUNT" -ne 1 ]]; then
    echo "FAIL: expected selected custom Gemini hook cleaned and project hook preserved" >&2
    cat "$GEMINI_CUSTOM_AND_PROJECT_HOOKS/settings.json" >&2
    cat "$GEMINI_CUSTOM_AND_PROJECT/.gemini/settings.json" >&2
    exit 1
fi
if [[ ! -f "$GEMINI_CUSTOM_AND_PROJECT/.gemini/aport/passport.json" ]]; then
    echo "FAIL: reset gemini custom hook deleted unrelated project-local state" >&2
    cat "$TEST_DIR/reset-gemini-custom-preserve-project.txt" >&2
    exit 1
fi

echo "  ✅ reset gemini custom hook preserves project state and hooks"

GEMINI_COLOCATED_PROJECT="$TEST_DIR/gemini-colocated-project"
GEMINI_COLOCATED_HOME="$TEST_DIR/gemini-colocated-home"
GEMINI_COLOCATED_GLOBAL="$GEMINI_COLOCATED_HOME/.gemini"
GEMINI_COLOCATED_PROJECT_CONFIG="$GEMINI_COLOCATED_PROJECT/.gemini"
mkdir -p "$GEMINI_COLOCATED_GLOBAL/aport/runtime/bin" "$GEMINI_COLOCATED_PROJECT_CONFIG"
touch "$GEMINI_COLOCATED_GLOBAL/aport/passport.json"
cat > "$GEMINI_COLOCATED_GLOBAL/settings.json" << EOF
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"$GEMINI_COLOCATED_GLOBAL/aport/runtime/bin/aport-gemini-cli-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cat > "$GEMINI_COLOCATED_PROJECT_CONFIG/settings.json" << EOF
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "*",
        "hooks": [
          {"type":"command","command":"$GEMINI_COLOCATED_GLOBAL/aport/runtime/bin/aport-gemini-cli-hook.sh","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF

echo "  Test: reset gemini --global preserves co-located state used by project hooks..."
(
    cd "$GEMINI_COLOCATED_PROJECT"
    HOME="$GEMINI_COLOCATED_HOME" APORT_CONFIG_DIR="$GEMINI_COLOCATED_GLOBAL" "$DISPATCHER" reset gemini-cli --global --yes > "$TEST_DIR/reset-gemini-colocated-global.txt" 2>&1
)
GEMINI_COLOCATED_GLOBAL_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_COLOCATED_GLOBAL/settings.json")
GEMINI_COLOCATED_PROJECT_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_COLOCATED_PROJECT_CONFIG/settings.json")
if [[ "$GEMINI_COLOCATED_GLOBAL_COUNT" -ne 0 || "$GEMINI_COLOCATED_PROJECT_COUNT" -ne 1 ]]; then
    echo "FAIL: expected global Gemini hook cleaned and project hook preserved" >&2
    cat "$GEMINI_COLOCATED_GLOBAL/settings.json" >&2
    cat "$GEMINI_COLOCATED_PROJECT_CONFIG/settings.json" >&2
    exit 1
fi
if [[ ! -f "$GEMINI_COLOCATED_GLOBAL/aport/passport.json" ]]; then
    echo "FAIL: reset gemini --global deleted state still referenced by project hook" >&2
    cat "$TEST_DIR/reset-gemini-colocated-global.txt" >&2
    exit 1
fi

echo "  ✅ reset gemini --global preserves co-located state used by project hooks"

GEMINI_CROSS_HOME="$TEST_DIR/gemini-cross-home"
GEMINI_CROSS_GLOBAL="$GEMINI_CROSS_HOME/.gemini"
GEMINI_CROSS_PROJECT_A="$TEST_DIR/gemini-cross-project-a"
GEMINI_CROSS_PROJECT_B="$TEST_DIR/gemini-cross-project-b"
mkdir -p "$GEMINI_CROSS_GLOBAL/aport/runtime/bin" "$GEMINI_CROSS_PROJECT_A/.gemini" "$GEMINI_CROSS_PROJECT_B"
touch "$GEMINI_CROSS_GLOBAL/aport/passport.json" "$GEMINI_CROSS_GLOBAL/aport/runtime/bin/marker"
cat > "$GEMINI_CROSS_GLOBAL/settings.json" << EOF
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": ".*",
        "hooks": [
          {"type":"command","command":"APORT_GEMINI_CLI_CONFIG_DIR='$GEMINI_CROSS_GLOBAL' '$GEMINI_CROSS_GLOBAL/aport/runtime/bin/aport-gemini-cli-hook.sh'","__aport_hook":true}
        ]
      }
    ]
  }
}
EOF
cp "$GEMINI_CROSS_GLOBAL/settings.json" "$GEMINI_CROSS_PROJECT_A/.gemini/settings.json"

echo "  Test: reset gemini --global preserves state referenced by another project..."
(
    cd "$GEMINI_CROSS_PROJECT_B"
    HOME="$GEMINI_CROSS_HOME" APORT_GEMINI_CLI_CONFIG_DIR="$GEMINI_CROSS_GLOBAL" "$DISPATCHER" reset gemini-cli --global --yes > "$TEST_DIR/reset-gemini-cross-project.txt" 2>&1
)
GEMINI_CROSS_GLOBAL_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_CROSS_GLOBAL/settings.json")
GEMINI_CROSS_PROJECT_A_COUNT=$(jq -r '[.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true)] | length' "$GEMINI_CROSS_PROJECT_A/.gemini/settings.json")
if [[ "$GEMINI_CROSS_GLOBAL_COUNT" -ne 0 || "$GEMINI_CROSS_PROJECT_A_COUNT" -ne 1 ]]; then
    echo "FAIL: expected global Gemini hook cleaned and unrelated project hook preserved" >&2
    cat "$GEMINI_CROSS_GLOBAL/settings.json" >&2
    cat "$GEMINI_CROSS_PROJECT_A/.gemini/settings.json" >&2
    exit 1
fi
if [[ ! -f "$GEMINI_CROSS_GLOBAL/aport/runtime/bin/marker" || ! -f "$GEMINI_CROSS_GLOBAL/aport/passport.json" ]]; then
    echo "FAIL: reset gemini --global deleted state still referenced by another project" >&2
    cat "$TEST_DIR/reset-gemini-cross-project.txt" >&2
    exit 1
fi

echo "  ✅ reset gemini --global preserves state referenced by another project"

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

GOOSE_CUSTOM_TWO_PROJECT_HOME="$TEST_DIR/goose-custom-two-project-home"
GOOSE_CUSTOM_TWO_PROJECT_A="$TEST_DIR/goose-custom-two-project-a"
GOOSE_CUSTOM_TWO_PROJECT_B="$TEST_DIR/goose-custom-two-project-b"
GOOSE_CUSTOM_TWO_PROJECT_PLUGIN="$TEST_DIR/goose-custom-two-project-plugin"
GOOSE_CUSTOM_TWO_PROJECT_STATE="$TEST_DIR/goose-custom-two-project-state"
GOOSE_CUSTOM_TWO_PROJECT_OTHER_PLUGIN="$GOOSE_CUSTOM_TWO_PROJECT_B/.agents/plugins/aport-guardrail"
mkdir -p "$GOOSE_CUSTOM_TWO_PROJECT_A" "$GOOSE_CUSTOM_TWO_PROJECT_HOME" "$GOOSE_CUSTOM_TWO_PROJECT_PLUGIN" "$GOOSE_CUSTOM_TWO_PROJECT_OTHER_PLUGIN" "$GOOSE_CUSTOM_TWO_PROJECT_STATE/aport"
printf '{"name":"aport-guardrail","version":"1.0.0"}\n' > "$GOOSE_CUSTOM_TWO_PROJECT_PLUGIN/plugin.json"
printf '{"name":"aport-guardrail","version":"1.0.0"}\n' > "$GOOSE_CUSTOM_TWO_PROJECT_OTHER_PLUGIN/plugin.json"
touch "$GOOSE_CUSTOM_TWO_PROJECT_STATE/aport/passport.json"

echo "  Test: reset goose custom plugin preserves shared state used by another project..."
(
    cd "$GOOSE_CUSTOM_TWO_PROJECT_A"
    HOME="$GOOSE_CUSTOM_TWO_PROJECT_HOME" APORT_GOOSE_CONFIG_DIR="$GOOSE_CUSTOM_TWO_PROJECT_STATE" APORT_GOOSE_PLUGIN_DIR="$GOOSE_CUSTOM_TWO_PROJECT_PLUGIN" "$DISPATCHER" reset goose --yes > "$TEST_DIR/reset-goose-custom-two-project.txt" 2>&1
)
if [[ -d "$GOOSE_CUSTOM_TWO_PROJECT_PLUGIN" ]]; then
    echo "FAIL: expected selected custom Goose plugin directory to be removed" >&2
    exit 1
fi
if [[ ! -d "$GOOSE_CUSTOM_TWO_PROJECT_OTHER_PLUGIN" ]]; then
    echo "FAIL: expected other project Goose plugin to remain" >&2
    exit 1
fi
if [[ ! -f "$GOOSE_CUSTOM_TWO_PROJECT_STATE/aport/passport.json" ]]; then
    echo "FAIL: custom Goose reset deleted shared state used by another project" >&2
    cat "$TEST_DIR/reset-goose-custom-two-project.txt" >&2
    exit 1
fi

echo "  ✅ reset goose custom plugin preserves shared state used by another project"

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

#!/usr/bin/env bash
# APort Cursor/Copilot/Claude Code hook: read JSON from stdin, call guardrail, return allow/deny; exit 2 = block.
# Compatible with Cursor (beforeShellExecution, preToolUse), VS Code Copilot, and Claude Code.
# Input: JSON with "command" and/or "tool"/"name"/"input" (host-dependent). We map to system.command.execute.
# Output: JSON with "permission": "allow"|"deny" (Cursor) and "allowed": true|false; optional "agentMessage"/"reason".
# Exit: 0 = allow, 2 = block (deny). Other exits = hook error (host may proceed or fail-open).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-bash.sh"

# Passport/config: resolver probes ~/.cursor, ~/.openclaw, ~/.aport/langchain, etc. when OPENCLAW_CONFIG_DIR not set
# shellcheck source=bin/aport-resolve-paths.sh
. "$ROOT_DIR/bin/aport-resolve-paths.sh"

# Read stdin (single JSON object; Cursor sends one payload per invocation)
INPUT=""
if [ -t 0 ]; then
  # No stdin (e.g. manual test): treat as allow to avoid blocking
  INPUT='{}'
else
  INPUT="$(cat)"
fi

# Empty or invalid JSON -> allow with warning (fail-open for bad input)
if [ -z "$INPUT" ]; then
  echo '{"permission":"allow","allowed":true,"agentMessage":"APort: no input received"}'
  exit 0
fi

# Parse and normalize to tool + context for guardrail
# Cursor beforeShellExecution: { "command": "..." }
# preToolUse / Copilot: { "tool": "runTerminalCommand", "input": { "command": "..." } } or similar
TOOL_NAME="exec.run"
CONTEXT_JSON="{}"
if command -v jq &>/dev/null; then
  CMD=$(echo "$INPUT" | jq -r '.command // .input.command // .input.cmd // .args[0] // ""')
  if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
    CONTEXT_JSON=$(echo "$INPUT" | jq -c '{command: (.command // .input.command // .input.cmd), args: (.args // .input.args // [])}' 2>/dev/null || echo "{}")
    if [ -z "$CONTEXT_JSON" ] || [ "$CONTEXT_JSON" = "null" ]; then
      CONTEXT_JSON=$(jq -n -c --arg cmd "$CMD" '{command: $cmd}')
    fi
  fi
  # If no command found, still pass through; guardrail may deny unknown
  if [ -z "$CONTEXT_JSON" ] || [ "$CONTEXT_JSON" = "null" ]; then
    CONTEXT_JSON="$INPUT"
  fi
else
  CONTEXT_JSON="$INPUT"
fi

# Call existing bash guardrail: exit 0 = allow, exit 1 = deny (forward config for subprocess)
set +e
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}" OPENCLAW_PASSPORT_FILE="${OPENCLAW_PASSPORT_FILE:-}" OPENCLAW_DECISION_FILE="${OPENCLAW_DECISION_FILE:-}" "$GUARDRAIL" "$TOOL_NAME" "$CONTEXT_JSON" 2>/dev/null
GUARDRAIL_EXIT=$?
set -e

if [ "$GUARDRAIL_EXIT" -eq 0 ]; then
  echo '{"permission":"allow","allowed":true}'
  exit 0
fi

# Deny: output reason from decision file if available (guardrail writes decision before exit 1)
REASON="Policy denied this action."
if [ -n "${OPENCLAW_DECISION_FILE:-}" ] && [ -f "$OPENCLAW_DECISION_FILE" ] && command -v jq &>/dev/null; then
  R=$(jq -r '.reasons[0].message // empty' "$OPENCLAW_DECISION_FILE" 2>/dev/null)
  if [ -n "$R" ]; then
    REASON="$R"
  fi
fi
# If no decision file was set, try common config dirs so we can show actual deny reason
if [ "$REASON" = "Policy denied this action." ] && command -v jq &>/dev/null; then
  for DEC in "${OPENCLAW_CONFIG_DIR:-$HOME/.cursor}/aport/decision.json" "$HOME/.cursor/aport/decision.json" "$HOME/.openclaw/aport/decision.json"; do
    if [ -f "$DEC" ]; then
      R=$(jq -r '.reasons[0].message // empty' "$DEC" 2>/dev/null)
      if [ -n "$R" ]; then REASON="$R"; break; fi
    fi
  done
fi
# Fallback: help user debug guardrail/script errors
if [ "$REASON" = "Policy denied this action." ]; then
  REASON="Policy denied or guardrail error. Check passport and guardrail script (see docs/frameworks/cursor.md)."
fi
echo "{\"permission\":\"deny\",\"allowed\":false,\"agentMessage\":$(echo "$REASON" | jq -Rs .),\"reason\":$(echo "$REASON" | jq -Rs .)}"
exit 2

#!/bin/bash
# Unit test: provider drift checks can exercise Codex mapping without invoking the full evaluator.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
CONFIG_DIR="$TEST_DIR/codex"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$CONFIG_DIR/aport"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$CONFIG_DIR/aport/passport.json"
cat > "$CONFIG_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF

export APORT_CODEX_CONFIG_DIR="$CONFIG_DIR"
export OPENCLAW_CONFIG_DIR="$CONFIG_DIR"
export OPENCLAW_PASSPORT_FILE="$CONFIG_DIR/aport/passport.json"
export OPENCLAW_DECISION_FILE="$CONFIG_DIR/aport/decision.json"
export OPENCLAW_AUDIT_LOG="$CONFIG_DIR/aport/audit.log"
export APORT_CODEX_TOOL_FALLBACK=off

allowed_out="$TEST_DIR/allowed.json"
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"sudo ls"}}' \
    | "$REPO_ROOT/bin/lib/command-hook-adapter.sh" codex --classify-only > "$allowed_out"
jq -e '. == {}' "$allowed_out" > /dev/null || fail "mapped Bash should pass classify-only mode"

if [[ -f "$CONFIG_DIR/aport/session-decisions.jsonl" ]]; then
    fail "classify-only mode should not invoke evaluator or write decision audit state"
fi

env_bypass_out="$TEST_DIR/env-bypass.json"
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"sudo ls"}}' \
    | APORT_HOOK_CLASSIFY_ONLY=1 APORT_ADAPTER_CLASSIFY_ONLY=1 "$REPO_ROOT/bin/aport-codex-hook.sh" > "$env_bypass_out"
jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_not_allowed") or contains("oap.blocked_command"))' "$env_bypass_out" > /dev/null \
    || fail "environment variables must not enable classify-only bypass for the real hook"

unknown_out="$TEST_DIR/unknown.json"
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"provider_new_unknown_tool","tool_input":{"command":"ls"}}' \
    | "$REPO_ROOT/bin/lib/command-hook-adapter.sh" codex --classify-only > "$unknown_out"
jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool"))' "$unknown_out" > /dev/null \
    || fail "unknown tools must still fail in classify-only mode"

echo "PASS: Codex classify-only mode checks mapping without policy evaluation"

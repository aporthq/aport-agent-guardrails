#!/bin/bash
# CLI tests that exercise the same guardrail context the OpenClaw plugin uses:
# - system.command.execute with mkdir and ls (plugin passes these tool name + context)
# - messaging.message.send (WhatsApp-style context); ALLOW with messaging.send passport, DENY without
# Run from repo root: bash tests/test-plugin-guardrail-cli.sh

source "$(dirname "$0")/setup.sh"

cd "$REPO_ROOT"

# Use bash guardrail (same script the plugin uses in local mode)
GUARDRAIL_BASH="$REPO_ROOT/bin/aport-guardrail-bash.sh"
FIXTURE_MESSAGING="$REPO_ROOT/tests/fixtures/passport-with-messaging.json"

echo "  Plugin-style CLI tests (same tool names + context as OpenClaw plugin)"
echo "  ─────────────────────────────────────────────────────────────────"
echo ""

# --- system.command.execute: mkdir (same context shape plugin sends) ---
echo "  system.command.execute: mkdir (ALLOW)..."
rm -f "$OPENCLAW_DECISION_FILE"
cp "$FIXTURE_PASSPORT" "$OPENCLAW_PASSPORT_FILE"
exit_mkdir=0
"$GUARDRAIL_BASH" system.command.execute '{"command":"mkdir -p /tmp/aport-test-dir"}' 2> /dev/null || exit_mkdir=$?
if [ "$exit_mkdir" -ne 0 ]; then
    echo "FAIL: mkdir should ALLOW (exit 0), got exit $exit_mkdir" >&2
    [ -f "$OPENCLAW_DECISION_FILE" ] && jq -r '.reasons[0].message // .allow' "$OPENCLAW_DECISION_FILE" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "mkdir decision.allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "policy_id" "system.command.execute.v1" "policy_id"
echo "    ALLOW OK"

# --- system.command.execute: ls (same context shape plugin sends) ---
echo "  system.command.execute: ls (ALLOW)..."
rm -f "$OPENCLAW_DECISION_FILE"
exit_ls=0
"$GUARDRAIL_BASH" system.command.execute '{"command":"ls /tmp/aport-test-dir"}' 2> /dev/null || exit_ls=$?
if [ "$exit_ls" -ne 0 ]; then
    echo "FAIL: ls should ALLOW (exit 0), got exit $exit_ls" >&2
    [ -f "$OPENCLAW_DECISION_FILE" ] && jq -r '.reasons[0].message // .allow' "$OPENCLAW_DECISION_FILE" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "ls decision.allow"
echo "    ALLOW OK"

# --- messaging.message.send: ALLOW when passport has messaging.send ---
echo "  messaging.message.send (ALLOW with messaging.send capability)..."
rm -f "$OPENCLAW_DECISION_FILE"
cp "$FIXTURE_MESSAGING" "$OPENCLAW_PASSPORT_FILE"
# Same context shape the plugin would pass (channel_id, message, message_type per policy)
MSG_CONTEXT='{"channel_id":"whatsapp:+15551234567","message":"test","message_type":"text"}'
exit_msg=0
"$GUARDRAIL_BASH" messaging.message.send "$MSG_CONTEXT" 2> /dev/null || exit_msg=$?
if [ "$exit_msg" -ne 0 ]; then
    echo "FAIL: messaging.message.send should ALLOW when passport has messaging.send, got exit $exit_msg" >&2
    [ -f "$OPENCLAW_DECISION_FILE" ] && jq -r '.reasons[0].code // .reasons[0].message // .allow' "$OPENCLAW_DECISION_FILE" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "messaging decision.allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "policy_id" "messaging.message.send.v1" "policy_id"
echo "    ALLOW OK"

# --- messaging.message.send: DENY when passport lacks messaging.send ---
echo "  messaging.message.send (DENY without capability)..."
rm -f "$OPENCLAW_DECISION_FILE"
cp "$FIXTURE_PASSPORT" "$OPENCLAW_PASSPORT_FILE"
exit_deny=0
"$GUARDRAIL_BASH" messaging.message.send "$MSG_CONTEXT" 2> /dev/null || exit_deny=$?
if [ "$exit_deny" -eq 0 ]; then
    echo "FAIL: messaging.message.send should DENY when passport has no messaging.send (exit non-zero)" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "messaging deny decision.allow"
code=$(jq -r '.reasons[0].code' "$OPENCLAW_DECISION_FILE")
if [ "$code" != "oap.unknown_capability" ]; then
    echo "FAIL: expected reasons[0].code oap.unknown_capability, got $code" >&2
    exit 1
fi
echo "    DENY (oap.unknown_capability) OK"

# Restore fixture for any tests that run after
cp "$FIXTURE_PASSPORT" "$OPENCLAW_PASSPORT_FILE"

echo ""
echo "  ✅ Plugin-style CLI tests passed (mkdir, ls, messaging.message.send ALLOW/DENY)."
exit 0

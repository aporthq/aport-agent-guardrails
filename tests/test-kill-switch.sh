#!/bin/bash
# Kill switch: when present, guardrail denies all actions with oap.kill_switch_active

source "$(dirname "$0")/setup.sh"

cd "$REPO_ROOT"

echo "  Kill switch: absent -> allow..."
rm -f "$OPENCLAW_KILL_SWITCH"
"$GUARDRAIL" git.create_pr '{"repo":"a/b","files_changed":1}' || { echo "FAIL: should allow when kill switch absent"; exit 1; }
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "allow when no kill switch"

echo "  Kill switch: present -> deny..."
touch "$OPENCLAW_KILL_SWITCH"
if "$GUARDRAIL" git.create_pr '{"repo":"a/b","files_changed":1}' 2>/dev/null; then
    echo "FAIL: should deny when kill switch present" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "deny when kill switch"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.kill_switch_active" "reasons[0].code"

echo "  Kill switch: removed -> allow again..."
rm -f "$OPENCLAW_KILL_SWITCH"
"$GUARDRAIL" git.create_pr '{"repo":"a/b","files_changed":1}' || { echo "FAIL: should allow after kill switch removed"; exit 1; }
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "allow after kill switch removed"

exit 0

#!/bin/bash
# Kill switch = passport status (source of truth per OAP spec). When status is suspended or revoked, guardrail denies with oap.passport_suspended.

source "$(dirname "$0")/setup.sh"

cd "$REPO_ROOT"

echo "  Passport status active -> allow..."
"$GUARDRAIL" git.create_pr '{"repo":"a/b","files_changed":1}' || { echo "FAIL: should allow when status active"; exit 1; }
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "allow when status active"

echo "  Passport status suspended -> deny (agent suspended)..."
jq '.status = "suspended"' "$OPENCLAW_PASSPORT_FILE" > "$OPENCLAW_PASSPORT_FILE.tmp" && mv "$OPENCLAW_PASSPORT_FILE.tmp" "$OPENCLAW_PASSPORT_FILE"
if "$GUARDRAIL" git.create_pr '{"repo":"a/b","files_changed":1}' 2>/dev/null; then
    echo "FAIL: should deny when passport status suspended" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "deny when suspended"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.passport_suspended" "reasons[0].code"

echo "  Passport status active again -> allow..."
jq '.status = "active"' "$OPENCLAW_PASSPORT_FILE" > "$OPENCLAW_PASSPORT_FILE.tmp" && mv "$OPENCLAW_PASSPORT_FILE.tmp" "$OPENCLAW_PASSPORT_FILE"
"$GUARDRAIL" git.create_pr '{"repo":"a/b","files_changed":1}' || { echo "FAIL: should allow after status active again"; exit 1; }
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "allow after status active again"

exit 0

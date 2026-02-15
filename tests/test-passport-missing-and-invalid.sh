#!/bin/bash
# Guardrail with missing or invalid passport: clear deny and oap.* error codes

source "$(dirname "$0")/setup.sh"

cd "$REPO_ROOT"

echo "  Guardrail: missing passport -> deny..."
rm -f "$OPENCLAW_PASSPORT_FILE"
if "$GUARDRAIL" git.create_pr '{"repo":"a/b","files_changed":1}' 2>/dev/null; then
    echo "FAIL: should deny when passport missing" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.passport_not_found" "reasons[0].code"

echo "  Guardrail: invalid JSON passport -> deny..."
echo "not json" > "$OPENCLAW_PASSPORT_FILE"
if "$GUARDRAIL" git.create_pr '{"repo":"a/b","files_changed":1}' 2>/dev/null; then
    echo "FAIL: should deny when passport invalid JSON" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.passport_invalid" "reasons[0].code"

echo "  Guardrail: suspended passport -> deny..."
cp "$FIXTURE_PASSPORT" "$OPENCLAW_PASSPORT_FILE"
jq '.status = "suspended"' "$OPENCLAW_PASSPORT_FILE" > "$OPENCLAW_PASSPORT_FILE.tmp" && mv "$OPENCLAW_PASSPORT_FILE.tmp" "$OPENCLAW_PASSPORT_FILE"
if "$GUARDRAIL" git.create_pr '{"repo":"a/b","files_changed":1}' 2>/dev/null; then
    echo "FAIL: should deny when passport suspended" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.passport_suspended" "reasons[0].code"

# Restore fixture
cp "$FIXTURE_PASSPORT" "$OPENCLAW_PASSPORT_FILE"

exit 0

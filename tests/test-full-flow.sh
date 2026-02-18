#!/bin/bash
# Full flow: create passport (wizard) -> guardrail allow -> guardrail deny -> status

source "$(dirname "$0")/setup.sh"

CREATE_SCRIPT="$REPO_ROOT/bin/aport-create-passport.sh"
GUARDRAIL="$REPO_ROOT/bin/aport-guardrail.sh"
STATUS_SCRIPT="$REPO_ROOT/bin/aport-status.sh"

FLOW_PASSPORT="$TEST_DIR/fullflow_passport.json"
# Use a dedicated passport for this flow so we don't rely on fixture
rm -f "$FLOW_PASSPORT" "$OPENCLAW_PASSPORT_FILE"

echo "  Full flow: create passport..."
# Always use --non-interactive so tests pass in CI (no TTY / pipe EOF issues)
"$CREATE_SCRIPT" --output "$FLOW_PASSPORT" --non-interactive

if [ ! -f "$FLOW_PASSPORT" ]; then
    echo "FAIL: passport was not created" >&2
    exit 1
fi

export OPENCLAW_PASSPORT_FILE="$FLOW_PASSPORT"
export OPENCLAW_DECISION_FILE="$TEST_DIR/decision.json"
export OPENCLAW_AUDIT_LOG="$TEST_DIR/audit.log"

cd "$REPO_ROOT"

echo "  Full flow: guardrail ALLOW (valid context)..."
if ! "$GUARDRAIL" git.create_pr '{"repo":"aporthq/repo","files_changed":10}'; then
    echo "FAIL: guardrail should ALLOW after created passport" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "decision.allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.allowed" "reasons[0].code"

echo "  Full flow: guardrail DENY (policy limit)..."
if "$GUARDRAIL" git.create_pr '{"repo":"aporthq/repo","files_changed":600}' 2>/dev/null; then
    echo "FAIL: guardrail should DENY when exceeding limit" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "decision.allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.limit_exceeded" "reasons[0].code"

echo "  Full flow: status shows passport..."
out=$("$STATUS_SCRIPT" --passport "$FLOW_PASSPORT" 2>&1) || true
echo "$out" | grep -q "Passport Information" || { echo "FAIL: status should show Passport Information"; exit 1; }
echo "$out" | grep -q "active" || { echo "FAIL: status should show active"; exit 1; }
echo "$out" | grep -q "oap/1.0" || { echo "FAIL: status should show spec version"; exit 1; }

exit 0

#!/bin/bash
# OAP v1 passport fixture and status script: required fields, metadata, never_expires, status output

source "$(dirname "$0")/setup.sh"

echo "  Passport fixture: required OAP v1 fields..."
assert_json_eq "$OPENCLAW_PASSPORT_FILE" "spec_version" "oap/1.0" "spec_version"
assert_json_eq "$OPENCLAW_PASSPORT_FILE" "kind" "template" "kind"
assert_json_has "$OPENCLAW_PASSPORT_FILE" "passport_id" "passport_id"
assert_json_has "$OPENCLAW_PASSPORT_FILE" "capabilities" "capabilities"
assert_json_has "$OPENCLAW_PASSPORT_FILE" "limits" "limits"
assert_json_has "$OPENCLAW_PASSPORT_FILE" "regions" "regions"
assert_json_has "$OPENCLAW_PASSPORT_FILE" "metadata" "metadata"
assert_json_eq "$OPENCLAW_PASSPORT_FILE" "metadata.name" "Test Agent" "metadata.name"
assert_json_eq "$OPENCLAW_PASSPORT_FILE" "never_expires" "true" "never_expires"
assert_json_eq "$OPENCLAW_PASSPORT_FILE" "status" "active" "status"

echo "  Status script: runs and shows OAP v1 fields..."
out=$("$STATUS_SCRIPT" --passport "$OPENCLAW_PASSPORT_FILE" 2>&1) || true
echo "$out" | grep -q "Passport Information" || { echo "FAIL: status should show Passport Information"; exit 1; }
echo "$out" | grep -q "Spec Version" || { echo "FAIL: status should show Spec Version"; exit 1; }
echo "$out" | grep -q "Assurance Level" || { echo "FAIL: status should show Assurance Level"; exit 1; }
echo "$out" | grep -q "Test Agent" || { echo "FAIL: status should show agent name from metadata"; exit 1; }
echo "$out" | grep -q "active" || { echo "FAIL: status should show active"; exit 1; }

echo "  Status script: missing passport exits non-zero..."
rm -f "$OPENCLAW_PASSPORT_FILE"
# Capture stdout too so expected "Passport: NOT FOUND" message doesn't clutter test log
if "$STATUS_SCRIPT" --passport "$OPENCLAW_PASSPORT_FILE" >/dev/null 2>&1; then
    echo "FAIL: status should exit 1 when passport missing" >&2
    exit 1
fi
# Restore for other tests
cp "$FIXTURE_PASSPORT" "$OPENCLAW_PASSPORT_FILE"

exit 0

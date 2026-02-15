#!/bin/bash
# Test passport creation: run aport-create-passport.sh with piped input and assert OAP v1 output

source "$(dirname "$0")/setup.sh"

CREATE_SCRIPT="$REPO_ROOT/bin/aport-create-passport.sh"
CREATED_PASSPORT="$TEST_DIR/passport_created.json"

# Remove fixture so we're testing the created passport only
rm -f "$OPENCLAW_PASSPORT_FILE"

echo "  Passport creation: run wizard with piped input..."
# Prompt order: owner_id, owner_type, agent_name, agent_description,
#   pr_cap, exec_cap, msg_cap, data_cap,
#   max_pr_size, max_prs_per_day, allowed_repos,
#   exec_allow_scope (default or *),
#   should_expire (n = never)
# Empty line = use default; y/n for capabilities; n = never expire
printf '%s\n' '' '' '' '' 'y' 'y' 'n' 'n' '500' '10' '*' '' 'n' | \
    "$CREATE_SCRIPT" --output "$CREATED_PASSPORT" >/dev/null 2>&1 || true

if [ ! -f "$CREATED_PASSPORT" ]; then
    echo "FAIL: passport file was not created at $CREATED_PASSPORT" >&2
    exit 1
fi

echo "  Passport creation: output has OAP v1 required fields..."
assert_json_eq "$CREATED_PASSPORT" "spec_version" "oap/1.0" "spec_version"
assert_json_eq "$CREATED_PASSPORT" "kind" "template" "kind"
assert_json_has "$CREATED_PASSPORT" "passport_id" "passport_id"
assert_json_has "$CREATED_PASSPORT" "capabilities" "capabilities"
assert_json_has "$CREATED_PASSPORT" "limits" "limits"
assert_json_has "$CREATED_PASSPORT" "regions" "regions"
assert_json_has "$CREATED_PASSPORT" "metadata" "metadata"
assert_json_eq "$CREATED_PASSPORT" "status" "active" "status"

# Should have repo and exec capabilities from our y/y/n/n choices
cap_ids=$(jq -r '.capabilities[].id' "$CREATED_PASSPORT")
echo "$cap_ids" | grep -q "repo.pr.create" || { echo "FAIL: expected repo.pr.create"; exit 1; }
echo "$cap_ids" | grep -q "repo.merge" || { echo "FAIL: expected repo.merge"; exit 1; }
echo "$cap_ids" | grep -q "system.command.execute" || { echo "FAIL: expected system.command.execute"; exit 1; }

# Limits should reflect our inputs (500, 10, *)
max_size=$(jq -r '.limits["code.repository.merge"].max_pr_size_kb' "$CREATED_PASSPORT")
max_prs=$(jq -r '.limits["code.repository.merge"].max_prs_per_day' "$CREATED_PASSPORT")
assert_eq "$max_size" "500" "max_pr_size_kb"
assert_eq "$max_prs" "10" "max_prs_per_day"

exit 0

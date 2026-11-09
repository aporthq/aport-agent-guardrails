#!/bin/bash
# Schema and sanitization gate for the release-verification record.
#
# The record is published in Git, so it must carry only bounded allowlisted metadata: identifiers, digests,
# counts, booleans and authored constants. This test checks the committed record and then feeds the validator
# deliberately poisoned copies, asserting that each is rejected: credentials, private paths, prompts, shell
# commands, raw tool inputs/outputs, missing artifact or fixture identity, and fixture-only evidence claimed
# as a live run. A validator that accepts a poisoned record is itself the defect.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECORD="$REPO_ROOT/docs/reviews/installation-reporting-release-1.0.37.json"
VALIDATOR="$REPO_ROOT/scripts/check-release-verification-record.mjs"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/aport-release-record.XXXXXX")}"
mkdir -p "$TEST_DIR"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

echo ""
echo "  Unit - release verification record schema and sanitization"
echo ""

command -v node > /dev/null || fail "node is required"
[ -f "$VALIDATOR" ] || fail "missing scripts/check-release-verification-record.mjs"
[ -f "$RECORD" ] || fail "missing docs/reviews/installation-reporting-release-1.0.37.json"

# 1. The committed record passes.
node "$VALIDATOR" "$RECORD" > "$TEST_DIR/clean.out" 2> "$TEST_DIR/clean.err" \
    || {
        echo "FAIL: RECORD_IS_CLEAN: the committed record does not validate" >&2
        cat "$TEST_DIR/clean.err" >&2
        exit 1
    }
echo "  OK RECORD_IS_CLEAN: the committed record validates"

# 2. The record must name this release and match the repository version.
RECORD_VERSION="$(node -p "require('$RECORD').candidate_version")"
REPO_VERSION="$(node -p "require('$REPO_ROOT/packages/core/package.json').version")"
[ "$RECORD_VERSION" = "$REPO_VERSION" ] \
    || fail "RECORD_MATCHES_RELEASE: record is $RECORD_VERSION but the repository is $REPO_VERSION"
echo "  OK RECORD_MATCHES_RELEASE: the record describes $REPO_VERSION"

# The recorded source revision must be a real commit in this history that already carries the release
# version. It is the commit the inspected artifacts were built from, so it is the parent of the commit that
# adds the record itself rather than HEAD; requiring it to equal HEAD would have no fixpoint.
RECORD_REVISION="$(node -p "require('$RECORD').prepared_from.source_revision")"
if git -C "$REPO_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
    if git -C "$REPO_ROOT" cat-file -e "$RECORD_REVISION" 2> /dev/null; then
        REVISION_VERSION="$(git -C "$REPO_ROOT" show "$RECORD_REVISION:packages/core/package.json" 2> /dev/null \
            | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).version||'')}catch{console.log('')}})")"
        [ "$REVISION_VERSION" = "$REPO_VERSION" ] \
            || fail "RECORD_REVISION_CARRIES_RELEASE: ${RECORD_REVISION} declares '${REVISION_VERSION}', expected $REPO_VERSION"
        echo "  OK RECORD_REVISION_CARRIES_RELEASE: the recorded revision exists and declares $REPO_VERSION"
    else
        # A shallow clone or a record built on another branch cannot resolve the revision; the shape is
        # still checked by the validator, so this is reported rather than failed.
        echo "  SKIP RECORD_REVISION_CARRIES_RELEASE: ${RECORD_REVISION} is not present in this checkout"
    fi
fi

# 3. Live qualification must be recorded as not run, with no invented deployment identity.
node -e '
const record = require(process.argv[1]);
const live = record.unresolved_and_deferred?.live_deployment_compatibility;
if (!live) { console.error("no live_deployment_compatibility entry"); process.exit(1); }
if (live.status !== "not_run") { console.error(`live status is ${live.status}, expected not_run`); process.exit(1); }
if (live.deployment_identifier !== null) {
  console.error(`live deployment_identifier must be null, got ${JSON.stringify(live.deployment_identifier)}`);
  process.exit(1);
}
if (live.waived_by_operator !== true) { console.error("live qualification must record the operator waiver"); process.exit(1); }
if (!Array.isArray(live.unverified_outcomes) || live.unverified_outcomes.length === 0) {
  console.error("live qualification must list the outcomes that remain unverified"); process.exit(1);
}
' "$RECORD" || fail "LIVE_NOT_RUN: live qualification is not recorded as not run"
echo "  OK LIVE_NOT_RUN: live qualification is not run with no invented deployment identity"

# 4. Deferred contract and Windows functionality stay distinguishable from fixture-verified behaviour.
node -e '
const record = require(process.argv[1]);
const deferred = record.unresolved_and_deferred || {};
const expected = {
  unsigned_failure_receipts: "deferred",
  windows_reporting: "unresolved",
  hosts_without_completion_signal: "not_reported",
};
for (const [key, status] of Object.entries(expected)) {
  if (deferred[key]?.status !== status) {
    console.error(`${key} status is ${deferred[key]?.status}, expected ${status}`);
    process.exit(1);
  }
}
const outcomes = record.deterministic_validation?.outcomes || [];
if (!outcomes.length) { console.error("no deterministic outcomes recorded"); process.exit(1); }
for (const outcome of outcomes) {
  if (!["fixture_response", "injected_fault", "local_only"].includes(outcome.evidence)) {
    console.error(`outcome ${outcome.outcome} has unrecognised evidence class ${outcome.evidence}`);
    process.exit(1);
  }
}
' "$RECORD" || fail "DEFERRED_DISTINGUISHED: deferred work is not distinguished from fixture evidence"
echo "  OK DEFERRED_DISTINGUISHED: deferred contract/Windows work is separate from fixture evidence"

# --- Poisoned copies must be rejected ---------------------------------------------------------------------
poison() {
    local name="$1" expect="$2" script="$3"
    local target="$TEST_DIR/poisoned-$name.json"
    node -e "$script" "$RECORD" "$target" || fail "could not build poisoned record $name"
    if node "$VALIDATOR" "$target" > "$TEST_DIR/$name.out" 2> "$TEST_DIR/$name.err"; then
        echo "FAIL: $expect: validator accepted a record containing $name" >&2
        exit 1
    fi
    grep -q . "$TEST_DIR/$name.err" || fail "$expect: rejection produced no diagnostic for $name"
    echo "  OK $expect: rejected $name"
}

WRITE='const fs=require("fs");const r=require(process.argv[1]);'
SAVE='fs.writeFileSync(process.argv[2], JSON.stringify(r,null,2));'

poison "a bearer credential" REJECTS_CREDENTIALS \
    "$WRITE r.deterministic_validation.outcomes[0].token='air1.eyJ2IjoxfQ.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'; $SAVE"

poison "an API key" REJECTS_CREDENTIALS \
    "$WRITE r.release_preparation.api_key='ap_live_sk_0123456789abcdef0123456789abcdef'; $SAVE"

poison "a private home path" REJECTS_PRIVATE_PATHS \
    "$WRITE r.deterministic_validation.runtime_under_test='/Users/someone/secret-checkout/src/installation-reporting'; $SAVE"

poison "a prompt" REJECTS_PROMPTS \
    "$WRITE r.deterministic_validation.outcomes[0].prompt='Draw a safe badge for the release'; $SAVE"

poison "a shell command" REJECTS_COMMANDS \
    "$WRITE r.deterministic_validation.outcomes[0].command='curl -sS https://api.example.com/v1/report -H \"Authorization: Bearer x\"'; $SAVE"

poison "raw tool input" REJECTS_RAW_TOOL_IO \
    "$WRITE r.deterministic_validation.outcomes[0].tool_input={file_path:'/etc/passwd',content:'root:x:0:0'}; $SAVE"

poison "raw tool output" REJECTS_RAW_TOOL_IO \
    "$WRITE r.deterministic_validation.outcomes[0].tool_output='total 48\\ndrwx------ 12 user staff'; $SAVE"

poison "a missing artifact digest" REJECTS_MISSING_ARTIFACT_IDENTITY \
    "$WRITE delete r.artifacts.npm[0].sha256; $SAVE"

poison "a missing source revision" REJECTS_MISSING_ARTIFACT_IDENTITY \
    "$WRITE delete r.prepared_from.source_revision; $SAVE"

poison "a missing fixture identity" REJECTS_MISSING_FIXTURE_IDENTITY \
    "$WRITE for (const o of r.deterministic_validation.outcomes) { delete o.evidence; } $SAVE"

poison "fixture evidence claimed as a live run" REJECTS_FIXTURE_CLAIMED_LIVE \
    "$WRITE r.unresolved_and_deferred.live_deployment_compatibility.status='passed'; $SAVE"

poison "an invented deployment identity" REJECTS_FIXTURE_CLAIMED_LIVE \
    "$WRITE r.unresolved_and_deferred.live_deployment_compatibility.deployment_identifier='agent-passport-prod-eu-1'; $SAVE"

poison "a fixture outcome relabelled live" REJECTS_FIXTURE_CLAIMED_LIVE \
    "$WRITE r.deterministic_validation.outcomes[0].evidence='live_deployment'; $SAVE"

echo ""
echo "  All release verification record tests passed."

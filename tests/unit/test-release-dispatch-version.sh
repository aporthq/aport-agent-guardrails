#!/bin/bash
# Regression: the main-merge release dispatcher decides correctly for a newly synchronized version, an
# already completed version, and an incomplete version that needs recovery; and the GitHub Release still
# waits for both npm and PyPI publication.
#
# The decision logic is not restated here. The "Resolve version change" script is extracted from
# .github/workflows/release-on-version.yml and executed as-is against mocked `git`, `gh` and `node`, so a
# change to the real workflow is what this test observes. Nothing publishes, tags, or reaches the network:
# `gh` is a mock that records its arguments and the test asserts no publishing command was ever attempted.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH_WORKFLOW="$REPO_ROOT/.github/workflows/release-on-version.yml"
RELEASE_WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/aport-release-dispatch.XXXXXX")}"
mkdir -p "$TEST_DIR"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

echo ""
echo "  Unit - release dispatch on version bump"
echo ""

[ -f "$DISPATCH_WORKFLOW" ] || fail "DISPATCH_WORKFLOW_PRESENT: missing release-on-version.yml"

# --- Extract the real resolve step so the mocked runs exercise the shipped logic -------------------------
STEP="$TEST_DIR/resolve-version.sh"
awk '
  /^      - name: Resolve version change$/ { in_step = 1; next }
  in_step && /^        run: \|$/ { in_run = 1; next }
  in_run && /^      - / { exit }
  in_run { sub(/^          /, ""); print }
' "$DISPATCH_WORKFLOW" > "$STEP"
[ -s "$STEP" ] || fail "RESOLVE_STEP_EXTRACTED: could not extract the Resolve version change script"
grep -q 'should_release' "$STEP" || fail "RESOLVE_STEP_EXTRACTED: extracted script does not set should_release"

# GitHub Actions expression interpolation happens before the shell runs. Substitute only the event name and
# before-SHA placeholders the step reads, per scenario.
render_step() {
    local event="$1" before="$2" out="$3"
    sed -e "s|\${{ github.event_name }}|$event|g" \
        -e "s|\${{ github.event.before }}|$before|g" \
        "$STEP" > "$out"
}

# --- Mocked transports ------------------------------------------------------------------------------------
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

# `node -p "require('./package.json').version"` is the only node use in the step.
cat > "$BIN/node" << 'MOCK'
#!/bin/bash
# Mock: report the staged package version without loading the real project.
if [ "${1:-}" = "-p" ]; then
  printf '%s\n' "$APORT_MOCK_PACKAGE_VERSION"
  exit 0
fi
# The previous-version read pipes package.json JSON through `node -e`.
if [ "${1:-}" = "-e" ]; then
  cat > /dev/null
  printf '%s\n' "${APORT_MOCK_PREVIOUS_VERSION:-}"
  exit 0
fi
exit 0
MOCK

cat > "$BIN/git" << 'MOCK'
#!/bin/bash
# Mock: tag existence and the previous package.json read. Never touches a real repository.
echo "git $*" >> "$APORT_MOCK_LOG"
case "$1 $2" in
  "ls-remote --exit-code")
    [ "$APORT_MOCK_TAG_EXISTS" = "true" ] && exit 0 || exit 2
    ;;
  "cat-file -e")
    [ -n "${APORT_MOCK_PREVIOUS_VERSION:-}" ] && exit 0 || exit 1
    ;;
  "show "*|"show")
    printf '{"version":"%s"}\n' "${APORT_MOCK_PREVIOUS_VERSION:-}"
    exit 0
    ;;
esac
exit 0
MOCK

cat > "$BIN/gh" << 'MOCK'
#!/bin/bash
# Mock: release lookup and workflow dispatch. Records every invocation; publishes nothing.
echo "gh $*" >> "$APORT_MOCK_LOG"
case "$1 $2" in
  "release view")
    [ "$APORT_MOCK_RELEASE_EXISTS" = "true" ] && exit 0 || exit 1
    ;;
esac
exit 0
MOCK

chmod +x "$BIN/node" "$BIN/git" "$BIN/gh"

# --- Scenario runner --------------------------------------------------------------------------------------
# Runs the extracted step with a GITHUB_OUTPUT file and returns its resolved outputs.
run_scenario() {
    local name="$1" event="$2" before="$3" current="$4" previous="$5" tag_exists="$6" release_exists="$7"
    local dir="$TEST_DIR/scenario-$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    render_step "$event" "$before" "$dir/step.sh"

    SCENARIO_OUTPUT="$dir/output.txt"
    SCENARIO_LOG="$dir/commands.log"
    SCENARIO_STDOUT="$dir/stdout.txt"
    : > "$SCENARIO_OUTPUT"
    : > "$SCENARIO_LOG"

    set +e
    PATH="$BIN:$PATH" \
        GITHUB_OUTPUT="$SCENARIO_OUTPUT" \
        GITHUB_REPOSITORY="aporthq/aport-agent-guardrails" \
        GH_TOKEN="mock-token-not-a-credential" \
        APORT_MOCK_LOG="$SCENARIO_LOG" \
        APORT_MOCK_PACKAGE_VERSION="$current" \
        APORT_MOCK_PREVIOUS_VERSION="$previous" \
        APORT_MOCK_TAG_EXISTS="$tag_exists" \
        APORT_MOCK_RELEASE_EXISTS="$release_exists" \
        bash "$dir/step.sh" > "$SCENARIO_STDOUT" 2>&1
    SCENARIO_EXIT=$?
    set -e

    SCENARIO_SHOULD_RELEASE="$(grep -m1 '^should_release=' "$SCENARIO_OUTPUT" | cut -d= -f2 || true)"
    SCENARIO_VERSION="$(grep -m1 '^version=' "$SCENARIO_OUTPUT" | cut -d= -f2 || true)"
}

# 1. A newly synchronized version dispatches the existing release flow.
run_scenario new-version push "abc1234" "1.0.37" "1.0.36" false false
[ "$SCENARIO_EXIT" -eq 0 ] || fail "NEW_VERSION_DISPATCHES: step exited $SCENARIO_EXIT"
[ "$SCENARIO_SHOULD_RELEASE" = "true" ] || fail "NEW_VERSION_DISPATCHES: should_release=$SCENARIO_SHOULD_RELEASE, expected true"
[ "$SCENARIO_VERSION" = "1.0.37" ] || fail "NEW_VERSION_DISPATCHES: version=$SCENARIO_VERSION, expected 1.0.37"
echo "  OK NEW_VERSION_DISPATCHES: a newly synchronized version dispatches the release flow"

# 2. An already completed version skips safely: unchanged version, tag and GitHub Release both present.
run_scenario completed push "abc1234" "1.0.37" "1.0.37" true true
[ "$SCENARIO_EXIT" -eq 0 ] || fail "COMPLETED_VERSION_SKIPS: step exited $SCENARIO_EXIT"
[ "$SCENARIO_SHOULD_RELEASE" = "false" ] || fail "COMPLETED_VERSION_SKIPS: should_release=$SCENARIO_SHOULD_RELEASE, expected false"
grep -q "skipping release dispatch" "$SCENARIO_STDOUT" || fail "COMPLETED_VERSION_SKIPS: no skip explanation"
echo "  OK COMPLETED_VERSION_SKIPS: an already completed version skips without dispatching"

# 2b. A re-pushed released version also skips when the tag and release already exist.
run_scenario completed-rerun push "abc1234" "1.0.36" "1.0.35" true true
[ "$SCENARIO_SHOULD_RELEASE" = "false" ] || fail "COMPLETED_VERSION_SKIPS: a fully released tag must not re-dispatch"
echo "  OK COMPLETED_VERSION_SKIPS: an existing tag and release skip even when the version changed"

# 3. Incomplete-version recovery remains supported: unchanged version, tag exists, Release missing.
run_scenario recover-missing-release push "abc1234" "1.0.37" "1.0.37" true false
[ "$SCENARIO_EXIT" -eq 0 ] || fail "INCOMPLETE_VERSION_RECOVERS: step exited $SCENARIO_EXIT"
[ "$SCENARIO_SHOULD_RELEASE" = "true" ] || fail "INCOMPLETE_VERSION_RECOVERS: should_release=$SCENARIO_SHOULD_RELEASE, expected true"
[ "$SCENARIO_VERSION" = "1.0.37" ] || fail "INCOMPLETE_VERSION_RECOVERS: version=$SCENARIO_VERSION"
grep -q "dispatching recovery" "$SCENARIO_STDOUT" || fail "INCOMPLETE_VERSION_RECOVERS: recovery was not announced"
echo "  OK INCOMPLETE_VERSION_RECOVERS: a tag without a GitHub Release dispatches recovery"

# 3b. A missing tag with an unchanged version also recovers rather than going silent.
run_scenario recover-missing-tag push "abc1234" "1.0.37" "1.0.37" false false
[ "$SCENARIO_SHOULD_RELEASE" = "true" ] || fail "INCOMPLETE_VERSION_RECOVERS: a missing tag must still dispatch"
echo "  OK INCOMPLETE_VERSION_RECOVERS: a missing tag with an unchanged version still dispatches"

# 3c. Manual workflow_dispatch recovery keeps working with no previous version to compare.
run_scenario manual-dispatch workflow_dispatch "" "1.0.37" "" false false
[ "$SCENARIO_SHOULD_RELEASE" = "true" ] || fail "MANUAL_DISPATCH_SUPPORTED: manual recovery must dispatch"
[ "$SCENARIO_VERSION" = "1.0.37" ] || fail "MANUAL_DISPATCH_SUPPORTED: version=$SCENARIO_VERSION"
echo "  OK MANUAL_DISPATCH_SUPPORTED: manual dispatch resolves the version without a push comparison"

# 4. A malformed version fails closed instead of dispatching an unresolvable release.
run_scenario invalid-version push "abc1234" "1.0.37-rc.1" "1.0.36" false false
[ "$SCENARIO_EXIT" -ne 0 ] || fail "INVALID_VERSION_FAILS_CLOSED: a non-release version must not dispatch"
[ "$SCENARIO_SHOULD_RELEASE" != "true" ] || fail "INVALID_VERSION_FAILS_CLOSED: should_release must not be true"
echo "  OK INVALID_VERSION_FAILS_CLOSED: a non-release version stops before dispatch"

# --- No publishing, tagging, or push was attempted by any scenario ---------------------------------------
for log in "$TEST_DIR"/scenario-*/commands.log; do
    [ -f "$log" ] || continue
    grep -qE '(^|[^a-z-])gh release create' "$log" && fail "NO_PUBLISH_SIDE_EFFECTS: a scenario tried to create a release"
    grep -qE 'npm (publish|dist-tag)' "$log" && fail "NO_PUBLISH_SIDE_EFFECTS: a scenario tried to publish to npm"
    grep -qE 'twine|pypi' "$log" && fail "NO_PUBLISH_SIDE_EFFECTS: a scenario tried to publish to PyPI"
    grep -qE 'git (tag|push)' "$log" && fail "NO_PUBLISH_SIDE_EFFECTS: a scenario tried to tag or push"
done
echo "  OK NO_PUBLISH_SIDE_EFFECTS: no scenario published, tagged, or pushed"

# The resolve step itself must never publish; dispatch is a separate gated step.
grep -qE 'npm publish|twine upload|gh release create' "$STEP" \
    && fail "DISPATCH_AUTHORITY_UNCHANGED: the resolve step must not publish"
grep -q 'gh workflow run release.yml' "$DISPATCH_WORKFLOW" \
    || fail "DISPATCH_AUTHORITY_UNCHANGED: dispatcher no longer invokes the existing release workflow"
grep -q "if: steps.version.outputs.should_release == 'true'" "$DISPATCH_WORKFLOW" \
    || fail "DISPATCH_AUTHORITY_UNCHANGED: dispatch is no longer gated on should_release"
echo "  OK DISPATCH_AUTHORITY_UNCHANGED: publication authority stays in the existing release workflow"

# --- The GitHub Release still waits for both ecosystems ---------------------------------------------------
[ -f "$RELEASE_WORKFLOW" ] || fail "RELEASE_WAITS_FOR_BOTH: missing release.yml"
CREATE_NEEDS="$(awk '
  /^  create-release:/ { in_job = 1; next }
  in_job && /^  [A-Za-z_-]+:/ { exit }
  in_job && /needs:/ { print; exit }
' "$RELEASE_WORKFLOW")"
[ -n "$CREATE_NEEDS" ] || fail "RELEASE_WAITS_FOR_BOTH: create-release declares no needs"
case "$CREATE_NEEDS" in
    *publish-npm*) ;;
    *) fail "RELEASE_WAITS_FOR_BOTH: create-release does not wait for publish-npm ($CREATE_NEEDS)" ;;
esac
case "$CREATE_NEEDS" in
    *publish-python*) ;;
    *) fail "RELEASE_WAITS_FOR_BOTH: create-release does not wait for publish-python ($CREATE_NEEDS)" ;;
esac
echo "  OK RELEASE_WAITS_FOR_BOTH: GitHub Release creation waits for npm and PyPI publication"

echo ""
echo "  All release dispatch tests passed."

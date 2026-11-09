#!/bin/bash
# Regression: the CI test job provisions Node and Python prerequisites before
# `make test`, both staging and main PRs run the same job, the release workflow
# keeps its main-only boundary, and the production reporting test wrapper
# names a missing prerequisite instead of failing deep inside a build.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CI_WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
RELEASE_WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"
WRAPPER="tests/unit/test-installation-reporting-integration.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aport-ci-bootstrap.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# --- Workflow order -----------------------------------------------------------
TEST_JOB="$TEST_DIR/test-job.yml"
awk '/^jobs:/ { in_jobs = 1; next }
     in_jobs && /^  test:/ { in_test = 1; next }
     in_test && /^  [A-Za-z_-]+:/ { in_test = 0 }
     in_test { print }' "$CI_WORKFLOW" > "$TEST_JOB"
[[ -s "$TEST_JOB" ]] || fail "CI_TEST_JOB_PRESENT: no 'test' job in ci.yml"

require_step() {
    local line
    line="$(grep -n -m1 -- "$2" "$TEST_JOB" | cut -d: -f1)"
    [[ -n "$line" ]] || fail "$1: '$2' is not part of the CI test job"
    printf '%s' "$line"
}

submodules="$(require_step CI_BOOTSTRAP_SUBMODULES 'submodules: recursive')"
setup_node="$(require_step CI_BOOTSTRAP_NODE_RUNTIME 'uses: actions/setup-node@')"
npm_ci="$(require_step CI_BOOTSTRAP_NODE_BEFORE_TESTS 'run: npm ci')"
setup_python="$(require_step CI_BOOTSTRAP_PYTHON_RUNTIME 'uses: actions/setup-python@')"
python_prereqs="$(require_step CI_BOOTSTRAP_PYTHON_BEFORE_TESTS 'Install Python test prerequisites')"
make_test="$(require_step CI_RUNS_MAKE_TEST 'run: make test')"

[[ "$submodules" -lt "$make_test" ]] || fail "CI_BOOTSTRAP_SUBMODULES: submodules initialize after make test"
[[ "$setup_node" -lt "$npm_ci" ]] || fail "CI_BOOTSTRAP_NODE_RUNTIME: npm ci runs before setup-node"
[[ "$npm_ci" -lt "$make_test" ]] || fail "CI_BOOTSTRAP_NODE_BEFORE_TESTS: npm ci runs after make test"
[[ "$setup_python" -lt "$python_prereqs" ]] || fail "CI_BOOTSTRAP_PYTHON_RUNTIME: Python prerequisites install before setup-python"
[[ "$python_prereqs" -lt "$make_test" ]] || fail "CI_BOOTSTRAP_PYTHON_BEFORE_TESTS: Python prerequisites install after make test"
grep -q 'python/aport_guardrails\[dev\]' "$TEST_JOB" || fail "CI_BOOTSTRAP_PYTHON_DECLARED: Python prerequisites are not the declared [dev] extras"
grep -q 'run: npm audit signatures' "$TEST_JOB" || fail "CI_RETAINS_NPM_SIGNATURES: npm audit signatures check was dropped"
grep -q 'check-codex-provider-tool-surface.sh' "$TEST_JOB" || fail "CI_RETAINS_CODEX_SURFACE: Codex provider drift gate was dropped"
grep -q 'test-enterprise-device-scripts.sh' "$TEST_JOB" || fail "CI_RETAINS_ENTERPRISE_BUNDLE: enterprise bundle check was dropped"
job_count="$(awk '/^jobs:/ { in_jobs = 1; next } in_jobs && /^  [A-Za-z_-]+:$/ { count++ } END { print count + 0 }' "$CI_WORKFLOW")"
[[ "$job_count" -eq 1 ]] || fail "CI_SINGLE_TEST_PIPELINE: ci.yml has $job_count jobs instead of reusing the single test job"

# --- Triggers -----------------------------------------------------------------
ON_BLOCK="$TEST_DIR/on.yml"
awk '/^on:/ { in_on = 1; next } in_on && /^[A-Za-z]/ { in_on = 0 } in_on { print }' "$CI_WORKFLOW" > "$ON_BLOCK"
for event in push pull_request; do
    branches="$(awk -v event="$event" '$1 == event":" { found = 1; next } found && /branches:/ { print; exit } found && /^  [a-z_]+:/ { exit }' "$ON_BLOCK")"
    [[ "$branches" == *main* && "$branches" == *staging* ]] \
        || fail "CI_STAGING_TRIGGER: '$event' does not run the full test job for both main and staging (got: ${branches:-none})"
done

# --- Release boundary ---------------------------------------------------------
RELEASE_ON="$TEST_DIR/release-on.yml"
awk '/^on:/ { in_on = 1; next } in_on && /^[A-Za-z]/ { in_on = 0 } in_on { print }' "$RELEASE_WORKFLOW" > "$RELEASE_ON"
if grep -q 'branches:' "$RELEASE_ON"; then
    fail "RELEASE_MAIN_ONLY_BOUNDARY: release.yml gained a branch trigger"
fi
grep -q 'tags:' "$RELEASE_ON" || fail "RELEASE_MAIN_ONLY_BOUNDARY: release.yml no longer triggers on tags"
grep -q 'Verify release ref is main-backed' "$RELEASE_WORKFLOW" || fail "RELEASE_MAIN_ONLY_BOUNDARY: main-backed release check was removed"
grep -q 'git merge-base --is-ancestor "$TAG_SHA" origin/main' "$RELEASE_WORKFLOW" || fail "RELEASE_MAIN_ONLY_BOUNDARY: release tags no longer have to reach origin/main"
if grep -q 'staging' "$RELEASE_WORKFLOW"; then
    fail "RELEASE_MAIN_ONLY_BOUNDARY: release.yml references staging"
fi

# --- Production wrapper in an isolated, dependency-free checkout --------------
ISOLATED="$TEST_DIR/checkout"
mkdir -p "$ISOLATED"
FILE_LIST="$TEST_DIR/tracked-files"
git -C "$REPO_ROOT" ls-files -z -- . ':(exclude)external' > "$FILE_LIST"
(cd "$REPO_ROOT" && tar --null -T "$FILE_LIST" -cf - | tar -C "$ISOLATED" -xf -)
[[ -f "$ISOLATED/$WRAPPER" ]] || fail "ISOLATED_CHECKOUT: wrapper missing from isolated copy"
[[ ! -e "$ISOLATED/node_modules" && ! -e "$ISOLATED/packages/core/dist" ]] || fail "ISOLATED_CHECKOUT: dependency or build output leaked into the isolated copy"

# A PATH with node, npm and python3 but no project or global TypeScript.
RESTRICTED_BIN="$TEST_DIR/bin"
mkdir -p "$RESTRICTED_BIN"
ln -s "$(command -v node)" "$RESTRICTED_BIN/node"
ln -s "$(command -v npm)" "$RESTRICTED_BIN/npm"
ln -s "$(command -v python3)" "$RESTRICTED_BIN/python3"
RESTRICTED_PATH="$RESTRICTED_BIN:/usr/bin:/bin"
if PATH="$RESTRICTED_PATH" command -v tsc > /dev/null 2>&1; then
    fail "ISOLATED_CHECKOUT: restricted PATH still resolves tsc"
fi

run_wrapper() {
    local label="$1" extra_path="$2" expected="$3" output="$TEST_DIR/$1.log"
    set +e
    (cd "$ISOLATED" && PATH="${extra_path:+$extra_path:}$RESTRICTED_PATH" HOME="$TEST_DIR/home" bash "$WRAPPER" > "$output" 2>&1)
    local status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        fail "$expected: wrapper passed without its prerequisites ($label)"
    fi
    grep -q "$expected" "$output" || {
        cat "$output" >&2
        fail "$expected: wrapper failed without naming the missing prerequisite ($label, exit $status)"
    }
}

# 1. No node_modules: the wrapper must name the Node prerequisite, not fail inside tsc.
run_wrapper no-node-modules "" REPORTING_WRAPPER_NODE_PREREQUISITE

# 2. Node dependencies present but no PyYAML: the wrapper must name the Python prerequisite.
mkdir -p "$ISOLATED/node_modules/.bin"
printf '#!/bin/sh\nexit 0\n' > "$ISOLATED/node_modules/.bin/tsc"
chmod +x "$ISOLATED/node_modules/.bin/tsc"
NO_YAML_BIN="$TEST_DIR/no-yaml-bin"
mkdir -p "$NO_YAML_BIN"
cat > "$NO_YAML_BIN/python3" << EOF
#!/bin/bash
# -I -S skips the site module, user packages and PYTHON* variables, so an
# installed PyYAML is invisible exactly as on a runner that never installed it.
exec "$(command -v python3)" -I -S "\$@"
EOF
chmod +x "$NO_YAML_BIN/python3"
run_wrapper no-pyyaml "$NO_YAML_BIN" REPORTING_WRAPPER_PYTHON_PREREQUISITE

echo "PASS: CI provisions Node and Python before make test and the reporting wrapper names missing prerequisites"

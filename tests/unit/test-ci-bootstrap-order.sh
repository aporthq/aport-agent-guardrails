#!/bin/bash
# Regression: CI and release validation provision Node and Python before
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
extract_job() {
    awk -v job="$2" '/^jobs:/ { in_jobs = 1; next }
         in_jobs && /^  [A-Za-z_-]+:/ { in_job = ($1 == job ":") }
         in_job { print }' "$1" > "$3"
    [[ -s "$3" ]] || fail "$4: no '$2' job in $1"
}

require_step() {
    local line
    line="$(grep -n -m1 -- "$3" "$1" | cut -d: -f1 || true)"
    [[ -n "$line" ]] || fail "$2: '$3' is not part of $(basename "$1")"
    printf '%s' "$line"
}

check_bootstrap() {
    local job="$1" label="$2"
    local submodules setup_node npm_ci setup_python python_version prereqs make_test integrity installer_call
    submodules="$(require_step "$job" "${label}_BOOTSTRAP_SUBMODULES" 'submodules: recursive')"
    setup_node="$(require_step "$job" "${label}_BOOTSTRAP_NODE_RUNTIME" 'uses: actions/setup-node@')"
    npm_ci="$(require_step "$job" "${label}_BOOTSTRAP_NODE_BEFORE_TESTS" 'run: npm ci')"
    setup_python="$(require_step "$job" "${label}_BOOTSTRAP_PYTHON_RUNTIME" 'uses: actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065')"
    python_version="$(require_step "$job" "${label}_BOOTSTRAP_PYTHON_VERSION" 'python-version: "3.11"')"
    installer_call='run: bash scripts/install-test-prerequisites.sh'
    if [[ "$label" == RELEASE ]]; then
        installer_call='run: bash "$RUNNER_TEMP/aport-test-prerequisites.sh" "$GITHUB_WORKSPACE"'
    fi
    prereqs="$(require_step "$job" "${label}_BOOTSTRAP_SHARED_INSTALLER" "$installer_call")"
    make_test="$(require_step "$job" "${label}_RUNS_MAKE_TEST" '[[:space:]]make test$')"
    integrity="$(grep -n 'uses: aporthq/policy-verify-action/integrity@' "$job" | tail -1 | cut -d: -f1)"
    [[ -n "$integrity" && "$integrity" -lt "$prereqs" && "$integrity" -lt "$npm_ci" ]] \
        || fail "${label}_BOOTSTRAP_INTEGRITY_FIRST: dependency installation precedes the last integrity check"
    [[ "$submodules" -lt "$make_test" ]] || fail "${label}_BOOTSTRAP_SUBMODULES: submodules initialize after make test"
    [[ "$setup_node" -lt "$npm_ci" ]] || fail "${label}_BOOTSTRAP_NODE_RUNTIME: npm ci runs before setup-node"
    [[ "$npm_ci" -lt "$make_test" ]] || fail "${label}_BOOTSTRAP_NODE_BEFORE_TESTS: npm ci runs after make test"
    [[ "$setup_python" -lt "$python_version" && "$python_version" -lt "$prereqs" ]] \
        || fail "${label}_BOOTSTRAP_PYTHON_RUNTIME: Python 3.11 must be configured before prerequisite installation"
    [[ "$prereqs" -lt "$make_test" ]] || fail "${label}_BOOTSTRAP_PYTHON_BEFORE_TESTS: prerequisites install after make test"
    grep -q 'run: npm audit signatures' "$job" || fail "${label}_RETAINS_NPM_SIGNATURES: npm audit signatures check was dropped"
}

RELEASE_JOB="$TEST_DIR/release-validate.yml"
extract_job "$RELEASE_WORKFLOW" validate "$RELEASE_JOB" RELEASE_VALIDATE_JOB_PRESENT
check_bootstrap "$RELEASE_JOB" RELEASE
preserve="$(require_step "$RELEASE_JOB" RELEASE_BOOTSTRAP_RECOVERY 'run: cp scripts/install-test-prerequisites.sh "$RUNNER_TEMP/aport-test-prerequisites.sh"')"
recover="$(require_step "$RELEASE_JOB" RELEASE_BOOTSTRAP_RECOVERY 'name: Checkout existing release tag for recovery')"
initial_integrity="$(require_step "$RELEASE_JOB" RELEASE_BOOTSTRAP_RECOVERY 'uses: aporthq/policy-verify-action/integrity@')"
[[ "$initial_integrity" -lt "$preserve" && "$preserve" -lt "$recover" ]] \
    || fail "RELEASE_BOOTSTRAP_RECOVERY: preserve the verified helper before checking out an older tag"
TEST_JOB="$TEST_DIR/test-job.yml"
extract_job "$CI_WORKFLOW" test "$TEST_JOB" CI_TEST_JOB_PRESENT
check_bootstrap "$TEST_JOB" CI
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

# Execute the real installer with inert command replacements; never install packages here.
INSTALLER="$REPO_ROOT/scripts/install-test-prerequisites.sh"
[[ -f "$INSTALLER" ]] || fail "BOOTSTRAP_SHARED_INSTALLER: shared installer is missing"
STUB_BIN="$TEST_DIR/install-bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/stub" << 'EOF'
#!/bin/bash
set -euo pipefail
[[ "$PWD" -ef "$BOOTSTRAP_ROOT" ]] || exit 98
printf '%s' "${0##*/}" >> "$BOOTSTRAP_LOG"
printf ' %s' "$@" >> "$BOOTSTRAP_LOG"
printf '\n' >> "$BOOTSTRAP_LOG"
count="$(wc -l < "$BOOTSTRAP_LOG")"
if [[ "$count" -eq "${BOOTSTRAP_FAIL_AT:-0}" ]]; then
    exit 47
fi
EOF
chmod +x "$STUB_BIN/stub"
for command in sudo python; do
    ln -s "$STUB_BIN/stub" "$STUB_BIN/$command"
done
# Reject direct install invocations instead of falling back to tools on the host.
for command in pip pip3 apt-get npm; do
    printf '#!/bin/sh\nexit 99\n' > "$STUB_BIN/$command"
    chmod +x "$STUB_BIN/$command"
done
INSTALL_LOG="$TEST_DIR/install.log"
PATH="$STUB_BIN:$PATH" BOOTSTRAP_LOG="$INSTALL_LOG" BOOTSTRAP_ROOT="$REPO_ROOT" bash "$INSTALLER"
cat > "$TEST_DIR/install-expected.log" << 'EOF'
sudo apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=20 update
sudo apt-get install -y --no-install-recommends curl jq uuid-runtime
python -m pip install --upgrade pip
python -m pip install --disable-pip-version-check --no-input build -e python/aport_guardrails[dev] -e python/langchain_adapter[dev]
python -m pip check
EOF
diff -u "$TEST_DIR/install-expected.log" "$INSTALL_LOG" \
    || fail "BOOTSTRAP_DECLARED_PREREQUISITES: shared installer changed the required commands or their order"
# The recovered tag need not contain this helper; its manifests remain the dependency owner.
RECOVERED="$TEST_DIR/recovered-tag"
mkdir -p "$RECOVERED"
cp "$INSTALLER" "$TEST_DIR/preserved-bootstrap.sh"
: > "$INSTALL_LOG"
PATH="$STUB_BIN:$PATH" BOOTSTRAP_LOG="$INSTALL_LOG" BOOTSTRAP_ROOT="$RECOVERED" \
    bash "$TEST_DIR/preserved-bootstrap.sh" "$RECOVERED"
diff -u "$TEST_DIR/install-expected.log" "$INSTALL_LOG" \
    || fail "BOOTSTRAP_RECOVERY_ROOT: preserved helper did not install from the recovered checkout"
for step in 1 2 3 4 5; do
    : > "$INSTALL_LOG"
    if PATH="$STUB_BIN:$PATH" BOOTSTRAP_LOG="$INSTALL_LOG" BOOTSTRAP_ROOT="$REPO_ROOT" BOOTSTRAP_FAIL_AT="$step" bash "$INSTALLER"; then
        fail "BOOTSTRAP_FAILS_CLOSED: installer ignored failure at step $step"
    fi
    [[ "$(wc -l < "$INSTALL_LOG")" -eq "$step" ]] \
        || fail "BOOTSTRAP_FAILS_CLOSED: installer continued after failure at step $step"
done
echo "PASS: shared installer invokes declared prerequisites; all five failures stop bootstrap"

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

echo "PASS: CI and release provision Node and Python before make test; main-only release and missing-prerequisite failures remain enforced"

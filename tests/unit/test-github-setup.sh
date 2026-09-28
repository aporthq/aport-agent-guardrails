#!/bin/bash
# Unit tests for GitHub one-command setup.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output/github-setup")}"
PROJECT_DIR="$TEST_DIR/project"

mkdir -p "$PROJECT_DIR"
git init -q "$PROJECT_DIR"
chmod +x "$DISPATCHER" "$REPO_ROOT/bin/github.sh" 2> /dev/null || true

echo ""
echo "  Unit — GitHub setup"
echo ""

out1="$TEST_DIR/github-1.txt"
"$DISPATCHER" github --project-dir "$PROJECT_DIR" --policy > "$out1" 2>&1
help_out="$TEST_DIR/github-help.txt"
"$DISPATCHER" github --help > "$help_out" 2>&1

WORKFLOW="$PROJECT_DIR/.github/workflows/aport-guard.yml"
POLICY="$PROJECT_DIR/.aport/policy.yaml"

[[ -f "$WORKFLOW" ]] || {
    echo "FAIL: expected workflow to be created" >&2
    cat "$out1" >&2
    exit 1
}
[[ -f "$POLICY" ]] || {
    echo "FAIL: expected policy to be created with --policy" >&2
    cat "$out1" >&2
    exit 1
}
grep -q "uses: aporthq/policy-verify-action@v1" "$WORKFLOW" || {
    echo "FAIL: workflow should use aporthq/policy-verify-action@v1" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q "id-token: write" "$WORKFLOW" || {
    echo "FAIL: auto mode should request GitHub OIDC permission" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q "mode: auto" "$WORKFLOW" || {
    echo "FAIL: workflow should default to mode: auto" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q "push:" "$WORKFLOW" && grep -q '      - "main"' "$WORKFLOW" || {
    echo "FAIL: workflow should watch pushes to main by default" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q "pull_request_review:" "$WORKFLOW" && grep -q "merge_group:" "$WORKFLOW" || {
    echo "FAIL: workflow should cover reviews and merge queue events" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
if grep -q "actions/checkout" "$WORKFLOW"; then
    echo "FAIL: workflow should not require checkout for auto mode" >&2
    cat "$WORKFLOW" >&2
    exit 1
fi
if grep -q "APORT_API_KEY\|curl .*bash\|curl | bash" "$WORKFLOW" "$POLICY" "$out1" "$help_out"; then
    echo "FAIL: setup must not require API keys or curl | bash" >&2
    cat "$out1" >&2
    cat "$help_out" >&2
    exit 1
fi
grep -q "Next steps (GitHub)" "$out1" || {
    echo "FAIL: expected clear next steps" >&2
    cat "$out1" >&2
    exit 1
}
echo "  ✅ github target writes workflow and optional policy"

printf 'custom workflow\n' > "$WORKFLOW"
printf 'custom policy\n' > "$POLICY"
out2="$TEST_DIR/github-2.txt"
"$DISPATCHER" github --project-dir "$PROJECT_DIR" --policy > "$out2" 2>&1
grep -q "custom workflow" "$WORKFLOW" || {
    echo "FAIL: existing workflow should not be clobbered by default" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q "custom policy" "$POLICY" || {
    echo "FAIL: existing policy should not be clobbered by default" >&2
    cat "$POLICY" >&2
    exit 1
}
grep -q "already exists; leaving unchanged" "$out2" || {
    echo "FAIL: expected skip message for existing files" >&2
    cat "$out2" >&2
    exit 1
}
echo "  ✅ github target preserves existing files by default"

out3="$TEST_DIR/github-3.txt"
"$DISPATCHER" github --project-dir "$PROJECT_DIR" --policy --force > "$out3" 2>&1
grep -q "uses: aporthq/policy-verify-action@v1" "$WORKFLOW" || {
    echo "FAIL: --force should rewrite workflow" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q "version: oap-github-policy/1" "$POLICY" || {
    echo "FAIL: --force should rewrite policy" >&2
    cat "$POLICY" >&2
    exit 1
}
echo "  ✅ --force explicitly overwrites generated files"

out4="$TEST_DIR/github-4.txt"
"$DISPATCHER" github \
    --project-dir "$PROJECT_DIR" \
    --force \
    --mode hosted \
    --branches "main,staging" \
    --block-protected-paths \
    --protected-paths ".github/workflows/**,.aport/**,bin/**,packages/**,scripts/**,package.json" > "$out4" 2>&1
grep -q "mode: hosted" "$WORKFLOW" || {
    echo "FAIL: --mode should update workflow mode" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q '      - "staging"' "$WORKFLOW" || {
    echo "FAIL: --branches should include staging" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q "protected-paths: >-" "$WORKFLOW" && grep -q ".github/workflows/\\*\\*,.aport/\\*\\*,bin/\\*\\*,packages/\\*\\*,scripts/\\*\\*,package.json" "$WORKFLOW" || {
    echo "FAIL: --protected-paths should pass custom protected path globs" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q "block-protected-paths: true" "$WORKFLOW" || {
    echo "FAIL: --block-protected-paths should enable protected-path blocking" >&2
    cat "$WORKFLOW" >&2
    exit 1
}
grep -q "Protected path globs" "$out4" || {
    echo "FAIL: expected next steps to mention protected path globs" >&2
    cat "$out4" >&2
    exit 1
}
grep -q "Protected path changes will fail hosted verification" "$out4" || {
    echo "FAIL: expected next steps to mention protected-path blocking" >&2
    cat "$out4" >&2
    exit 1
}
echo "  ✅ mode, branch, and protected-path options are reflected in generated workflow"

out4b="$TEST_DIR/github-4b.txt"
"$DISPATCHER" github --project-dir "$PROJECT_DIR" --force --mode evidence-only > "$out4b" 2>&1
if grep -q "id-token: write" "$WORKFLOW"; then
    echo "FAIL: evidence-only mode should not request GitHub OIDC permission" >&2
    cat "$WORKFLOW" >&2
    exit 1
fi
echo "  ✅ evidence-only mode does not request OIDC permission"

PROJECT_DIR_ALIAS="$TEST_DIR/project-alias"
mkdir -p "$PROJECT_DIR_ALIAS"
git init -q "$PROJECT_DIR_ALIAS"
out5="$TEST_DIR/github-5.txt"
"$DISPATCHER" --framework=github --project-dir "$PROJECT_DIR_ALIAS" > "$out5" 2>&1
[[ -f "$PROJECT_DIR_ALIAS/.github/workflows/aport-guard.yml" ]] || {
    echo "FAIL: --framework=github should route to the GitHub setup target" >&2
    cat "$out5" >&2
    exit 1
}
echo "  ✅ --framework=github routes to the project setup target"

NESTED_REPO="$TEST_DIR/nested-project"
mkdir -p "$NESTED_REPO/packages/app"
git init -q "$NESTED_REPO"
out6="$TEST_DIR/github-6.txt"
"$DISPATCHER" github --project-dir "$NESTED_REPO/packages/app" > "$out6" 2>&1
[[ -f "$NESTED_REPO/.github/workflows/aport-guard.yml" ]] || {
    echo "FAIL: nested project setup should write workflow at git root" >&2
    cat "$out6" >&2
    exit 1
}
[[ ! -f "$NESTED_REPO/packages/app/.github/workflows/aport-guard.yml" ]] || {
    echo "FAIL: nested project setup must not write workflow under cwd subdir" >&2
    exit 1
}
echo "  ✅ nested project setup resolves the git root"

LOCAL_JSON_REPO="$TEST_DIR/local-json-project"
mkdir -p "$LOCAL_JSON_REPO"
git init -q "$LOCAL_JSON_REPO"
out7="$TEST_DIR/github-7.txt"
set +e
"$DISPATCHER" github --project-dir "$LOCAL_JSON_REPO" --mode local-json > "$out7" 2>&1
e7=$?
set -e
[[ "$e7" -ne 0 ]] || {
    echo "FAIL: local-json should fail when trusted passport file is missing" >&2
    cat "$out7" >&2
    exit 1
}
grep -q "requires a trusted passport file" "$out7" || {
    echo "FAIL: expected clear local-json passport error" >&2
    cat "$out7" >&2
    exit 1
}
mkdir -p "$LOCAL_JSON_REPO/.aport"
printf '{"spec_version":"oap/1.0","agent_id":"ap_test"}\n' > "$LOCAL_JSON_REPO/.aport/passport.json"
out8="$TEST_DIR/github-8.txt"
"$DISPATCHER" github --project-dir "$LOCAL_JSON_REPO" --mode local-json > "$out8" 2>&1
grep -q 'passport-path: ".aport/passport.json"' "$LOCAL_JSON_REPO/.github/workflows/aport-guard.yml" || {
    echo "FAIL: local-json workflow should include trusted passport path" >&2
    cat "$LOCAL_JSON_REPO/.github/workflows/aport-guard.yml" >&2
    exit 1
}
if grep -q "actions/checkout@v4" "$LOCAL_JSON_REPO/.github/workflows/aport-guard.yml"; then
    echo "FAIL: local-json workflow should not checkout PR-controlled repository content" >&2
    cat "$LOCAL_JSON_REPO/.github/workflows/aport-guard.yml" >&2
    exit 1
fi
echo "  ✅ local-json requires and emits a trusted passport path"

SYMLINK_REPO="$TEST_DIR/symlink-project"
SYMLINK_TARGET="$TEST_DIR/symlink-target.yml"
mkdir -p "$SYMLINK_REPO/.github/workflows"
git init -q "$SYMLINK_REPO"
ln -s "$SYMLINK_TARGET" "$SYMLINK_REPO/.github/workflows/aport-guard.yml"
out9="$TEST_DIR/github-9.txt"
set +e
"$DISPATCHER" github --project-dir "$SYMLINK_REPO" --force > "$out9" 2>&1
e9=$?
set -e
[[ "$e9" -ne 0 ]] || {
    echo "FAIL: setup should refuse writing through a workflow symlink" >&2
    cat "$out9" >&2
    exit 1
}
grep -q "Refusing to write through symlink" "$out9" || {
    echo "FAIL: expected symlink refusal message" >&2
    cat "$out9" >&2
    exit 1
}
[[ ! -e "$SYMLINK_TARGET" ]] || {
    echo "FAIL: symlink target should not be created or modified" >&2
    exit 1
}
echo "  ✅ setup refuses symlink overwrite targets"

NEWLINE_REPO="$TEST_DIR/newline-project"
mkdir -p "$NEWLINE_REPO"
git init -q "$NEWLINE_REPO"
out10="$TEST_DIR/github-10.txt"
set +e
"$DISPATCHER" github --project-dir "$NEWLINE_REPO" --branches $'main\npermissions: write-all' > "$out10" 2>&1
e10=$?
set -e
[[ "$e10" -ne 0 ]] || {
    echo "FAIL: setup should reject branch values containing newlines" >&2
    cat "$out10" >&2
    exit 1
}
grep -q "single-line list" "$out10" || {
    echo "FAIL: expected clear newline branch error" >&2
    cat "$out10" >&2
    exit 1
}
echo "  ✅ branch input rejects CR/LF injection"

PROTECTED_NEWLINE_REPO="$TEST_DIR/protected-newline-project"
mkdir -p "$PROTECTED_NEWLINE_REPO"
git init -q "$PROTECTED_NEWLINE_REPO"
out11="$TEST_DIR/github-11.txt"
set +e
"$DISPATCHER" github --project-dir "$PROTECTED_NEWLINE_REPO" --protected-paths $'.github/**\npermissions: write-all' > "$out11" 2>&1
e11=$?
set -e
[[ "$e11" -ne 0 ]] || {
    echo "FAIL: setup should reject protected-path values containing newlines" >&2
    cat "$out11" >&2
    exit 1
}
grep -q "protected-paths must be a comma-separated single-line list" "$out11" || {
    echo "FAIL: expected clear newline protected-paths error" >&2
    cat "$out11" >&2
    exit 1
}
echo "  ✅ protected-path input rejects CR/LF injection"

# YAML parse helper: prefers PyYAML, falls back to js-yaml from the repo, else skips.
parse_yaml() {
    if python3 -c 'import yaml' 2> /dev/null; then
        python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$1"
    elif NODE_PATH="$REPO_ROOT/node_modules" node -e 'require("js-yaml")' 2> /dev/null; then
        NODE_PATH="$REPO_ROOT/node_modules" node -e 'require("js-yaml").load(require("fs").readFileSync(process.argv[1], "utf8"))' "$1"
    else
        echo "  (no YAML parser available; skipping parse of $1)"
    fi
}

PROTECT_REPO="$TEST_DIR/protect-project"
mkdir -p "$PROTECT_REPO"
git init -q "$PROTECT_REPO"
PROTECT_WORKFLOW="$PROTECT_REPO/.github/workflows/aport-guard.yml"
out12="$TEST_DIR/github-12.txt"
"$DISPATCHER" github --project-dir "$PROTECT_REPO" > "$out12" 2>&1
if grep -q "protect-default-branch" "$PROTECT_WORKFLOW"; then
    echo "FAIL: default-branch protection must be opt-in" >&2
    cat "$PROTECT_WORKFLOW" >&2
    exit 1
fi
grep -q "^concurrency:" "$PROTECT_WORKFLOW" && grep -q "cancel-in-progress: \${{ github.event_name == 'pull_request' }}" "$PROTECT_WORKFLOW" || {
    echo "FAIL: workflow should cancel superseded pull_request runs only" >&2
    cat "$PROTECT_WORKFLOW" >&2
    exit 1
}
parse_yaml "$PROTECT_WORKFLOW" || {
    echo "FAIL: default generated workflow must be valid YAML" >&2
    cat "$PROTECT_WORKFLOW" >&2
    exit 1
}
echo "  ✅ default workflow parses and leaves default-branch protection off"

out13="$TEST_DIR/github-13.txt"
"$DISPATCHER" github --project-dir "$PROTECT_REPO" --force --protect-default-branch > "$out13" 2>&1
grep -q "protect-default-branch: true" "$PROTECT_WORKFLOW" || {
    echo "FAIL: --protect-default-branch should pass the protect-default-branch input to the Action" >&2
    cat "$PROTECT_WORKFLOW" >&2
    exit 1
}
if grep -q "name: Protect default branch" "$PROTECT_WORKFLOW"; then
    echo "FAIL: protection belongs to the Action; no inline step should be rendered" >&2
    cat "$PROTECT_WORKFLOW" >&2
    exit 1
fi
grep -q "Default-branch protection" "$out13" || {
    echo "FAIL: expected next steps to mention default-branch protection" >&2
    cat "$out13" >&2
    exit 1
}
parse_yaml "$PROTECT_WORKFLOW" || {
    echo "FAIL: workflow with default-branch protection must be valid YAML" >&2
    cat "$PROTECT_WORKFLOW" >&2
    exit 1
}
echo "  ✅ --protect-default-branch passes the input to the Action and renders parseable YAML"

out14="$TEST_DIR/github-14.txt"
APORT_GITHUB_PROTECT_DEFAULT_BRANCH=true "$DISPATCHER" github --project-dir "$PROTECT_REPO" --force > "$out14" 2>&1
grep -q "protect-default-branch: true" "$PROTECT_WORKFLOW" || {
    echo "FAIL: APORT_GITHUB_PROTECT_DEFAULT_BRANCH=true should enable the protect-default-branch input" >&2
    cat "$PROTECT_WORKFLOW" >&2
    exit 1
}
out15="$TEST_DIR/github-15.txt"
set +e
APORT_GITHUB_PROTECT_DEFAULT_BRANCH=maybe "$DISPATCHER" github --project-dir "$PROTECT_REPO" --force > "$out15" 2>&1
e15=$?
set -e
[[ "$e15" -ne 0 ]] || {
    echo "FAIL: invalid APORT_GITHUB_PROTECT_DEFAULT_BRANCH value should be rejected" >&2
    cat "$out15" >&2
    exit 1
}
echo "  ✅ APORT_GITHUB_PROTECT_DEFAULT_BRANCH env toggles and validates"

REPO_WORKFLOW="$REPO_ROOT/.github/workflows/aport-repository-guard.yml"
parse_yaml "$REPO_WORKFLOW" || {
    echo "FAIL: repository guard workflow must be valid YAML" >&2
    exit 1
}
grep -Eq "uses: aporthq/policy-verify-action@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+" "$REPO_WORKFLOW" || {
    echo "FAIL: repository guard workflow should pin the action to a commit SHA with a version comment" >&2
    exit 1
}
grep -q "vars.APORT_PROTECT_DEFAULT_BRANCH == 'true'" "$REPO_WORKFLOW" || {
    echo "FAIL: repository guard workflow should gate default-branch protection on a repository variable" >&2
    exit 1
}
# At the v1.0.11 pin the Action ignores protect-default-branch, so push must never fail the run: the enforce
# step is gated on the event alone and the push warning step runs regardless of earlier step outcomes.
grep -q "github.event_name != 'push' &&" "$REPO_WORKFLOW" || {
    echo "FAIL: repository guard workflow must not fail push events at the v1.0.11 pin" >&2
    exit 1
}
if grep -Eq "^[[:space:]]+\(github.event_name != 'push' \|\| vars.APORT_PROTECT_DEFAULT_BRANCH == 'true'\) &&" "$REPO_WORKFLOW"; then
    echo "FAIL: the push-failing condition must stay in the comment until the pin honours protect-default-branch" >&2
    exit 1
fi
grep -A3 "name: Record push audit warning" "$REPO_WORKFLOW" | grep -q "always()" || {
    echo "FAIL: the push audit warning step must run with always()" >&2
    exit 1
}
echo "  ✅ repository guard workflow parses, pins by SHA, and gates default-branch protection"

echo ""
echo "  All GitHub setup tests passed."
echo ""

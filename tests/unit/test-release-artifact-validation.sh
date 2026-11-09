#!/bin/bash
# Regression: artifact inspection must require the shared reporter to be present, not just byte-identical
# where it happens to appear.
#
# Comparing only the entries an archive already contains means an archive that omits the reporter directory
# passes with zero files compared. This builds synthetic archives in a temporary directory and asserts the
# validator rejects a package that must bundle the reporter but does not, accepts a dependency-only adapter
# that legitimately ships none, and rejects an entirely missing bundling artifact.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-release-artifacts.mjs"
REPORTER_DIR="$REPO_ROOT/src/installation-reporting"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/aport-release-artifacts.XXXXXX")}"
mkdir -p "$TEST_DIR"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

echo ""
echo "  Unit - release artifact reporter completeness"
echo ""

command -v node > /dev/null || fail "node is required"
[ -f "$VALIDATOR" ] || fail "missing scripts/validate-release-artifacts.mjs"

VERSION="$(node -p "require('$REPO_ROOT/packages/core/package.json').version")"

# Build a .tgz shaped like `npm pack` output: everything under a top-level package/ directory.
# $1 output dir, $2 published name, $3 reporter root inside package/ ("" to omit the reporter entirely)
make_tarball() {
    local out_dir="$1" name="$2" reporter_root="$3"
    local stage="$TEST_DIR/stage-$(echo "$name" | tr '/@' '__')"
    rm -rf "$stage"
    mkdir -p "$stage/package"
    node -e '
const { writeFileSync } = require("fs");
writeFileSync(process.argv[1], JSON.stringify({ name: process.argv[2], version: process.argv[3] }, null, 2));
' "$stage/package/package.json" "$name" "$VERSION"
    if [ -n "$reporter_root" ]; then
        mkdir -p "$stage/package/$reporter_root"
        cp "$REPORTER_DIR"/*.js "$stage/package/$reporter_root/"
    fi
    mkdir -p "$out_dir"
    local tarname
    tarname="$(echo "$name" | sed 's|^@||; s|/|-|g')-$VERSION.tgz"
    (cd "$stage" && tar -czf "$out_dir/$tarname" package)
}

# The validator also inspects the real Python wheels and enterprise bundle, so its exit status covers more than
# the synthetic npm set. Only the reporter-completeness diagnostics are asserted here, by message.
run_validator() {
    local npm_dir="$1" log="$2"
    set +e
    node "$VALIDATOR" --npm-dir "$npm_dir" --out "$TEST_DIR/evidence.json" > "$log" 2>&1
    VALIDATOR_EXIT=$?
    set -e
}

# 1. A package that must bundle the reporter but ships none is rejected, naming the missing files.
MISSING_DIR="$TEST_DIR/npm-missing"
rm -rf "$MISSING_DIR"
make_tarball "$MISSING_DIR" "@aporthq/aport-agent-guardrails-core" ""
run_validator "$MISSING_DIR" "$TEST_DIR/missing.log"
[ "$VALIDATOR_EXIT" -ne 0 ] || fail "REQUIRES_REPORTER_PRESENT: an archive with no reporter was accepted"
grep -q "must bundle the shared reporter at package/dist/installation-reporting" "$TEST_DIR/missing.log" \
    || {
        echo "FAIL: REQUIRES_REPORTER_PRESENT: no completeness diagnostic" >&2
        cat "$TEST_DIR/missing.log" >&2
        exit 1
    }
echo "  OK REQUIRES_REPORTER_PRESENT: a core archive without the reporter is rejected"

# 2. A partial reporter directory is rejected too: the inventory must be complete, not merely non-empty.
PARTIAL_DIR="$TEST_DIR/npm-partial"
rm -rf "$PARTIAL_DIR"
make_tarball "$PARTIAL_DIR" "@aporthq/aport-agent-guardrails-core" "dist/installation-reporting"
PARTIAL_STAGE="$TEST_DIR/stage-_aporthq_aport-agent-guardrails-core"
rm -f "$PARTIAL_STAGE/package/dist/installation-reporting/worker.js"
rm -f "$PARTIAL_DIR"/*.tgz
(cd "$PARTIAL_STAGE" && tar -czf "$PARTIAL_DIR/aporthq-aport-agent-guardrails-core-$VERSION.tgz" package)
run_validator "$PARTIAL_DIR" "$TEST_DIR/partial.log"
[ "$VALIDATOR_EXIT" -ne 0 ] || fail "REQUIRES_COMPLETE_REPORTER: a partial reporter inventory was accepted"
grep -q "missing 1/" "$TEST_DIR/partial.log" \
    || {
        echo "FAIL: REQUIRES_COMPLETE_REPORTER: partial inventory not reported" >&2
        cat "$TEST_DIR/partial.log" >&2
        exit 1
    }
grep -q "worker.js" "$TEST_DIR/partial.log" || fail "REQUIRES_COMPLETE_REPORTER: missing file not named"
echo "  OK REQUIRES_COMPLETE_REPORTER: a partial reporter inventory is rejected and the gap is named"

# 3. A dependency-only adapter legitimately ships no reporter and must not be flagged for it.
ADAPTER_DIR="$TEST_DIR/npm-adapter"
rm -rf "$ADAPTER_DIR"
make_tarball "$ADAPTER_DIR" "@aporthq/aport-agent-guardrails-langchain" ""
run_validator "$ADAPTER_DIR" "$TEST_DIR/adapter.log"
grep -q "aport-agent-guardrails-langchain must bundle the shared reporter" "$TEST_DIR/adapter.log" \
    && fail "ADAPTER_MAY_OMIT_REPORTER: a dependency-only adapter was required to bundle the reporter"
echo "  OK ADAPTER_MAY_OMIT_REPORTER: a dependency-only adapter is not required to bundle the reporter"

# 4. An omitted bundling artifact cannot produce successful evidence by simply not being inspected.
grep -q "@aporthq/aport-agent-guardrails must bundle the shared reporter but no .* artifact was inspected" \
    "$TEST_DIR/adapter.log" \
    || {
        echo "FAIL: REQUIRES_BUNDLING_ARTIFACTS: an omitted bundling package was not reported" >&2
        cat "$TEST_DIR/adapter.log" >&2
        exit 1
    }
echo "  OK REQUIRES_BUNDLING_ARTIFACTS: an uninspected bundling package is reported"

echo ""
echo "  All release artifact validation tests passed."

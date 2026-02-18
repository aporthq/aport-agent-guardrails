#!/bin/bash
# Unit tests for Story A: framework detection (bin/lib/detect.sh).
# Covers detect_framework, detect_frameworks_list, and conflict (multiple detected).
# Usage: ./test-detect-framework.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$REPO_ROOT/bin/lib"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2>/dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"

# shellcheck source=../../bin/lib/detect.sh
source "$LIB_DIR/detect.sh"

assert_eq() {
  local actual="$1" expected="$2" msg="${3:-expected '$expected', got '$actual'}"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $msg" >&2
    exit 1
  fi
}

# Assert list contains exactly these words (order-independent for "contains")
assert_list_contains() {
  local list="$1" word="$2"
  [[ " $list " == *" $word "* ]] || { echo "FAIL: list '$list' should contain '$word'" >&2; exit 1; }
}

echo ""
echo "  Unit — bin/lib/detect.sh (detect_framework + detect_frameworks_list)"
echo "  Test dir: $TEST_DIR"
echo ""

# 1. Empty dir -> empty
dir_empty="$TEST_DIR/empty"
mkdir -p "$dir_empty"
assert_eq "$(detect_framework "$dir_empty")" "" "empty dir"
assert_eq "$(detect_frameworks_list "$dir_empty")" "" "empty dir list"
echo "  ✅ empty dir -> ''"

# 2. Single: pyproject langchain
dir_lc="$TEST_DIR/langchain-py"
mkdir -p "$dir_lc"
echo 'dependencies = ["langchain"]' > "$dir_lc/pyproject.toml"
assert_eq "$(detect_framework "$dir_lc")" "langchain" "single langchain"
assert_eq "$(detect_frameworks_list "$dir_lc")" "langchain" "list langchain"
echo "  ✅ pyproject (langchain) -> langchain"

# 3. Single: package.json openclaw
dir_oc="$TEST_DIR/openclaw-js"
mkdir -p "$dir_oc"
echo '{"dependencies":{"openclaw":"^1.0.0"}}' > "$dir_oc/package.json"
assert_eq "$(detect_framework "$dir_oc")" "openclaw" "single openclaw"
assert_eq "$(detect_frameworks_list "$dir_oc")" "openclaw" "list openclaw"
echo "  ✅ package.json (openclaw) -> openclaw"

# 4. Conflict: both langchain and openclaw (pyproject + package.json)
dir_both="$TEST_DIR/both"
mkdir -p "$dir_both"
echo 'dependencies = ["langchain"]' > "$dir_both/pyproject.toml"
echo '{"dependencies":{"openclaw":"x"}}' > "$dir_both/package.json"
first="$(detect_framework "$dir_both")"
list="$(detect_frameworks_list "$dir_both")"
assert_eq "$first" "langchain" "first detected in conflict (pyproject before package.json)"
assert_list_contains "$list" "langchain"
assert_list_contains "$list" "openclaw"
[[ $(echo "$list" | wc -w) -eq 2 ]] || { echo "FAIL: list should have 2 words" >&2; exit 1; }
echo "  ✅ conflict (langchain + openclaw) -> list has both, first=langchain"

# 5. Conflict: langchain + crewai in same pyproject
dir_lc_cr="$TEST_DIR/langchain-crewai"
mkdir -p "$dir_lc_cr"
echo 'dependencies = ["langchain", "crewai"]' > "$dir_lc_cr/pyproject.toml"
first2="$(detect_framework "$dir_lc_cr")"
list2="$(detect_frameworks_list "$dir_lc_cr")"
assert_list_contains "$list2" "langchain"
assert_list_contains "$list2" "crewai"
assert_eq "$first2" "langchain" "first in pyproject is langchain (before crewai)"
echo "  ✅ conflict (langchain + crewai in pyproject) -> list has both"

# 6. Nonexistent dir -> empty
assert_eq "$(detect_framework "$TEST_DIR/nonexistent")" "" "nonexistent"
echo "  ✅ nonexistent dir -> ''"

echo ""
echo "  All detect_framework / detect_frameworks_list tests passed."
echo ""

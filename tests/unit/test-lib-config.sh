#!/bin/bash
# Unit tests for bin/lib/config.sh: get_config_dir, write_config_template.
# Uses a temp dir for config write so we don't touch ~/.aport or ~/.openclaw.
# Usage: ./test-lib-config.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$REPO_ROOT/bin/lib"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2>/dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"

# Override HOME so get_config_dir and write_config_template use our temp dir
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"

# shellcheck source=../../bin/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=../../bin/lib/config.sh
source "$LIB_DIR/config.sh"

assert_eq() {
  local actual="$1" expected="$2" msg="${3:-}"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $msg (expected '$expected', got '$actual')" >&2
    exit 1
  fi
}

echo ""
echo "  Unit — bin/lib/config.sh"
echo "  Test dir: $TEST_DIR"
echo ""

# get_config_dir openclaw -> $HOME/.openclaw (or APORT_OPENCLAW_CONFIG_DIR)
got=$(get_config_dir openclaw)
[[ "$got" == *".openclaw"* ]] || { echo "FAIL: get_config_dir openclaw" >&2; exit 1; }
echo "  ✅ get_config_dir openclaw"

# get_config_dir langchain -> $HOME/.aport/langchain
got=$(get_config_dir langchain)
[[ "$got" == *".aport"* ]] && [[ "$got" == *"langchain"* ]] || { echo "FAIL: get_config_dir langchain" >&2; exit 1; }
echo "  ✅ get_config_dir langchain"

# get_config_dir crewai -> .aport/crewai
got=$(get_config_dir crewai)
[[ "$got" == *"crewai"* ]] || { echo "FAIL: get_config_dir crewai" >&2; exit 1; }
echo "  ✅ get_config_dir crewai"

# get_config_dir cursor -> $HOME/.cursor (where Cursor stores hooks)
got=$(get_config_dir cursor)
[[ "$got" == *"cursor"* ]] || { echo "FAIL: get_config_dir cursor" >&2; exit 1; }
echo "  ✅ get_config_dir cursor"

# get_default_passport_path: returns config_dir/aport/passport.json per framework
got=$(get_default_passport_path cursor)
[[ "$got" == *"/aport/passport.json"* ]] && [[ "$got" == *"cursor"* ]] || { echo "FAIL: get_default_passport_path cursor" >&2; exit 1; }
got=$(get_default_passport_path openclaw)
[[ "$got" == *"/aport/passport.json"* ]] && [[ "$got" == *"openclaw"* ]] || { echo "FAIL: get_default_passport_path openclaw" >&2; exit 1; }
echo "  ✅ get_default_passport_path cursor / openclaw"

# write_config_template creates directory and echoes path (stderr has log_info)
written=$(write_config_template langchain 2>/dev/null)
[[ -n "$written" ]] || { echo "FAIL: write_config_template should echo path" >&2; exit 1; }
[[ -d "$written" ]] || { echo "FAIL: write_config_template should create dir: $written" >&2; exit 1; }
[[ "$written" == *"langchain"* ]] || { echo "FAIL: write_config_template path" >&2; exit 1; }
echo "  ✅ write_config_template langchain creates dir"

# write_config_template n8n
written2=$(write_config_template n8n 2>/dev/null)
[[ -d "$written2" ]] || { echo "FAIL: write_config_template n8n: $written2" >&2; exit 1; }
echo "  ✅ write_config_template n8n"

echo ""
echo "  All config.sh tests passed."
echo ""

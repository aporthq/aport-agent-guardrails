#!/bin/bash
# Unit/integration tests for Story A: agent-guardrails dispatcher.
# Covers: --framework=, -f, pass-through args, unknown framework, -f without value,
# non-interactive (APORT_NONINTERACTIVE/CI), APORT_FRAMEWORK, multiple detected conflict.
# Usage: ./test-agent-guardrails-dispatcher.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"
# Empty dir for "no detection" and "conflict" tests so cwd doesn't affect detection
EMPTY_DIR="$TEST_DIR/empty_cwd"
mkdir -p "$EMPTY_DIR"

chmod +x "$DISPATCHER" 2> /dev/null || true
chmod +x "$REPO_ROOT/bin/frameworks/"*.sh 2> /dev/null || true

run_dispatcher() {
    local outfile="$1" cwd="${2:-}"
    shift 2
    set +e
    if [[ -n "$cwd" ]]; then
        (cd "$cwd" && "$DISPATCHER" "$@" < /dev/null > "$outfile" 2>&1)
    else
        "$DISPATCHER" "$@" < /dev/null > "$outfile" 2>&1
    fi
    DISPATCHER_EXIT=$?
    set -e
}

echo ""
echo "  Unit/Integration — agent-guardrails dispatcher"
echo "  Dispatcher: $DISPATCHER"
echo ""

# 1. --framework=openclaw invalid_agent_id -> openclaw receives arg, rejects (pass-through)
echo "  Test: --framework=openclaw invalid_agent_id (pass-through)..."
out1="$TEST_DIR/dispatcher-1.txt"
run_dispatcher "$out1" "" --framework=openclaw invalid_agent_id
[[ "$DISPATCHER_EXIT" -ne 0 ]] || {
    echo "FAIL: expected non-zero" >&2
    exit 1
}
grep -q "Invalid agent_id format" "$out1" || {
    echo "FAIL: openclaw should receive invalid_agent_id" >&2
    cat "$out1" >&2
    exit 1
}
echo "  ✅ --framework=openclaw invalid_agent_id -> pass-through and reject"

# 2. -f openclaw invalid_agent_id
out2="$TEST_DIR/dispatcher-2.txt"
run_dispatcher "$out2" "" -f openclaw invalid_agent_id
[[ "$DISPATCHER_EXIT" -ne 0 ]] || {
    echo "FAIL: expected non-zero" >&2
    exit 1
}
grep -q "Invalid agent_id format" "$out2" || {
    echo "FAIL: -f openclaw pass-through" >&2
    exit 1
}
echo "  ✅ -f openclaw invalid_agent_id -> pass-through"

# 3. Positional: openclaw invalid_agent_id -> openclaw receives args (use APORT_FRAMEWORK to skip detection).
out3="$TEST_DIR/dispatcher-3.txt"
set +e
APORT_FRAMEWORK=openclaw APORT_NONINTERACTIVE=1 "$DISPATCHER" openclaw invalid_agent_id > "$out3" 2>&1
DISPATCHER_EXIT=$?
set -e
[[ "$DISPATCHER_EXIT" -ne 0 ]] || {
    echo "FAIL: expected non-zero" >&2
    exit 1
}
grep -q "Invalid agent_id format" "$out3" || {
    echo "FAIL: openclaw should get args from empty cwd" >&2
    cat "$out3" >&2
    exit 1
}
echo "  ✅ openclaw invalid_agent_id (empty cwd) -> openclaw receives args"

# 4. Unknown framework -> exit 1 and error message
out4="$TEST_DIR/dispatcher-4.txt"
run_dispatcher "$out4" "" --framework=nosuchframework
[[ "$DISPATCHER_EXIT" -ne 0 ]] || {
    echo "FAIL: unknown framework should exit 1" >&2
    exit 1
}
grep -qi "unknown\|unsupported\|nosuchframework" "$out4" || {
    echo "FAIL: error message" >&2
    exit 1
}
echo "  ✅ unknown framework -> exit 1"

# 5. -f without value -> exit 1
out5="$TEST_DIR/dispatcher-5.txt"
run_dispatcher "$out5" "" -f
[[ "$DISPATCHER_EXIT" -ne 0 ]] || {
    echo "FAIL: -f without value" >&2
    exit 1
}
grep -q "requires a value\|ERROR" "$out5" || {
    echo "FAIL: -f error message" >&2
    exit 1
}
echo "  ✅ -f without value -> exit 1"

# 6. Non-interactive: no detection -> exit 1 and hint (APORT_NONINTERACTIVE=1)
#    Restrict PATH and HOME so host `claude` binary / ~/.claude don't trigger auto-detection
CLEAN_HOME="$TEST_DIR/clean_home"
mkdir -p "$CLEAN_HOME"
out6="$TEST_DIR/dispatcher-6.txt"
set +e
PATH="/usr/bin:/bin" HOME="$CLEAN_HOME" APORT_NONINTERACTIVE=1 APORT_PROJECT_DIR="$EMPTY_DIR" "$DISPATCHER" < /dev/null > "$out6" 2>&1
e6=$?
set -e
[[ "$e6" -ne 0 ]] || {
    echo "FAIL: non-interactive no detection should exit 1" >&2
    exit 1
}
grep -q "No framework detected\|APORT_FRAMEWORK\|--framework" "$out6" || {
    echo "FAIL: non-interactive message" >&2
    cat "$out6" >&2
    exit 1
}
echo "  ✅ Non-interactive (no detection) -> exit 1 and hint"

# 7. Non-interactive: APORT_FRAMEWORK overrides -> runs framework
out7="$TEST_DIR/dispatcher-7.txt"
run_dispatcher "$out7" "" # we can't set env in run_dispatcher for exec'd process; run inline
set +e
APORT_NONINTERACTIVE=1 APORT_FRAMEWORK=openclaw APORT_PROJECT_DIR="$EMPTY_DIR" "$DISPATCHER" invalid_agent_id < /dev/null > "$out7" 2>&1
e7=$?
set -e
[[ "$e7" -ne 0 ]] || {
    echo "FAIL: openclaw with invalid_agent_id should exit 1" >&2
    exit 1
}
grep -q "Invalid agent_id format" "$out7" || {
    echo "FAIL: APORT_FRAMEWORK=openclaw should run openclaw" >&2
    cat "$out7" >&2
    exit 1
}
echo "  ✅ APORT_FRAMEWORK=openclaw -> runs openclaw (non-interactive)"

# 8. Multiple detected + non-interactive -> exit 1 and show conflict
conflict_dir="$TEST_DIR/conflict"
mkdir -p "$conflict_dir"
echo 'dependencies = ["langchain"]' > "$conflict_dir/pyproject.toml"
echo '{"dependencies":{"openclaw":"x"}}' > "$conflict_dir/package.json"
out8="$TEST_DIR/dispatcher-8.txt"
set +e
APORT_NONINTERACTIVE=1 APORT_PROJECT_DIR="$conflict_dir" "$DISPATCHER" < /dev/null > "$out8" 2>&1
e8=$?
set -e
[[ "$e8" -ne 0 ]] || {
    echo "FAIL: non-interactive conflict should exit 1" >&2
    exit 1
}
grep -q "Multiple frameworks detected" "$out8" || {
    echo "FAIL: conflict message" >&2
    cat "$out8" >&2
    exit 1
}
grep -q "langchain" "$out8" && grep -q "openclaw" "$out8" || {
    echo "FAIL: conflict should list both" >&2
    exit 1
}
echo "  ✅ Non-interactive (multiple detected) -> exit 1 and show both options"

# 9. --framework=claude-code -> runs claude-code installer (not "unknown framework")
out9="$TEST_DIR/dispatcher-9.txt"
CLAUDE_TEST_DIR="$TEST_DIR/claude_install"
mkdir -p "$CLAUDE_TEST_DIR"
run_dispatcher "$out9" "" --framework=claude-code --output "$CLAUDE_TEST_DIR/aport/passport.json" --non-interactive
# Installer may exit 0 or non-zero (e.g. wizard); we only require it's not "unknown framework"
if grep -q "Unknown or unsupported framework" "$out9"; then
    echo "FAIL: claude-code should be supported" >&2
    cat "$out9" >&2
    exit 1
fi
echo "  ✅ --framework=claude-code -> runs claude-code (not unknown)"

# 10. --integration-mode is CrewAI-only -> reject for other frameworks before forwarding
out10="$TEST_DIR/dispatcher-10.txt"
run_dispatcher "$out10" "" --framework=openclaw --integration-mode=native
[[ "$DISPATCHER_EXIT" -ne 0 ]] || {
    echo "FAIL: expected non-zero for non-CrewAI integration mode" >&2
    exit 1
}
grep -q "only supported for CrewAI" "$out10" || {
    echo "FAIL: expected CrewAI-only integration mode error" >&2
    cat "$out10" >&2
    exit 1
}
echo "  ✅ --integration-mode rejected for non-CrewAI frameworks"

# 11. --non-interactive flag should set APORT_NONINTERACTIVE for custom frameworks
out11="$TEST_DIR/dispatcher-11.txt"
CLAUDE_FLAG_DIR="$TEST_DIR/claude_noninteractive_flag"
mkdir -p "$CLAUDE_FLAG_DIR"
set +e
APORT_CLAUDE_CODE_CONFIG_DIR="$CLAUDE_FLAG_DIR" "$DISPATCHER" --framework=claude-code ap_04c65c1dd7224160b36b756960e2cc48 --non-interactive < /dev/null > "$out11" 2>&1
e11=$?
set -e
[[ "$e11" -eq 0 ]] || {
    echo "FAIL: --non-interactive flag should let hosted Claude setup finish without prompts" >&2
    cat "$out11" >&2
    exit 1
}
grep -q "Guardrail mode: api" "$out11" || {
    echo "FAIL: expected Claude setup to complete in api mode" >&2
    cat "$out11" >&2
    exit 1
}
echo "  ✅ --non-interactive flag works for hosted Claude setup"

echo ""
echo "  All dispatcher tests passed."
echo ""

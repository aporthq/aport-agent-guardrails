#!/bin/bash
# Unit test: the framework installers derive their hook timeout from a NORMALIZED APORT_API_TIMEOUT.
#
# A Claude Code PreToolUse hook that reaches its timeout does not block the tool call, and Cursor needs
# failClosed plus a budget above the evaluator bound for the same reason. Reading APORT_API_TIMEOUT straight
# into shell arithmetic disagreed with the evaluator in both directions: APORT_API_TIMEOUT=0 or -5 left the
# evaluator on its 15 s fallback while the hook budget came out at 15 s or 12 s (a hook shorter than the
# request it is waiting on, so it fails open), and "1.5" or "abc" aborted setup with an arithmetic error.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# shellcheck source=../../bin/lib/common.sh
source "$REPO_ROOT/bin/lib/common.sh"

# 1. The shell normalizer agrees with apiTimeoutMs() in src/evaluator.js on every value the finding names.
check_norm() {
    local raw="$1" expected="$2"
    local got
    got="$(APORT_API_TIMEOUT="$raw" aport_api_timeout_seconds)" || fail "normalizer errored on \"$raw\""
    [[ "$got" = "$expected" ]] || fail "APORT_API_TIMEOUT=\"$raw\" normalized to $got, expected $expected"
}

check_norm "" 15    # unset falls back
check_norm "0" 15   # zero is not a bound
check_norm "-5" 15  # negative is not a bound
check_norm "abc" 15 # not a number
check_norm "1.5" 2  # fractional, rounded up so the budget never understates the bound
check_norm "45" 45  # a usable value is used
check_norm "15" 15
check_norm "0.4" 1        # rounds up to the 1 s floor apiTimeoutMs also enforces
check_norm "+30" 30       # an explicit sign is still a number
check_norm "1e3" 1000     # exponent notation, because the evaluator Number()s the same string
check_norm "0.0" 15       # zero however it is spelled
check_norm "15s" 15       # a unit suffix is not a number, same as the evaluator
check_norm "30 " 30       # Number() trims whitespace, so the evaluator would use 30 s and so does this
check_norm "0x10" 16      # Number("0x10") is 16
check_norm "0b1000000" 64 # Number("0b1000000") is 64
check_norm "0o100" 64     # Number("0o100") is 64
check_norm "+0b10" 15     # signed non-decimal strings are NaN to Number()
check_norm "-0o10" 15
check_norm "Infinity" 15 # not finite, so the evaluator falls back and so does this
check_norm "NaN" 15
echo "PASS: APORT_API_TIMEOUT normalization matches the evaluator"

# 2. The evaluator and this helper agree, checked against src/evaluator.js rather than restated.
if command -v node > /dev/null 2>&1; then
    for raw in "" "0" "-5" "abc" "1.5" "45" "15" "0.4" "1e3" "15s" "NaN" "0x10" "0b1000000" "0o100" "+0b10" "-0o10" "Infinity" "30 " "+30" "0.0"; do
        evaluator_ms="$(APORT_API_TIMEOUT="$raw" node -e '
          const {apiTimeoutMs} = require("./src/evaluator.js");
          process.stdout.write(String(apiTimeoutMs(process.env.APORT_API_TIMEOUT)));
        ' 2> /dev/null)" || fail "evaluator apiTimeoutMs threw on \"$raw\""
        shell_s="$(APORT_API_TIMEOUT="$raw" aport_api_timeout_seconds)"
        # The shell helper works in whole seconds and rounds up, so it is at or above the evaluator bound.
        (((shell_s * 1000) >= evaluator_ms)) || fail "APORT_API_TIMEOUT=\"$raw\": hook budget base ${shell_s}s is below the evaluator bound ${evaluator_ms}ms"
    done
    echo "PASS: the shell budget base is never below the evaluator bound"
else
    echo "SKIP: node not available; evaluator cross-check skipped"
fi

# 3. Each framework installer derives a budget above the evaluator bound for every value, and never errors.
#    The scripts run run_setup at the bottom, so the head is copied up to and including the APORT_HOOK_TIMEOUT
#    assignment and sourced instead. The copy sits beside the real script so its LIB lookup, which resolves
#    relative to BASH_SOURCE, still finds bin/lib.
budget_for() {
    local script="$1" raw="$2"
    local head="${script%.sh}.timeout-probe.$$.sh"
    sed -n '1,/^APORT_HOOK_TIMEOUT=/p' "$script" > "$head"
    local out status
    set +e
    out="$(APORT_API_TIMEOUT="$raw" bash -c '
      set -euo pipefail
      # shellcheck disable=SC1090
      source "$1"
      printf "%s" "$APORT_HOOK_TIMEOUT"
    ' _ "$head" 2>&1)"
    status=$?
    set -e
    rm -f "$head"
    [[ "$status" -eq 0 ]] || {
        printf '%s' "$out"
        return "$status"
    }
    printf '%s' "$out"
}

for script in "$REPO_ROOT/bin/frameworks/claude-code.sh" "$REPO_ROOT/bin/frameworks/cursor.sh"; do
    name="$(basename "$script")"
    for raw in "" "0" "-5" "abc" "1.5" "45" "0b1000000" "0o100"; do
        got="$(budget_for "$script" "$raw")" || fail "$name errored deriving a budget for APORT_API_TIMEOUT=\"$raw\""
        [[ "$got" =~ ^[0-9]+$ ]] || fail "$name produced a non-numeric timeout \"$got\" for APORT_API_TIMEOUT=\"$raw\""
        # 15 s of margin over the normalized bound: node startup plus the audit write.
        expected=$(($(APORT_API_TIMEOUT="$raw" aport_api_timeout_seconds) + 15))
        [[ "$got" = "$expected" ]] || fail "$name derived $got for APORT_API_TIMEOUT=\"$raw\", expected $expected"
        # The budget must clear the bound the evaluator will actually use, with margin. When the value is
        # unusable (0, -5, "abc") the evaluator falls back to 15 s, so the budget must reach 30 -- the case
        # the finding names, where the old arithmetic produced 15 or 12 and the hook failed open first.
        bound="$(APORT_API_TIMEOUT="$raw" aport_api_timeout_seconds)"
        ((got > bound)) || fail "$name derived $got for APORT_API_TIMEOUT=\"$raw\", which does not clear the ${bound}s evaluator bound"
        case "$raw" in
            "" | "0" | "-5" | "abc")
                ((got >= 30)) || fail "$name derived $got for APORT_API_TIMEOUT=\"$raw\"; the evaluator uses its 15 s fallback there, so the hook needs at least 30"
                ;;
        esac
    done
    # An explicit APORT_HOOK_TIMEOUT still wins, so an operator can raise it.
    got="$(APORT_HOOK_TIMEOUT=90 budget_for "$script" "45")"
    [[ "$got" = "90" ]] || fail "$name should honour an explicit APORT_HOOK_TIMEOUT, got $got"
    echo "PASS: $name derives a safe hook budget for every APORT_API_TIMEOUT"
done

# 4. The Claude Code settings file carries the derived budget, not a hardcoded one that could drift below it.
grep -q '"timeout": ${APORT_HOOK_TIMEOUT}' "$REPO_ROOT/bin/frameworks/claude-code.sh" \
    || fail "the no-jq settings fallback in claude-code.sh must write the derived timeout, not a literal"
echo "PASS: the settings writers use the derived budget"

echo "PASS: hook timeout budget"

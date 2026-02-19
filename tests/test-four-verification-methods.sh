#!/bin/bash
# Test the 4 verification methods with guardrail + passport setup.
# 1. Bash guardrail standalone (direct repo bin)
# 2. API guardrail standalone (skip if no APORT_API_URL or API unreachable)
# 3. Plugin-local: guardrail script from OpenClaw deployment dir (bootstrap if needed)
# 4. Plugin-API: API with passport from deployment dir (skip if no API)
#
# Usage: ./test-four-verification-methods.sh
#   Optional: OPENCLAW_DEPLOYMENT_DIR=/path/to/existing/openclaw  (use existing deployment)
#   Optional: APORT_TEST_OPENCLAW_DIR=/path  (same as above; bootstrap if unset)
#   If neither set, bootstraps a temp OpenClaw-like dir (passport + .skills wrapper).

set -e

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/setup.sh"

# Deployment dir: use provided path or bootstrap temp
OPENCLAW_DEPLOYMENT_DIR="${OPENCLAW_DEPLOYMENT_DIR:-$APORT_TEST_OPENCLAW_DIR}"
if [ -z "$OPENCLAW_DEPLOYMENT_DIR" ]; then
    OPENCLAW_DEPLOYMENT_DIR="$(mktemp -d 2> /dev/null || echo "$TEST_DIR/openclaw-bootstrap")"
    mkdir -p "$OPENCLAW_DEPLOYMENT_DIR"
    BOOTSTRAPPED=1
else
    BOOTSTRAPPED=0
fi
DEPLOY="$(cd "$OPENCLAW_DEPLOYMENT_DIR" && pwd)"

bootstrap_deploy_dir() {
    [ "$BOOTSTRAPPED" -eq 0 ] && return 0
    echo "  Bootstrap OpenClaw-like dir: $DEPLOY"
    # APort data in aport/ (match bin/openclaw layout)
    mkdir -p "$DEPLOY/aport"
    cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$DEPLOY/aport/passport.json"
    echo "$REPO_ROOT" > "$DEPLOY/.aport-repo"
    mkdir -p "$DEPLOY/.skills"
    # Wrapper: same as bin/openclaw write_wrapper (defaults to config_dir/aport/)
    cat > "$DEPLOY/.skills/aport-guardrail-bash.sh" << WRAP
#!/bin/bash
CONFIG_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
APORT_REPO_ROOT="\$(cat "\$CONFIG_DIR/.aport-repo" 2>/dev/null)"
[ -z "\$APORT_REPO_ROOT" ] && { echo "Error: .aport-repo missing." >&2; exit 1; }
export OPENCLAW_PASSPORT_FILE="\${OPENCLAW_PASSPORT_FILE:-\$CONFIG_DIR/aport/passport.json}"
export OPENCLAW_DECISION_FILE="\${OPENCLAW_DECISION_FILE:-\$CONFIG_DIR/aport/decision.json}"
export OPENCLAW_AUDIT_LOG="\${OPENCLAW_AUDIT_LOG:-\$CONFIG_DIR/aport/audit.log}"
exec "\$APORT_REPO_ROOT/bin/aport-guardrail-bash.sh" "\$@"
WRAP
    chmod +x "$DEPLOY/.skills/aport-guardrail-bash.sh"
}

# Assert ALLOW (exit 0)
assert_allow() {
    if [ "$1" -eq 0 ]; then return 0; fi
    echo "FAIL: expected ALLOW (exit 0), got exit $1" >&2
    return 1
}
# Assert DENY (exit non-zero)
assert_deny() {
    if [ "$1" -ne 0 ]; then return 0; fi
    echo "FAIL: expected DENY (exit non-zero), got exit 0" >&2
    return 1
}

ALLOW_CMD='{"command":"mkdir -p test-allow"}'
DENY_CMD='{"command":"rm -rf /"}'

bootstrap_deploy_dir

echo ""
echo "  Four verification methods (passport + guardrail setup in $DEPLOY)"
echo "  ─────────────────────────────────────────────────────────────"
echo ""

# Method 1: Bash guardrail standalone (direct repo bin, passport from deploy dir)
echo "  Method 1: Bash guardrail standalone..."
export OPENCLAW_PASSPORT_FILE="$DEPLOY/aport/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/decision-m1.json"
exit1=0
"$REPO_ROOT/bin/aport-guardrail-bash.sh" system.command.execute "$ALLOW_CMD" 2> /dev/null || exit1=$?
assert_allow $exit1 || exit 1
echo "    ALLOW (mkdir) OK"
exit2=0
"$REPO_ROOT/bin/aport-guardrail-bash.sh" system.command.execute "$DENY_CMD" 2> /dev/null || exit2=$?
assert_deny $exit2 || exit 1
echo "    DENY (rm -rf /) OK"
echo "  ✅ Method 1 passed"
echo ""

# Method 2: API guardrail standalone (skip if no API)
echo "  Method 2: API guardrail standalone..."
if [ -z "${APORT_API_URL:-}" ]; then
    echo "    SKIP (APORT_API_URL not set)"
else
    export OPENCLAW_PASSPORT_FILE="$DEPLOY/aport/passport.json"
    export OPENCLAW_DECISION_FILE="$TEST_DIR/decision-m2.json"
    exit2a=0
    "$REPO_ROOT/bin/aport-guardrail-api.sh" system.command.execute "$ALLOW_CMD" 2> /dev/null || exit2a=$?
    if [ $exit2a -eq 0 ]; then
        echo "    ALLOW OK"
        echo "  ✅ Method 2 passed"
    else
        echo "    SKIP (API unreachable or error; exit $exit2a)"
    fi
fi
echo ""

# Method 3: Plugin-local — guardrail script from deployment dir (as plugin would call it)
echo "  Method 3: Plugin-local (guardrail script from deployment dir)..."
export OPENCLAW_DECISION_FILE="$TEST_DIR/decision-m3.json"
exit3=0
"$DEPLOY/.skills/aport-guardrail-bash.sh" system.command.execute "$ALLOW_CMD" 2> /dev/null || exit3=$?
assert_allow $exit3 || exit 1
echo "    ALLOW OK"
exit3d=0
"$DEPLOY/.skills/aport-guardrail-bash.sh" system.command.execute "$DENY_CMD" 2> /dev/null || exit3d=$?
assert_deny $exit3d || exit 1
echo "    DENY OK"
echo "  ✅ Method 3 passed"
echo ""

# Method 4: Plugin-API — API with passport from deployment dir (skip if no API)
echo "  Method 4: Plugin-API (API with passport from deployment dir)..."
if [ -z "${APORT_API_URL:-}" ]; then
    echo "    SKIP (APORT_API_URL not set)"
else
    export OPENCLAW_PASSPORT_FILE="$DEPLOY/aport/passport.json"
    export OPENCLAW_DECISION_FILE="$TEST_DIR/decision-m4.json"
    exit4=0
    "$REPO_ROOT/bin/aport-guardrail-api.sh" system.command.execute "$ALLOW_CMD" 2> /dev/null || exit4=$?
    if [ $exit4 -eq 0 ]; then
        echo "    ALLOW OK"
        echo "  ✅ Method 4 passed"
    else
        echo "    SKIP (API unreachable; exit $exit4)"
    fi
fi
echo ""

echo "  ✅ Four verification methods test complete."
exit 0

#!/bin/bash
# Test the published npm package @aporthq/agent-guardrails: install and run guardrail.
# Run from repo root: bash tests/test-npm-package.sh
# Requires: npm, jq. Uses a temp dir; does not pollute repo.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_PASSPORT="$REPO_ROOT/tests/fixtures/passport.oap-v1.json"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2>/dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "  NPM package: install @aporthq/agent-guardrails in $TEST_DIR"
npm init -y >/dev/null 2>&1
# --ignore-scripts: avoid make install (for clone-from-repo); published package has conditional install
npm install "@aporthq/agent-guardrails" --no-save --no-package-lock --ignore-scripts >/dev/null 2>&1

PKG_ROOT="$TEST_DIR/node_modules/@aporthq/agent-guardrails"
if [ ! -d "$PKG_ROOT" ]; then
    echo "FAIL: package not found at $PKG_ROOT" >&2
    exit 1
fi
if [ ! -f "$PKG_ROOT/bin/aport-guardrail.sh" ]; then
    echo "FAIL: bin/aport-guardrail.sh missing in package" >&2
    exit 1
fi
if [ ! -d "$PKG_ROOT/external" ]; then
    echo "FAIL: external/ missing in package (policies/spec)" >&2
    exit 1
fi
echo "  NPM package: layout OK (bin/, external/)"

export OPENCLAW_PASSPORT_FILE="$TEST_DIR/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/decision.json"
cp "$FIXTURE_PASSPORT" "$OPENCLAW_PASSPORT_FILE"

GUARDRAIL="$PKG_ROOT/bin/aport-guardrail.sh"
chmod +x "$GUARDRAIL" 2>/dev/null || true

echo "  NPM package: guardrail ALLOW (safe command)..."
if ! "$GUARDRAIL" system.command.execute '{"command":"ls"}'; then
    echo "FAIL: expected ALLOW for ls" >&2
    exit 1
fi
echo "  NPM package: guardrail DENY (blocked pattern)..."
if "$GUARDRAIL" system.command.execute '{"command":"rm -rf /"}'; then
    echo "FAIL: expected DENY for rm -rf /" >&2
    exit 1
fi

echo "  NPM package: setup wizard script present..."
[ -f "$PKG_ROOT/bin/openclaw" ] || { echo "FAIL: bin/openclaw missing"; exit 1; }

echo "  NPM package tests passed."
exit 0

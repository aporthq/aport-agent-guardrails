#!/bin/bash
# Framework hooks should not inherit stale config/passport paths from another framework.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.claude/aport" "$HOME/.cursor/aport"

# shellcheck source=../../bin/lib/framework-hook-paths.sh
source "$REPO_ROOT/bin/lib/framework-hook-paths.sh"

APORT_CONFIG_DIR="$HOME/.claude"
OPENCLAW_CONFIG_DIR="$HOME/.claude"
APORT_PASSPORT_FILE="$HOME/.claude/aport/passport.json"
OPENCLAW_PASSPORT_FILE="$HOME/.claude/aport/passport.json"
APORT_DECISION_FILE="$HOME/.claude/aport/decision.json"
OPENCLAW_AUDIT_LOG="$HOME/.claude/aport/audit.log"
export APORT_CONFIG_DIR OPENCLAW_CONFIG_DIR APORT_PASSPORT_FILE OPENCLAW_PASSPORT_FILE APORT_DECISION_FILE OPENCLAW_AUDIT_LOG

aport_hook_prepare_framework_paths "cursor" "" "$HOME/.cursor"

[ "$APORT_CONFIG_DIR" = "$HOME/.cursor" ] || {
    echo "FAIL: cursor hook should set canonical APORT_CONFIG_DIR" >&2
    exit 1
}
[ "$OPENCLAW_CONFIG_DIR" = "$HOME/.cursor" ] || {
    echo "FAIL: cursor hook should ignore stale Claude OPENCLAW_CONFIG_DIR" >&2
    exit 1
}
[ -z "${APORT_PASSPORT_FILE:-}" ] || {
    echo "FAIL: cursor hook should ignore stale Claude APORT_PASSPORT_FILE" >&2
    exit 1
}
[ -z "${OPENCLAW_PASSPORT_FILE:-}" ] || {
    echo "FAIL: cursor hook should ignore stale Claude OPENCLAW_PASSPORT_FILE" >&2
    exit 1
}
[ -z "${APORT_DECISION_FILE:-}" ] || {
    echo "FAIL: cursor hook should ignore stale Claude APORT_DECISION_FILE" >&2
    exit 1
}
[ -z "${OPENCLAW_AUDIT_LOG:-}" ] || {
    echo "FAIL: cursor hook should ignore stale Claude OPENCLAW_AUDIT_LOG" >&2
    exit 1
}

APORT_CURSOR_CONFIG_DIR="$TEST_DIR/custom-cursor"
unset APORT_CONFIG_DIR APORT_PASSPORT_FILE APORT_DECISION_FILE OPENCLAW_AUDIT_LOG
OPENCLAW_CONFIG_DIR="$HOME/.claude"
APORT_PASSPORT_FILE="$APORT_CURSOR_CONFIG_DIR/aport/passport.json"
APORT_DECISION_FILE="$APORT_CURSOR_CONFIG_DIR/aport/decision.json"
OPENCLAW_AUDIT_LOG="$APORT_CURSOR_CONFIG_DIR/aport/audit.log"
export APORT_CURSOR_CONFIG_DIR OPENCLAW_CONFIG_DIR APORT_PASSPORT_FILE APORT_DECISION_FILE OPENCLAW_AUDIT_LOG

aport_hook_prepare_framework_paths "cursor" "$APORT_CURSOR_CONFIG_DIR" "$HOME/.cursor"

[ "$APORT_CONFIG_DIR" = "$APORT_CURSOR_CONFIG_DIR" ] || {
    echo "FAIL: framework-specific config dir should set canonical APORT_CONFIG_DIR" >&2
    exit 1
}
[ "$OPENCLAW_CONFIG_DIR" = "$APORT_CURSOR_CONFIG_DIR" ] || {
    echo "FAIL: framework-specific config dir should win" >&2
    exit 1
}
[ "$APORT_PASSPORT_FILE" = "$APORT_CURSOR_CONFIG_DIR/aport/passport.json" ] || {
    echo "FAIL: canonical passport inside framework config dir should be preserved" >&2
    exit 1
}
[ "$OPENCLAW_PASSPORT_FILE" = "$APORT_CURSOR_CONFIG_DIR/aport/passport.json" ] || {
    echo "FAIL: passport inside framework config dir should be preserved" >&2
    exit 1
}
[ "$OPENCLAW_DECISION_FILE" = "$APORT_CURSOR_CONFIG_DIR/aport/decision.json" ] || {
    echo "FAIL: decision file inside framework config dir should be preserved" >&2
    exit 1
}
[ "$APORT_AUDIT_LOG" = "$APORT_CURSOR_CONFIG_DIR/aport/audit.log" ] || {
    echo "FAIL: audit log inside framework config dir should be preserved" >&2
    exit 1
}

unset APORT_CURSOR_CONFIG_DIR APORT_CONFIG_DIR APORT_PASSPORT_FILE
OPENCLAW_CONFIG_DIR="$HOME/.cursor"
OPENCLAW_PASSPORT_FILE="$HOME/.claude/aport/passport.json"
APORT_ALLOW_EXTERNAL_PASSPORT_FILE=1
export OPENCLAW_CONFIG_DIR OPENCLAW_PASSPORT_FILE APORT_ALLOW_EXTERNAL_PASSPORT_FILE

aport_hook_prepare_framework_paths "cursor" "" "$HOME/.cursor"

[ "$APORT_PASSPORT_FILE" = "$HOME/.claude/aport/passport.json" ] || {
    echo "FAIL: canonical explicit external passport opt-in should be preserved" >&2
    exit 1
}
[ "$OPENCLAW_PASSPORT_FILE" = "$HOME/.claude/aport/passport.json" ] || {
    echo "FAIL: explicit external passport opt-in should be preserved" >&2
    exit 1
}

echo "OK test-framework-hook-paths.sh"

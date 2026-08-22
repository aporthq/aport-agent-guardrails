#!/bin/bash
# Ensure git trailers use retained session decisions when hook decision files are cleaned up.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
CONFIG_DIR="$TEST_DIR/aport"
mkdir -p "$CONFIG_DIR"

export APORT_CONFIG_DIR="$TEST_DIR"
export OPENCLAW_CONFIG_DIR="$TEST_DIR"
export APORT_DECISION_FILE="$CONFIG_DIR/decision.json"
export OPENCLAW_DECISION_FILE="$APORT_DECISION_FILE"
export APORT_SESSION_DECISIONS_FILE="$CONFIG_DIR/session-decisions.jsonl"

cat > "$APORT_SESSION_DECISIONS_FILE" << 'EOF'
{"session_id":"sess-old","decision":{"decision_id":"dec-old","agent_id":"ap_old"}}
{"session_id":"sess-latest","decision":{"decision_id":"dec-latest","agent_id":"ap_latest"}}
EOF

OUT="$TEST_DIR/trailers.out"
"$REPO_ROOT/bin/aport-git-trailers.sh" --print > "$OUT"

grep -q '^APort-Session: sess-latest$' "$OUT" || {
    echo "FAIL: expected latest session id from session-decisions.jsonl" >&2
    cat "$OUT" >&2
    exit 1
}

grep -q '^APort-Decision: dec-latest$' "$OUT" || {
    echo "FAIL: expected latest decision id from session-decisions.jsonl" >&2
    cat "$OUT" >&2
    exit 1
}

grep -q '^APort-Agent: ap_latest$' "$OUT" || {
    echo "FAIL: expected latest agent id from session-decisions.jsonl" >&2
    cat "$OUT" >&2
    exit 1
}

echo "OK test-git-trailers.sh"

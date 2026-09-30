#!/bin/bash
# Regression tests for the local pre-push wrapper behavior.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
FAKE_BIN="$TEST_DIR/fake-bin"
LOG_FILE="$TEST_DIR/pre-push.log"
OUT_FILE="$TEST_DIR/pre-push.out"
REAL_BASH="$(command -v bash)"

fail() {
    echo "FAIL: $*" >&2
    cat "$OUT_FILE" >&2 2> /dev/null || true
    cat "$LOG_FILE" >&2 2> /dev/null || true
    exit 1
}

mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/bash" << 'EOF'
#!/bin/bash
set -euo pipefail

printf 'bash %s\n' "$*" >> "$APORT_PRE_PUSH_FAKE_LOG"

case "${1:-}" in
    -n)
        exit 0
        ;;
    -lc)
        case "${2:-}" in
            *shfmt*)
                printf 'shfmt\n' >> "$APORT_PRE_PUSH_FAKE_LOG"
                ;;
            *OPENCLAW_HOME*)
                printf 'openclaw-live\n' >> "$APORT_PRE_PUSH_FAKE_LOG"
                ;;
        esac
        exit 0
        ;;
    scripts/check-codex-provider-tool-surface.sh)
        printf 'codex-provider-surface\n' >> "$APORT_PRE_PUSH_FAKE_LOG"
        printf 'cache-root %s\n' "${APORT_CODEX_PROVIDER_CACHE_ROOT:-}" >> "$APORT_PRE_PUSH_FAKE_LOG"
        exit 0
        ;;
esac

exec "$APORT_REAL_BASH" "$@"
EOF

cat > "$FAKE_BIN/node" << 'EOF'
#!/bin/bash
set -euo pipefail

printf 'node %s\n' "$*" >> "$APORT_PRE_PUSH_FAKE_LOG"
exit 0
EOF

cat > "$FAKE_BIN/gitleaks" << 'EOF'
#!/bin/bash
set -euo pipefail

printf 'gitleaks %s\n' "$*" >> "$APORT_PRE_PUSH_FAKE_LOG"
exit 0
EOF

cat > "$FAKE_BIN/trufflehog" << 'EOF'
#!/bin/bash
set -euo pipefail

printf 'trufflehog %s\n' "$*" >> "$APORT_PRE_PUSH_FAKE_LOG"
exit 0
EOF

chmod +x "$FAKE_BIN/bash" "$FAKE_BIN/node" "$FAKE_BIN/gitleaks" "$FAKE_BIN/trufflehog"

set +e
PATH="$FAKE_BIN:$PATH" \
    APORT_REAL_BASH="$REAL_BASH" \
    APORT_PRE_PUSH_FAKE_LOG="$LOG_FILE" \
    APORT_PRE_PUSH_TMP_ROOT="$TEST_DIR/tmp" \
    APORT_PRE_PUSH_HOME="$TEST_DIR/home" \
    APORT_PRE_PUSH_INCLUDE_OPENCLAW_LIVE=1 \
    APORT_PRE_PUSH_INCLUDE_OPTIONAL=1 \
    APORT_CODEX_PROVIDER_CACHE_ROOT="$TEST_DIR/custom-cache" \
    "$REAL_BASH" "$REPO_ROOT/scripts/pre-push-check.sh" > "$OUT_FILE" 2>&1
exit_code=$?
set -e

if [ "$exit_code" -ne 0 ]; then
    fail "fast pre-push with opt-in checks exited $exit_code"
fi

grep -q '^codex-provider-surface$' "$LOG_FILE" || fail "fast pre-push did not run the Codex provider surface check"
grep -q "^cache-root $TEST_DIR/custom-cache$" "$LOG_FILE" || fail "pre-push overwrote the explicit Codex provider cache root"
grep -q '^openclaw-live$' "$LOG_FILE" || fail "fast pre-push ignored APORT_PRE_PUSH_INCLUDE_OPENCLAW_LIVE=1"
grep -q '^gitleaks detect ' "$LOG_FILE" || fail "fast pre-push ignored APORT_PRE_PUSH_INCLUDE_OPTIONAL=1 for gitleaks"
grep -q '^trufflehog filesystem ' "$LOG_FILE" || fail "fast pre-push ignored APORT_PRE_PUSH_INCLUDE_OPTIONAL=1 for trufflehog"
grep -q 'Fast pre-push checks passed' "$OUT_FILE" || fail "fast pre-push did not report success"

echo "PASS: fast pre-push honors opt-in checks before returning"

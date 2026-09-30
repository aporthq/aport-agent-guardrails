#!/bin/bash
# Regression tests for Codex provider source cache selection.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
FAKE_BIN="$TEST_DIR/fake-bin"
LOG_FILE="$TEST_DIR/provider-cache.log"
REAL_NODE="$(command -v node)"

fail() {
    echo "FAIL: $*" >&2
    cat "$LOG_FILE" >&2 2> /dev/null || true
    exit 1
}

mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/git" << 'EOF'
#!/bin/bash
set -euo pipefail

log() {
    printf '%s\n' "$*" >> "$APORT_FAKE_GIT_LOG"
}

write_source_tree() {
    local dest="$1"
    local repo="$2"
    mkdir -p "$dest/.git" "$dest/codex-rs/core/src/tools"
    printf '%s' "$repo" > "$dest/.git/origin-url"
    printf '// fake Codex provider source\n' > "$dest/codex-rs/core/src/tools/spec_plan.rs"
}

if [ "${1:-}" = "clone" ]; then
    args=("$@")
    last_index=$((${#args[@]} - 1))
    repo_index=$((${#args[@]} - 2))
    repo="${args[$repo_index]}"
    dest="${args[$last_index]}"
    log "clone $repo $dest"
    write_source_tree "$dest" "$repo"
    exit 0
fi

if [ "${1:-}" = "-C" ]; then
    source_dir="$2"
    shift 2
    case "$1 ${2:-} ${3:-}" in
        "remote get-url origin")
            if [ -f "$source_dir/.git/origin-url" ]; then
                cat "$source_dir/.git/origin-url"
                exit 0
            fi
            exit 1
            ;;
        "remote set-url origin")
            log "set-url $source_dir $4"
            mkdir -p "$source_dir/.git"
            printf '%s' "$4" > "$source_dir/.git/origin-url"
            exit 0
            ;;
        "remote add origin")
            log "add-origin $source_dir $4"
            mkdir -p "$source_dir/.git"
            printf '%s' "$4" > "$source_dir/.git/origin-url"
            exit 0
            ;;
        "fetch --depth 1")
            log "fetch $source_dir $5"
            exit 0
            ;;
        "checkout --quiet FETCH_HEAD")
            log "checkout $source_dir"
            exit 0
            ;;
    esac
fi

echo "unexpected fake git invocation: $*" >&2
exit 1
EOF

cat > "$FAKE_BIN/node" << EOF
#!/bin/bash
set -euo pipefail

case "\${1:-}" in
    "$REPO_ROOT/scripts/extract-codex-provider-tools.mjs")
        printf 'Bash\n'
        exit 0
        ;;
esac

exec "$REAL_NODE" "\$@"
EOF

chmod +x "$FAKE_BIN/git" "$FAKE_BIN/node"

run_surface_check() {
    PATH="$FAKE_BIN:$PATH" \
        APORT_FAKE_GIT_LOG="$LOG_FILE" \
        APORT_CODEX_PROVIDER_CACHE_ROOT="$TEST_DIR/cache" \
        APORT_CODEX_PROVIDER_TOOL_TIMEOUT=5 \
        APORT_CODEX_PROVIDER_REPO="$1" \
        APORT_CODEX_PROVIDER_REF=main \
        bash "$REPO_ROOT/scripts/check-codex-provider-tool-surface.sh" > "$TEST_DIR/surface.out" 2> "$TEST_DIR/surface.err"
}

run_surface_check "https://example.com/codex-one.git"
run_surface_check "https://example.com/codex-two.git"

clone_count="$(grep -c '^clone ' "$LOG_FILE" || true)"
if [ "$clone_count" -ne 2 ]; then
    fail "repo-aware default cache should clone once per provider repo; saw $clone_count clone(s)"
fi

first_dest="$(grep '^clone https://example.com/codex-one.git ' "$LOG_FILE" | awk '{print $3}')"
second_dest="$(grep '^clone https://example.com/codex-two.git ' "$LOG_FILE" | awk '{print $3}')"
if [ -z "$first_dest" ] || [ -z "$second_dest" ] || [ "$first_dest" = "$second_dest" ]; then
    fail "provider cache path should include repository identity"
fi

explicit_cache="$TEST_DIR/explicit-cache"
mkdir -p "$explicit_cache/.git" "$explicit_cache/codex-rs/core/src/tools"
printf 'https://example.com/old.git' > "$explicit_cache/.git/origin-url"
printf '// fake Codex provider source\n' > "$explicit_cache/codex-rs/core/src/tools/spec_plan.rs"

PATH="$FAKE_BIN:$PATH" \
    APORT_FAKE_GIT_LOG="$LOG_FILE" \
    APORT_CODEX_PROVIDER_CACHE_DIR="$explicit_cache" \
    APORT_CODEX_PROVIDER_TOOL_TIMEOUT=5 \
    APORT_CODEX_PROVIDER_REPO="https://example.com/new.git" \
    APORT_CODEX_PROVIDER_REF=main \
    bash "$REPO_ROOT/scripts/check-codex-provider-tool-surface.sh" > "$TEST_DIR/explicit.out" 2> "$TEST_DIR/explicit.err"

grep -q "^set-url $explicit_cache https://example.com/new.git$" "$LOG_FILE" \
    || fail "explicit provider cache did not update a stale origin remote"

echo "PASS: Codex provider cache is keyed by repo and corrects stale remotes"

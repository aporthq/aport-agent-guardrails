#!/usr/bin/env bash
# Fail when the Codex hook adapter leaves an upstream provider tool unclassified.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER_REPO="${APORT_CODEX_PROVIDER_REPO:-https://github.com/openai/codex.git}"
PROVIDER_REF="${APORT_CODEX_PROVIDER_REF:-main}"
SOURCE_DIR="${APORT_CODEX_PROVIDER_SOURCE_DIR:-}"
TMP_ROOT="${APORT_CODEX_PROVIDER_TMP_ROOT:-}"
PROVIDER_CACHE_DIR="${APORT_CODEX_PROVIDER_CACHE_DIR:-}"
TOOL_TIMEOUT_SECONDS="${APORT_CODEX_PROVIDER_TOOL_TIMEOUT:-10}"
CLEANUP_TMP=0

cleanup() {
    if [ "$CLEANUP_TMP" = "1" ] && [ -n "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}
trap cleanup EXIT

if [ -z "$SOURCE_DIR" ]; then
    if [ -z "$PROVIDER_CACHE_DIR" ] && [ -z "${CI:-}" ] && [ -n "${HOME:-}" ]; then
        cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/aport/codex-provider"
        cache_key="$(printf '%s' "$PROVIDER_REF" | tr -c 'A-Za-z0-9._-' '_')"
        PROVIDER_CACHE_DIR="$cache_root/$cache_key"
    fi

    if [ -n "$PROVIDER_CACHE_DIR" ]; then
        SOURCE_DIR="$PROVIDER_CACHE_DIR"
        if [ -d "$SOURCE_DIR/.git" ]; then
            git -C "$SOURCE_DIR" fetch --depth 1 origin "$PROVIDER_REF" >&2
            git -C "$SOURCE_DIR" checkout --quiet FETCH_HEAD >&2
        else
            mkdir -p "$(dirname "$SOURCE_DIR")"
            git clone --depth 1 --branch "$PROVIDER_REF" "$PROVIDER_REPO" "$SOURCE_DIR" >&2
        fi
    else
        TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aport-codex-provider.XXXXXX")"
        CLEANUP_TMP=1
        SOURCE_DIR="$TMP_ROOT/codex"
        git clone --depth 1 --branch "$PROVIDER_REF" "$PROVIDER_REPO" "$SOURCE_DIR" >&2
    fi
fi

if [ ! -f "$SOURCE_DIR/codex-rs/core/src/tools/spec_plan.rs" ]; then
    echo "FAIL: $SOURCE_DIR is not an openai/codex source tree" >&2
    exit 1
fi

SURFACE_FILE="$(mktemp "${TMPDIR:-/tmp}/aport-codex-surface.XXXXXX")"
node "$REPO_ROOT/scripts/extract-codex-provider-tools.mjs" "$SOURCE_DIR" > "$SURFACE_FILE"

if [ ! -s "$SURFACE_FILE" ]; then
    echo "FAIL: provider tool extractor returned no Codex tools" >&2
    exit 1
fi

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aport-codex-hook.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"; cleanup' EXIT
mkdir -p "$TEST_ROOT/aport"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$TEST_ROOT/aport/passport.json"
cat > "$TEST_ROOT/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF

export APORT_CODEX_CONFIG_DIR="$TEST_ROOT"
export OPENCLAW_CONFIG_DIR="$TEST_ROOT"
export OPENCLAW_PASSPORT_FILE="$TEST_ROOT/aport/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_ROOT/aport/decision.json"
export OPENCLAW_AUDIT_LOG="$TEST_ROOT/aport/audit.log"
export APORT_CODEX_TOOL_FALLBACK=off

case "$TOOL_TIMEOUT_SECONDS" in
    '' | *[!0-9]*)
        echo "FAIL: APORT_CODEX_PROVIDER_TOOL_TIMEOUT must be a positive integer number of seconds" >&2
        exit 1
        ;;
    0)
        echo "FAIL: APORT_CODEX_PROVIDER_TOOL_TIMEOUT must be greater than zero" >&2
        exit 1
        ;;
esac

payload_for_tool() {
    local tool="$1"
    jq -nc --arg tool "$tool" '
      {
        hook_event_name: "PreToolUse",
        tool_name: $tool,
        tool_call_id: ("provider-surface-" + ($tool | gsub("[^A-Za-z0-9_.-]"; "-"))),
        tool_input: {
          command: "ls -la",
          cmd: "ls -la",
          script: "ls -la",
          chars: "ls -la\n",
          file_path: "/tmp/aport-provider-surface.txt",
          path: "/tmp/aport-provider-surface.txt",
          url: "https://example.com/provider-surface",
          action: "open",
          prompt: "provider surface prompt",
          num_last_images_to_include: 0,
          questions: [
            {
              id: "continue",
              header: "Continue",
              question: "Continue?",
              title: "Continue?",
              options: [
                {"label":"Yes (Recommended)","description":"Continue."},
                {"label":"No","description":"Stop."}
              ]
            }
          ],
          task_handle: "provider-surface"
        }
      }'
}

kill_process_tree() {
    local pid="$1"
    local child children
    children="$(pgrep -P "$pid" 2> /dev/null || true)"
    for child in $children; do
        kill_process_tree "$child"
    done
    kill "$pid" 2> /dev/null || true
}

failures=0
while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    out="$TEST_ROOT/out.json"
    err="$TEST_ROOT/err.txt"
    timeout_marker="$TEST_ROOT/timed-out"
    rm -f "$out" "$err" "$timeout_marker"

    set +e
    (
        payload_for_tool "$tool" | "$REPO_ROOT/bin/lib/command-hook-adapter.sh" codex --classify-only
    ) > "$out" 2> "$err" &
    hook_pid=$!
    (
        sleep "$TOOL_TIMEOUT_SECONDS"
        if kill -0 "$hook_pid" 2> /dev/null; then
            printf '%s\n' "$tool" > "$timeout_marker"
            kill_process_tree "$hook_pid"
        fi
    ) &
    watchdog_pid=$!
    wait "$hook_pid"
    exit_code=$?
    kill "$watchdog_pid" 2> /dev/null || true
    wait "$watchdog_pid" 2> /dev/null || true
    set -e

    if [ -f "$timeout_marker" ]; then
        echo "FAIL: Codex provider tool $tool exceeded ${TOOL_TIMEOUT_SECONDS}s during hook classification" >&2
        cat "$out" >&2 || true
        cat "$err" >&2 || true
        failures=$((failures + 1))
        continue
    fi

    if [ -s "$out" ] && ! jq -e . "$out" > /dev/null 2>&1; then
        echo "FAIL: Codex provider tool $tool produced non-JSON hook stdout" >&2
        cat "$out" >&2 || true
        cat "$err" >&2 || true
        failures=$((failures + 1))
        continue
    fi

    if grep -E 'oap\.unknown_tool|Unknown Codex tool' "$out" "$err" > /dev/null 2>&1; then
        echo "FAIL: Codex provider tool $tool is not classified by APort" >&2
        cat "$out" >&2 || true
        cat "$err" >&2 || true
        failures=$((failures + 1))
        continue
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo "FAIL: Codex provider tool $tool exited $exit_code" >&2
        cat "$out" >&2 || true
        cat "$err" >&2 || true
        failures=$((failures + 1))
    fi
done < "$SURFACE_FILE"

if grep -Fxq "request_user_input_sync" "$SURFACE_FILE"; then
    echo "FAIL: provider now exposes request_user_input_sync; add an explicit mapping and regression test" >&2
    failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
    echo "FAIL: Codex provider tool surface drift detected ($failures failure(s))" >&2
    exit 1
fi

printf '✅ Codex provider tool surface is classified (%s tools)\n' "$(wc -l < "$SURFACE_FILE" | tr -d ' ')"

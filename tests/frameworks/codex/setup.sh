#!/bin/bash
# Integration test: run agent-guardrails codex and assert repo-local hooks.json is written.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output/codex")}"
CODEX_DIR="$TEST_DIR/project/.codex"
CODEX_STATE_DIR="$TEST_DIR/home/.aport/codex"
PASSPORT_PATH="$CODEX_STATE_DIR/aport/passport.json"

rm -rf "$TEST_DIR/project"
mkdir -p "$CODEX_DIR" "$(dirname "$PASSPORT_PATH")" "$TEST_DIR/home"

cat > "$CODEX_DIR/hooks.json" << 'EOF'
{
  "description": "existing hooks",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type":"command","command":"/tmp/stale/aport-codex-hook.sh","__aport_hook":true},
          {"type":"command","command":"/usr/local/bin/custom-codex-hook"}
        ]
      }
    ]
  }
}
EOF

echo ""
echo "  Integration — Codex setup"
echo ""

export APORT_NONINTERACTIVE=1
export APORT_CODEX_HOOKS_DIR="$CODEX_DIR"
export APORT_CODEX_CONFIG_DIR="$CODEX_STATE_DIR"
(
    cd "$TEST_DIR/project"
    HOME="$TEST_DIR/home" "$DISPATCHER" codex --output "$PASSPORT_PATH" --non-interactive --mode=local > "$TEST_DIR/codex-setup.log" 2>&1
)

[[ -f "$CODEX_DIR/hooks.json" ]] || {
    echo "FAIL: expected Codex hooks.json" >&2
    exit 1
}
jq -e '
  ([.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true and (.command | contains("aport-codex-hook.sh")))] | length) == 1
  and ([.hooks.PostToolUse[]?.hooks[]? | select(.__aport_hook == true and (.command | contains("aport-codex-hook.sh")))] | length) == 1
  and ([.hooks.PermissionRequest[]?.hooks[]? | select(.__aport_hook == true and (.command | contains("aport-codex-hook.sh")))] | length) == 0
  and ([.hooks.PreToolUse[]?.hooks[]? | select(.command == "/usr/local/bin/custom-codex-hook")] | length) == 1
' "$CODEX_DIR/hooks.json" > /dev/null || {
    echo "FAIL: Codex hooks.json should upsert APort PreToolUse/PostToolUse hooks and preserve custom hooks" >&2
    jq -c '.hooks' "$CODEX_DIR/hooks.json" >&2
    exit 1
}

[[ -f "$CODEX_STATE_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: expected Codex mode file" >&2
    exit 1
}
grep -q '^APORT_GUARDRAIL_MODE=local$' "$CODEX_STATE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: expected local mode for Codex setup" >&2
    cat "$CODEX_STATE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}

[[ -x "$CODEX_STATE_DIR/aport/runtime/bin/aport-codex-hook.sh" ]] || {
    echo "FAIL: expected stable Codex runtime hook at $CODEX_STATE_DIR/aport/runtime/bin/aport-codex-hook.sh" >&2
    exit 1
}
jq -e --arg runtime_hook "$CODEX_STATE_DIR/aport/runtime/bin/aport-codex-hook.sh" '
  [.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true) | .command // ""]
  | any(contains($runtime_hook))
' "$CODEX_DIR/hooks.json" > /dev/null || {
    echo "FAIL: Codex hooks.json should point to the stable APort runtime hook" >&2
    jq -c '.hooks.PreToolUse' "$CODEX_DIR/hooks.json" >&2
    exit 1
}

[[ ! -e "$CODEX_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: Codex setup must not write mode secrets into repo-local .codex" >&2
    cat "$CODEX_DIR/aport/guardrail-mode.env" >&2
    exit 1
}

echo "  ✅ Codex setup integration passed"

HOSTED_CODEX_DIR="$TEST_DIR/hosted-project/.codex"
HOSTED_CODEX_STATE_DIR="$TEST_DIR/hosted-home/.aport/codex"
rm -rf "$TEST_DIR/hosted-project" "$TEST_DIR/hosted-home"
mkdir -p "$HOSTED_CODEX_DIR" "$HOSTED_CODEX_STATE_DIR" "$TEST_DIR/hosted-home"

(
    cd "$TEST_DIR/hosted-project"
    HOME="$TEST_DIR/hosted-home" \
        APORT_NONINTERACTIVE=1 \
        APORT_CODEX_HOOKS_DIR="$HOSTED_CODEX_DIR" \
        APORT_CODEX_CONFIG_DIR="$HOSTED_CODEX_STATE_DIR" \
        APORT_AGENT_ID="ap_1234567890abcdef1234567890abcdef" \
        APORT_API_KEY="apk_secret_should_not_be_in_repo" \
        "$DISPATCHER" codex --non-interactive --mode=api > "$TEST_DIR/codex-hosted-setup.log" 2>&1
)

grep -q '^APORT_API_KEY=apk_secret_should_not_be_in_repo$' "$HOSTED_CODEX_STATE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: Codex hosted API key should be stored in state mode file" >&2
    cat "$HOSTED_CODEX_STATE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
if grep -R 'apk_secret_should_not_be_in_repo' "$HOSTED_CODEX_DIR" > /dev/null 2>&1; then
    echo "FAIL: Codex hosted API key must not be written into repo-local .codex" >&2
    grep -R 'apk_secret_should_not_be_in_repo' "$HOSTED_CODEX_DIR" >&2 || true
    exit 1
fi

echo "  ✅ Codex hosted setup keeps API key out of repo-local hook config"

SYMLINK_CODEX_DIR="$TEST_DIR/symlink-project/.codex"
SYMLINK_STATE_DIR="$TEST_DIR/symlink-home/.aport/codex"
SYMLINK_TARGET="$TEST_DIR/symlink-target-hooks.json"
rm -rf "$TEST_DIR/symlink-project" "$TEST_DIR/symlink-home"
mkdir -p "$SYMLINK_CODEX_DIR" "$SYMLINK_STATE_DIR" "$TEST_DIR/symlink-home"
printf '{"hooks":{}}\n' > "$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$SYMLINK_CODEX_DIR/hooks.json"

set +e
(
    cd "$TEST_DIR/symlink-project"
    HOME="$TEST_DIR/symlink-home" \
        APORT_NONINTERACTIVE=1 \
        APORT_CODEX_HOOKS_DIR="$SYMLINK_CODEX_DIR" \
        APORT_CODEX_CONFIG_DIR="$SYMLINK_STATE_DIR" \
        "$DISPATCHER" codex --output "$SYMLINK_STATE_DIR/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/codex-symlink-setup.log" 2>&1
)
SYMLINK_EXIT=$?
set -e
if [[ "$SYMLINK_EXIT" -eq 0 ]]; then
    echo "FAIL: Codex setup should reject symlinked hooks.json" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/codex-symlink-setup.log" || {
    echo "FAIL: expected symlink refusal in Codex setup output" >&2
    cat "$TEST_DIR/codex-symlink-setup.log" >&2
    exit 1
}
if [[ "$(cat "$SYMLINK_TARGET")" != '{"hooks":{}}' ]]; then
    echo "FAIL: Codex setup modified symlink target" >&2
    cat "$SYMLINK_TARGET" >&2
    exit 1
fi

echo "  ✅ Codex setup rejects symlinked hook config targets"

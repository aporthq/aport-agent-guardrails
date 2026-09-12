#!/bin/bash
# Integration test: run agent-guardrails gemini and assert settings.json is written.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output/gemini")}"
GEMINI_DIR="$TEST_DIR/project/.gemini"
GEMINI_STATE_DIR="$TEST_DIR/home/.aport/gemini-cli"
PASSPORT_PATH="$GEMINI_STATE_DIR/aport/passport.json"

rm -rf "$TEST_DIR/project"
mkdir -p "$GEMINI_DIR" "$(dirname "$PASSPORT_PATH")" "$TEST_DIR/home"

cat > "$GEMINI_DIR/settings.json" << 'EOF'
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": ".*",
        "hooks": [
          {"type":"command","command":"/tmp/stale/aport-gemini-cli-hook.sh","__aport_hook":true},
          {"type":"command","command":"/usr/local/bin/custom-gemini-hook"}
        ]
      }
    ]
  }
}
EOF

echo ""
echo "  Integration — Gemini CLI setup"
echo ""

export APORT_NONINTERACTIVE=1
export APORT_GEMINI_CLI_HOOKS_DIR="$GEMINI_DIR"
export APORT_GEMINI_CLI_CONFIG_DIR="$GEMINI_STATE_DIR"
(
    cd "$TEST_DIR/project"
    HOME="$TEST_DIR/home" "$DISPATCHER" gemini --output "$PASSPORT_PATH" --non-interactive --mode=local > "$TEST_DIR/gemini-setup.log" 2>&1
)

[[ -f "$GEMINI_DIR/settings.json" ]] || {
    echo "FAIL: expected Gemini settings.json" >&2
    exit 1
}
jq -e '
  ([.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true and (.command | contains("aport-gemini-cli-hook.sh")) and .timeout == 10000)] | length) == 1
  and ([.hooks.BeforeTool[]?.hooks[]? | select(.command == "/usr/local/bin/custom-gemini-hook")] | length) == 1
' "$GEMINI_DIR/settings.json" > /dev/null || {
    echo "FAIL: Gemini settings.json should upsert APort hook and preserve custom hooks" >&2
    jq -c '.hooks' "$GEMINI_DIR/settings.json" >&2
    exit 1
}

[[ -f "$GEMINI_STATE_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: expected Gemini mode file" >&2
    exit 1
}
grep -q '^APORT_GUARDRAIL_MODE=local$' "$GEMINI_STATE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: expected local mode for Gemini setup" >&2
    cat "$GEMINI_STATE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}

[[ -x "$GEMINI_STATE_DIR/aport/runtime/bin/aport-gemini-cli-hook.sh" ]] || {
    echo "FAIL: expected stable Gemini CLI runtime hook at $GEMINI_STATE_DIR/aport/runtime/bin/aport-gemini-cli-hook.sh" >&2
    exit 1
}
jq -e --arg runtime_hook "$GEMINI_STATE_DIR/aport/runtime/bin/aport-gemini-cli-hook.sh" '
  [.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true) | .command // ""]
  | any(contains($runtime_hook))
' "$GEMINI_DIR/settings.json" > /dev/null || {
    echo "FAIL: Gemini settings.json should point to the stable APort runtime hook" >&2
    jq -c '.hooks.BeforeTool' "$GEMINI_DIR/settings.json" >&2
    exit 1
}

[[ ! -e "$GEMINI_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: Gemini setup must not write mode secrets into repo-local .gemini" >&2
    cat "$GEMINI_DIR/aport/guardrail-mode.env" >&2
    exit 1
}

echo "  ✅ Gemini CLI setup integration passed"

HOSTED_GEMINI_DIR="$TEST_DIR/hosted-project/.gemini"
HOSTED_GEMINI_STATE_DIR="$TEST_DIR/hosted-home/.aport/gemini-cli"
rm -rf "$TEST_DIR/hosted-project" "$TEST_DIR/hosted-home"
mkdir -p "$HOSTED_GEMINI_DIR" "$HOSTED_GEMINI_STATE_DIR" "$TEST_DIR/hosted-home"

(
    cd "$TEST_DIR/hosted-project"
    HOME="$TEST_DIR/hosted-home" \
        APORT_NONINTERACTIVE=1 \
        APORT_GEMINI_CLI_HOOKS_DIR="$HOSTED_GEMINI_DIR" \
        APORT_GEMINI_CLI_CONFIG_DIR="$HOSTED_GEMINI_STATE_DIR" \
        APORT_AGENT_ID="ap_1234567890abcdef1234567890abcdef" \
        APORT_API_KEY="apk_secret_should_not_be_in_repo" \
        "$DISPATCHER" gemini --non-interactive --mode=api > "$TEST_DIR/gemini-hosted-setup.log" 2>&1
)

grep -q '^APORT_API_KEY=apk_secret_should_not_be_in_repo$' "$HOSTED_GEMINI_STATE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: Gemini hosted API key should be stored in state mode file" >&2
    cat "$HOSTED_GEMINI_STATE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
if grep -R 'apk_secret_should_not_be_in_repo' "$HOSTED_GEMINI_DIR" > /dev/null 2>&1; then
    echo "FAIL: Gemini hosted API key must not be written into repo-local .gemini" >&2
    grep -R 'apk_secret_should_not_be_in_repo' "$HOSTED_GEMINI_DIR" >&2 || true
    exit 1
fi

echo "  ✅ Gemini hosted setup keeps API key out of repo-local hook config"

SYMLINK_GEMINI_DIR="$TEST_DIR/symlink-project/.gemini"
SYMLINK_STATE_DIR="$TEST_DIR/symlink-home/.aport/gemini-cli"
SYMLINK_TARGET="$TEST_DIR/symlink-target-settings.json"
rm -rf "$TEST_DIR/symlink-project" "$TEST_DIR/symlink-home"
mkdir -p "$SYMLINK_GEMINI_DIR" "$SYMLINK_STATE_DIR" "$TEST_DIR/symlink-home"
printf '{"hooks":{}}\n' > "$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$SYMLINK_GEMINI_DIR/settings.json"

set +e
(
    cd "$TEST_DIR/symlink-project"
    HOME="$TEST_DIR/symlink-home" \
        APORT_NONINTERACTIVE=1 \
        APORT_GEMINI_CLI_HOOKS_DIR="$SYMLINK_GEMINI_DIR" \
        APORT_GEMINI_CLI_CONFIG_DIR="$SYMLINK_STATE_DIR" \
        "$DISPATCHER" gemini --output "$SYMLINK_STATE_DIR/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/gemini-symlink-setup.log" 2>&1
)
SYMLINK_EXIT=$?
set -e
if [[ "$SYMLINK_EXIT" -eq 0 ]]; then
    echo "FAIL: Gemini setup should reject symlinked settings.json" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/gemini-symlink-setup.log" || {
    echo "FAIL: expected symlink refusal in Gemini setup output" >&2
    cat "$TEST_DIR/gemini-symlink-setup.log" >&2
    exit 1
}
if [[ "$(cat "$SYMLINK_TARGET")" != '{"hooks":{}}' ]]; then
    echo "FAIL: Gemini setup modified symlink target" >&2
    cat "$SYMLINK_TARGET" >&2
    exit 1
fi

echo "  ✅ Gemini setup rejects symlinked settings targets"

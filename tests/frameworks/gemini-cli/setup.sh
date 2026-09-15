#!/bin/bash
# Integration test: run agent-guardrails gemini and assert settings.json is written.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output/gemini")}"
GEMINI_DIR="$TEST_DIR/project/.gemini"
GEMINI_STATE_DIR="$TEST_DIR/home/.aport/gemini-cli"
PASSPORT_PATH="$GEMINI_STATE_DIR/aport/passport.json"

file_mode() {
    stat -c '%a' "$1" 2> /dev/null || stat -f '%Lp' "$1"
}

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

SCHEMA_GEMINI_DIR="$TEST_DIR/schema-project/.gemini"
SCHEMA_STATE_DIR="$TEST_DIR/schema-home/.aport/gemini-cli"
rm -rf "$TEST_DIR/schema-project" "$TEST_DIR/schema-home"
mkdir -p "$SCHEMA_GEMINI_DIR" "$SCHEMA_STATE_DIR" "$TEST_DIR/schema-home"
printf '{"hooks":[]}\n' > "$SCHEMA_GEMINI_DIR/settings.json"

set +e
(
    cd "$TEST_DIR/schema-project"
    HOME="$TEST_DIR/schema-home" \
        APORT_NONINTERACTIVE=1 \
        APORT_GEMINI_CLI_HOOKS_DIR="$SCHEMA_GEMINI_DIR" \
        APORT_GEMINI_CLI_CONFIG_DIR="$SCHEMA_STATE_DIR" \
        "$DISPATCHER" gemini --output "$SCHEMA_STATE_DIR/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/gemini-schema-hooks-array.log" 2>&1
)
SCHEMA_EXIT=$?
set -e
if [[ "$SCHEMA_EXIT" -eq 0 ]]; then
    echo "FAIL: Gemini setup should reject array-shaped hooks JSON" >&2
    cat "$SCHEMA_GEMINI_DIR/settings.json" >&2
    exit 1
fi
grep -q "non-object hooks" "$TEST_DIR/gemini-schema-hooks-array.log" || {
    echo "FAIL: expected Gemini non-object hooks refusal" >&2
    cat "$TEST_DIR/gemini-schema-hooks-array.log" >&2
    exit 1
}

echo "  ✅ Gemini setup rejects array-shaped hooks JSON"

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

PRECEDENCE_GEMINI_DIR="$TEST_DIR/precedence-project/.gemini"
PRECEDENCE_GENERIC_STATE_DIR="$TEST_DIR/precedence-home/.aport/generic"
PRECEDENCE_GEMINI_STATE_DIR="$TEST_DIR/precedence-home/.aport/gemini-specific"
rm -rf "$TEST_DIR/precedence-project" "$TEST_DIR/precedence-home"
mkdir -p "$PRECEDENCE_GEMINI_DIR" "$PRECEDENCE_GENERIC_STATE_DIR" "$PRECEDENCE_GEMINI_STATE_DIR" "$TEST_DIR/precedence-home"

(
    cd "$TEST_DIR/precedence-project"
    HOME="$TEST_DIR/precedence-home" \
        APORT_NONINTERACTIVE=1 \
        APORT_CONFIG_DIR="$PRECEDENCE_GENERIC_STATE_DIR" \
        APORT_GEMINI_CLI_CONFIG_DIR="$PRECEDENCE_GEMINI_STATE_DIR" \
        APORT_GEMINI_CLI_HOOKS_DIR="$PRECEDENCE_GEMINI_DIR" \
        APORT_AGENT_ID="ap_1234567890abcdef1234567890abcdef" \
        APORT_API_KEY="apk_secret_should_not_be_in_repo" \
        "$DISPATCHER" gemini --non-interactive --mode=api > "$TEST_DIR/gemini-precedence-setup.log" 2>&1
)

[[ -f "$PRECEDENCE_GEMINI_STATE_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: Gemini setup should prefer APORT_GEMINI_CLI_CONFIG_DIR over generic APORT_CONFIG_DIR" >&2
    cat "$TEST_DIR/gemini-precedence-setup.log" >&2
    exit 1
}
[[ ! -e "$PRECEDENCE_GENERIC_STATE_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: Gemini setup wrote mode state to generic APORT_CONFIG_DIR despite framework-specific override" >&2
    cat "$PRECEDENCE_GENERIC_STATE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
jq -e --arg state "$PRECEDENCE_GEMINI_STATE_DIR" '
  [.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true) | .command // ""]
  | any(contains("APORT_GEMINI_CLI_CONFIG_DIR=") and contains($state))
' "$PRECEDENCE_GEMINI_DIR/settings.json" > /dev/null || {
    echo "FAIL: Gemini hook command should point at framework-specific state directory" >&2
    jq -c '.hooks.BeforeTool' "$PRECEDENCE_GEMINI_DIR/settings.json" >&2
    exit 1
}
if jq -r '.hooks.BeforeTool[]?.hooks[]? | select(.__aport_hook == true) | .command // ""' "$PRECEDENCE_GEMINI_DIR/settings.json" | grep -F "$PRECEDENCE_GENERIC_STATE_DIR" > /dev/null; then
    echo "FAIL: Gemini hook command should not point at generic APORT_CONFIG_DIR when APORT_GEMINI_CLI_CONFIG_DIR is set" >&2
    jq -c '.hooks.BeforeTool' "$PRECEDENCE_GEMINI_DIR/settings.json" >&2
    exit 1
fi

echo "  ✅ Gemini setup prefers framework-specific config overrides"

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

SYMLINK_AUDIT_PROJECT="$TEST_DIR/symlink-audit-project"
SYMLINK_AUDIT_HOME="$TEST_DIR/symlink-audit-home"
SYMLINK_AUDIT_DIR="$SYMLINK_AUDIT_HOME/.aport/gemini-cli"
SYMLINK_AUDIT_TARGET="$TEST_DIR/symlink-audit-target.log"
rm -rf "$SYMLINK_AUDIT_PROJECT" "$SYMLINK_AUDIT_HOME"
mkdir -p "$SYMLINK_AUDIT_PROJECT/.gemini" "$SYMLINK_AUDIT_DIR/aport" "$SYMLINK_AUDIT_HOME"
printf 'audit-target\n' > "$SYMLINK_AUDIT_TARGET"
chmod 644 "$SYMLINK_AUDIT_TARGET"
ln -s "$SYMLINK_AUDIT_TARGET" "$SYMLINK_AUDIT_DIR/aport/audit.log"

set +e
(
    cd "$SYMLINK_AUDIT_PROJECT"
    HOME="$SYMLINK_AUDIT_HOME" \
        APORT_NONINTERACTIVE=1 \
        APORT_GEMINI_CLI_HOOKS_DIR="$SYMLINK_AUDIT_PROJECT/.gemini" \
        APORT_GEMINI_CLI_CONFIG_DIR="$SYMLINK_AUDIT_DIR" \
        "$DISPATCHER" gemini --output "$SYMLINK_AUDIT_DIR/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/gemini-symlink-audit.log" 2>&1
)
SYMLINK_AUDIT_EXIT=$?
set -e
if [[ "$SYMLINK_AUDIT_EXIT" -eq 0 ]]; then
    echo "FAIL: Gemini setup should reject symlinked audit.log" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/gemini-symlink-audit.log" || {
    echo "FAIL: expected audit-log symlink refusal in Gemini setup output" >&2
    cat "$TEST_DIR/gemini-symlink-audit.log" >&2
    exit 1
}
if [[ "$(cat "$SYMLINK_AUDIT_TARGET")" != "audit-target" ]]; then
    echo "FAIL: Gemini setup modified symlinked audit target contents" >&2
    cat "$SYMLINK_AUDIT_TARGET" >&2
    exit 1
fi
if [[ "$(file_mode "$SYMLINK_AUDIT_TARGET")" != "644" ]]; then
    echo "FAIL: Gemini setup modified symlinked audit target permissions" >&2
    ls -l "$SYMLINK_AUDIT_TARGET" >&2
    exit 1
fi

echo "  ✅ Gemini setup rejects symlinked audit log targets"

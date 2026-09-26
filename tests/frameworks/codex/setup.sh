#!/bin/bash
# Integration test: run agent-guardrails codex and assert repo-local hooks.json is written.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output/codex")}"
CODEX_DIR="$TEST_DIR/project/.codex"
CODEX_STATE_DIR="$TEST_DIR/home/.aport/codex"
PASSPORT_PATH="$CODEX_STATE_DIR/aport/passport.json"

file_mode() {
    stat -c '%a' "$1" 2> /dev/null || stat -f '%Lp' "$1"
}

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
jq -e '
  any(.capabilities[]; .id == "media.image.generate")
  and (.limits["media.image.generate"].allowed_providers | type == "array")
  and (.limits["media.image.generate"].max_prompt_length | type == "number")
  and (.limits["media.image.generate"].max_referenced_images | type == "number")
  and (.limits["media.image.generate"].max_output_images | type == "number")
  and (.limits["media.image.generate"].allowed_output_formats | type == "array")
' "$PASSPORT_PATH" > /dev/null || {
    echo "FAIL: Codex setup passport should include media.image.generate capability and required limits" >&2
    cat "$PASSPORT_PATH" >&2
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

CUSTOM_CODEX_HOME_PROJECT="$TEST_DIR/custom-codex-home-project"
CUSTOM_CODEX_HOME_ROOT="$TEST_DIR/custom-codex-home"
CUSTOM_CODEX_HOME_USER="$TEST_DIR/custom-codex-user-home"
CUSTOM_CODEX_HOME_STATE="$TEST_DIR/custom-codex-user-home/.aport/codex"
rm -rf "$CUSTOM_CODEX_HOME_PROJECT" "$CUSTOM_CODEX_HOME_ROOT" "$CUSTOM_CODEX_HOME_USER"
mkdir -p "$CUSTOM_CODEX_HOME_PROJECT" "$CUSTOM_CODEX_HOME_ROOT" "$CUSTOM_CODEX_HOME_STATE" "$CUSTOM_CODEX_HOME_USER"

echo "  Test: Codex global setup honors CODEX_HOME..."
(
    cd "$CUSTOM_CODEX_HOME_PROJECT"
    unset APORT_CODEX_HOOKS_DIR
    HOME="$CUSTOM_CODEX_HOME_USER" \
        CODEX_HOME="$CUSTOM_CODEX_HOME_ROOT" \
        APORT_NONINTERACTIVE=1 \
        APORT_CODEX_CONFIG_DIR="$CUSTOM_CODEX_HOME_STATE" \
        "$DISPATCHER" codex --global --output "$CUSTOM_CODEX_HOME_STATE/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/codex-custom-codex-home.log" 2>&1
)
[[ -f "$CUSTOM_CODEX_HOME_ROOT/hooks.json" ]] || {
    echo "FAIL: Codex global setup should write hooks.json under CODEX_HOME" >&2
    cat "$TEST_DIR/codex-custom-codex-home.log" >&2
    exit 1
}
[[ ! -e "$CUSTOM_CODEX_HOME_USER/.codex/hooks.json" ]] || {
    echo "FAIL: Codex global setup wrote hooks.json to HOME/.codex instead of CODEX_HOME" >&2
    cat "$CUSTOM_CODEX_HOME_USER/.codex/hooks.json" >&2
    exit 1
}
jq -e --arg state "$CUSTOM_CODEX_HOME_STATE" '
  [.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true) | .command // ""]
  | any(contains("APORT_CODEX_CONFIG_DIR=") and contains($state))
' "$CUSTOM_CODEX_HOME_ROOT/hooks.json" > /dev/null || {
    echo "FAIL: CODEX_HOME hooks should point at the selected APort state directory" >&2
    jq -c '.hooks.PreToolUse' "$CUSTOM_CODEX_HOME_ROOT/hooks.json" >&2
    exit 1
}

echo "  ✅ Codex global setup honors CODEX_HOME"

SCHEMA_CODEX_DIR="$TEST_DIR/schema-project/.codex"
SCHEMA_STATE_DIR="$TEST_DIR/schema-home/.aport/codex"
rm -rf "$TEST_DIR/schema-project" "$TEST_DIR/schema-home"
mkdir -p "$SCHEMA_CODEX_DIR" "$SCHEMA_STATE_DIR" "$TEST_DIR/schema-home"
printf '{"hooks":[]}\n' > "$SCHEMA_CODEX_DIR/hooks.json"

set +e
(
    cd "$TEST_DIR/schema-project"
    HOME="$TEST_DIR/schema-home" \
        APORT_NONINTERACTIVE=1 \
        APORT_CODEX_HOOKS_DIR="$SCHEMA_CODEX_DIR" \
        APORT_CODEX_CONFIG_DIR="$SCHEMA_STATE_DIR" \
        "$DISPATCHER" codex --output "$SCHEMA_STATE_DIR/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/codex-schema-hooks-array.log" 2>&1
)
SCHEMA_EXIT=$?
set -e
if [[ "$SCHEMA_EXIT" -eq 0 ]]; then
    echo "FAIL: Codex setup should reject array-shaped hooks JSON" >&2
    cat "$SCHEMA_CODEX_DIR/hooks.json" >&2
    exit 1
fi
grep -q "non-object hooks" "$TEST_DIR/codex-schema-hooks-array.log" || {
    echo "FAIL: expected Codex non-object hooks refusal" >&2
    cat "$TEST_DIR/codex-schema-hooks-array.log" >&2
    exit 1
}

echo "  ✅ Codex setup rejects array-shaped hooks JSON"

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

PRECEDENCE_CODEX_DIR="$TEST_DIR/precedence-project/.codex"
PRECEDENCE_GENERIC_STATE_DIR="$TEST_DIR/precedence-home/.aport/generic"
PRECEDENCE_CODEX_STATE_DIR="$TEST_DIR/precedence-home/.aport/codex-specific"
rm -rf "$TEST_DIR/precedence-project" "$TEST_DIR/precedence-home"
mkdir -p "$PRECEDENCE_CODEX_DIR" "$PRECEDENCE_GENERIC_STATE_DIR" "$PRECEDENCE_CODEX_STATE_DIR" "$TEST_DIR/precedence-home"

(
    cd "$TEST_DIR/precedence-project"
    HOME="$TEST_DIR/precedence-home" \
        APORT_NONINTERACTIVE=1 \
        APORT_CONFIG_DIR="$PRECEDENCE_GENERIC_STATE_DIR" \
        APORT_CODEX_CONFIG_DIR="$PRECEDENCE_CODEX_STATE_DIR" \
        APORT_CODEX_HOOKS_DIR="$PRECEDENCE_CODEX_DIR" \
        APORT_AGENT_ID="ap_1234567890abcdef1234567890abcdef" \
        APORT_API_KEY="apk_secret_should_not_be_in_repo" \
        "$DISPATCHER" codex --non-interactive --mode=api > "$TEST_DIR/codex-precedence-setup.log" 2>&1
)

[[ -f "$PRECEDENCE_CODEX_STATE_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: Codex setup should prefer APORT_CODEX_CONFIG_DIR over generic APORT_CONFIG_DIR" >&2
    cat "$TEST_DIR/codex-precedence-setup.log" >&2
    exit 1
}
[[ ! -e "$PRECEDENCE_GENERIC_STATE_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: Codex setup wrote mode state to generic APORT_CONFIG_DIR despite framework-specific override" >&2
    cat "$PRECEDENCE_GENERIC_STATE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
jq -e --arg state "$PRECEDENCE_CODEX_STATE_DIR" '
  [.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true) | .command // ""]
  | any(contains("APORT_CODEX_CONFIG_DIR=") and contains($state))
' "$PRECEDENCE_CODEX_DIR/hooks.json" > /dev/null || {
    echo "FAIL: Codex hook command should point at framework-specific state directory" >&2
    jq -c '.hooks.PreToolUse' "$PRECEDENCE_CODEX_DIR/hooks.json" >&2
    exit 1
}
if jq -r '.hooks.PreToolUse[]?.hooks[]? | select(.__aport_hook == true) | .command // ""' "$PRECEDENCE_CODEX_DIR/hooks.json" | grep -F "$PRECEDENCE_GENERIC_STATE_DIR" > /dev/null; then
    echo "FAIL: Codex hook command should not point at generic APORT_CONFIG_DIR when APORT_CODEX_CONFIG_DIR is set" >&2
    jq -c '.hooks.PreToolUse' "$PRECEDENCE_CODEX_DIR/hooks.json" >&2
    exit 1
fi

echo "  ✅ Codex setup prefers framework-specific config overrides"

HOSTED_SYMLINK_CODEX_DIR="$TEST_DIR/hosted-symlink-project/.codex"
HOSTED_SYMLINK_STATE_DIR="$TEST_DIR/hosted-symlink-home/.aport/codex"
HOSTED_SYMLINK_TARGET="$TEST_DIR/hosted-symlink-passport-target.json"
rm -rf "$TEST_DIR/hosted-symlink-project" "$TEST_DIR/hosted-symlink-home"
mkdir -p "$HOSTED_SYMLINK_CODEX_DIR" "$HOSTED_SYMLINK_STATE_DIR/aport" "$TEST_DIR/hosted-symlink-home"
printf '{"sentinel":true}\n' > "$HOSTED_SYMLINK_TARGET"
chmod 644 "$HOSTED_SYMLINK_TARGET"
ln -s "$HOSTED_SYMLINK_TARGET" "$HOSTED_SYMLINK_STATE_DIR/aport/passport.json"
if (
    cd "$TEST_DIR/hosted-symlink-project"
    HOME="$TEST_DIR/hosted-symlink-home" \
        APORT_NONINTERACTIVE=1 \
        APORT_CODEX_HOOKS_DIR="$HOSTED_SYMLINK_CODEX_DIR" \
        APORT_CODEX_CONFIG_DIR="$HOSTED_SYMLINK_STATE_DIR" \
        APORT_AGENT_ID="ap_1234567890abcdef1234567890abcdef" \
        APORT_API_KEY="apk_secret_should_not_be_in_repo" \
        "$DISPATCHER" codex --non-interactive --mode=api > "$TEST_DIR/codex-hosted-symlink-passport.log" 2>&1
); then
    echo "FAIL: Codex hosted setup should reject symlinked passport files before chmod" >&2
    cat "$TEST_DIR/codex-hosted-symlink-passport.log" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/codex-hosted-symlink-passport.log" || {
    echo "FAIL: expected hosted symlink passport refusal in Codex setup output" >&2
    cat "$TEST_DIR/codex-hosted-symlink-passport.log" >&2
    exit 1
}
if [[ "$(file_mode "$HOSTED_SYMLINK_TARGET")" != "644" ]]; then
    echo "FAIL: Codex hosted setup must not chmod symlinked passport target" >&2
    ls -l "$HOSTED_SYMLINK_TARGET" >&2
    exit 1
fi

echo "  ✅ Codex hosted setup rejects symlinked passport targets"

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

SYMLINK_ROOT_PROJECT="$TEST_DIR/symlink-root-project"
SYMLINK_ROOT_HOME="$TEST_DIR/symlink-root-home"
SYMLINK_ROOT_LINK="$SYMLINK_ROOT_HOME/.aport/codex"
SYMLINK_ROOT_TARGET="$TEST_DIR/symlink-state-root-target"
rm -rf "$SYMLINK_ROOT_PROJECT" "$SYMLINK_ROOT_HOME" "$SYMLINK_ROOT_TARGET"
mkdir -p "$SYMLINK_ROOT_PROJECT" "$(dirname "$SYMLINK_ROOT_LINK")" "$SYMLINK_ROOT_TARGET"
printf 'sentinel\n' > "$SYMLINK_ROOT_TARGET/sentinel.txt"
ln -s "$SYMLINK_ROOT_TARGET" "$SYMLINK_ROOT_LINK"

set +e
(
    cd "$SYMLINK_ROOT_PROJECT"
    HOME="$SYMLINK_ROOT_HOME" \
        APORT_NONINTERACTIVE=1 \
        APORT_CODEX_CONFIG_DIR="$SYMLINK_ROOT_LINK" \
        "$DISPATCHER" codex --output "$SYMLINK_ROOT_LINK/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/codex-symlink-state-root.log" 2>&1
)
SYMLINK_ROOT_EXIT=$?
set -e
if [[ "$SYMLINK_ROOT_EXIT" -eq 0 ]]; then
    echo "FAIL: Codex setup should reject symlinked state roots" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/codex-symlink-state-root.log" || {
    echo "FAIL: expected state-root symlink refusal in Codex setup output" >&2
    cat "$TEST_DIR/codex-symlink-state-root.log" >&2
    exit 1
}
if [[ -e "$SYMLINK_ROOT_TARGET/aport" ]]; then
    echo "FAIL: Codex setup wrote through symlinked state root" >&2
    find "$SYMLINK_ROOT_TARGET" -maxdepth 2 -print >&2
    exit 1
fi
[[ "$(cat "$SYMLINK_ROOT_TARGET/sentinel.txt")" = "sentinel" ]] || {
    echo "FAIL: Codex setup modified symlinked state target" >&2
    cat "$SYMLINK_ROOT_TARGET/sentinel.txt" >&2
    exit 1
}

echo "  ✅ Codex setup rejects symlinked state roots before writes"

SYMLINK_AUDIT_PROJECT="$TEST_DIR/symlink-audit-project"
SYMLINK_AUDIT_HOME="$TEST_DIR/symlink-audit-home"
SYMLINK_AUDIT_DIR="$SYMLINK_AUDIT_HOME/.aport/codex"
SYMLINK_AUDIT_TARGET="$TEST_DIR/symlink-audit-target.log"
rm -rf "$SYMLINK_AUDIT_PROJECT" "$SYMLINK_AUDIT_HOME"
mkdir -p "$SYMLINK_AUDIT_PROJECT/.codex" "$SYMLINK_AUDIT_DIR/aport" "$SYMLINK_AUDIT_HOME"
printf 'audit-target\n' > "$SYMLINK_AUDIT_TARGET"
chmod 644 "$SYMLINK_AUDIT_TARGET"
ln -s "$SYMLINK_AUDIT_TARGET" "$SYMLINK_AUDIT_DIR/aport/audit.log"

set +e
(
    cd "$SYMLINK_AUDIT_PROJECT"
    HOME="$SYMLINK_AUDIT_HOME" \
        APORT_NONINTERACTIVE=1 \
        APORT_CODEX_HOOKS_DIR="$SYMLINK_AUDIT_PROJECT/.codex" \
        APORT_CODEX_CONFIG_DIR="$SYMLINK_AUDIT_DIR" \
        "$DISPATCHER" codex --output "$SYMLINK_AUDIT_DIR/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/codex-symlink-audit.log" 2>&1
)
SYMLINK_AUDIT_EXIT=$?
set -e
if [[ "$SYMLINK_AUDIT_EXIT" -eq 0 ]]; then
    echo "FAIL: Codex setup should reject symlinked audit.log" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/codex-symlink-audit.log" || {
    echo "FAIL: expected audit-log symlink refusal in Codex setup output" >&2
    cat "$TEST_DIR/codex-symlink-audit.log" >&2
    exit 1
}
if [[ "$(cat "$SYMLINK_AUDIT_TARGET")" != "audit-target" ]]; then
    echo "FAIL: Codex setup modified symlinked audit target contents" >&2
    cat "$SYMLINK_AUDIT_TARGET" >&2
    exit 1
fi
if [[ "$(file_mode "$SYMLINK_AUDIT_TARGET")" != "644" ]]; then
    echo "FAIL: Codex setup modified symlinked audit target permissions" >&2
    ls -l "$SYMLINK_AUDIT_TARGET" >&2
    exit 1
fi

echo "  ✅ Codex setup rejects symlinked audit log targets"

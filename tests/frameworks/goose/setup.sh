#!/bin/bash
# Integration test: run agent-guardrails goose and assert Open Plugin layout.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output/goose")}"
PROJECT_DIR="$TEST_DIR/project"
GOOSE_CONFIG_DIR="$TEST_DIR/.aport/goose"
GOOSE_PLUGIN_DIR="$PROJECT_DIR/.agents/plugins/aport-guardrail"
PASSPORT_PATH="$GOOSE_CONFIG_DIR/aport/passport.json"

file_mode() {
    stat -c '%a' "$1" 2> /dev/null || stat -f '%Lp' "$1"
}

rm -rf "$PROJECT_DIR" "$GOOSE_CONFIG_DIR"
mkdir -p "$PROJECT_DIR" "$(dirname "$PASSPORT_PATH")"

echo ""
echo "  Integration — Goose setup"
echo ""

export APORT_NONINTERACTIVE=1
export APORT_GOOSE_CONFIG_DIR="$GOOSE_CONFIG_DIR"
export APORT_GOOSE_PLUGIN_DIR="$GOOSE_PLUGIN_DIR"
export APORT_API_KEY="apk_test_should_not_be_in_plugin"
(
    cd "$PROJECT_DIR"
    "$DISPATCHER" goose --output "$PASSPORT_PATH" --non-interactive --mode=api --api-url=https://api.aport.io ap_test123 > "$TEST_DIR/goose-setup.log" 2>&1
)

[[ -f "$GOOSE_PLUGIN_DIR/plugin.json" ]] || {
    echo "FAIL: expected Goose plugin.json" >&2
    exit 1
}
[[ -f "$GOOSE_PLUGIN_DIR/hooks/hooks.json" ]] || {
    echo "FAIL: expected Goose hooks/hooks.json" >&2
    exit 1
}
[[ -x "$GOOSE_PLUGIN_DIR/scripts/aport-goose-hook.sh" ]] || {
    echo "FAIL: expected executable Goose hook wrapper" >&2
    exit 1
}

jq -e '.name == "aport-guardrail"' "$GOOSE_PLUGIN_DIR/plugin.json" > /dev/null || {
    echo "FAIL: Goose plugin name should be aport-guardrail" >&2
    cat "$GOOSE_PLUGIN_DIR/plugin.json" >&2
    exit 1
}
jq -e '
  .hooks.PreToolUse[0].hooks[0].type == "command"
  and .hooks.PreToolUse[0].hooks[0].command == "\"${PLUGIN_ROOT}/scripts/aport-goose-hook.sh\""
  and .hooks.PreToolUse[0].hooks[0].on_failure == "block"
' "$GOOSE_PLUGIN_DIR/hooks/hooks.json" > /dev/null || {
    echo "FAIL: Goose hooks file should register blocking PreToolUse command hook" >&2
    cat "$GOOSE_PLUGIN_DIR/hooks/hooks.json" >&2
    exit 1
}

[[ -x "$GOOSE_CONFIG_DIR/aport/runtime/bin/aport-goose-hook.sh" ]] || {
    echo "FAIL: expected stable Goose runtime hook at $GOOSE_CONFIG_DIR/aport/runtime/bin/aport-goose-hook.sh" >&2
    exit 1
}
grep -q "$GOOSE_CONFIG_DIR/aport/runtime/bin/aport-goose-hook.sh" "$GOOSE_PLUGIN_DIR/scripts/aport-goose-hook.sh" || {
    echo "FAIL: Goose plugin wrapper should execute the stable APort runtime hook" >&2
    cat "$GOOSE_PLUGIN_DIR/scripts/aport-goose-hook.sh" >&2
    exit 1
}

if grep -R 'apk_test_should_not_be_in_plugin' "$GOOSE_PLUGIN_DIR" > /dev/null 2>&1; then
    echo "FAIL: Goose plugin files must not contain APort API keys" >&2
    exit 1
fi

[[ -f "$GOOSE_CONFIG_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: expected Goose mode file" >&2
    exit 1
}
grep -q '^APORT_API_KEY=apk_test_should_not_be_in_plugin$' "$GOOSE_CONFIG_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: API key should be stored only in Goose APort mode file" >&2
    cat "$GOOSE_CONFIG_DIR/aport/guardrail-mode.env" >&2
    exit 1
}

echo "  ✅ Goose setup integration passed"

GENERIC_PROJECT_DIR="$TEST_DIR/generic-config-project"
GENERIC_CONFIG_DIR="$TEST_DIR/.aport/goose-generic"
GENERIC_PLUGIN_DIR="$GENERIC_PROJECT_DIR/.agents/plugins/aport-guardrail"
rm -rf "$GENERIC_PROJECT_DIR" "$GENERIC_CONFIG_DIR"
mkdir -p "$GENERIC_PROJECT_DIR"
(
    cd "$GENERIC_PROJECT_DIR"
    unset APORT_GOOSE_CONFIG_DIR
    APORT_NONINTERACTIVE=1 \
        APORT_CONFIG_DIR="$GENERIC_CONFIG_DIR" \
        APORT_GOOSE_PLUGIN_DIR="$GENERIC_PLUGIN_DIR" \
        APORT_API_KEY="apk_test_should_not_be_in_plugin" \
        "$DISPATCHER" goose --non-interactive --mode=api ap_test123 > "$TEST_DIR/goose-generic-config-setup.log" 2>&1
)

[[ -f "$GENERIC_CONFIG_DIR/aport/guardrail-mode.env" ]] || {
    echo "FAIL: Goose setup should honor generic APORT_CONFIG_DIR" >&2
    cat "$TEST_DIR/goose-generic-config-setup.log" >&2
    exit 1
}
grep -q "$GENERIC_CONFIG_DIR/aport/runtime/bin/aport-goose-hook.sh" "$GENERIC_PLUGIN_DIR/scripts/aport-goose-hook.sh" || {
    echo "FAIL: Goose generic config wrapper should execute the runtime hook under APORT_CONFIG_DIR" >&2
    cat "$GENERIC_PLUGIN_DIR/scripts/aport-goose-hook.sh" >&2
    exit 1
}

echo "  ✅ Goose setup honors generic APORT_CONFIG_DIR"

SPACES_PROJECT_DIR="$TEST_DIR/project with spaces"
SPACES_CONFIG_DIR="$TEST_DIR/.aport/goose with spaces"
SPACES_PLUGIN_DIR="$SPACES_PROJECT_DIR/.agents/plugins/aport-guardrail"
rm -rf "$SPACES_PROJECT_DIR" "$SPACES_CONFIG_DIR"
mkdir -p "$SPACES_PROJECT_DIR"
(
    cd "$SPACES_PROJECT_DIR"
    APORT_NONINTERACTIVE=1 \
        APORT_GOOSE_CONFIG_DIR="$SPACES_CONFIG_DIR" \
        APORT_GOOSE_PLUGIN_DIR="$SPACES_PLUGIN_DIR" \
        "$DISPATCHER" goose --non-interactive --mode=local > "$TEST_DIR/goose-spaces-setup.log" 2>&1
)

SPACES_HOOK_COMMAND="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SPACES_PLUGIN_DIR/hooks/hooks.json")"
[[ "$SPACES_HOOK_COMMAND" == '"${PLUGIN_ROOT}/scripts/aport-goose-hook.sh"' ]] || {
    echo "FAIL: Goose hook command should quote PLUGIN_ROOT path for spaces" >&2
    cat "$SPACES_PLUGIN_DIR/hooks/hooks.json" >&2
    exit 1
}
set +e
PLUGIN_ROOT="$SPACES_PLUGIN_DIR" sh -c "$SPACES_HOOK_COMMAND" > "$TEST_DIR/goose-spaces-hook.out" 2>&1 < /dev/null
SPACES_HOOK_EXIT=$?
set -e
if [[ "$SPACES_HOOK_EXIT" -ne 0 ]]; then
    echo "FAIL: Goose hook command should execute from paths containing spaces" >&2
    cat "$TEST_DIR/goose-spaces-hook.out" >&2
    exit 1
fi
grep -q 'oap.empty_input' "$TEST_DIR/goose-spaces-hook.out" || {
    echo "FAIL: Goose hook command should reach the APort hook, not fail shell parsing" >&2
    cat "$TEST_DIR/goose-spaces-hook.out" >&2
    exit 1
}

echo "  ✅ Goose setup quotes hook command for paths with spaces"

WARN_PROJECT_DIR="$TEST_DIR/warn-project"
WARN_CONFIG_DIR="$TEST_DIR/.aport/goose-warn"
WARN_PLUGIN_DIR="$WARN_PROJECT_DIR/.agents/plugins/aport-guardrail"
mkdir -p "$WARN_PROJECT_DIR"
(
    cd "$WARN_PROJECT_DIR"
    APORT_NONINTERACTIVE=1 \
        APORT_GOOSE_CONFIG_DIR="$WARN_CONFIG_DIR" \
        APORT_GOOSE_PLUGIN_DIR="$WARN_PLUGIN_DIR" \
        APORT_API_KEY="apk_test_should_not_be_in_plugin" \
        "$DISPATCHER" goose --non-interactive --mode=api --enforcement=warn ap_test123 > "$TEST_DIR/goose-warn-setup.log" 2>&1
)

jq -e '.hooks.PreToolUse[0].hooks[0].on_failure == "block"' "$WARN_PLUGIN_DIR/hooks/hooks.json" > /dev/null || {
    echo "FAIL: Goose warn mode must keep hook failures fail-closed with on_failure=block" >&2
    cat "$WARN_PLUGIN_DIR/hooks/hooks.json" >&2
    exit 1
}
echo "  ✅ Goose warn mode keeps hook failures fail-closed"

SYMLINK_PROJECT_DIR="$TEST_DIR/symlink-project"
SYMLINK_CONFIG_DIR="$TEST_DIR/.aport/goose-symlink"
SYMLINK_PLUGIN_DIR="$SYMLINK_PROJECT_DIR/.agents/plugins/aport-guardrail"
SYMLINK_TARGET="$TEST_DIR/goose-symlink-plugin-target.json"
rm -rf "$SYMLINK_PROJECT_DIR" "$SYMLINK_CONFIG_DIR"
rm -f "$SYMLINK_TARGET"
mkdir -p "$SYMLINK_PLUGIN_DIR" "$SYMLINK_PROJECT_DIR"
printf '{"name":"aport-guardrail","version":"existing"}\n' > "$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$SYMLINK_PLUGIN_DIR/plugin.json"

set +e
(
    cd "$SYMLINK_PROJECT_DIR"
    APORT_NONINTERACTIVE=1 \
        APORT_GOOSE_CONFIG_DIR="$SYMLINK_CONFIG_DIR" \
        APORT_GOOSE_PLUGIN_DIR="$SYMLINK_PLUGIN_DIR" \
        "$DISPATCHER" goose --non-interactive --mode=local > "$TEST_DIR/goose-symlink-setup.log" 2>&1
)
SYMLINK_EXIT=$?
set -e
if [[ "$SYMLINK_EXIT" -eq 0 ]]; then
    echo "FAIL: Goose setup should reject symlinked plugin files" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/goose-symlink-setup.log" || {
    echo "FAIL: expected symlink refusal in Goose setup output" >&2
    cat "$TEST_DIR/goose-symlink-setup.log" >&2
    exit 1
}
if [[ "$(cat "$SYMLINK_TARGET")" != '{"name":"aport-guardrail","version":"existing"}' ]]; then
    echo "FAIL: Goose setup modified symlink target" >&2
    cat "$SYMLINK_TARGET" >&2
    exit 1
fi

echo "  ✅ Goose setup rejects symlinked plugin targets"

SYMLINK_AUDIT_PROJECT="$TEST_DIR/symlink-audit-project"
SYMLINK_AUDIT_CONFIG_DIR="$TEST_DIR/.aport/goose-symlink-audit"
SYMLINK_AUDIT_PLUGIN_DIR="$SYMLINK_AUDIT_PROJECT/.agents/plugins/aport-guardrail"
SYMLINK_AUDIT_TARGET="$TEST_DIR/goose-symlink-audit-target.log"
rm -rf "$SYMLINK_AUDIT_PROJECT" "$SYMLINK_AUDIT_CONFIG_DIR"
mkdir -p "$SYMLINK_AUDIT_PROJECT" "$SYMLINK_AUDIT_CONFIG_DIR/aport"
printf 'audit-target\n' > "$SYMLINK_AUDIT_TARGET"
chmod 644 "$SYMLINK_AUDIT_TARGET"
ln -s "$SYMLINK_AUDIT_TARGET" "$SYMLINK_AUDIT_CONFIG_DIR/aport/audit.log"

set +e
(
    cd "$SYMLINK_AUDIT_PROJECT"
    APORT_NONINTERACTIVE=1 \
        APORT_GOOSE_CONFIG_DIR="$SYMLINK_AUDIT_CONFIG_DIR" \
        APORT_GOOSE_PLUGIN_DIR="$SYMLINK_AUDIT_PLUGIN_DIR" \
        "$DISPATCHER" goose --output "$SYMLINK_AUDIT_CONFIG_DIR/aport/passport.json" --non-interactive --mode=local > "$TEST_DIR/goose-symlink-audit.log" 2>&1
)
SYMLINK_AUDIT_EXIT=$?
set -e
if [[ "$SYMLINK_AUDIT_EXIT" -eq 0 ]]; then
    echo "FAIL: Goose setup should reject symlinked audit.log" >&2
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/goose-symlink-audit.log" || {
    echo "FAIL: expected audit-log symlink refusal in Goose setup output" >&2
    cat "$TEST_DIR/goose-symlink-audit.log" >&2
    exit 1
}
if [[ "$(cat "$SYMLINK_AUDIT_TARGET")" != "audit-target" ]]; then
    echo "FAIL: Goose setup modified symlinked audit target contents" >&2
    cat "$SYMLINK_AUDIT_TARGET" >&2
    exit 1
fi
if [[ "$(file_mode "$SYMLINK_AUDIT_TARGET")" != "644" ]]; then
    echo "FAIL: Goose setup modified symlinked audit target permissions" >&2
    ls -l "$SYMLINK_AUDIT_TARGET" >&2
    exit 1
fi

echo "  ✅ Goose setup rejects symlinked audit log targets"

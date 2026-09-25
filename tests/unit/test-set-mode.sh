#!/bin/bash
# Unit test: mode changes update config only and preserve existing passport settings.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
MODE_HELPER="$REPO_ROOT/bin/aport-set-mode.sh"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"

shell_quote_value() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

echo ""
echo "  Unit — aport set-mode"
echo ""

REUSE_HOME="$TEST_DIR/reuse-home"
mkdir -p "$REUSE_HOME"
if HOME="$REUSE_HOME" "$MODE_HELPER" claude-code --mode=api --reuse-from=codex > "$TEST_DIR/reuse-flag.out" 2>&1; then
    echo "FAIL: set-mode should reject --reuse-from, which is an install option" >&2
    cat "$TEST_DIR/reuse-flag.out" >&2
    exit 1
fi
grep -q "install option" "$TEST_DIR/reuse-flag.out" || {
    echo "FAIL: set-mode should explain that --reuse-from belongs to the installer" >&2
    cat "$TEST_DIR/reuse-flag.out" >&2
    exit 1
}
echo "  ✅ set-mode rejects --reuse-from with the install command to run instead"

HELP_HOME="$TEST_DIR/help-home"
mkdir -p "$HELP_HOME"
HOME="$HELP_HOME" "$MODE_HELPER" langchain --help > "$TEST_DIR/langchain-help.out"
grep -q '^Usage:' "$TEST_DIR/langchain-help.out" || {
    echo "FAIL: framework-scoped --help should show usage" >&2
    cat "$TEST_DIR/langchain-help.out" >&2
    exit 1
}
if [[ -e "$HELP_HOME/.aport" ]]; then
    echo "FAIL: framework-scoped --help should not create config" >&2
    find "$HELP_HOME/.aport" -maxdepth 3 -type f >&2
    exit 1
fi

TYPO_DIR="$TEST_DIR/typo-langchain"
mkdir -p "$TYPO_DIR"
if APORT_LANGCHAIN_CONFIG_DIR="$TYPO_DIR" "$MODE_HELPER" langchain --mode=api --enforcment=warn > "$TEST_DIR/langchain-typo.out" 2>&1; then
    echo "FAIL: set-mode should reject unknown options" >&2
    cat "$TEST_DIR/langchain-typo.out" >&2
    exit 1
fi
grep -q 'Unexpected argument' "$TEST_DIR/langchain-typo.out" || {
    echo "FAIL: unknown option rejection should explain the unexpected argument" >&2
    cat "$TEST_DIR/langchain-typo.out" >&2
    exit 1
}
if [[ -f "$TYPO_DIR/aport/guardrail-mode.env" ]]; then
    echo "FAIL: unknown option should not write a mode file" >&2
    cat "$TYPO_DIR/aport/guardrail-mode.env" >&2
    exit 1
fi

CLAUDE_DIR="$TEST_DIR/.claude"
mkdir -p "$CLAUDE_DIR/aport"
cat > "$CLAUDE_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_ENFORCEMENT=enforce
APORT_API_URL=https://api.aport.io
APORT_AGENT_ID=ap_1234567890abcdef1234567890abcdef
APORT_API_KEY=apk_runtime_key_to_preserve
EOF

APORT_CLAUDE_CODE_CONFIG_DIR="$CLAUDE_DIR" "$DISPATCHER" mode claude-code --enforcement=warn > "$TEST_DIR/claude-mode.out"
grep -q '^APORT_GUARDRAIL_MODE=api$' "$CLAUDE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: set-mode should preserve hosted api mode" >&2
    cat "$CLAUDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q '^APORT_ENFORCEMENT=warn$' "$CLAUDE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: set-mode should update enforcement" >&2
    cat "$CLAUDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q '^APORT_ENFORCEMENT_MODE=warn$' "$CLAUDE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: set-mode should write explicit enforcement mode" >&2
    cat "$CLAUDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q '^APORT_AGENT_ID=ap_1234567890abcdef1234567890abcdef$' "$CLAUDE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: set-mode should preserve hosted passport id" >&2
    cat "$CLAUDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q '^APORT_API_KEY=apk_runtime_key_to_preserve$' "$CLAUDE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: set-mode should preserve runtime API key" >&2
    cat "$CLAUDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}

if APORT_CLAUDE_CODE_CONFIG_DIR="$CLAUDE_DIR" "$DISPATCHER" mode claude-code --mode=local > "$TEST_DIR/claude-local-missing.out" 2>&1; then
    echo "FAIL: hosted-only set-mode should reject local mode without a local passport" >&2
    cat "$TEST_DIR/claude-local-missing.out" >&2
    exit 1
fi
grep -q "no valid local passport exists" "$TEST_DIR/claude-local-missing.out" || {
    echo "FAIL: local mode rejection should explain the missing passport" >&2
    cat "$TEST_DIR/claude-local-missing.out" >&2
    exit 1
}
grep -q '^APORT_GUARDRAIL_MODE=api$' "$CLAUDE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: failed local switch should leave hosted mode intact" >&2
    cat "$CLAUDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}

cat > "$CLAUDE_DIR/aport/passport.json" << 'EOF'
{"agent_id":"ap_local_claude_test","capabilities":[],"limits":{}}
EOF
APORT_CLAUDE_CODE_CONFIG_DIR="$CLAUDE_DIR" "$DISPATCHER" mode claude-code --mode=local > "$TEST_DIR/claude-local.out"
grep -q '^APORT_GUARDRAIL_MODE=local$' "$CLAUDE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: valid local passport should allow local mode" >&2
    cat "$CLAUDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
if grep -Eq '^APORT_(AGENT_ID|API_KEY|API_URL)=' "$CLAUDE_DIR/aport/guardrail-mode.env"; then
    echo "FAIL: local mode file should not preserve hosted credentials" >&2
    cat "$CLAUDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
fi

LANGCHAIN_DIR="$TEST_DIR/langchain"
mkdir -p "$LANGCHAIN_DIR"
cat > "$LANGCHAIN_DIR/config.yaml" << 'EOF'
framework: 'langchain'
mode: local
passport_path: '/tmp/passport.json'
EOF
APORT_LANGCHAIN_CONFIG_DIR="$LANGCHAIN_DIR" "$MODE_HELPER" langchain --mode=api --api-url=https://staging-api.aport.io --enforcement=warn > "$TEST_DIR/langchain-mode.out"
grep -q '^APORT_GUARDRAIL_MODE=api$' "$LANGCHAIN_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: generic set-mode should write api mode file" >&2
    cat "$LANGCHAIN_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q '^APORT_ENFORCEMENT=warn$' "$LANGCHAIN_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: generic set-mode should write warn enforcement" >&2
    cat "$LANGCHAIN_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q '^APORT_ENFORCEMENT_MODE=warn$' "$LANGCHAIN_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: generic set-mode should write explicit enforcement mode" >&2
    cat "$LANGCHAIN_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q '^mode: api$' "$LANGCHAIN_DIR/config.yaml" || {
    echo "FAIL: generic config should update mode" >&2
    cat "$LANGCHAIN_DIR/config.yaml" >&2
    exit 1
}
grep -q "^enforcement_mode: 'warn'$" "$LANGCHAIN_DIR/config.yaml" || {
    echo "FAIL: generic config should update enforcement_mode" >&2
    cat "$LANGCHAIN_DIR/config.yaml" >&2
    exit 1
}
grep -q "^api_url: 'https://staging-api.aport.io'$" "$LANGCHAIN_DIR/config.yaml" || {
    echo "FAIL: generic config should update api_url" >&2
    cat "$LANGCHAIN_DIR/config.yaml" >&2
    exit 1
}

cat > "$LANGCHAIN_DIR/config.yaml" << 'EOF'
framework: 'langchain'
mode: local
enforcement_mode: warn
passport_path: '/tmp/passport.json'
EOF
APORT_LANGCHAIN_CONFIG_DIR="$LANGCHAIN_DIR" "$MODE_HELPER" langchain --mode=api --api-url=https://staging-api.aport.io > "$TEST_DIR/langchain-preserve-enforcement.out"
grep -q '^APORT_ENFORCEMENT=warn$' "$LANGCHAIN_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: generic mode-only update should preserve existing warn enforcement" >&2
    cat "$LANGCHAIN_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q "^enforcement_mode: 'warn'$" "$LANGCHAIN_DIR/config.yaml" || {
    echo "FAIL: generic config should preserve warn enforcement_mode" >&2
    cat "$LANGCHAIN_DIR/config.yaml" >&2
    exit 1
}

PROJECT_DIR="$TEST_DIR/project-local-langchain"
PROJECT_HOME="$TEST_DIR/project-local-home"
mkdir -p "$PROJECT_DIR/.aport" "$PROJECT_HOME/.aport/langchain"
cat > "$PROJECT_DIR/.aport/config.yaml" << 'EOF'
framework: 'langchain'
mode: warn
agent_id: 'ap_project_existing'
api_url: 'https://project-old.aport.io'
EOF
cat > "$PROJECT_HOME/.aport/langchain/config.yaml" << 'EOF'
framework: 'langchain'
mode: local
api_url: 'https://home-old.aport.io'
EOF
(
    cd "$PROJECT_DIR"
    HOME="$PROJECT_HOME" "$MODE_HELPER" langchain --mode=api --api-url=https://project-api.aport.io --enforcement=warn
) > "$TEST_DIR/langchain-project-local.out"
grep -q '^mode: api$' "$PROJECT_DIR/.aport/config.yaml" || {
    echo "FAIL: project-local generic config should update the active .aport config" >&2
    cat "$PROJECT_DIR/.aport/config.yaml" >&2
    exit 1
}
grep -q "^api_url: 'https://project-api.aport.io'$" "$PROJECT_DIR/.aport/config.yaml" || {
    echo "FAIL: project-local generic config should update the project API URL" >&2
    cat "$PROJECT_DIR/.aport/config.yaml" >&2
    exit 1
}
grep -q "Config dir:  $PROJECT_DIR/.aport" "$TEST_DIR/langchain-project-local.out" || {
    echo "FAIL: set-mode output should identify the active project-local config" >&2
    cat "$TEST_DIR/langchain-project-local.out" >&2
    exit 1
}
if grep -q "project-api.aport.io" "$PROJECT_HOME/.aport/langchain/config.yaml"; then
    echo "FAIL: project-local set-mode should not update the inactive home config" >&2
    cat "$PROJECT_HOME/.aport/langchain/config.yaml" >&2
    exit 1
fi

CODEX_OVERRIDE_DIR="$TEST_DIR/codex-override"
CODEX_OVERRIDE_HOME="$TEST_DIR/codex-override-home"
mkdir -p "$CODEX_OVERRIDE_DIR/aport" "$CODEX_OVERRIDE_HOME"
cat > "$CODEX_OVERRIDE_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_ENFORCEMENT=enforce
APORT_API_URL=https://api.aport.io
APORT_AGENT_ID=ap_codex_override_existing
APORT_API_KEY=apk_codex_override_key
EOF
HOME="$CODEX_OVERRIDE_HOME" APORT_CONFIG_DIR="$CODEX_OVERRIDE_DIR" "$MODE_HELPER" codex --enforcement=warn > "$TEST_DIR/codex-override.out"
grep -q '^APORT_ENFORCEMENT=warn$' "$CODEX_OVERRIDE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: codex set-mode should honor APORT_CONFIG_DIR override" >&2
    cat "$CODEX_OVERRIDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q "Config dir:  $CODEX_OVERRIDE_DIR" "$TEST_DIR/codex-override.out" || {
    echo "FAIL: codex set-mode output should identify APORT_CONFIG_DIR" >&2
    cat "$TEST_DIR/codex-override.out" >&2
    exit 1
}
if [[ -e "$CODEX_OVERRIDE_HOME/.aport/codex/aport/guardrail-mode.env" ]]; then
    echo "FAIL: codex set-mode should not write inactive home state when APORT_CONFIG_DIR is set" >&2
    cat "$CODEX_OVERRIDE_HOME/.aport/codex/aport/guardrail-mode.env" >&2
    exit 1
fi

CODEX_HOOK_PROJECT="$TEST_DIR/codex-hook-project"
CODEX_HOOK_HOME="$TEST_DIR/codex-hook-home"
CODEX_HOOK_STATE="$CODEX_HOOK_HOME/.aport/codex"
mkdir -p "$CODEX_HOOK_PROJECT/.codex/aport" "$CODEX_HOOK_STATE/aport"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$CODEX_HOOK_STATE/aport/passport.json"
cat > "$CODEX_HOOK_PROJECT/.codex/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
APORT_ENFORCEMENT_MODE=warn
EOF
cat > "$CODEX_HOOK_STATE/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
APORT_ENFORCEMENT_MODE=warn
EOF
cat > "$CODEX_HOOK_PROJECT/.codex/hooks.json" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "APORT_CODEX_CONFIG_DIR='$CODEX_HOOK_STATE' '$REPO_ROOT/bin/aport-codex-hook.sh'",
            "__aport_hook": true
          }
        ]
      }
    ]
  }
}
EOF
(
    cd "$CODEX_HOOK_PROJECT"
    HOME="$CODEX_HOOK_HOME" "$MODE_HELPER" codex --enforcement=enforce
) > "$TEST_DIR/codex-hook-state.out"
grep -q '^APORT_ENFORCEMENT=enforce$' "$CODEX_HOOK_STATE/aport/guardrail-mode.env" || {
    echo "FAIL: codex set-mode should update the installed hook state directory" >&2
    cat "$CODEX_HOOK_STATE/aport/guardrail-mode.env" >&2
    cat "$TEST_DIR/codex-hook-state.out" >&2
    exit 1
}
grep -q '^APORT_ENFORCEMENT=warn$' "$CODEX_HOOK_PROJECT/.codex/aport/guardrail-mode.env" || {
    echo "FAIL: codex set-mode should not update incidental project-local state when hook uses shared state" >&2
    cat "$CODEX_HOOK_PROJECT/.codex/aport/guardrail-mode.env" >&2
    exit 1
}
set +e
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"rm -rf /tmp/x"}}' \
    | HOME="$CODEX_HOOK_HOME" APORT_CODEX_CONFIG_DIR="$CODEX_HOOK_STATE" "$REPO_ROOT/bin/aport-codex-hook.sh" > "$TEST_DIR/codex-hook-state-hook.out" 2> "$TEST_DIR/codex-hook-state-hook.err"
CODEX_HOOK_STATUS=$?
set -e
if [[ "$CODEX_HOOK_STATUS" -ne 0 ]]; then
    echo "FAIL: codex hook should return structured JSON" >&2
    cat "$TEST_DIR/codex-hook-state-hook.err" >&2
    exit 1
fi
jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$TEST_DIR/codex-hook-state-hook.out" > /dev/null || {
    echo "FAIL: codex installed hook state should now enforce denials" >&2
    cat "$TEST_DIR/codex-hook-state-hook.out" >&2
    cat "$TEST_DIR/codex-hook-state-hook.err" >&2
    exit 1
}

CODEX_QUOTED_PROJECT="$TEST_DIR/codex-quoted-hook-project"
CODEX_QUOTED_HOME="$TEST_DIR/codex-quoted-hook-home"
CODEX_QUOTED_STATE="$TEST_DIR/codex owner's-state"
mkdir -p "$CODEX_QUOTED_PROJECT/.codex" "$CODEX_QUOTED_HOME" "$CODEX_QUOTED_STATE/aport"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$CODEX_QUOTED_STATE/aport/passport.json"
cat > "$CODEX_QUOTED_STATE/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
APORT_ENFORCEMENT_MODE=warn
EOF
CODEX_QUOTED_COMMAND="APORT_CODEX_CONFIG_DIR=$(shell_quote_value "$CODEX_QUOTED_STATE") $(shell_quote_value "$REPO_ROOT/bin/aport-codex-hook.sh")"
jq -n --arg cmd "$CODEX_QUOTED_COMMAND" \
    '{hooks:{PreToolUse:[{matcher:"*",hooks:[{type:"command",command:$cmd,__aport_hook:true}]}]}}' \
    > "$CODEX_QUOTED_PROJECT/.codex/hooks.json"
(
    cd "$CODEX_QUOTED_PROJECT"
    HOME="$CODEX_QUOTED_HOME" "$MODE_HELPER" codex --enforcement=enforce
) > "$TEST_DIR/codex-quoted-hook-state.out"
grep -q '^APORT_ENFORCEMENT=enforce$' "$CODEX_QUOTED_STATE/aport/guardrail-mode.env" || {
    echo "FAIL: codex set-mode should use discovered quoted hook state for passport validation and updates" >&2
    cat "$CODEX_QUOTED_STATE/aport/guardrail-mode.env" >&2
    cat "$TEST_DIR/codex-quoted-hook-state.out" >&2
    exit 1
}
if [[ -e "$CODEX_QUOTED_HOME/.aport/codex/aport/guardrail-mode.env" ]]; then
    echo "FAIL: codex quoted hook state discovery should not write inactive default state" >&2
    cat "$CODEX_QUOTED_HOME/.aport/codex/aport/guardrail-mode.env" >&2
    exit 1
fi

CODEX_HOME_MODE_DIR="$TEST_DIR/codex-home-mode"
CODEX_HOME_MODE_HOME="$TEST_DIR/codex-home-mode-user"
CODEX_HOME_MODE_STATE="$TEST_DIR/codex-home-mode-state"
mkdir -p "$CODEX_HOME_MODE_DIR" "$CODEX_HOME_MODE_HOME" "$CODEX_HOME_MODE_STATE/aport"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$CODEX_HOME_MODE_STATE/aport/passport.json"
cat > "$CODEX_HOME_MODE_STATE/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=enforce
APORT_ENFORCEMENT_MODE=enforce
EOF
CODEX_HOME_MODE_COMMAND="APORT_CODEX_CONFIG_DIR=$(shell_quote_value "$CODEX_HOME_MODE_STATE") $(shell_quote_value "$REPO_ROOT/bin/aport-codex-hook.sh")"
jq -n --arg cmd "$CODEX_HOME_MODE_COMMAND" \
    '{hooks:{PreToolUse:[{matcher:"*",hooks:[{type:"command",command:$cmd,__aport_hook:true}]}]}}' \
    > "$CODEX_HOME_MODE_DIR/hooks.json"
(
    cd "$TEST_DIR"
    HOME="$CODEX_HOME_MODE_HOME" CODEX_HOME="$CODEX_HOME_MODE_DIR" "$MODE_HELPER" codex --enforcement=warn
) > "$TEST_DIR/codex-home-mode.out"
grep -q '^APORT_ENFORCEMENT=warn$' "$CODEX_HOME_MODE_STATE/aport/guardrail-mode.env" || {
    echo "FAIL: codex set-mode should discover state from CODEX_HOME" >&2
    cat "$CODEX_HOME_MODE_STATE/aport/guardrail-mode.env" >&2
    cat "$TEST_DIR/codex-home-mode.out" >&2
    exit 1
}

CODEX_HOOKS_OVERRIDE_DIR="$TEST_DIR/codex-hooks-dir-override"
CODEX_HOOKS_OVERRIDE_HOME="$TEST_DIR/codex-hooks-dir-home"
CODEX_HOOKS_OVERRIDE_STATE="$TEST_DIR/codex-hooks-dir-state"
mkdir -p "$CODEX_HOOKS_OVERRIDE_DIR" "$CODEX_HOOKS_OVERRIDE_HOME" "$CODEX_HOOKS_OVERRIDE_STATE/aport"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$CODEX_HOOKS_OVERRIDE_STATE/aport/passport.json"
cat > "$CODEX_HOOKS_OVERRIDE_STATE/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
APORT_ENFORCEMENT_MODE=warn
EOF
CODEX_HOOKS_OVERRIDE_COMMAND="APORT_CODEX_CONFIG_DIR=$(shell_quote_value "$CODEX_HOOKS_OVERRIDE_STATE") $(shell_quote_value "$REPO_ROOT/bin/aport-codex-hook.sh")"
jq -n --arg cmd "$CODEX_HOOKS_OVERRIDE_COMMAND" \
    '{hooks:{PreToolUse:[{matcher:"*",hooks:[{type:"command",command:$cmd,__aport_hook:true}]}]}}' \
    > "$CODEX_HOOKS_OVERRIDE_DIR/hooks.json"
(
    cd "$TEST_DIR"
    HOME="$CODEX_HOOKS_OVERRIDE_HOME" APORT_CODEX_HOOKS_DIR="$CODEX_HOOKS_OVERRIDE_DIR" "$MODE_HELPER" codex --enforcement=enforce
) > "$TEST_DIR/codex-hooks-dir-override.out"
grep -q '^APORT_ENFORCEMENT=enforce$' "$CODEX_HOOKS_OVERRIDE_STATE/aport/guardrail-mode.env" || {
    echo "FAIL: codex set-mode should discover state from APORT_CODEX_HOOKS_DIR" >&2
    cat "$CODEX_HOOKS_OVERRIDE_STATE/aport/guardrail-mode.env" >&2
    cat "$TEST_DIR/codex-hooks-dir-override.out" >&2
    exit 1
}

GOOSE_SPECIFIC_DIR="$TEST_DIR/goose-specific-override"
GOOSE_GENERIC_DIR="$TEST_DIR/goose-generic-override"
GOOSE_OVERRIDE_HOME="$TEST_DIR/goose-override-home"
mkdir -p "$GOOSE_SPECIFIC_DIR/aport" "$GOOSE_GENERIC_DIR/aport" "$GOOSE_OVERRIDE_HOME"
cat > "$GOOSE_SPECIFIC_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_ENFORCEMENT=enforce
APORT_API_URL=https://api.aport.io
APORT_AGENT_ID=ap_goose_specific_existing
APORT_API_KEY=apk_goose_specific_key
EOF
cat > "$GOOSE_GENERIC_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_ENFORCEMENT=enforce
APORT_API_URL=https://api.aport.io
APORT_AGENT_ID=ap_goose_generic_existing
APORT_API_KEY=apk_goose_generic_key
EOF
HOME="$GOOSE_OVERRIDE_HOME" APORT_CONFIG_DIR="$GOOSE_GENERIC_DIR" APORT_GOOSE_CONFIG_DIR="$GOOSE_SPECIFIC_DIR" "$MODE_HELPER" goose --enforcement=warn > "$TEST_DIR/goose-specific-override.out"
grep -q '^APORT_ENFORCEMENT=warn$' "$GOOSE_SPECIFIC_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: goose set-mode should prefer APORT_GOOSE_CONFIG_DIR over generic APORT_CONFIG_DIR" >&2
    cat "$GOOSE_SPECIFIC_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q '^APORT_ENFORCEMENT=enforce$' "$GOOSE_GENERIC_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: goose set-mode should not update inactive generic APORT_CONFIG_DIR when framework override is set" >&2
    cat "$GOOSE_GENERIC_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q "Config dir:  $GOOSE_SPECIFIC_DIR" "$TEST_DIR/goose-specific-override.out" || {
    echo "FAIL: goose set-mode output should identify the framework-specific config dir" >&2
    cat "$TEST_DIR/goose-specific-override.out" >&2
    exit 1
}

GOOSE_HOOK_PROJECT="$TEST_DIR/goose-hook-project"
GOOSE_HOOK_HOME="$TEST_DIR/goose-hook-home"
GOOSE_HOOK_STATE="$TEST_DIR/goose owner's-state"
mkdir -p "$GOOSE_HOOK_PROJECT" "$GOOSE_HOOK_HOME"
(
    cd "$GOOSE_HOOK_PROJECT"
    HOME="$GOOSE_HOOK_HOME" APORT_NONINTERACTIVE=1 APORT_GOOSE_CONFIG_DIR="$GOOSE_HOOK_STATE" "$DISPATCHER" goose --non-interactive --mode=api ap_test123
) > "$TEST_DIR/goose-hook-setup.out" 2>&1
(
    cd "$GOOSE_HOOK_PROJECT"
    HOME="$GOOSE_HOOK_HOME" "$MODE_HELPER" goose --enforcement=warn
) > "$TEST_DIR/goose-hook-state.out"
grep -q '^APORT_ENFORCEMENT=warn$' "$GOOSE_HOOK_STATE/aport/guardrail-mode.env" || {
    echo "FAIL: goose set-mode should discover state from installed plugin wrapper" >&2
    cat "$GOOSE_HOOK_STATE/aport/guardrail-mode.env" >&2
    cat "$TEST_DIR/goose-hook-state.out" >&2
    exit 1
}
grep -q "Config dir:  $GOOSE_HOOK_STATE" "$TEST_DIR/goose-hook-state.out" || {
    echo "FAIL: goose set-mode output should identify installed plugin state" >&2
    cat "$TEST_DIR/goose-hook-state.out" >&2
    exit 1
}
if [[ -e "$GOOSE_HOOK_HOME/.aport/goose/aport/guardrail-mode.env" ]]; then
    echo "FAIL: goose installed plugin discovery should not write inactive default state" >&2
    cat "$GOOSE_HOOK_HOME/.aport/goose/aport/guardrail-mode.env" >&2
    exit 1
fi

GEMINI_OVERRIDE_DIR="$TEST_DIR/gemini-override"
GEMINI_OVERRIDE_HOME="$TEST_DIR/gemini-override-home"
mkdir -p "$GEMINI_OVERRIDE_DIR/aport" "$GEMINI_OVERRIDE_HOME"
cat > "$GEMINI_OVERRIDE_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_ENFORCEMENT=enforce
APORT_API_URL=https://api.aport.io
APORT_AGENT_ID=ap_gemini_override_existing
APORT_API_KEY=apk_gemini_override_key
EOF
HOME="$GEMINI_OVERRIDE_HOME" APORT_CONFIG_DIR="$GEMINI_OVERRIDE_DIR" "$MODE_HELPER" gemini --enforcement=warn > "$TEST_DIR/gemini-override.out"
grep -q '^APORT_ENFORCEMENT=warn$' "$GEMINI_OVERRIDE_DIR/aport/guardrail-mode.env" || {
    echo "FAIL: gemini set-mode should honor APORT_CONFIG_DIR override" >&2
    cat "$GEMINI_OVERRIDE_DIR/aport/guardrail-mode.env" >&2
    exit 1
}
grep -q "Config dir:  $GEMINI_OVERRIDE_DIR" "$TEST_DIR/gemini-override.out" || {
    echo "FAIL: gemini set-mode output should identify APORT_CONFIG_DIR" >&2
    cat "$TEST_DIR/gemini-override.out" >&2
    exit 1
}
if [[ -e "$GEMINI_OVERRIDE_HOME/.aport/gemini-cli/aport/guardrail-mode.env" ]]; then
    echo "FAIL: gemini set-mode should not write inactive home state when APORT_CONFIG_DIR is set" >&2
    cat "$GEMINI_OVERRIDE_HOME/.aport/gemini-cli/aport/guardrail-mode.env" >&2
    exit 1
fi

GEMINI_HOOK_PROJECT="$TEST_DIR/gemini-hook-project"
GEMINI_HOOK_HOME="$TEST_DIR/gemini-hook-home"
GEMINI_HOOK_STATE="$GEMINI_HOOK_HOME/.aport/gemini-cli"
mkdir -p "$GEMINI_HOOK_PROJECT/.gemini/aport" "$GEMINI_HOOK_STATE/aport"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$GEMINI_HOOK_STATE/aport/passport.json"
cat > "$GEMINI_HOOK_PROJECT/.gemini/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
APORT_ENFORCEMENT_MODE=warn
EOF
cat > "$GEMINI_HOOK_STATE/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
APORT_ENFORCEMENT_MODE=warn
EOF
cat > "$GEMINI_HOOK_PROJECT/.gemini/settings.json" << EOF
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "APORT_GEMINI_CLI_CONFIG_DIR='$GEMINI_HOOK_STATE' '$REPO_ROOT/bin/aport-gemini-cli-hook.sh'",
            "__aport_hook": true
          }
        ]
      }
    ]
  }
}
EOF
(
    cd "$GEMINI_HOOK_PROJECT"
    HOME="$GEMINI_HOOK_HOME" "$MODE_HELPER" gemini --enforcement=enforce
) > "$TEST_DIR/gemini-hook-state.out"
grep -q '^APORT_ENFORCEMENT=enforce$' "$GEMINI_HOOK_STATE/aport/guardrail-mode.env" || {
    echo "FAIL: gemini set-mode should update the installed hook state directory" >&2
    cat "$GEMINI_HOOK_STATE/aport/guardrail-mode.env" >&2
    cat "$TEST_DIR/gemini-hook-state.out" >&2
    exit 1
}
grep -q '^APORT_ENFORCEMENT=warn$' "$GEMINI_HOOK_PROJECT/.gemini/aport/guardrail-mode.env" || {
    echo "FAIL: gemini set-mode should not update incidental project-local state when hook uses shared state" >&2
    cat "$GEMINI_HOOK_PROJECT/.gemini/aport/guardrail-mode.env" >&2
    exit 1
}
set +e
printf '%s' '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"rm -rf /tmp/x"}}' \
    | HOME="$GEMINI_HOOK_HOME" APORT_GEMINI_CLI_CONFIG_DIR="$GEMINI_HOOK_STATE" "$REPO_ROOT/bin/aport-gemini-cli-hook.sh" > "$TEST_DIR/gemini-hook-state-hook.out" 2> "$TEST_DIR/gemini-hook-state-hook.err"
GEMINI_HOOK_STATUS=$?
set -e
if [[ "$GEMINI_HOOK_STATUS" -ne 0 ]]; then
    echo "FAIL: gemini hook should return structured JSON" >&2
    cat "$TEST_DIR/gemini-hook-state-hook.err" >&2
    exit 1
fi
jq -e '.decision == "deny"' "$TEST_DIR/gemini-hook-state-hook.out" > /dev/null || {
    echo "FAIL: gemini installed hook state should now enforce denials" >&2
    cat "$TEST_DIR/gemini-hook-state-hook.out" >&2
    cat "$TEST_DIR/gemini-hook-state-hook.err" >&2
    exit 1
}

GEMINI_QUOTED_PROJECT="$TEST_DIR/gemini-quoted-hook-project"
GEMINI_QUOTED_HOME="$TEST_DIR/gemini-quoted-hook-home"
GEMINI_QUOTED_STATE="$TEST_DIR/gemini owner's-state"
mkdir -p "$GEMINI_QUOTED_PROJECT/.gemini" "$GEMINI_QUOTED_HOME" "$GEMINI_QUOTED_STATE/aport"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$GEMINI_QUOTED_STATE/aport/passport.json"
cat > "$GEMINI_QUOTED_STATE/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
APORT_ENFORCEMENT_MODE=warn
EOF
GEMINI_QUOTED_COMMAND="APORT_GEMINI_CLI_CONFIG_DIR=$(shell_quote_value "$GEMINI_QUOTED_STATE") $(shell_quote_value "$REPO_ROOT/bin/aport-gemini-cli-hook.sh")"
jq -n --arg cmd "$GEMINI_QUOTED_COMMAND" \
    '{hooks:{BeforeTool:[{matcher:".*",hooks:[{type:"command",command:$cmd,__aport_hook:true}]}]}}' \
    > "$GEMINI_QUOTED_PROJECT/.gemini/settings.json"
(
    cd "$GEMINI_QUOTED_PROJECT"
    HOME="$GEMINI_QUOTED_HOME" "$MODE_HELPER" gemini --enforcement=enforce
) > "$TEST_DIR/gemini-quoted-hook-state.out"
grep -q '^APORT_ENFORCEMENT=enforce$' "$GEMINI_QUOTED_STATE/aport/guardrail-mode.env" || {
    echo "FAIL: gemini set-mode should use discovered quoted hook state for passport validation and updates" >&2
    cat "$GEMINI_QUOTED_STATE/aport/guardrail-mode.env" >&2
    cat "$TEST_DIR/gemini-quoted-hook-state.out" >&2
    exit 1
}
if [[ -e "$GEMINI_QUOTED_HOME/.aport/gemini-cli/aport/guardrail-mode.env" ]]; then
    echo "FAIL: gemini quoted hook state discovery should not write inactive default state" >&2
    cat "$GEMINI_QUOTED_HOME/.aport/gemini-cli/aport/guardrail-mode.env" >&2
    exit 1
fi

GEMINI_HOOKS_OVERRIDE_DIR="$TEST_DIR/gemini-hooks-dir-override"
GEMINI_HOOKS_OVERRIDE_HOME="$TEST_DIR/gemini-hooks-dir-home"
GEMINI_HOOKS_OVERRIDE_STATE="$TEST_DIR/gemini-hooks-dir-state"
mkdir -p "$GEMINI_HOOKS_OVERRIDE_DIR" "$GEMINI_HOOKS_OVERRIDE_HOME" "$GEMINI_HOOKS_OVERRIDE_STATE/aport"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$GEMINI_HOOKS_OVERRIDE_STATE/aport/passport.json"
cat > "$GEMINI_HOOKS_OVERRIDE_STATE/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
APORT_ENFORCEMENT_MODE=warn
EOF
GEMINI_HOOKS_OVERRIDE_COMMAND="APORT_GEMINI_CLI_CONFIG_DIR=$(shell_quote_value "$GEMINI_HOOKS_OVERRIDE_STATE") $(shell_quote_value "$REPO_ROOT/bin/aport-gemini-cli-hook.sh")"
jq -n --arg cmd "$GEMINI_HOOKS_OVERRIDE_COMMAND" \
    '{hooks:{BeforeTool:[{matcher:".*",hooks:[{type:"command",command:$cmd,__aport_hook:true}]}]}}' \
    > "$GEMINI_HOOKS_OVERRIDE_DIR/settings.json"
(
    cd "$TEST_DIR"
    HOME="$GEMINI_HOOKS_OVERRIDE_HOME" APORT_GEMINI_CLI_HOOKS_DIR="$GEMINI_HOOKS_OVERRIDE_DIR" "$MODE_HELPER" gemini --enforcement=enforce
) > "$TEST_DIR/gemini-hooks-dir-override.out"
grep -q '^APORT_ENFORCEMENT=enforce$' "$GEMINI_HOOKS_OVERRIDE_STATE/aport/guardrail-mode.env" || {
    echo "FAIL: gemini set-mode should discover state from APORT_GEMINI_CLI_HOOKS_DIR" >&2
    cat "$GEMINI_HOOKS_OVERRIDE_STATE/aport/guardrail-mode.env" >&2
    cat "$TEST_DIR/gemini-hooks-dir-override.out" >&2
    exit 1
}

cat > "$LANGCHAIN_DIR/passport.json" << 'EOF'
{"agent_id":"ap_local_langchain_test","capabilities":[],"limits":{}}
EOF
cat > "$LANGCHAIN_DIR/config.yaml" << EOF
framework: 'langchain'
mode: api
agent_id: 'ap_langchain_hosted'
api_url: 'https://api.aport.io'
passport_path: '$LANGCHAIN_DIR/passport.json'
EOF
APORT_LANGCHAIN_CONFIG_DIR="$LANGCHAIN_DIR" "$MODE_HELPER" langchain --mode=local > "$TEST_DIR/langchain-local.out"
grep -q '^mode: local$' "$LANGCHAIN_DIR/config.yaml" || {
    echo "FAIL: generic config should switch to local mode" >&2
    cat "$LANGCHAIN_DIR/config.yaml" >&2
    exit 1
}
grep -q "^passport_path: '$LANGCHAIN_DIR/passport.json'$" "$LANGCHAIN_DIR/config.yaml" || {
    echo "FAIL: generic local config should preserve passport_path" >&2
    cat "$LANGCHAIN_DIR/config.yaml" >&2
    exit 1
}
if grep -Eq '^(agent_id|api_url):' "$LANGCHAIN_DIR/config.yaml"; then
    echo "FAIL: generic local config should remove hosted API settings" >&2
    cat "$LANGCHAIN_DIR/config.yaml" >&2
    exit 1
fi

OPENCLAW_DIR="$TEST_DIR/openclaw"
mkdir -p "$OPENCLAW_DIR"
cat > "$OPENCLAW_DIR/openclaw.json" << 'EOF'
{"plugins":{"entries":{"openclaw-aport":{"enabled":true,"config":{"mode":"api","agentId":"ap_existing","apiUrl":"https://api.aport.io","enforcementMode":"enforce"}}}}}
EOF
APORT_OPENCLAW_CONFIG_DIR="$OPENCLAW_DIR" "$MODE_HELPER" openclaw --enforcement=warn > "$TEST_DIR/openclaw-mode.out"
node -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const plugin = cfg.plugins.entries["openclaw-aport"].config;
if (plugin.mode !== "api") process.exit(1);
if (plugin.agentId !== "ap_existing") process.exit(2);
if (plugin.enforcementMode !== "warn") process.exit(3);
' "$OPENCLAW_DIR/openclaw.json" || {
    echo "FAIL: OpenClaw JSON config should preserve mode/passport and update enforcement" >&2
    cat "$OPENCLAW_DIR/openclaw.json" >&2
    exit 1
}

APORT_OPENCLAW_CONFIG_DIR="$OPENCLAW_DIR" "$MODE_HELPER" openclaw --mode=api > "$TEST_DIR/openclaw-preserve-enforcement.out"
node -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const plugin = cfg.plugins.entries["openclaw-aport"].config;
if (plugin.mode !== "api") process.exit(1);
if (plugin.enforcementMode !== "warn") process.exit(2);
' "$OPENCLAW_DIR/openclaw.json" || {
    echo "FAIL: OpenClaw mode-only update should preserve existing warn enforcement" >&2
    cat "$OPENCLAW_DIR/openclaw.json" >&2
    exit 1
}

OPENCLAW_JSON_PASSPORT_DIR="$TEST_DIR/openclaw-json-passport-api"
mkdir -p "$OPENCLAW_JSON_PASSPORT_DIR"
cat > "$OPENCLAW_JSON_PASSPORT_DIR/custom-passport.json" << 'EOF'
{"agent_id":"ap_local_api_openclaw_test","capabilities":[],"limits":{}}
EOF
cat > "$OPENCLAW_JSON_PASSPORT_DIR/openclaw.json" << EOF
{"plugins":{"entries":{"openclaw-aport":{"enabled":true,"config":{"mode":"local","passportFile":"$OPENCLAW_JSON_PASSPORT_DIR/custom-passport.json","guardrailScript":"/custom/aport-guardrail-bash.sh","enforcementMode":"warn"}}}}}
EOF
APORT_OPENCLAW_CONFIG_DIR="$OPENCLAW_JSON_PASSPORT_DIR" "$MODE_HELPER" openclaw --mode=api --api-url=https://api.aport.io > "$TEST_DIR/openclaw-json-passport-api.out"
node -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const expectedPassport = process.argv[2];
const plugin = cfg.plugins.entries["openclaw-aport"].config;
if (plugin.mode !== "api") process.exit(1);
if (plugin.agentId) process.exit(2);
if (plugin.passportFile !== expectedPassport) process.exit(3);
if (!plugin.guardrailScript) process.exit(4);
if (plugin.enforcementMode !== "warn") process.exit(5);
' "$OPENCLAW_JSON_PASSPORT_DIR/openclaw.json" "$OPENCLAW_JSON_PASSPORT_DIR/custom-passport.json" || {
    echo "FAIL: OpenClaw JSON API mode without hosted agentId should preserve local passport payload config" >&2
    cat "$OPENCLAW_JSON_PASSPORT_DIR/openclaw.json" >&2
    exit 1
}

OPENCLAW_YAML_DIR="$TEST_DIR/openclaw-yaml"
mkdir -p "$OPENCLAW_YAML_DIR"
cat > "$OPENCLAW_YAML_DIR/aport-passport.json" << 'EOF'
{"agent_id":"ap_local_openclaw_test","capabilities":[],"limits":{}}
EOF
cat > "$OPENCLAW_YAML_DIR/config.yaml" << EOF
gateway:
  mode: local
plugins:
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: api
        agentId: "ap_yaml_existing"
        apiUrl: "https://api.aport.io"
        passportFile: "$OPENCLAW_YAML_DIR/aport-passport.json"
        enforcementMode: "enforce"
EOF
APORT_OPENCLAW_CONFIG_DIR="$OPENCLAW_YAML_DIR" "$MODE_HELPER" openclaw --enforcement=warn > "$TEST_DIR/openclaw-yaml-mode.out"
grep -q 'mode: "api"' "$OPENCLAW_YAML_DIR/config.yaml" || {
    echo "FAIL: OpenClaw YAML should preserve plugin api mode instead of reading gateway.mode" >&2
    cat "$OPENCLAW_YAML_DIR/config.yaml" >&2
    exit 1
}
grep -q 'agentId: "ap_yaml_existing"' "$OPENCLAW_YAML_DIR/config.yaml" || {
    echo "FAIL: OpenClaw YAML should preserve plugin agentId" >&2
    cat "$OPENCLAW_YAML_DIR/config.yaml" >&2
    exit 1
}
grep -q 'enforcementMode: "warn"' "$OPENCLAW_YAML_DIR/config.yaml" || {
    echo "FAIL: OpenClaw YAML should update plugin enforcement" >&2
    cat "$OPENCLAW_YAML_DIR/config.yaml" >&2
    exit 1
}

OPENCLAW_YAML_4_DIR="$TEST_DIR/openclaw-yaml-four-space"
mkdir -p "$OPENCLAW_YAML_4_DIR"
cat > "$OPENCLAW_YAML_4_DIR/aport-passport.json" << 'EOF'
{"agent_id":"ap_local_openclaw_4_space_test","capabilities":[],"limits":{}}
EOF
cat > "$OPENCLAW_YAML_4_DIR/config.yaml" << EOF
plugins:
    entries:
        openclaw-aport:
            enabled: true
            config:
                mode: api
                agentId: "ap_yaml_4_existing"
                apiUrl: "https://api.aport.io"
                passportFile: "$OPENCLAW_YAML_4_DIR/aport-passport.json"
                enforcementMode: "warn"
EOF
APORT_OPENCLAW_CONFIG_DIR="$OPENCLAW_YAML_4_DIR" "$MODE_HELPER" openclaw --enforcement=enforce > "$TEST_DIR/openclaw-yaml-four-space.out"
grep -q '^                enforcementMode: "enforce"$' "$OPENCLAW_YAML_4_DIR/config.yaml" || {
    echo "FAIL: OpenClaw YAML should update fields under config: with existing four-space indentation" >&2
    cat "$OPENCLAW_YAML_4_DIR/config.yaml" >&2
    exit 1
}
if grep -q '^            enforcementMode:' "$OPENCLAW_YAML_4_DIR/config.yaml"; then
    echo "FAIL: OpenClaw YAML should not write enforcementMode alongside config:" >&2
    cat "$OPENCLAW_YAML_4_DIR/config.yaml" >&2
    exit 1
fi

OPENCLAW_YAML_PASSPORT_DIR="$TEST_DIR/openclaw-yaml-passport-api"
mkdir -p "$OPENCLAW_YAML_PASSPORT_DIR"
cat > "$OPENCLAW_YAML_PASSPORT_DIR/custom-passport.json" << 'EOF'
{"agent_id":"ap_local_openclaw_api_test","capabilities":[],"limits":{}}
EOF
cat > "$OPENCLAW_YAML_PASSPORT_DIR/config.yaml" << EOF
plugins:
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: local
        passportFile: "$OPENCLAW_YAML_PASSPORT_DIR/custom-passport.json"
        guardrailScript: "/custom/aport-guardrail-bash.sh"
        enforcementMode: "warn"
EOF
APORT_OPENCLAW_CONFIG_DIR="$OPENCLAW_YAML_PASSPORT_DIR" "$MODE_HELPER" openclaw --mode=api --api-url=https://api.aport.io > "$TEST_DIR/openclaw-yaml-passport-api.out"
grep -q 'mode: "api"' "$OPENCLAW_YAML_PASSPORT_DIR/config.yaml" || {
    echo "FAIL: OpenClaw YAML should switch local-passport API config to api mode" >&2
    cat "$OPENCLAW_YAML_PASSPORT_DIR/config.yaml" >&2
    exit 1
}
grep -q "passportFile: \"$OPENCLAW_YAML_PASSPORT_DIR/custom-passport.json\"" "$OPENCLAW_YAML_PASSPORT_DIR/config.yaml" || {
    echo "FAIL: OpenClaw YAML API mode without hosted agentId should preserve passportFile" >&2
    cat "$OPENCLAW_YAML_PASSPORT_DIR/config.yaml" >&2
    exit 1
}
grep -q 'guardrailScript: "' "$OPENCLAW_YAML_PASSPORT_DIR/config.yaml" || {
    echo "FAIL: OpenClaw YAML API mode without hosted agentId should preserve guardrailScript" >&2
    cat "$OPENCLAW_YAML_PASSPORT_DIR/config.yaml" >&2
    exit 1
}
if grep -q 'agentId:' "$OPENCLAW_YAML_PASSPORT_DIR/config.yaml"; then
    echo "FAIL: OpenClaw YAML local-passport API mode should not invent hosted agentId" >&2
    cat "$OPENCLAW_YAML_PASSPORT_DIR/config.yaml" >&2
    exit 1
fi

OPENCLAW_EMPTY_DIR="$TEST_DIR/openclaw-empty"
mkdir -p "$OPENCLAW_EMPTY_DIR/aport"
cat > "$OPENCLAW_EMPTY_DIR/openclaw.json" << 'EOF'
{"plugins":{"entries":{}}}
EOF
cat > "$OPENCLAW_EMPTY_DIR/aport/passport.json" << 'EOF'
{"agent_id":"ap_local_empty_openclaw_test","capabilities":[],"limits":{}}
EOF
APORT_OPENCLAW_CONFIG_DIR="$OPENCLAW_EMPTY_DIR" "$MODE_HELPER" openclaw --enforcement=warn > "$TEST_DIR/openclaw-empty-mode.out"
node -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (cfg.plugins.entries["openclaw-aport"]) process.exit(1);
' "$OPENCLAW_EMPTY_DIR/openclaw.json" || {
    echo "FAIL: set-mode should not create a partial OpenClaw plugin entry" >&2
    cat "$OPENCLAW_EMPTY_DIR/openclaw.json" >&2
    exit 1
}

SYMLINK_TARGET_DIR="$TEST_DIR/set-mode-symlink-target"
SYMLINK_CONFIG_DIR="$TEST_DIR/set-mode-symlink-config"
mkdir -p "$SYMLINK_TARGET_DIR"
ln -s "$SYMLINK_TARGET_DIR" "$SYMLINK_CONFIG_DIR"
set +e
APORT_CODEX_CONFIG_DIR="$SYMLINK_CONFIG_DIR" "$MODE_HELPER" codex --enforcement=warn > "$TEST_DIR/set-mode-symlink.out" 2> "$TEST_DIR/set-mode-symlink.err"
SYMLINK_SET_MODE_EXIT=$?
set -e
if [[ "$SYMLINK_SET_MODE_EXIT" -eq 0 ]]; then
    echo "FAIL: set-mode should reject symlinked config directories" >&2
    cat "$TEST_DIR/set-mode-symlink.out" >&2 || true
    cat "$TEST_DIR/set-mode-symlink.err" >&2 || true
    exit 1
fi
grep -q "Refusing to write through symlink" "$TEST_DIR/set-mode-symlink.err" || {
    echo "FAIL: set-mode should explain symlink rejection" >&2
    cat "$TEST_DIR/set-mode-symlink.out" >&2 || true
    cat "$TEST_DIR/set-mode-symlink.err" >&2 || true
    exit 1
}
if [[ -e "$SYMLINK_TARGET_DIR/aport/guardrail-mode.env" ]]; then
    echo "FAIL: set-mode should not write through rejected symlink target" >&2
    exit 1
fi

echo "  ✅ set-mode preserves passports and updates enforcement"
echo ""

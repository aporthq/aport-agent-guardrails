#!/bin/bash
# Unit test: mode changes update config only and preserve existing passport settings.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
MODE_HELPER="$REPO_ROOT/bin/aport-set-mode.sh"
DISPATCHER="$REPO_ROOT/bin/agent-guardrails"

echo ""
echo "  Unit — aport set-mode"
echo ""

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

echo "  ✅ set-mode preserves passports and updates enforcement"
echo ""

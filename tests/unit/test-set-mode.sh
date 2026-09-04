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

OPENCLAW_EMPTY_DIR="$TEST_DIR/openclaw-empty"
mkdir -p "$OPENCLAW_EMPTY_DIR"
cat > "$OPENCLAW_EMPTY_DIR/openclaw.json" << 'EOF'
{"plugins":{"entries":{}}}
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

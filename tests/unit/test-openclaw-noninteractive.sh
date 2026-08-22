#!/bin/bash
# OpenClaw hosted quick setup must complete without prompts and honor --api-url.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
FAKE_BIN="$TEST_DIR/bin-openclaw-noninteractive"
OPENCLAW_HOME="$TEST_DIR/.openclaw-noninteractive"
LOG_FILE="$TEST_DIR/openclaw.log"
mkdir -p "$FAKE_BIN" "$OPENCLAW_HOME"
mkdir -p "$OPENCLAW_HOME/aport"
printf '{"passport_id":"local-existing"}\n' > "$OPENCLAW_HOME/aport/passport.json"

cat > "$FAKE_BIN/openclaw" << 'EOF'
#!/bin/bash
set -e
case "$*" in
  "plugins list --json")
    printf '{"plugins":[{"id":"openclaw-aport","version":"test"}]}'
    ;;
  "plugins list")
    printf 'openclaw-aport test\n'
    ;;
  plugins\ install*)
    exit 0
    ;;
  "gateway restart")
    exit 0
    ;;
  "gateway probe")
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$FAKE_BIN/openclaw"

cat > "$FAKE_BIN/curl" << 'EOF'
#!/bin/bash
set -e
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    -w)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
agent_id="${APORT_TEST_ISSUE_AGENT_ID:-ap_1234567890abcdef1234567890abcdef}"
printf '{"agent_id":"%s","api_key":"apk_runtime_test","api_key_id":"key_runtime"}' "$agent_id" > "$output"
printf '201'
EOF
chmod +x "$FAKE_BIN/curl"

PATH="$FAKE_BIN:$PATH" \
    OPENCLAW_HOME="$OPENCLAW_HOME" \
    APORT_NONINTERACTIVE=1 \
    "$REPO_ROOT/bin/openclaw" \
    --quick-hosted \
    --email dev@example.com \
    --issue-url http://issue.local/api/issue \
    --api-url http://127.0.0.1:9 \
    --non-interactive \
    < /dev/null > "$LOG_FILE" 2>&1 || {
    echo "FAIL: OpenClaw non-interactive hosted setup failed" >&2
    cat "$LOG_FILE" >&2
    exit 1
}

CONFIG_YAML="$OPENCLAW_HOME/config.yaml"
[ -f "$CONFIG_YAML" ] || {
    echo "FAIL: expected OpenClaw config.yaml" >&2
    cat "$LOG_FILE" >&2
    exit 1
}

grep -q '^        agentId: ap_1234567890abcdef1234567890abcdef$' "$CONFIG_YAML" || {
    echo "FAIL: config.yaml should include hosted agent id" >&2
    cat "$CONFIG_YAML" >&2
    exit 1
}

if grep -q 'passportFile:' "$CONFIG_YAML"; then
    echo "FAIL: quick-hosted OpenClaw setup should prefer hosted mode over an existing local passport" >&2
    cat "$CONFIG_YAML" >&2
    exit 1
fi

grep -q '^        apiUrl: http://127.0.0.1:9$' "$CONFIG_YAML" || {
    echo "FAIL: config.yaml should honor --api-url" >&2
    cat "$CONFIG_YAML" >&2
    exit 1
}

grep -q '^        allowUnmappedTools: true$' "$CONFIG_YAML" || {
    echo "FAIL: non-interactive strict mode default should allow unmapped tools" >&2
    cat "$CONFIG_YAML" >&2
    exit 1
}

PATH="$FAKE_BIN:$PATH" \
    OPENCLAW_HOME="$OPENCLAW_HOME" \
    APORT_NONINTERACTIVE=1 \
    APORT_TEST_ISSUE_AGENT_ID="ap_fedcba9876543210fedcba9876543210" \
    "$REPO_ROOT/bin/openclaw" \
    --quick-hosted \
    --email dev@example.com \
    --issue-url http://issue.local/api/issue \
    --api-url http://127.0.0.1:10 \
    --non-interactive \
    < /dev/null >> "$LOG_FILE" 2>&1 || {
    echo "FAIL: OpenClaw hosted rerun failed" >&2
    cat "$LOG_FILE" >&2
    exit 1
}

grep -q '^        agentId: "ap_fedcba9876543210fedcba9876543210"$' "$CONFIG_YAML" || {
    echo "FAIL: existing config.yaml should update hosted agent id on rerun" >&2
    cat "$CONFIG_YAML" >&2
    exit 1
}

grep -q '^        apiUrl: "http://127.0.0.1:10"$' "$CONFIG_YAML" || {
    echo "FAIL: existing config.yaml should update API URL on rerun" >&2
    cat "$CONFIG_YAML" >&2
    exit 1
}

echo "OK test-openclaw-noninteractive.sh"

#!/bin/bash
# Unit test for quick hosted issuance orchestration. Preset/default details stay server-side.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
FAKE_BIN="$TEST_DIR/bin"
CONFIG_DIR="$TEST_DIR/.claude"
LOG_FILE="$TEST_DIR/curl.log"
mkdir -p "$FAKE_BIN" "$CONFIG_DIR"

cat > "$FAKE_BIN/curl" << 'EOF'
#!/bin/bash
set -e
payload=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --data)
      payload="$2"
      shift 2
      ;;
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
printf '%s' "$payload" > "$APORT_TEST_CURL_LOG"
printf '{"agent_id":"ap_1234567890abcdef1234567890abcdef","api_key":"apk_runtime_test","api_key_id":"key_runtime"}' > "$output"
printf '201'
EOF
chmod +x "$FAKE_BIN/curl"

PATH="$FAKE_BIN:$PATH"
export PATH APORT_TEST_CURL_LOG="$LOG_FILE"
export APORT_OWNER_EMAIL="dev@example.com"

# shellcheck source=../../bin/lib/common.sh
source "$REPO_ROOT/bin/lib/common.sh"
# shellcheck source=../../bin/lib/guardrail-mode.sh
source "$REPO_ROOT/bin/lib/guardrail-mode.sh"
# shellcheck source=../../bin/lib/quick-hosted.sh
source "$REPO_ROOT/bin/lib/quick-hosted.sh"

aport_quick_hosted_issue_passport "claude-code" "$CONFIG_DIR"

[ "$APORT_AGENT_ID" = "ap_1234567890abcdef1234567890abcdef" ] || {
    echo "FAIL: expected APORT_AGENT_ID from issue response" >&2
    exit 1
}
[ "$APORT_API_KEY" = "apk_runtime_test" ] || {
    echo "FAIL: expected APORT_API_KEY from issue response" >&2
    exit 1
}

node -e '
const fs = require("fs");
const payload = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (payload.email !== "dev@example.com") process.exit(1);
if (payload.framework?.[0] !== "claude-code") process.exit(2);
if (payload.showInGallery !== false) process.exit(3);
if ("tenant_ref" in payload || "platform_id" in payload || "device_info" in payload) process.exit(4);
if ("name" in payload || "description" in payload) process.exit(5);
' "$LOG_FILE" || {
    echo "FAIL: quick hosted payload should contain only email/framework install inputs" >&2
    cat "$LOG_FILE" >&2
    exit 1
}

MODE_FILE="$(write_guardrail_mode_file "$CONFIG_DIR" api https://api.aport.io "$APORT_AGENT_ID")"
grep -q '^APORT_API_KEY=apk_runtime_test$' "$MODE_FILE" || {
    echo "FAIL: hosted mode file should persist runtime setup key" >&2
    cat "$MODE_FILE" >&2
    exit 1
}

SENTINEL="$TEST_DIR/mode-file-source-executed"
export APORT_API_KEY="apk runtime test \$(touch $SENTINEL)"
MODE_FILE="$(write_guardrail_mode_file "$CONFIG_DIR" api "https://api.aport.io/with space" "$APORT_AGENT_ID")"
if load_guardrail_mode_for_hooks "$CONFIG_DIR" > "$TEST_DIR/unsafe-mode.out" 2>&1; then
    echo "FAIL: hosted mode parser should reject unsafe values" >&2
    cat "$MODE_FILE" >&2
    exit 1
fi
[ ! -e "$SENTINEL" ] || {
    echo "FAIL: parsing hosted mode file executed API key contents" >&2
    cat "$MODE_FILE" >&2
    exit 1
}

EXISTING_CONFIG_DIR="$TEST_DIR/existing-hosted"
mkdir -p "$EXISTING_CONFIG_DIR/aport"
cat > "$EXISTING_CONFIG_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_API_URL=https://private.aport.example
APORT_AGENT_ID=agt_inst_existing123
APORT_API_KEY=apk_existing_runtime
EOF
: > "$LOG_FILE"
unset APORT_AGENT_ID APORT_API_KEY APORT_API_URL APORT_SELECTED_API_URL
aport_maybe_configure_hosted_passport "claude-code" "$EXISTING_CONFIG_DIR" || {
    echo "FAIL: expected existing hosted mode file to be reused" >&2
    exit 1
}
[ "$APORT_AGENT_ID" = "agt_inst_existing123" ] || {
    echo "FAIL: expected existing hosted agent id to be loaded" >&2
    exit 1
}
[ "$APORT_API_KEY" = "apk_existing_runtime" ] || {
    echo "FAIL: expected existing hosted runtime key to be loaded" >&2
    exit 1
}
[ "$APORT_API_URL" = "https://private.aport.example" ] || {
    echo "FAIL: expected existing hosted API URL to be loaded" >&2
    exit 1
}
[ "$APORT_SELECTED_API_URL" = "https://private.aport.example" ] || {
    echo "FAIL: expected selected API URL to use existing hosted API URL" >&2
    exit 1
}
[ ! -s "$LOG_FILE" ] || {
    echo "FAIL: existing hosted config should not call issue endpoint" >&2
    cat "$LOG_FILE" >&2
    exit 1
}

for valid_id in ap_1234567890abcdef1234567890abcdef apt_template_123 agt_inst_existing123 agt_tmpl_existing123; do
    aport_quick_hosted_is_valid_agent_id "$valid_id" || {
        echo "FAIL: expected hosted ID to be accepted: $valid_id" >&2
        exit 1
    }
done

unset APORT_AGENT_ID APORT_API_KEY
APORT_GUARDRAIL_MODE_CLI=local
if aport_maybe_configure_hosted_passport "claude-code" "$EXISTING_CONFIG_DIR"; then
    echo "FAIL: explicit local mode should not silently reuse hosted config" >&2
    exit 1
fi
[ -z "${APORT_AGENT_ID:-}" ] || {
    echo "FAIL: explicit local mode should not export hosted agent id" >&2
    exit 1
}
unset APORT_GUARDRAIL_MODE_CLI

APORT_GUARDRAIL_MODE_CLI=local
if select_guardrail_mode "claude-code" "agt_inst_existing123" > "$TEST_DIR/mode-conflict.out" 2>&1; then
    echo "FAIL: --mode=local with hosted agent id should fail with a conflict" >&2
    exit 1
fi
grep -q 'mode=local cannot be combined' "$TEST_DIR/mode-conflict.out" || {
    echo "FAIL: mode conflict should produce a clear error" >&2
    cat "$TEST_DIR/mode-conflict.out" >&2
    exit 1
}
unset APORT_GUARDRAIL_MODE_CLI

echo "OK test-quick-hosted.sh"

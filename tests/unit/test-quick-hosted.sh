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
if ("name" in payload || "description" in payload) process.exit(4);
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

echo "OK test-quick-hosted.sh"

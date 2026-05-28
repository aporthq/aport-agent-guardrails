#!/bin/bash
# Test the public enterprise device deployment script contract and core mocked flow.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTERPRISE_DIR="$SCRIPT_DIR/enterprise-scripts"
LIB="$ENTERPRISE_DIR/aport-device-lib.sh"
CORE="$ENTERPRISE_DIR/aport-device-core.mjs"
SCRIPT="$ENTERPRISE_DIR/aport-device-deploy.sh"
ENFORCE_SCRIPT="$ENTERPRISE_DIR/aport-device-enforce.sh"
UNINSTALL_SCRIPT="$ENTERPRISE_DIR/aport-device-uninstall.sh"
DIST="$SCRIPT_DIR/dist/enterprise-scripts"
TMP_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
FAKE_BIN="$TMP_DIR/fake-bin"
LOG_DIR="$TMP_DIR/logs"
HOME_DIR="$TMP_DIR/home"
STATE_DIR="$TMP_DIR/state"

echo "🧪 Testing: enterprise-device-scripts"
echo "================================"

[ -f "$LIB" ] && [ -f "$CORE" ] && [ -f "$SCRIPT" ] || {
    echo "FAIL: missing enterprise lib, core, or deploy script" >&2
    exit 1
}
bash -n "$LIB"
bash -n "$SCRIPT"
node --check "$CORE"
bash -n "$ENFORCE_SCRIPT"
bash -n "$UNINSTALL_SCRIPT"

grep -q 'APORT_FRAMEWORK="${APORT_FRAMEWORK:-claude-code}"' "$SCRIPT" || {
    echo "FAIL: deploy should expose APORT_FRAMEWORK in the editable config block" >&2
    exit 1
}
grep -q 'aport_device_invoke install' "$SCRIPT" || {
    echo "FAIL: deploy should invoke install via aport_device_invoke" >&2
    exit 1
}
grep -q 'aport-device-core.mjs' "$LIB" || {
    echo "FAIL: lib should launch aport-device-core.mjs" >&2
    exit 1
}
grep -q 'function installAction' "$CORE" || {
    echo "FAIL: core should define installAction" >&2
    exit 1
}
grep -q '/setup-key' "$CORE" || {
    echo "FAIL: core should mint read-scoped runtime setup keys" >&2
    exit 1
}
grep -q 'APORT_RUNTIME_API_KEY' "$CORE" || {
    echo "FAIL: core should persist runtime setup key in state" >&2
    exit 1
}

mkdir -p "$FAKE_BIN" "$LOG_DIR" "$HOME_DIR"

cat > "$FAKE_BIN/curl" << 'EOF'
#!/bin/bash
set -e
printf '%s\n' "$*" >> "$APORT_TEST_CURL_LOG"
case "$*" in
    *"/api/check-instance"*)
        if [ "${APORT_TEST_CHECK_INSTANCE_FAIL:-}" = "1" ]; then
            exit 22
        fi
        printf '{"exists":false}'
        ;;
    *"/api/passports/"*"/instances"*)
        printf '{"instance_id":"ap_instance_1234567890abcdef1234567890abcdef"}'
        ;;
    *"/api/passports/"*"/setup-key"*)
        printf '{"key":"apk_runtime_test"}'
        ;;
    *)
        printf '{"error":"unexpected curl call"}' >&2
        exit 1
        ;;
esac
EOF

cat > "$FAKE_BIN/npx" << 'EOF'
#!/bin/bash
set -e
{
    printf 'APORT_AGENT_ID=%s\n' "${APORT_AGENT_ID:-}"
    printf 'APORT_API_KEY=%s\n' "${APORT_API_KEY:-}"
    printf 'ARGS=%s\n' "$*"
} >> "$APORT_TEST_NPX_LOG"
EOF

chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/npx"

export APORT_TEST_CURL_LOG="$LOG_DIR/curl.log"
export APORT_TEST_NPX_LOG="$LOG_DIR/npx.log"

PATH="$FAKE_BIN:$PATH" \
    APORT_SKIP_USER_SWITCH=1 \
    APORT_TARGET_USER="testuser" \
    APORT_TARGET_HOME="$HOME_DIR" \
    APORT_STATE_DIR="$STATE_DIR" \
    APORT_DEVICE_ID="device-123" \
    APORT_API_KEY="apk_enrollment_test" \
    APORT_TEMPLATE_ID="ap_template_test" \
    APORT_FRAMEWORK="claude-code" \
    bash "$SCRIPT"

STATE_FILE="$STATE_DIR/state.env"
MODE_FILE="$HOME_DIR/.claude/aport/guardrail-mode.env"

grep -qE 'APORT_AGENT_ID=("|\047)?ap_instance_1234567890abcdef1234567890abcdef' "$STATE_FILE" || {
    echo "FAIL: state should persist the created agent id" >&2
    cat "$STATE_FILE" >&2
    exit 1
}
grep -qE 'APORT_RUNTIME_API_KEY=("|\047)?apk_runtime_test' "$STATE_FILE" || {
    echo "FAIL: state should persist runtime setup key" >&2
    cat "$STATE_FILE" >&2
    exit 1
}
if grep -q 'apk_enrollment_test' "$STATE_FILE"; then
    echo "FAIL: state should not persist enrollment API key" >&2
    exit 1
fi
grep -qE "^APORT_API_KEY=('|\")?apk_runtime_test" "$MODE_FILE" || {
    echo "FAIL: framework mode file should contain runtime setup key for hooks" >&2
    cat "$MODE_FILE" >&2
    exit 1
}
grep -q 'APORT_API_KEY=apk_runtime_test' "$APORT_TEST_NPX_LOG" || {
    echo "FAIL: npx installer should receive runtime setup key" >&2
    exit 1
}
grep -q '/api/passports/ap_instance_1234567890abcdef1234567890abcdef/setup-key' "$APORT_TEST_CURL_LOG" || {
    echo "FAIL: install should mint runtime setup key for created instance" >&2
    exit 1
}
grep -q '"device_info"' "$APORT_TEST_CURL_LOG" || {
    echo "FAIL: install should send device metadata by default" >&2
    cat "$APORT_TEST_CURL_LOG" >&2
    exit 1
}
grep -q '"device_id":"device-123"' "$APORT_TEST_CURL_LOG" || {
    echo "FAIL: device metadata should include configured device ID" >&2
    cat "$APORT_TEST_CURL_LOG" >&2
    exit 1
}
grep -q '"device_id_source":"env"' "$APORT_TEST_CURL_LOG" || {
    echo "FAIL: device metadata should include device ID source" >&2
    cat "$APORT_TEST_CURL_LOG" >&2
    exit 1
}

DISABLED_INFO_STATE_DIR="$TMP_DIR/disabled-device-info-state"
: > "$APORT_TEST_CURL_LOG"
PATH="$FAKE_BIN:$PATH" \
    APORT_SKIP_USER_SWITCH=1 \
    APORT_TARGET_USER="testuser" \
    APORT_TARGET_HOME="$HOME_DIR" \
    APORT_STATE_DIR="$DISABLED_INFO_STATE_DIR" \
    APORT_DEVICE_ID="device-456" \
    APORT_API_KEY="apk_enrollment_test" \
    APORT_TEMPLATE_ID="ap_template_test" \
    APORT_FRAMEWORK="claude-code" \
    DISABLE_DEVICE_INFO=1 \
    bash "$SCRIPT"

if grep -q '"device_info"' "$APORT_TEST_CURL_LOG"; then
    echo "FAIL: DISABLE_DEVICE_INFO should omit device metadata" >&2
    cat "$APORT_TEST_CURL_LOG" >&2
    exit 1
fi

: > "$APORT_TEST_CURL_LOG"
PATH="$FAKE_BIN:$PATH" \
    APORT_SKIP_USER_SWITCH=1 \
    APORT_TARGET_USER="testuser" \
    APORT_TARGET_HOME="$HOME_DIR" \
    APORT_STATE_DIR="$STATE_DIR" \
    APORT_DEVICE_ID="device-123" \
    APORT_API_KEY="apk_enrollment_test" \
    APORT_TEMPLATE_ID="ap_template_test" \
    APORT_FRAMEWORK="claude-code" \
    bash "$SCRIPT"

if grep -q '/instances\|/setup-key' "$APORT_TEST_CURL_LOG"; then
    echo "FAIL: second install should reuse persisted state without reissuing" >&2
    cat "$APORT_TEST_CURL_LOG" >&2
    exit 1
fi

: > "$APORT_TEST_CURL_LOG"
PATH="$FAKE_BIN:$PATH" \
    APORT_SKIP_USER_SWITCH=1 \
    APORT_TARGET_USER="testuser" \
    APORT_TARGET_HOME="$HOME_DIR" \
    APORT_STATE_DIR="$STATE_DIR" \
    APORT_DEVICE_ID="device-123" \
    APORT_API_KEY="apk_enrollment_test" \
    APORT_TEMPLATE_ID="ap_template_test" \
    APORT_FRAMEWORK="claude-code" \
    bash "$ENFORCE_SCRIPT"

if grep -q '/instances\|/setup-key' "$APORT_TEST_CURL_LOG"; then
    echo "FAIL: enforce should reuse persisted state without reissuing" >&2
    cat "$APORT_TEST_CURL_LOG" >&2
    exit 1
fi

FAIL_STATE_DIR="$TMP_DIR/fail-state"
: > "$APORT_TEST_CURL_LOG"
set +e
PATH="$FAKE_BIN:$PATH" \
    APORT_SKIP_USER_SWITCH=1 \
    APORT_TARGET_USER="testuser" \
    APORT_TARGET_HOME="$HOME_DIR" \
    APORT_STATE_DIR="$FAIL_STATE_DIR" \
    APORT_DEVICE_ID="device-123" \
    APORT_API_KEY="apk_enrollment_test" \
    APORT_TEMPLATE_ID="ap_template_test" \
    APORT_FRAMEWORK="claude-code" \
    APORT_TEST_CHECK_INSTANCE_FAIL=1 \
    bash "$SCRIPT" > "$LOG_DIR/lookup-fail.out" 2>&1
LOOKUP_FAIL_EXIT=$?
set -e

if [ "$LOOKUP_FAIL_EXIT" -eq 0 ]; then
    echo "FAIL: install should fail closed when check-instance lookup fails" >&2
    cat "$LOG_DIR/lookup-fail.out" >&2
    exit 1
fi
if grep -q '/instances' "$APORT_TEST_CURL_LOG"; then
    echo "FAIL: install should not create an instance after lookup failure" >&2
    cat "$APORT_TEST_CURL_LOG" >&2
    exit 1
fi

[ -f "$ENTERPRISE_DIR/README.md" ] || {
    echo "FAIL: missing enterprise scripts README.md" >&2
    exit 1
}

grep -q 'aport_device_invoke enforce' "$ENFORCE_SCRIPT" || {
    echo "FAIL: enforce should invoke enforce via aport_device_invoke" >&2
    exit 1
}
grep -q "function enforceAction" "$CORE" || {
    echo "FAIL: core should define enforceAction" >&2
    exit 1
}
grep -q "reset', cfg.framework" "$CORE" || {
    echo "FAIL: core should call npx reset on uninstall" >&2
    exit 1
}

# Bundled artifacts (what IT deploys) must be self-contained
rm -rf "$DIST"
APORT_BUNDLE_VERSION="$(node -p "require('$SCRIPT_DIR/package.json').version")" \
    bash "$SCRIPT_DIR/scripts/bundle-enterprise-scripts.sh"
for name in aport-device-deploy.bundled.sh aport-device-enforce.bundled.sh aport-device-uninstall.bundled.sh; do
    f="$DIST/$name"
    bash -n "$f"
    grep -q 'APORT_DEVICE_CORE' "$f"
    grep -q 'exec node -' "$f"
    if grep -q 'source.*aport-device-lib' "$f"; then
        echo "FAIL: $name must not source external lib" >&2
        exit 1
    fi
done
node -e "
const m = require(process.argv[1]);
const fs = require('fs');
const path = require('path');
const dist = process.argv[2];
for (const s of m.scripts) {
  const shaPath = path.join(dist, s.filename + '.sha256');
  const sha = fs.readFileSync(shaPath, 'utf8').trim();
  if (sha !== s.sha256) throw new Error('sha mismatch ' + s.filename);
}
" "$DIST/enterprise-scripts-manifest.json" "$DIST"

echo
echo "✅ Enterprise device script tests passed!"

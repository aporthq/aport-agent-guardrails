#!/bin/bash
# Ensure bin/openclaw stops immediately if plugin installation fails.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
FAKE_BIN="$TEST_DIR/bin-openclaw-installer-failure"
CONFIG_DIR="$TEST_DIR/.openclaw-installer-failure"
LOG_FILE="$TEST_DIR/openclaw-install-failure.log"
AGENT_ID="ap_8955f5450cd542fe8f67bbbf07c3e103"

mkdir -p "$FAKE_BIN" "$CONFIG_DIR"

cat > "$FAKE_BIN/openclaw" << 'SCRIPT'
#!/bin/bash
if [[ "$1" == "plugins" && "$2" == "install" ]]; then
  echo "Plugin installation blocked: simulated failure" >&2
  exit 42
fi
exit 0
SCRIPT
chmod +x "$FAKE_BIN/openclaw"

set +e
printf '\n' | env PATH="$FAKE_BIN:/usr/bin:/bin" OPENCLAW_HOME="$CONFIG_DIR" \
    "$REPO_ROOT/bin/openclaw" "$AGENT_ID" > "$LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "FAIL: expected bin/openclaw to exit non-zero when plugin installation fails" >&2
    cat "$LOG_FILE" >&2
    exit 1
fi

grep -q "Plugin installation failed" "$LOG_FILE" || {
    echo "FAIL: expected plugin installation failure message" >&2
    cat "$LOG_FILE" >&2
    exit 1
}

if [[ -f "$CONFIG_DIR/config.yaml" || -f "$CONFIG_DIR/openclaw.json" ]]; then
    echo "FAIL: installer should not write plugin config after install failure" >&2
    ls -la "$CONFIG_DIR" >&2
    exit 1
fi

if [[ -f "$CONFIG_DIR/.aport-repo" || -d "$CONFIG_DIR/.skills" ]]; then
    echo "FAIL: installer should not install wrappers after plugin installation failure" >&2
    ls -la "$CONFIG_DIR" >&2
    exit 1
fi

echo "  ✅ bin/openclaw exits before writing config when plugin installation fails"

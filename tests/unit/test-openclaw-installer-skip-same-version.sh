#!/bin/bash
# Ensure bin/openclaw does not reinstall the plugin when the same version is already installed.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
FAKE_BIN="$TEST_DIR/bin"
CONFIG_DIR="$TEST_DIR/.openclaw"
LOG_FILE="$TEST_DIR/openclaw-skip-install.log"
AGENT_ID="ap_8955f5450cd542fe8f67bbbf07c3e103"
PLUGIN_VERSION="$(node -e 'const fs=require("node:fs"); const pkg=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(pkg.version);' "$REPO_ROOT/extensions/openclaw-aport/package.json")"

mkdir -p "$FAKE_BIN" "$CONFIG_DIR"
NODE_DIR="$(dirname "$(command -v node)")"

cat > "$FAKE_BIN/openclaw" << 'SCRIPT'
#!/bin/bash
set -e
LOG_FILE="${APORT_FAKE_OPENCLAW_LOG:?}"

if [[ "$1" == "plugins" && "$2" == "list" && "$3" == "--json" ]]; then
  cat <<JSON
[plugins] [APort] Loaded: mode=local, passportFile=/tmp/passport.json, unmapped=allow, mapExec=true
{
  "plugins": [
    {
      "id": "openclaw-aport",
      "version": "__PLUGIN_VERSION__"
    }
  ]
}
JSON
  exit 0
fi

if [[ "$1" == "plugins" && "$2" == "list" ]]; then
  echo "openclaw-aport"
  exit 0
fi

if [[ "$1" == "plugins" && "$2" == "install" ]]; then
  echo "INSTALL_CALLED" >> "__LOG_FILE__"
  exit 99
fi

if [[ "$1" == "gateway" && "$2" == "restart" ]]; then
  exit 0
fi

if [[ "$1" == "gateway" && "$2" == "probe" ]]; then
  exit 0
fi

if [[ "$1" == "gateway" && "$2" == "start" ]]; then
  exit 0
fi

exit 0
SCRIPT
sed -i '' "s|__PLUGIN_VERSION__|$PLUGIN_VERSION|g" "$FAKE_BIN/openclaw"
sed -i '' "s|__LOG_FILE__|$LOG_FILE|g" "$FAKE_BIN/openclaw"
chmod +x "$FAKE_BIN/openclaw"

printf '\n\n\n' | env PATH="$FAKE_BIN:$NODE_DIR:/usr/bin:/bin" OPENCLAW_HOME="$CONFIG_DIR" APORT_FAKE_OPENCLAW_LOG="$LOG_FILE" \
    "$REPO_ROOT/bin/openclaw" "$AGENT_ID" > "$TEST_DIR/stdout.log" 2>&1

if [[ -f "$LOG_FILE" ]] && grep -q "INSTALL_CALLED" "$LOG_FILE"; then
    echo "FAIL: expected bin/openclaw to skip reinstall for same plugin version" >&2
    cat "$TEST_DIR/stdout.log" >&2
    exit 1
fi

grep -q "already installed; skipping reinstall" "$TEST_DIR/stdout.log" || {
    echo "FAIL: expected skip reinstall message" >&2
    cat "$TEST_DIR/stdout.log" >&2
    exit 1
}

if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
    echo "FAIL: expected config.yaml to still be written after skip" >&2
    cat "$TEST_DIR/stdout.log" >&2
    exit 1
fi

echo "  ✅ bin/openclaw skips reinstall when the same plugin version is already installed"

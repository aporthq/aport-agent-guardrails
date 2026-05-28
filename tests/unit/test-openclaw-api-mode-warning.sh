#!/bin/bash
# Ensure bin/openclaw does not fail setup when the post-install API smoke check fails.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
FAKE_BIN="$TEST_DIR/bin"
CONFIG_DIR="$TEST_DIR/.openclaw"
LOG_FILE="$TEST_DIR/openclaw-api-warning.log"
PLUGIN_VERSION="$(node -e 'const fs=require("node:fs"); const pkg=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(pkg.version);' "$REPO_ROOT/extensions/openclaw-aport/package.json")"

mkdir -p "$FAKE_BIN" "$CONFIG_DIR/aport"
NODE_DIR="$(dirname "$(command -v node)")"
cp "$REPO_ROOT/tests/fixtures/passport.oap-v1.json" "$CONFIG_DIR/aport/passport.json"

cat > "$FAKE_BIN/openclaw" << 'SCRIPT'
#!/bin/bash
set -e
PLUGIN_VERSION="${APORT_FAKE_OPENCLAW_PLUGIN_VERSION:?}"

if [[ "$1" == "plugins" && "$2" == "list" && "$3" == "--json" ]]; then
  cat <<JSON
{
  "plugins": [
    {
      "id": "openclaw-aport",
      "version": "$PLUGIN_VERSION"
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
  echo "FAIL: install should be skipped when the same version is already installed" >&2
  exit 99
fi

if [[ "$1" == "gateway" && ( "$2" == "restart" || "$2" == "probe" || "$2" == "start" ) ]]; then
  exit 0
fi

exit 0
SCRIPT
chmod +x "$FAKE_BIN/openclaw"

set +e
printf '\nN\n2\n\n' | env \
    PATH="$FAKE_BIN:$NODE_DIR:/usr/bin:/bin" \
    OPENCLAW_HOME="$CONFIG_DIR" \
    APORT_FAKE_OPENCLAW_PLUGIN_VERSION="$PLUGIN_VERSION" \
    "$REPO_ROOT/bin/openclaw" --api-url http://127.0.0.1:1 > "$LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

if [[ "$EXIT_CODE" -ne 0 ]]; then
    echo "FAIL: expected bin/openclaw to complete successfully when the smoke check fails" >&2
    cat "$LOG_FILE" >&2
    exit 1
fi

grep -q "Smoke check did not return ALLOW" "$LOG_FILE" || {
    echo "FAIL: expected warning about smoke check failure" >&2
    cat "$LOG_FILE" >&2
    exit 1
}

if grep -q "Setup incomplete" "$LOG_FILE"; then
    echo "FAIL: setup should not be marked incomplete after successful plugin config" >&2
    cat "$LOG_FILE" >&2
    exit 1
fi

grep -q "Plugin setup complete" "$LOG_FILE" || {
    echo "FAIL: expected plugin setup completion message" >&2
    cat "$LOG_FILE" >&2
    exit 1
}

grep -q "aport-guardrail-api.sh system.command.execute" "$LOG_FILE" || {
    echo "FAIL: expected API smoke command in next steps output" >&2
    cat "$LOG_FILE" >&2
    exit 1
}

grep -q "mode: api" "$CONFIG_DIR/config.yaml" || {
    echo "FAIL: expected config.yaml to use api mode" >&2
    cat "$CONFIG_DIR/config.yaml" >&2
    exit 1
}

grep -q "apiUrl: http://127.0.0.1:1" "$CONFIG_DIR/config.yaml" || {
    echo "FAIL: expected config.yaml to use CLI-provided API URL" >&2
    cat "$CONFIG_DIR/config.yaml" >&2
    exit 1
}

echo "  ✅ bin/openclaw completes setup even when the API smoke check fails"

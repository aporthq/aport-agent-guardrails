#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/openclaw" << 'MOCK'
#!/bin/bash
case "$*" in
  'plugins list --json') printf '{"plugins":[{"id":"openclaw-aport","version":"test"}]}' ;;
  'plugins list') [ "${MOCK_PLUGIN_VERIFIED:-1}" = 1 ] && printf 'openclaw-aport test\n' ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$TEST_ROOT/bin/openclaw"
cat > "$TEST_ROOT/fetch-mock.js" << 'MOCK'
global.fetch = async () => ({ ok: true, json: async () => ({ decision_id: 'decision_1', reasons: [], allow: process.env.MOCK_VERIFY_ALLOW === '1' }) });
MOCK
umask 077
node - > "$TEST_ROOT/handoff.json" << 'NODE'
const id = 'ai_fixture';
const token = Buffer.from(JSON.stringify({v:1,owner_id:'ap_user_fixture',region:'US',installation_id:id})).toString('base64url');
process.stdout.write(JSON.stringify({schema_version:'agent-installation-handoff/v1',installation_id:id,
  reporter_endpoint:`https://sandbox.aport.io/api/agent-installations/${id}/reports`,
  test_result_endpoint:`https://sandbox.aport.io/api/agent-installations/${id}/tests/{test_id}/results`,
  token_presentation:'Authorization: Bearer <reporter_token>',reporter_token:`air1.${token}.${'A'.repeat(43)}`}));
NODE
run_setup() {
    local name="$1" allowed="$2" verified="$3" handoff="${4-$TEST_ROOT/handoff.json}"
    PATH="$TEST_ROOT/bin:$PATH" OPENCLAW_HOME="$TEST_ROOT/$name" APORT_NONINTERACTIVE=1 \
        APORT_API_URL=https://sandbox.aport.io APORT_API_KEY=fixture \
        APORT_INSTALLATION_HANDOFF_FILE="$handoff" \
        MOCK_VERIFY_ALLOW="$allowed" MOCK_PLUGIN_VERIFIED="$verified" NODE_OPTIONS="--require=$TEST_ROOT/fetch-mock.js" \
        "$REPO_ROOT/bin/openclaw" ap_fixture > "$TEST_ROOT/$name.log" 2>&1
}
for target in config.yaml openclaw.json openclaw.json.bak aport/passport.json.bak .skills/aport-status.sh workspace/AGENTS.md; do
    name="symlink-${target//\//-}"
    name="${name//./-}"
    mkdir -p "$TEST_ROOT/$name/$(dirname "$target")"
    printf 'preserve' > "$TEST_ROOT/$name-victim"
    ln -s "$TEST_ROOT/$name-victim" "$TEST_ROOT/$name/$target"
    if run_setup "$name" 1 1; then
        echo "FAIL: setup accepted symlinked $target" >&2
        exit 1
    fi
    [[ "$(cat "$TEST_ROOT/$name-victim")" = preserve ]] || {
        echo 'FAIL: setup changed a symlink target' >&2
        exit 1
    }
done
mkdir "$TEST_ROOT/symlink-state" "$TEST_ROOT/state-victim"
ln -s "$TEST_ROOT/state-victim" "$TEST_ROOT/symlink-state/aport"
if run_setup symlink-state 1 1; then
    echo 'FAIL: setup accepted a symlinked state directory' >&2
    exit 1
fi
[[ -z "$(ls -A "$TEST_ROOT/state-victim")" ]] || {
    echo 'FAIL: setup changed a symlinked state target' >&2
    exit 1
}
run_setup failed-smoke 0 1
if compgen -G "$TEST_ROOT/failed-smoke/aport/installation-v1-*.json" > /dev/null; then
    echo 'FAIL: failed smoke test consumed the handoff' >&2
    exit 1
fi
run_setup unverified-plugin 1 0
if compgen -G "$TEST_ROOT/unverified-plugin/aport/installation-v1-*.json" > /dev/null; then
    echo 'FAIL: unverified plugin consumed the handoff' >&2
    exit 1
fi
mkdir "$TEST_ROOT/invalid-host-config"
printf '%s' '{invalid' > "$TEST_ROOT/invalid-host-config/openclaw.json"
run_setup invalid-host-config 1 1
if compgen -G "$TEST_ROOT/invalid-host-config/aport/installation-v1-*.json" > /dev/null; then
    echo 'FAIL: invalid host config consumed the handoff' >&2
    exit 1
fi
mkdir -p "$TEST_ROOT/failed-backup/openclaw.json.bak/openclaw.json"
printf '%s' '{}' > "$TEST_ROOT/failed-backup/openclaw.json"
run_setup failed-backup 1 1
if compgen -G "$TEST_ROOT/failed-backup/aport/installation-v1-*.json" > /dev/null; then
    echo 'FAIL: a failed config backup consumed the handoff' >&2
    exit 1
fi
[[ "$(cat "$TEST_ROOT/failed-backup/openclaw.json")" = '{}' ]] || {
    echo 'FAIL: failed backup replaced host config' >&2
    exit 1
}
if compgen -G "$TEST_ROOT/failed-backup/openclaw.json.??????" > /dev/null; then
    echo 'FAIL: failed config update retained a temporary file' >&2
    exit 1
fi
mkdir "$TEST_ROOT/snippet-only"
printf 'plugins:\n  enabled: true\n' > "$TEST_ROOT/snippet-only/config.yaml"
run_setup snippet-only 1 1
if compgen -G "$TEST_ROOT/snippet-only/aport/installation-v1-*.json" > /dev/null; then
    echo 'FAIL: snippet-only setup consumed the handoff' >&2
    exit 1
fi
run_setup verified 1 1
files=("$TEST_ROOT"/verified/aport/installation-v1-*.json)
[[ -f "${files[0]}" ]] || {
    echo 'FAIL: verified setup did not store the handoff' >&2
    grep -iE 'handoff|smoke|plugin|reporting' "$TEST_ROOT/verified.log" >&2 || true
    exit 1
}
jq -e 'keys == ["installation_id", "reporter_token"] and .installation_id == "ai_fixture"' "${files[0]}" > /dev/null
grep -q 'reporting connection is unverified' "$TEST_ROOT/verified.log"
if grep -q 'air1\.' "$TEST_ROOT/verified.log"; then
    echo 'FAIL: setup logged reporter credential' >&2
    exit 1
fi
run_setup verified 1 1 ''
grep -q 'Reporting connection: unverified' "$TEST_ROOT/verified.log"
run_setup no-handoff 1 1 ''
grep -q 'Reporting connection: not configured' "$TEST_ROOT/no-handoff.log"
mkdir "$TEST_ROOT/verified/aport/.installation-binding.lock"
if APORT_OPENCLAW_CONFIG_DIR="$TEST_ROOT/verified" "$REPO_ROOT/bin/agent-guardrails" reset openclaw --yes > "$TEST_ROOT/reset-locked.log" 2>&1; then
    echo 'FAIL: reset must refuse a locked installation binding' >&2
    exit 1
fi
[[ -f "${files[0]}" ]] || {
    echo 'FAIL: locked reset removed the binding' >&2
    exit 1
}
rmdir "$TEST_ROOT/verified/aport/.installation-binding.lock"
APORT_OPENCLAW_CONFIG_DIR="$TEST_ROOT/verified" "$REPO_ROOT/bin/agent-guardrails" reset openclaw --yes > "$TEST_ROOT/reset.log" 2>&1
[[ ! -e "$TEST_ROOT/verified/aport" ]] || {
    echo 'FAIL: reset did not remove the unlocked binding' >&2
    exit 1
}
echo 'PASS: OpenClaw setup binds only after verified plugin and successful smoke test'

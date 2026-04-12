#!/bin/bash
# Build/install the Python package from dist and verify the generic provider
# works with a bootstrapped CrewAI config.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output/python-package")}"
VENV_DIR="$TEST_DIR/venv"
CONFIG_DIR="$TEST_DIR/.aport/crewai"
FIXTURE_PASSPORT="$REPO_ROOT/tests/fixtures/passport.oap-v1.json"
STUB_DIR="$TEST_DIR/bin"

rm -rf "$VENV_DIR" "$CONFIG_DIR" "$STUB_DIR" "$REPO_ROOT/python/aport_guardrails/dist"

echo ""
echo "  Integration — Python package build/install"
echo "  Test dir: $TEST_DIR"
echo ""

python3 -m pip install --quiet build
python3 -m build "$REPO_ROOT/python/aport_guardrails" > /dev/null

WHEEL="$(ls "$REPO_ROOT/python/aport_guardrails"/dist/*.whl | head -n 1)"
if [[ -z "$WHEEL" ]]; then
    echo "FAIL: wheel not found" >&2
    exit 1
fi
echo "  ✅ built wheel: $(basename "$WHEEL")"

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --quiet "$WHEEL"

mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/npx" << 'EOF'
#!/bin/sh
echo "FAIL: python bootstrap should not shell out to npx" >&2
exit 99
EOF
chmod +x "$STUB_DIR/npx"

PATH="$STUB_DIR:$PATH" \
    APORT_CREWAI_CONFIG_DIR="$CONFIG_DIR" \
    APORT_NONINTERACTIVE=1 \
    "$VENV_DIR/bin/aport" setup --framework=crewai --integration-mode=native > /dev/null

if [[ ! -f "$CONFIG_DIR/aport/passport.json" ]]; then
    echo "FAIL: python bootstrap did not create passport.json" >&2
    exit 1
fi

cp "$FIXTURE_PASSPORT" "$CONFIG_DIR/aport/passport.json"

"$VENV_DIR/bin/python" - << PY
from pathlib import Path
from types import SimpleNamespace

from aport_guardrails.providers import OAPGuardrailProvider

site_pkg = next(p for p in Path("$VENV_DIR").rglob("site-packages/aport_guardrails"))
assert (site_pkg / "core" / "tool-pack-mapping.json").is_file(), "tool-pack-mapping.json missing from wheel"
assert (site_pkg / "core" / "default-passport-paths.json").is_file(), "default-passport-paths.json missing from wheel"
assert (site_pkg / "runtime-bundle" / "manifest.txt").is_file(), "runtime manifest missing from wheel"
assert (site_pkg / "runtime-bundle" / "bin" / "aport-create-passport.sh").is_file(), "wizard script missing from wheel"
assert (site_pkg / "runtime-bundle" / "external" / "aport-policies").is_dir(), "policy bundle missing from wheel"

provider = OAPGuardrailProvider(
    framework="crewai",
    config_path="$CONFIG_DIR/config.yaml",
)

allow = provider.evaluate(SimpleNamespace(tool_name="bash", tool_input={"command": "git status"}))
deny = provider.evaluate(SimpleNamespace(tool_name="bash", tool_input={"command": "sudo ls"}))

assert allow.allow is True, f"expected allow, got {allow.allow}"
assert deny.allow is False, f"expected deny, got {deny.allow}"
print("ok")
PY

echo "  ✅ installed wheel includes JSON assets"
echo "  ✅ installed wheel includes bundled runtime assets"
echo "  ✅ python CLI bootstrap works without npx"
echo "  ✅ generic provider allow/deny smoke test passed"
echo ""

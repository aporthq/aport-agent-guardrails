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
DIST_DIR="$TEST_DIR/dist"
BUILD_ROOT="$TEST_DIR/build-root"
PKG_SRC="$BUILD_ROOT/python/aport_guardrails"

rm -rf "$VENV_DIR" "$CONFIG_DIR" "$STUB_DIR" "$DIST_DIR" "$BUILD_ROOT"
mkdir -p "$(dirname "$PKG_SRC")" "$BUILD_ROOT/external/aport-spec/oap" "$BUILD_ROOT/local-overrides"
cp -R "$REPO_ROOT/python/aport_guardrails" "$PKG_SRC"
find "$PKG_SRC" \( -name '__pycache__' -o -name '.pytest_cache' -o -name 'build' -o -name 'dist' -o -name '*.egg-info' \) -prune -exec rm -rf {} +
cp -R "$REPO_ROOT/bin" "$BUILD_ROOT/bin"
cp -R "$REPO_ROOT/src" "$BUILD_ROOT/src"
cp -R "$REPO_ROOT/external/aport-policies" "$BUILD_ROOT/external/aport-policies"
cp "$REPO_ROOT/external/aport-spec/oap/passport-schema.json" "$BUILD_ROOT/external/aport-spec/oap/passport-schema.json"

echo ""
echo "  Integration — Python package build/install"
echo "  Test dir: $TEST_DIR"
echo ""

if ! python3 -m build --version > /dev/null 2>&1; then
    if ! python3 -m pip install --quiet build; then
        if [[ -n "${APORT_SKIP_REMOTE_PASSPORT_TEST:-}" && "${GITHUB_ACTIONS:-}" != "true" ]]; then
            echo "  SKIP: python build package is unavailable in this local/offline environment"
            exit 0
        fi
        echo "FAIL: python build package is required" >&2
        exit 1
    fi
fi
BUILD_LOG="$TEST_DIR/python-build.log"
if ! python3 -m build "$PKG_SRC" --outdir "$DIST_DIR" > "$BUILD_LOG" 2>&1; then
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        cat "$BUILD_LOG" >&2
        exit 1
    fi
    if [[ -n "${APORT_SKIP_REMOTE_PASSPORT_TEST:-}" || -n "${APORT_PYTHON_BUILD_NO_ISOLATION:-}" ]]; then
        if ! python3 -c "import wheel" > /dev/null 2>&1; then
            echo "  SKIP: isolated build failed and local wheel package is unavailable for offline fallback"
            exit 0
        fi
        echo "  ⚠ isolated build failed; retrying without build isolation"
        FALLBACK_BUILD_LOG="$TEST_DIR/python-build-no-isolation.log"
        if ! python3 -m build --wheel --no-isolation --skip-dependency-check "$PKG_SRC" --outdir "$DIST_DIR" > "$FALLBACK_BUILD_LOG" 2>&1; then
            cat "$FALLBACK_BUILD_LOG" >&2
            exit 1
        fi
    else
        cat "$BUILD_LOG" >&2
        exit 1
    fi
fi

WHEEL="$(ls "$DIST_DIR"/*.whl | head -n 1)"
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

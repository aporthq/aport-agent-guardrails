#!/bin/bash
# Unit test: every library a manifest file sources is itself in the runtime manifest, so the installed runtime
# tree is self-contained. Regression for passport-reuse.sh, sourced by quick-hosted.sh but not copied.
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/bin/lib/runtime-manifest.txt"
ROOT_DIR="$REPO_ROOT"
export ROOT_DIR
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -q '^file bin/lib/passport-reuse.sh$' "$MANIFEST" || fail "bin/lib/passport-reuse.sh must be in the runtime manifest"
grep -q '^file local-overrides/policies/media.image.generate.v1.json$' "$MANIFEST" || fail "media.image.generate local policy must be in the runtime manifest"

listed="$(grep '^file bin/' "$MANIFEST" | sed 's/^file //')"
while IFS= read -r file; do
    case "$file" in bin/lib/*.sh | bin/*.sh) ;; *) continue ;; esac
    # Sibling sources spelled as source "$<dir>/name.sh" or source "$(...)/name.sh" inside the lib dir.
    for dep in $(grep -oE 'source "[^"]*/(lib/)?[a-z-]+\.sh"' "$REPO_ROOT/$file" | grep -oE '[a-z-]+\.sh"$' | tr -d '"' | sort -u); do
        [[ -f "$REPO_ROOT/bin/lib/$dep" ]] || continue
        grep -qx "bin/lib/$dep" <<< "$listed" || fail "$file sources bin/lib/$dep, which is not in the runtime manifest"
    done
done <<< "$listed"

# Regression: installed runtimes must include local override policies too. If the image-generation policy is
# missing, a passport without media.image.generate can accidentally pass because the local evaluator sees no
# requires_capabilities entry.
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"

# shellcheck source=../../bin/lib/runtime.sh
source "$REPO_ROOT/bin/lib/runtime.sh"

CONFIG_DIR="$TEST_DIR/runtime-config"
install_runtime_tree "$CONFIG_DIR"
RUNTIME_DIR="$CONFIG_DIR/aport/runtime"
for reporting_file in contract.js reporter.js binding.js bind-openclaw.js status-openclaw.js; do
    cmp "$REPO_ROOT/src/installation-reporting/$reporting_file" "$RUNTIME_DIR/src/installation-reporting/$reporting_file" > /dev/null \
        || fail "installed runtime must include the shared reporting owner: $reporting_file"
done
node -e 'const r = require(process.argv[1]); if (typeof r.InstallationReporter !== "function") process.exit(1)' \
    "$RUNTIME_DIR/src/installation-reporting/reporter.js" || fail "installed shared reporting owner must load"
[ -f "$RUNTIME_DIR/local-overrides/policies/media.image.generate.v1.json" ] || fail "installed runtime missing media.image.generate policy"
jq -e '.requires_capabilities[] == "media.image.generate"' "$RUNTIME_DIR/local-overrides/policies/media.image.generate.v1.json" > /dev/null \
    || fail "installed media.image.generate policy must require media.image.generate"

mkdir -p "$CONFIG_DIR/aport"
cat > "$CONFIG_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "runtime-image-policy-test",
  "agent_id": "runtime-image-policy-test",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "web.fetch"}],
  "limits": {
    "media.image.generate": {
      "allowed_providers": ["*"],
      "max_prompt_length": 8000,
      "max_referenced_images": 0,
      "max_output_images": 4,
      "allowed_output_formats": ["png"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
cat > "$CONFIG_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT_MODE=enforce
EOF

OUT="$TEST_DIR/installed-runtime-image-hook.json"
ERR="$TEST_DIR/installed-runtime-image-hook.err"
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a square","num_last_images_to_include":0}}' \
    | APORT_CODEX_CONFIG_DIR="$CONFIG_DIR" "$RUNTIME_DIR/bin/aport-codex-hook.sh" > "$OUT" 2> "$ERR" || true
jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_capability"))' "$OUT" > /dev/null || {
    echo "FAIL: installed runtime hook must enforce media.image.generate required capability" >&2
    cat "$OUT" >&2 || true
    cat "$ERR" >&2 || true
    exit 1
}

# Regression: manifest "tree" entries are submodule checkouts. In a recursive clone `external/<sub>/.git` is a
# directory holding the object database and `.git/config` remote URLs; in a worktree checkout it is a gitlink
# file. Before the fix all three installers (bin/lib/runtime.sh, python setup.py, runtime_assets.py) copied it
# verbatim, so an installed runtime and the published sdist/wheel carried submodule VCS metadata.
VCS_FIXTURE="$TEST_DIR/vcs-fixture"
rm -rf "$VCS_FIXTURE"
mkdir -p "$VCS_FIXTURE/external/aport-policies/.git/objects" "$VCS_FIXTURE/external/aport-policies/policies"
# Both shapes at once: a real .git directory with config, and a sibling gitlink file.
printf '[remote "origin"]\n\turl = https://example.invalid/private.git\n' \
    > "$VCS_FIXTURE/external/aport-policies/.git/config"
printf 'ref: refs/heads/main\n' > "$VCS_FIXTURE/external/aport-policies/.git/HEAD"
printf '{"id":"policy"}\n' > "$VCS_FIXTURE/external/aport-policies/policies/sample.json"
mkdir -p "$VCS_FIXTURE/external/aport-spec"
printf 'gitdir: ../../.git/modules/external/aport-spec\n' > "$VCS_FIXTURE/external/aport-spec/.git"
# A submodule may nest its own submodules, so the exclusion must hold at any depth, not just near the root.
mkdir -p "$VCS_FIXTURE/external/aport-policies/packs/a/b/c/nested/.git/objects"
printf '[core]\n' > "$VCS_FIXTURE/external/aport-policies/packs/a/b/c/nested/.git/config"
printf '{"id":"nested"}\n' > "$VCS_FIXTURE/external/aport-policies/packs/a/b/c/nested/pack.json"

VCS_DEST="$TEST_DIR/vcs-dest"
rm -rf "$VCS_DEST"
mkdir -p "$VCS_DEST"
(
    ROOT_DIR="$VCS_FIXTURE"
    export ROOT_DIR
    # shellcheck source=../../bin/lib/runtime.sh
    source "$REPO_ROOT/bin/lib/runtime.sh"
    _runtime_copy_tree "$VCS_DEST" "external/aport-policies"
    _runtime_copy_tree "$VCS_DEST" "external/aport-spec"
)
[ -f "$VCS_DEST/external/aport-policies/policies/sample.json" ] \
    || fail "RUNTIME_TREE_KEEPS_CONTENT: shell installer dropped real tree content"
[ ! -e "$VCS_DEST/external/aport-policies/.git" ] \
    || fail "RUNTIME_TREE_EXCLUDES_VCS: shell installer copied a .git directory into the runtime"
[ ! -e "$VCS_DEST/external/aport-spec/.git" ] \
    || fail "RUNTIME_TREE_EXCLUDES_VCS: shell installer copied a .git gitlink into the runtime"
[ -f "$VCS_DEST/external/aport-policies/packs/a/b/c/nested/pack.json" ] \
    || fail "RUNTIME_TREE_KEEPS_CONTENT: shell installer dropped deeply nested tree content"
[ ! -e "$VCS_DEST/external/aport-policies/packs/a/b/c/nested/.git" ] \
    || fail "RUNTIME_TREE_EXCLUDES_VCS: a nested .git directory survived the strip"
echo "  OK RUNTIME_TREE_EXCLUDES_VCS: shell installer keeps tree content and drops VCS metadata at any depth"

# The Python installer and the packaging hook share the same rule; check them against the same fixture.
if command -v python3 > /dev/null; then
    PY_DEST="$TEST_DIR/vcs-dest-python"
    rm -rf "$PY_DEST"
    python3 - "$REPO_ROOT" "$VCS_FIXTURE" "$PY_DEST" << 'PYCHECK' || fail "RUNTIME_TREE_EXCLUDES_VCS: Python copiers copied VCS metadata"
import shutil
import sys
from pathlib import Path

repo_root, fixture, dest = (Path(a) for a in sys.argv[1:4])
sys.path.insert(0, str(repo_root / "python"))
from aport_guardrails.core.runtime_assets import _ignore_vcs_metadata as runtime_ignore

problems = []
for label, ignore in (("runtime_assets", runtime_ignore),):
    target = dest / label
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(fixture / "external" / "aport-policies", target, ignore=ignore)
    if not (target / "policies" / "sample.json").is_file():
        problems.append(f"{label}: dropped real tree content")
    if (target / ".git").exists():
        problems.append(f"{label}: copied a .git directory")
    nested = target / "packs" / "a" / "b" / "c" / "nested"
    if not (nested / "pack.json").is_file():
        problems.append(f"{label}: dropped deeply nested tree content")
    if (nested / ".git").exists():
        problems.append(f"{label}: copied a nested .git directory")

# The packaging hook declares the same exclusion set; compare it rather than re-running setuptools.
hook_source = (repo_root / "python" / "aport_guardrails" / "setup.py").read_text()
if "_ignore_vcs_metadata" not in hook_source or "ignore=_ignore_vcs_metadata" not in hook_source:
    problems.append("setup.py: packaging hook does not exclude VCS metadata when copying a manifest tree")

for problem in problems:
    print(f"FAIL: {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
PYCHECK
    echo "  OK RUNTIME_TREE_EXCLUDES_VCS: Python runtime installer and packaging hook exclude VCS metadata"
fi

echo "PASS: runtime manifest lists every sourced library"

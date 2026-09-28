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

echo "PASS: runtime manifest lists every sourced library"

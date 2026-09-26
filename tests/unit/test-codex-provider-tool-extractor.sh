#!/bin/bash
# Unit test: the Codex provider extractor scans the production tool-spec tree, not just handlers.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
SOURCE_DIR="$TEST_DIR/fake-openai-codex"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$SOURCE_DIR/codex-rs/core/src/tools"

cat > "$SOURCE_DIR/codex-rs/core/src/tools/spec_plan.rs" << 'EOF'
pub(crate) const SPEC_PLAN_TOOL: &str = "fixture_spec_plan_tool";

pub(crate) fn spec_plan_tool() -> ToolName {
    ToolName::plain(SPEC_PLAN_TOOL)
}
EOF

cat > "$SOURCE_DIR/codex-rs/core/src/tools/spec_browser.rs" << 'EOF'
pub(crate) fn browser_tool() -> ToolName {
    ToolName::plain("fixture_sibling_spec_tool")
}
EOF

out="$(node "$REPO_ROOT/scripts/extract-codex-provider-tools.mjs" "$SOURCE_DIR")"
printf '%s\n' "$out" | grep -Fx "fixture_spec_plan_tool" > /dev/null \
    || fail "tool declared in core/src/tools/spec_plan.rs was not extracted: $out"
printf '%s\n' "$out" | grep -Fx "fixture_sibling_spec_tool" > /dev/null \
    || fail "tool declared in a sibling core/src/tools spec module was not extracted: $out"

echo "PASS: Codex provider extractor scans core tool specs"

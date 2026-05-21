#!/bin/bash
# Unit tests: tool-pack-mapping.json resolves Claude Code and guardrail tool names.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=bin/lib/tool-mapping.sh
. "$REPO_ROOT/bin/lib/tool-mapping.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

check_pack() {
    local tool="$1"
    local expected="$2"
    local got
    got="$(resolve_policy_id_from_tool_name "$tool" || true)"
    if [[ "$got" != "$expected" ]]; then
        fail "tool '$tool' -> '$got' (expected '$expected')"
    fi
}

CORE_JSON="$REPO_ROOT/packages/core/src/core/tool-pack-mapping.json"
PY_JSON="$REPO_ROOT/python/aport_guardrails/core/tool-pack-mapping.json"

echo ""
echo "  Unit — tool-pack-mapping.json (Claude Code + guardrail aliases)"
echo ""

if ! diff -q "$CORE_JSON" "$PY_JSON" > /dev/null 2>&1; then
    fail "core and python tool-pack-mapping.json are out of sync"
fi
echo "  ✅ core/python JSON files are identical"

check_pack "bash" "system.command.execute.v1"
check_pack "Agent" "agent.session.create.v1"
check_pack "agent" "agent.session.create.v1"
check_pack "Agent(Explore)" "agent.session.create.v1"
check_pack "session.create" "agent.session.create.v1"
check_pack "websearch" "web.fetch.v1"
check_pack "WebSearch" "web.fetch.v1"
check_pack "webfetch" "web.fetch.v1"
check_pack "write" "data.file.write.v1"
check_pack "mcp.tool" "mcp.tool.execute.v1"
check_pack "powershell" "system.command.execute.v1"
check_pack "SendMessage" "agent.session.create.v1"
check_pack "sessions_spawn" "agent.session.create.v1"
check_pack "sessions_list" "data.file.read.v1"
check_pack "browser" "web.browser.v1"
check_pack "croncreate" "agent.session.create.v1"
check_pack "cronlist" "data.file.read.v1"
check_pack "session.create" "agent.session.create.v1"
if resolve_policy_id_from_tool_name "unknown_xyz_tool" 2> /dev/null; then
    fail "unknown_xyz_tool should not resolve via bash mapping (fail-closed)"
fi

echo "  All tool-pack-mapping unit tests passed."
echo ""

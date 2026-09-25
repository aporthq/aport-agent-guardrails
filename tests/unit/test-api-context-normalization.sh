#!/bin/bash
# Unit test: hook-built context is shaped for the hosted verify API before it is sent.
# Regression for: Codex/Claude Bash calls in hosted mode denied with oap.evaluation_error because the context
# carried shell:"" or shell:"/bin/bash", which the API's schema rejects (HTTP 400 context_validation_failed).
# Shaping is keyed on the resolved policy id, so every tool that maps to the command policy is treated alike.
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../bin/lib/validation.sh
source "$REPO_ROOT/bin/lib/validation.sh"
# shellcheck source=../../bin/lib/tool-mapping.sh
source "$REPO_ROOT/bin/lib/tool-mapping.sh"
# shellcheck source=../../bin/lib/harness-context.sh
source "$REPO_ROOT/bin/lib/harness-context.sh"
fail() {
    echo "FAIL: $*" >&2
    exit 1
}
CMD="system.command.execute.v1"

out="$(normalize_api_context "$CMD" '{"command":"ls -la","shell":""}')"
[ "$out" = '{"command":"ls -la"}' ] || fail "empty shell must be dropped: $out"

out="$(normalize_api_context "$CMD" '{"command":"ls","shell":"/bin/bash","timeout":30}')"
[ "$out" = '{"command":"ls","shell":"bash","timeout":30}' ] || fail "path shell must become its basename: $out"

out="$(normalize_api_context "$CMD" '{"command":"ls","shell":"/usr/local/bin/dash"}')"
[ "$out" = '{"command":"ls"}' ] || fail "a shell outside the API enum must be dropped: $out"

out="$(normalize_api_context "$CMD" '{"command":"ls","shell":"zsh"}')"
[ "$out" = '{"command":"ls","shell":"zsh"}' ] || fail "an accepted shell must pass through: $out"

out="$(normalize_api_context "$CMD" '{"command":"ls","shell":null}')"
[ "$out" = '{"command":"ls"}' ] || fail "null shell must be dropped: $out"

out="$(normalize_api_context "$CMD" '{"command":"ls"}')"
[ "$out" = '{"command":"ls"}' ] || fail "absent shell must stay absent: $out"

out="$(normalize_api_context data.file.write.v1 '{"file_path":"/tmp/x","shell":""}')"
[ "$out" = '{"file_path":"/tmp/x","shell":""}' ] || fail "other policies are left alone: $out"

# Every tool that resolves to the command policy gets the same shaping, not only the ones a list named.
for tool in terminal run_terminal_cmd execute_command; do
    policy="$(resolve_policy_id_from_tool_name "$tool" || true)"
    [[ "$policy" == system.command.execute* ]] || {
        echo "  (skip: $tool maps to '${policy:-nothing}')"
        continue
    }
    out="$(normalize_api_context "$policy" '{"command":"ls","shell":"/bin/zsh"}')"
    [ "$out" = '{"command":"ls","shell":"zsh"}' ] || fail "$tool (policy $policy) must get its shell basenamed: $out"
done

# The builder itself never emits an empty shell, and basenames a path, so the local evaluator and the hosted one
# see the same value.
out="$(aport_hook_context_from_payload '{"tool_name":"Bash","tool_input":{"command":"ls"}}' shell bash claude-code)"
[[ "$out" != *'"shell"'* ]] || fail "the builder must not emit shell when the call names none: $out"
out="$(aport_hook_context_from_payload '{"tool_name":"Bash","tool_input":{"command":"ls","shell":"/bin/zsh"}}' shell bash claude-code)"
[[ "$out" == *'"shell":"zsh"'* ]] || fail "the builder must basename a shell path: $out"

echo "PASS: api context normalization"

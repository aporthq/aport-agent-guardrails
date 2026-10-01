#!/bin/bash
# Unit test: hook-built context is shaped for the hosted verify API before it is sent.
# Regression for: Codex/Claude Bash calls in hosted mode denied with oap.evaluation_error because the context
# carried shell:"" or shell:"/bin/bash", which the API's schema rejects (HTTP 400 context_validation_failed).
# Shaping is keyed on the resolved policy id, so every tool that maps to the command policy is treated alike.
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
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

APORT_USER_ID="user-from-env"
out="$(normalize_api_context agent.session.create.v1 '{"description_length":12,"session_operation":"create","session_type":"interactive"}')"
printf '%s' "$out" | jq -e '.user_id == "user-from-env" and .session_type == "interactive"' > /dev/null \
    || fail "session API context must add user_id and keep valid session_type: $out"
unset APORT_USER_ID

APORT_AGENT_ID="ap_hosted_session_test"
out="$(normalize_api_context agent.session.create.v1 '{"description_length":12,"session_operation":"create"}')"
printf '%s' "$out" | jq -e '.user_id == "ap_hosted_session_test" and .session_type == "interactive"' > /dev/null \
    || fail "session API context must derive hosted user_id and default session_type: $out"
unset APORT_AGENT_ID

stale_passport="$TEST_DIR/stale-local-passport.json"
printf '{"owner_id":"stale-local-owner","agent_id":"ap_stale_local"}\n' > "$stale_passport"
APORT_GUARDRAIL_MODE="api"
APORT_AGENT_ID="ap_hosted_session_test"
PASSPORT_FILE="$stale_passport"
out="$(normalize_api_context agent.session.create.v1 '{"description_length":12,"session_operation":"create"}')"
printf '%s' "$out" | jq -e '.user_id == "ap_hosted_session_test" and .session_type == "interactive"' > /dev/null \
    || fail "hosted session API context must prefer hosted agent id over stale local passport: $out"
unset APORT_GUARDRAIL_MODE APORT_AGENT_ID PASSPORT_FILE

APORT_USER_ID="user-from-env"
out="$(normalize_api_context agent.session.create.v1 '{"user_id":"payload-user","session_type":"experimental"}')"
printf '%s' "$out" | jq -e '.user_id == "payload-user" and .session_type == "experimental"' > /dev/null \
    || fail "session API context must not hide explicit invalid session_type values: $out"
unset APORT_USER_ID

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"explore repo","prompt":"secret_prompt_should_not_persist","subagent_type":"reviewer","duration_ms":3600000}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.session_type == "interactive" and .description_length > 0 and .subagent_type == "reviewer" and .current_active_sessions == 0 and .requested_duration == 3600' > /dev/null \
    || fail "Claude Agent(Explore) session context should include hosted session_type and bounded metadata without raw prompt: $out"
printf '%s' "$out" | grep -q 'secret_prompt_should_not_persist' && fail "session context must not include raw prompt"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"batch work","session_type":"batch"}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.session_type == "batch" and (. | has("invalid_session_type") | not)' > /dev/null \
    || fail "session context must preserve explicit valid session_type: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"bad type","session_type":"root"}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.invalid_session_type == true' > /dev/null \
    || fail "session context must flag invalid explicit session_type: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"bad type","session_type":["batch"]}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.invalid_session_type == true' > /dev/null \
    || fail "session context must reject non-string explicit session_type: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"matching type","session_type":"batch","sessionType":"Batch"}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.session_type == "batch" and (. | has("invalid_session_type") | not)' > /dev/null \
    || fail "session context must accept matching session_type aliases: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"conflicting type","session_type":"interactive","sessionType":"batch"}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.invalid_session_type == true' > /dev/null \
    || fail "session context must reject conflicting session_type aliases: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"explore repo","duration_ms":30000}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e 'has("requested_duration") | not' > /dev/null \
    || fail "session context must not emit schema-invalid requested_duration values: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"collaboration.wait_agent","active_session_count":0,"tool_input":{"id":"child-1","timeout_ms":30000}}' session 'collaboration.wait_agent' codex)"
printf '%s' "$out" | jq -e '.session_operation == "list" and (. | has("requested_duration") | not) and (. | has("invalid_session_duration") | not)' > /dev/null \
    || fail "wait_agent timeout_ms must not be treated as a requested session duration: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"conflicting duration","duration_seconds":60,"duration_ms":172800000}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.invalid_session_duration == true' > /dev/null \
    || fail "session context must flag conflicting duration aliases: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"current_active_sessions":10,"tool_input":{"description":"conflicting count"}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.invalid_session_count == true and .active_session_count == null and .current_active_sessions == null' > /dev/null \
    || fail "session context must flag conflicting active-session count aliases: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":"5","current_active_sessions":5,"tool_input":{"description":"matching count"}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.active_session_count == 5 and .current_active_sessions == 5 and (. | has("invalid_session_count") | not)' > /dev/null \
    || fail "session context must accept matching active-session count aliases: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"fractional overflow","duration_ms":86400999}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.invalid_session_duration == true' > /dev/null \
    || fail "session context must reject millisecond durations that round over the max: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"Agent(Explore)","active_session_count":0,"tool_input":{"description":"fractional ms","duration_ms":60000.1}}' session 'Agent(Explore)' claude-code)"
printf '%s' "$out" | jq -e '.invalid_session_duration == true' > /dev/null \
    || fail "session context must reject fractional millisecond durations: $out"

out="$(aport_hook_context_from_payload '{"tool_name":"CronCreate","active_session_count":0,"tool_input":{"description":"daily check"}}' session 'CronCreate' claude-code)"
printf '%s' "$out" | jq -e '.session_type == "scheduled"' > /dev/null \
    || fail "CronCreate session context should be scheduled: $out"

FAKE_NODE_DIR="$TEST_DIR/fake-node"
mkdir -p "$FAKE_NODE_DIR"
cat > "$FAKE_NODE_DIR/node" << 'EOF'
#!/bin/bash
set -e
printf '%s' "$2" > "$APORT_TEST_POLICY_FILE"
printf '%s' "$3" > "$APORT_TEST_CONTEXT_FILE"
EOF
chmod +x "$FAKE_NODE_DIR/node"
APORT_TEST_POLICY_FILE="$TEST_DIR/api-policy.txt" \
    APORT_TEST_CONTEXT_FILE="$TEST_DIR/api-session-context.json" \
    APORT_AGENT_ID="ap_hosted_wrapper_session_test" \
    APORT_USER_ID="hosted-wrapper-user" \
    OPENCLAW_CONFIG_DIR="$TEST_DIR" \
    PATH="$FAKE_NODE_DIR:$PATH" \
    "$REPO_ROOT/bin/aport-guardrail-api.sh" session.create '{"description_length":12,"session_operation":"create","session_type":"interactive"}'
grep -q '^agent.session.create.v1$' "$TEST_DIR/api-policy.txt" || fail "API wrapper should resolve session.create policy"
jq -e '.user_id == "hosted-wrapper-user" and .session_type == "interactive"' "$TEST_DIR/api-session-context.json" > /dev/null \
    || fail "API wrapper must send hosted-required session fields: $(cat "$TEST_DIR/api-session-context.json")"

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

# The builder never emits an empty shell, and it keeps the RAW path when the call names one. The basename is
# taken here, in normalize_api_context, on the way to the hosted API and nowhere earlier: the trust check in
# aport_hook_shell_override_is_trusted has to see the whole path, or "/tmp/bash" basenames to "bash", passes
# as a trusted interpreter, and the host runs an attacker-controlled binary while APort judges the command.
out="$(aport_hook_context_from_payload '{"tool_name":"Bash","tool_input":{"command":"ls"}}' shell bash claude-code)"
[[ "$out" != *'"shell"'* ]] || fail "the builder must not emit shell when the call names none: $out"
out="$(aport_hook_context_from_payload '{"tool_name":"Bash","tool_input":{"command":"ls","shell":"/bin/zsh"}}' shell bash claude-code)"
[[ "$out" == *'"shell":"/bin/zsh"'* ]] || fail "the builder must keep the raw shell path for the trust check: $out"
[[ "$(normalize_api_context system.command.execute.v1 "$out" | jq -r '.shell')" = "zsh" ]] \
    || fail "the API context must still receive the basename"
# A planted interpreter keeps its path all the way to the trust check, so it cannot masquerade as /bin/bash.
out="$(aport_hook_context_from_payload '{"tool_name":"Bash","tool_input":{"command":"ls","shell":"/tmp/bash"}}' shell bash claude-code)"
[[ "$out" == *'"shell":"/tmp/bash"'* ]] || fail "the builder must not collapse /tmp/bash to bash: $out"
# shellcheck source=../../bin/lib/hook-runtime.sh
source "$REPO_ROOT/bin/lib/hook-runtime.sh"
if aport_hook_shell_override_is_trusted "/tmp/bash"; then fail "/tmp/bash must not be trusted"; fi
aport_hook_shell_override_is_trusted "/bin/bash" || fail "/bin/bash must be trusted"

for shell_path in /tmp/bash /usr/local/bin/dash; do
    out="$TEST_DIR/direct-api-shell.out"
    err="$TEST_DIR/direct-api-shell.err"
    set +e
    APORT_AGENT_ID=ap_test_direct_shell OPENCLAW_CONFIG_DIR="$TEST_DIR" \
        "$REPO_ROOT/bin/aport-guardrail-api.sh" bash "{\"command\":\"ls\",\"shell\":\"$shell_path\"}" > "$out" 2> "$err"
    exit_code=$?
    set -e
    [ "$exit_code" -ne 0 ] || fail "direct API wrapper must reject untrusted shell $shell_path"
    grep -q 'oap.shell_not_allowed' "$err" || {
        cat "$out" >&2 || true
        cat "$err" >&2 || true
        fail "direct API wrapper should report shell_not_allowed for $shell_path"
    }
done

echo "PASS: api context normalization"

#!/bin/bash
# Shared adapter tests for Codex, Gemini CLI, and Goose hooks.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "$0")/../setup.sh"

mkdir -p "$TEST_DIR/aport"
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF

export OPENCLAW_CONFIG_DIR="$TEST_DIR"
export OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json"
export OPENCLAW_AUDIT_LOG="$TEST_DIR/aport/audit.log"

chmod +x "$REPO_ROOT/bin/aport-codex-hook.sh" "$REPO_ROOT/bin/aport-gemini-cli-hook.sh" "$REPO_ROOT/bin/aport-goose-hook.sh" 2> /dev/null || true

run_hook() {
    local desc="$1"
    local framework="$2"
    local script="$3"
    local input="$4"
    local jq_assertion="$5"
    local out="$TEST_DIR/out-${framework}-${RANDOM}.json"
    local err="$TEST_DIR/err-${framework}-${RANDOM}.txt"

    set +e
    printf '%s' "$input" | "$script" > "$out" 2> "$err"
    local exit_code=$?
    set -e

    if [[ "$exit_code" -ne 0 ]]; then
        echo "FAIL: $desc exited $exit_code" >&2
        cat "$out" >&2 || true
        cat "$err" >&2 || true
        exit 1
    fi
    if [[ -s "$out" ]]; then
        jq -e . "$out" > /dev/null || {
            echo "FAIL: $desc stdout must be valid JSON" >&2
            cat "$out" >&2
            exit 1
        }
        jq -e "$jq_assertion" "$out" > /dev/null || {
            echo "FAIL: $desc did not match expected response" >&2
            cat "$out" >&2
            exit 1
        }
    else
        [[ "$jq_assertion" = "empty" ]] || {
            echo "FAIL: $desc expected JSON output" >&2
            exit 1
        }
    fi

    echo "  ✅ $desc"
}

echo ""
echo "  Unit — shared command-hook adapter"
echo ""

CODEX="$REPO_ROOT/bin/aport-codex-hook.sh"
GEMINI="$REPO_ROOT/bin/aport-gemini-cli-hook.sh"
GOOSE="$REPO_ROOT/bin/aport-goose-hook.sh"

INCOMPLETE_RUNTIME="$TEST_DIR/incomplete-runtime"
mkdir -p "$INCOMPLETE_RUNTIME/bin/lib"
cp "$REPO_ROOT/bin/aport-gemini-cli-hook.sh" "$INCOMPLETE_RUNTIME/bin/aport-gemini-cli-hook.sh"
cp "$REPO_ROOT/bin/lib/command-hook-adapter.sh" "$INCOMPLETE_RUNTIME/bin/lib/command-hook-adapter.sh"
INCOMPLETE_OUT="$TEST_DIR/incomplete-runtime-out.json"
INCOMPLETE_ERR="$TEST_DIR/incomplete-runtime-err.txt"
set +e
printf '%s' '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"rm -rf /tmp/test"}}' \
    | bash "$INCOMPLETE_RUNTIME/bin/aport-gemini-cli-hook.sh" > "$INCOMPLETE_OUT" 2> "$INCOMPLETE_ERR"
INCOMPLETE_EXIT=$?
set -e
if [[ "$INCOMPLETE_EXIT" -ne 0 ]]; then
    echo "FAIL: incomplete command-hook runtime must return structured deny, got exit $INCOMPLETE_EXIT" >&2
    cat "$INCOMPLETE_OUT" >&2 || true
    cat "$INCOMPLETE_ERR" >&2 || true
    exit 1
fi
jq -e '.decision == "deny" and (.reason | contains("oap.missing_dependency"))' "$INCOMPLETE_OUT" > /dev/null || {
    echo "FAIL: incomplete command-hook runtime should emit missing-dependency deny JSON" >&2
    cat "$INCOMPLETE_OUT" >&2
    cat "$INCOMPLETE_ERR" >&2
    exit 1
}
echo "  ✅ Incomplete command-hook runtime fails closed with structured deny"

run_hook "Codex Bash allow returns empty success JSON" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    '. == {}'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex shell session context stores hash instead of raw command" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls secret_should_not_persist","timeout_seconds":5,"cwd":"/tmp"}}' \
    '. == {}'
if grep -q 'secret_should_not_persist\|ls ' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: shell decision context must not persist raw command text" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '
  .guardrail_tool == "bash"
  and .context.command_length > 0
  and (.context.command_hash_sha256 | type == "string" and length == 64)
  and .context.timeout == 5
  and (.context | has("command") | not)
' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: shell decision context should contain command metadata only" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Shell session decision context stores metadata only"

# Explicitly mapped Codex tools reach their policy by name, never by payload shape.
run_hook "Codex webrun reaches the web policy instead of unknown_tool" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"webrun","tool_input":{"url":"https://example.com/page"}}' \
    '(. == {}) or ((.hookSpecificOutput.permissionDecisionReason // "") | contains("oap.unknown_tool") | not)'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex browser navigation reaches browser policy, not web fetch" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"browser","tool_input":{"action":"open","url":"https://example.com/page"}}' \
    '. == {}'
jq -e '
  .original_tool == "browser"
  and .guardrail_tool == "browser"
  and .decision.policy_id == "web.browser.v1"
  and .context.action == "navigate"
  and .context.url == "https://example.com"
' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Codex browser navigation should be authorized as web.browser metadata" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Codex browser navigation maps to web.browser"

run_hook "Codex browser click fails closed locally instead of using web.fetch" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"browser","tool_input":{"action":"click","url":"https://example.com/page","selector":"#approve"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.interactive_browser_unsupported")) and ((.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool")) | not)'

run_hook "Codex browser rejects conflicting action aliases before choosing one" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"browser","tool_input":{"action":"click","url":"https://example.com/page","args":{"action":"navigate"}}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex browser rejects non-string action aliases before defaulting to navigation" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"browser","tool_input":{"action":{"type":"click"},"url":"https://example.com/page"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex computer_use is recognized but not authorized as web.fetch locally" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"computer_use","tool_input":{"action":"type","text":"secret_text_should_not_persist","url":"https://example.com/form"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.interactive_browser_unsupported")) and ((.hookSpecificOutput.permissionDecisionReason | contains("secret_text_should_not_persist")) | not)'

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
EOF
run_hook "Codex hosted computer_use without an explicit action fails closed before API evaluation" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"computer_use","tool_input":{"url":"https://example.com/form"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'

run_hook "Codex hosted computer_use rejects non-string action evidence before API evaluation" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"computer_use","tool_input":{"url":"https://example.com/form","action":{"kind":"type"}}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'
run_hook "Codex hosted computer_use rejects conflicting URL evidence before API evaluation" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"computer_use","url":"https://allowed.example/","tool_input":{"url":"https://evil.example/","action":"click"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex image_gen.imagegen reaches image generation policy without prompt text" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"secret_should_not_persist","num_last_images_to_include":0}}' \
    '. == {}'
if grep -q 'secret_should_not_persist' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: image generation decision context must not persist prompt text" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '
  .original_tool == "image_gen.imagegen"
  and .guardrail_tool == "image.generate"
  and .decision.policy_id == "media.image.generate.v1"
  and .context.provider == "openai"
  and .context.prompt_length == 25
  and .context.output_count == 1
  and .context.output_format == "png"
  and (.context | has("prompt") | not)
  and (.context | has("referenced_image_paths") | not)
' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: image generation should be authorized as sanitized media metadata" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Codex image generation records provider metadata only"

run_hook "Codex image_genimagegen concatenated host name reaches image generation policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_genimagegen","tool_input":{"prompt":"draw a safe badge"}}' \
    '. == {}'

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-wizard-image-test.json"
"$REPO_ROOT/bin/aport-create-passport.sh" --framework=codex --output "$TEST_DIR/aport/passport.json" --non-interactive > "$TEST_DIR/codex-wizard-image-passport.log" 2>&1
jq -e '
  any(.capabilities[]; .id == "media.image.generate")
  and (.limits["media.image.generate"].allowed_providers | type == "array")
  and (.limits["media.image.generate"].max_prompt_length | type == "number")
  and (.limits["media.image.generate"].max_referenced_images | type == "number")
  and (.limits["media.image.generate"].max_output_images | type == "number")
  and (.limits["media.image.generate"].allowed_output_formats | type == "array")
' "$TEST_DIR/aport/passport.json" > /dev/null || {
    echo "FAIL: Codex wizard passport should include media.image.generate capability and required limits" >&2
    cat "$TEST_DIR/aport/passport.json" >&2
    exit 1
}
run_hook "Codex wizard-generated local passport authorizes image generation metadata" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"wizard generated image passport","num_last_images_to_include":0}}' \
    '. == {}'
mv "$TEST_DIR/aport/passport.before-wizard-image-test.json" "$TEST_DIR/aport/passport.json"

run_hook "Codex image generation enforces previous-image reference count" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"edit the last image","num_last_images_to_include":1}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.referenced_image_limit_exceeded"))'

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-image-prompt-limit-test.json"
jq '.limits["media.image.generate"].max_prompt_length = 10' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
run_hook "Codex image generation enforces prompt length limit" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"this prompt is too long"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.prompt_too_large"))'
mv "$TEST_DIR/aport/passport.before-image-prompt-limit-test.json" "$TEST_DIR/aport/passport.json"

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-image-output-count-test.json"
jq '.limits["media.image.generate"].max_output_images = 1' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
run_hook "Codex image generation enforces output image count" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge","n":2}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.output_image_limit_exceeded"))'
mv "$TEST_DIR/aport/passport.before-image-output-count-test.json" "$TEST_DIR/aport/passport.json"

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-image-format-test.json"
jq '.limits["media.image.generate"].allowed_output_formats = ["png"]' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
run_hook "Codex image generation enforces output format allowlist" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge","output_format":"gif"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.output_format_not_allowed"))'
mv "$TEST_DIR/aport/passport.before-image-format-test.json" "$TEST_DIR/aport/passport.json"

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-image-missing-limit-test.json"
jq 'del(.limits["media.image.generate"].max_prompt_length)' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
run_hook "Codex image generation fails closed when required media limits are missing" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_limit"))'
mv "$TEST_DIR/aport/passport.before-image-missing-limit-test.json" "$TEST_DIR/aport/passport.json"

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-image-provider-test.json"
jq '.limits["media.image.generate"].allowed_providers = ["openai"]' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
APORT_IMAGE_GENERATION_PROVIDER=blocked-provider run_hook "Codex image generation enforces provider allowlist" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.provider_not_allowed"))'
mv "$TEST_DIR/aport/passport.before-image-provider-test.json" "$TEST_DIR/aport/passport.json"

run_hook "Codex image generation with referenced local paths fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"edit this","referenced_image_paths":["/tmp/source.png"]}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.multi_policy_tool_unsupported"))'

run_hook "Codex image generation rejects malformed referenced_image_paths" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"edit this","referenced_image_paths":"/tmp/source.png"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex image generation rejects malformed referenced image entries" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"edit this","referenced_image_paths":["/tmp/source.png",17]}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex image generation rejects malformed previous-image count" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"edit the last image","num_last_images_to_include":"many"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex image generation rejects fractional output count" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge","n":1.5}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex image generation rejects non-positive output count" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge","output_count":0}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex image generation rejects conflicting output count aliases" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge","n":1,"num_images":100,"output_format":"png"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-image-capability-test.json"
jq 'del(.capabilities[] | select(.id == "media.image.generate"))' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
run_hook "Codex image generation requires media.image.generate capability" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_capability"))'
mv "$TEST_DIR/aport/passport.before-image-capability-test.json" "$TEST_DIR/aport/passport.json"

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-image-unsupported-limit-test.json"
jq '.limits["media.image.generate"].unsupported_limit = true' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
run_hook "Codex image generation rejects unsupported media limits" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unsupported_limit"))'
mv "$TEST_DIR/aport/passport.before-image-unsupported-limit-test.json" "$TEST_DIR/aport/passport.json"

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-image-format-limit-test.json"
jq '.limits["media.image.generate"].allowed_output_formats = "png"' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
run_hook "Codex image generation rejects malformed output format limits" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"draw a safe badge"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_limit"))'
mv "$TEST_DIR/aport/passport.before-image-format-limit-test.json" "$TEST_DIR/aport/passport.json"

run_hook "Codex image generation rejects conflicting prompt containers" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"this prompt must not be shadowed"},"args":{"prompt":"ok"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex image generation rejects conflicting referenced image containers" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"image_gen.imagegen","tool_input":{"prompt":"edit","referenced_image_paths":["/tmp/source-a-secret.png"]},"args":{"referenced_image_paths":["/tmp/source-b-secret.png"]}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments")) and ((.hookSpecificOutput.permissionDecisionReason | contains("source-a-secret")) | not) and ((.hookSpecificOutput.permissionDecisionReason | contains("source-b-secret")) | not)'

run_hook "Codex update_plan is session bookkeeping and is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"update_plan","tool_input":{"plan":[{"step":"x","status":"pending"}]}}' \
    '. == {}'

run_hook "Codex request_user_input_async is prompt bookkeeping and is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"request_user_input_async","tool_input":{"question":"Continue?","task_handle":"surface-user-input"}}' \
    '. == {}'

run_hook "Codex request_user_input_sync remains unmapped until observed in Codex" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"request_user_input_sync","tool_input":{"question":"Continue?"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool"))'

run_hook "Codex skills.read provider tool is explicitly classified" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"skills.read","tool_input":{"package":"skill://example","resource":"skill://example/SKILL.md"}}' \
    '. == {}'

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-memory-write-test.json"
jq '.capabilities = [] | .limits = {}' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
run_hook "Codex memories.add_ad_hoc_note fails closed as an unrepresentable provider-memory write" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"memories.add_ad_hoc_note","tool_input":{"note":"secret_note_should_not_persist"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unrepresentable_tool")) and ((.hookSpecificOutput.permissionDecisionReason | contains("secret_note_should_not_persist")) | not)'
mv "$TEST_DIR/aport/passport.before-memory-write-test.json" "$TEST_DIR/aport/passport.json"

run_hook "Codex memories.search provider metadata read remains explicitly classified" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"memories.search","tool_input":{"query":"project"}}' \
    '. == {}'

run_hook "Codex memory_read provider metadata read remains explicitly classified" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"memory_read","tool_input":{"key":"project"}}' \
    '. == {}'

run_hook "Codex memory_write fails closed instead of matching a wildcard" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"memory_write","tool_input":{"value":"secret_memory_should_not_persist"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool")) and ((.hookSpecificOutput.permissionDecisionReason | contains("secret_memory_should_not_persist")) | not)'

run_hook "Codex plugin candidate listing is explicitly classified" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"list_available_plugins_to_install","tool_input":{}}' \
    '. == {}'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex plugin install request routes through MCP policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"request_plugin_install","tool_input":{"tool_id":"private-plugin-should-not-persist","tool_type":"plugin","suggest_reason":"secret_reason_should_not_persist"}}' \
    '. == {}'
if grep -q 'private-plugin-should-not-persist\|secret_reason_should_not_persist' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: Codex plugin install context must not persist raw requested plugin values" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '
  .guardrail_tool == "mcp.tool"
  and .context.mcp_server == "codex"
  and .context.mcp_tool == "request_plugin_install"
  and (.context.parameter_keys | index("tool_id") != null)
  and (.context.parameter_keys | index("suggest_reason") != null)
' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Codex plugin install should route to codex/request_plugin_install MCP policy metadata" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Codex plugin install request maps to MCP policy metadata"

cp "$TEST_DIR/aport/passport.json" "$TEST_DIR/aport/passport.before-plugin-install-spoof-test.json"
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_plugin_install_codex_denied",
  "agent_id": "ap_plugin_install_codex_denied",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["evil"],
      "allowed_tools": ["harmless"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex plugin install ignores spoofed MCP routing metadata" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"request_plugin_install","mcp_context":{"server":"evil","tool":"harmless"},"tool_input":{"tool_id":"safe-looking-plugin"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.mcp_server_not_allowed"))'
mv "$TEST_DIR/aport/passport.before-plugin-install-spoof-test.json" "$TEST_DIR/aport/passport.json"

run_hook "Codex local_shell maps to the shell policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"local_shell","tool_input":{"command":"rm -rf /tmp/test"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and ((.hookSpecificOutput.permissionDecisionReason // "") | contains("oap.unknown_tool") | not)'

# An unmapped Codex tool denies by default. Routing by payload shape authorizes by shape, not by what the
# tool does, so it is off unless the operator turns it on for a tool surface they have reviewed.
run_hook "Codex unmapped tool with a url denies by default" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"web_page_runner","tool_input":{"url":"https://example.com/"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool"))'

run_hook "Codex unmapped tool with a command denies by default" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"execute_sql","tool_input":{"command":"ls -la"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool"))'

run_hook "Codex unmapped tool with a path denies by default" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"vault_reader","tool_input":{"path":"/etc/hosts"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool"))'

# Same three payloads with the operator opt-in. They now reach a policy instead of oap.unknown_tool.
run_codex_fallback_on() {
    local desc="$1" input="$2" assertion="$3"
    local out="$TEST_DIR/out-codex-fallback-on-${RANDOM}.json"
    printf '%s' "$input" \
        | APORT_CODEX_TOOL_FALLBACK=on APORT_CODEX_CONFIG_DIR="$TEST_DIR" "$CODEX" > "$out" 2> /dev/null || true
    jq -e "$assertion" "$out" > /dev/null || {
        echo "FAIL: $desc" >&2
        cat "$out" >&2
        exit 1
    }
    echo "  ✅ $desc"
}

run_codex_fallback_on "Opt-in fallback routes an unmapped tool with a url to the web policy" \
    '{"hook_event_name":"PreToolUse","tool_name":"web_page_runner","tool_input":{"url":"https://example.com/"}}' \
    '(. == {}) or ((.hookSpecificOutput.permissionDecisionReason // "") | contains("oap.unknown_tool") | not)'

# execute_sql carries only a command, so the command policy judges that string (allowed_commands,
# blocked_patterns); nothing in the name is trusted. That is the opt-in fallback's contract.
run_codex_fallback_on "Opt-in fallback judges a command-only unmapped tool by the command policy" \
    '{"hook_event_name":"PreToolUse","tool_name":"execute_sql","tool_input":{"command":"rm -rf /tmp/test"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and ((.hookSpecificOutput.permissionDecisionReason // "") | contains("oap.unknown_tool") | not)'

run_codex_fallback_on "Opt-in fallback still fails closed on a payload that says nothing" \
    '{"hook_event_name":"PreToolUse","tool_name":"frobnicate","tool_input":{"x":1}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool"))'

run_codex_fallback_on "Opt-in fallback: a name that sounds like a read but carries no path is unknown" \
    '{"hook_event_name":"PreToolUse","tool_name":"read_secret_from_vault","tool_input":{"key":"db/creds"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool"))'

# A payload carrying more than one effect denies even with the opt-in. Picking one effect means dropping the
# others unevaluated: this payload used to route to web.fetch, drop the denied command, and return allow.
run_codex_fallback_on "Opt-in fallback denies a mixed command+url payload instead of picking one" \
    '{"hook_event_name":"PreToolUse","tool_name":"mystery_tool","tool_input":{"command":"rm -rf /","url":"https://example.com/"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_codex_fallback_on "Opt-in fallback denies a mixed command+path payload" \
    '{"hook_event_name":"PreToolUse","tool_name":"mystery_tool","tool_input":{"command":"rm -rf /","file_path":"/tmp/x","content":"hi"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_codex_fallback_on "Opt-in fallback denies a mixed url+path payload" \
    '{"hook_event_name":"PreToolUse","tool_name":"mystery_tool","tool_input":{"url":"https://example.com/","file_path":"/tmp/x"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_codex_fallback_on "Opt-in fallback denies mixed effects hidden in nested args" \
    '{"hook_event_name":"PreToolUse","tool_name":"mystery_tool","tool_input":{"args":{"command":"rm -rf /tmp/test"},"url":"https://example.com/"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_codex_fallback_on "Opt-in fallback denies mixed effects hidden in nested arguments" \
    '{"hook_event_name":"PreToolUse","tool_name":"mystery_tool","args":{"arguments":{"command":"rm -rf /tmp/test"},"url":"https://example.com/"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

CODEX_FALLBACK_OFF_OUT="$TEST_DIR/out-codex-fallback-off.json"
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"web_page_runner","tool_input":{"url":"https://example.com/"}}' \
    | APORT_CODEX_TOOL_FALLBACK=off APORT_CODEX_CONFIG_DIR="$TEST_DIR" "$CODEX" > "$CODEX_FALLBACK_OFF_OUT" 2> /dev/null || true
jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_tool"))' "$CODEX_FALLBACK_OFF_OUT" > /dev/null || {
    echo "FAIL: APORT_CODEX_TOOL_FALLBACK=off should keep the strict list only" >&2
    cat "$CODEX_FALLBACK_OFF_OUT" >&2
    exit 1
}
echo "  ✅ Codex tool fallback can be switched off explicitly too"

# write_stdin submits keystrokes into a session an exec_command already opened. When that session is an
# interactive shell the keystrokes are a new command, so they are evaluated as shell input rather than
# waved through as session bookkeeping.
run_hook "Codex write_stdin carrying a denied command does not allow" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"write_stdin","tool_input":{"session_id":"s1","chars":"rm -rf /tmp/test\n"}}' \
    '.hookSpecificOutput.permissionDecision == "deny"'

run_hook "Codex write_stdin rejects conflicting input containers" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"write_stdin","tool_input":{"session_id":"s1","chars":"rm -rf /tmp/test\n"},"args":{"chars":"ls -la\n"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments")) and ((.hookSpecificOutput.permissionDecisionReason | contains("rm -rf")) | not)'

run_hook "Codex write_stdin carrying an allowed command reaches the command policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"write_stdin","tool_input":{"session_id":"s1","chars":"ls -la\n"}}' \
    '. == {}'

run_hook "Codex write_stdin partial command fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"write_stdin","tool_input":{"session_id":"s1","chars":"rm"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.partial_stdin_unsupported"))'

run_hook "Codex write_stdin denies trailing partial input after a newline" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"write_stdin","tool_input":{"session_id":"s1","chars":"echo ok\nrm -"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.partial_stdin_unsupported"))'

WRITE_STDIN_BACKSLASH_INPUT="$(
    jq -nc --arg chars $'rm \\\n' \
        '{hook_event_name:"PreToolUse",tool_name:"write_stdin",tool_input:{session_id:"s1",chars:$chars}}'
)"
run_hook "Codex write_stdin rejects trailing backslash shell continuation" \
    codex "$CODEX" \
    "$WRITE_STDIN_BACKSLASH_INPUT" \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.partial_stdin_unsupported"))'

WRITE_STDIN_OPEN_QUOTE_INPUT="$(
    jq -nc --arg chars $'echo "unterminated\n' \
        '{hook_event_name:"PreToolUse",tool_name:"write_stdin",tool_input:{session_id:"s1",chars:$chars}}'
)"
run_hook "Codex write_stdin rejects open-quote shell continuation" \
    codex "$CODEX" \
    "$WRITE_STDIN_OPEN_QUOTE_INPUT" \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.partial_stdin_unsupported"))'

run_hook "Codex write_stdin control-only input fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"write_stdin","tool_input":{"session_id":"s1","chars":"\n"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.partial_stdin_unsupported"))'

WRITE_STDIN_VERTICAL_TAB_INPUT="$(
    jq -nc --arg chars $'\v\n' \
        '{hook_event_name:"PreToolUse",tool_name:"write_stdin",tool_input:{session_id:"s1",chars:$chars}}'
)"
run_hook "Codex write_stdin vertical-tab control-only input fails closed" \
    codex "$CODEX" \
    "$WRITE_STDIN_VERTICAL_TAB_INPUT" \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.partial_stdin_unsupported"))'

WRITE_STDIN_DEL_INPUT="$(
    jq -nc --arg chars $'\177\n' \
        '{hook_event_name:"PreToolUse",tool_name:"write_stdin",tool_input:{session_id:"s1",chars:$chars}}'
)"
run_hook "Codex write_stdin DEL control-only input fails closed" \
    codex "$CODEX" \
    "$WRITE_STDIN_DEL_INPUT" \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.partial_stdin_unsupported"))'

run_hook "Codex write_stdin with no characters is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"write_stdin","tool_input":{"session_id":"s1","chars":""}}' \
    '. == {}'
echo "  ✅ Codex write_stdin is evaluated, not assumed harmless"

run_hook "Codex exec_command maps to shell policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"ls -la"}}' \
    '. == {}'

run_hook "Codex exec_command rejects untrusted shell override" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"ls -la","shell":"/tmp/untrusted-shell"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.shell_not_allowed"))'

# The trust check has to see the whole path. An attacker-planted /tmp/bash basenames to "bash", which is in
# the trusted set, so a context builder that basenamed before the check let the host run /tmp/bash while
# APort judged only "ls -la". The name of the interpreter is not evidence about the interpreter.
run_hook "Codex exec_command rejects /tmp/bash, whose basename would pass as trusted" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"ls -la","shell":"/tmp/bash"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.shell_not_allowed"))'

run_hook "Codex exec_command rejects a planted /tmp/sh too" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"ls -la","shell":"/tmp/sh"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.shell_not_allowed"))'

# The context the trust check reads keeps the raw path; only normalize_api_context basenames it, on the way
# to the hosted API, whose schema takes the enum and not a path.
(
    source "$REPO_ROOT/bin/lib/harness-context.sh"
    source "$REPO_ROOT/bin/lib/validation.sh"
    raw="$(aport_hook_context_from_payload '{"tool_input":{"cmd":"ls","shell":"/bin/bash"}}' shell exec_command codex)"
    [[ "$(printf '%s' "$raw" | jq -r '.shell')" == "/bin/bash" ]] || {
        echo "FAIL: hook context must keep the raw shell path, got $raw" >&2
        exit 1
    }
    api="$(normalize_api_context system.command.execute.v1 "$raw")"
    [[ "$(printf '%s' "$api" | jq -r '.shell')" == "bash" ]] || {
        echo "FAIL: API context must receive the basename, got $api" >&2
        exit 1
    }
) || exit 1
echo "  ✅ Shell trust is decided on the full path; the API still gets the basename"

ALT_BASH_DIR="$TEST_DIR/alternate-bash"
mkdir -p "$ALT_BASH_DIR"
cat > "$ALT_BASH_DIR/bash" << 'EOF'
#!/bin/sh
exec /bin/bash "$@"
EOF
chmod +x "$ALT_BASH_DIR/bash"
CODEX_SYSTEM_SHELL_OUT="$TEST_DIR/out-codex-system-shell.json"
CODEX_SYSTEM_SHELL_ERR="$TEST_DIR/err-codex-system-shell.txt"
set +e
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"ls -la","shell":"/bin/bash"}}' \
    | PATH="$ALT_BASH_DIR:$PATH" "$CODEX" > "$CODEX_SYSTEM_SHELL_OUT" 2> "$CODEX_SYSTEM_SHELL_ERR"
CODEX_SYSTEM_SHELL_EXIT=$?
set -e
if [[ "$CODEX_SYSTEM_SHELL_EXIT" -ne 0 ]]; then
    echo "FAIL: Codex exec_command with explicit /bin/bash exited $CODEX_SYSTEM_SHELL_EXIT" >&2
    cat "$CODEX_SYSTEM_SHELL_OUT" >&2 || true
    cat "$CODEX_SYSTEM_SHELL_ERR" >&2 || true
    exit 1
fi
jq -e '. == {}' "$CODEX_SYSTEM_SHELL_OUT" > /dev/null || {
    echo "FAIL: Codex exec_command should allow explicit /bin/bash even when PATH has another bash first" >&2
    cat "$CODEX_SYSTEM_SHELL_OUT" >&2
    cat "$CODEX_SYSTEM_SHELL_ERR" >&2
    exit 1
}
echo "  ✅ Codex exec_command trusts explicit system shell independent of PATH ordering"

run_hook "Codex exec_command rejects unsupported fish shell override" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"git (touch /tmp/aport-review-marker)","shell":"fish"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.shell_not_allowed"))'

run_hook "Codex exec_command rejects conflicting command aliases" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"rm -rf /tmp/unauthorized-target","command":"ls"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex exec_command rejects conflicting command containers" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"command":"rm -rf /tmp/not-executed"},"input":{"command":"ls"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex exec_command rejects non-string command aliases" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":{"unexpected":"shape"}}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex Bash deny uses PreToolUse permissionDecision" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny"'

run_hook "Codex Bash without command fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"description":"missing command"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_command"))'

run_hook "Codex shell allowlist rejects prefixed executable names" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git-malware status"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_not_allowed"))'

run_hook "Gemini shell allowlist rejects prefixed executable names" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"git-malware status"}}' \
    '.decision == "deny" and (.reason | contains("oap.command_not_allowed"))'

run_hook "Goose shell allowlist rejects prefixed executable names" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__shell","tool_input":{"command":"git-malware status"}}' \
    '.decision == "block" and (.reason | contains("oap.command_not_allowed"))'

run_hook "Codex shell allowlist rejects chained commands" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status; unauthorized-command"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_chain_unsupported"))'

reentrant_background_payload="$(jq -nc --arg cmd "$REPO_ROOT/bin/aport-guardrail-bash.sh & touch /tmp/aport-unauthorized" \
    '{hook_event_name:"PreToolUse",tool_name:"exec_command",tool_input:{cmd:$cmd}}')"
run_hook "Codex reentrant guardrail command rejects background chains" \
    codex "$CODEX" \
    "$reentrant_background_payload" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_chain_unsupported"))'

run_hook "Gemini shell allowlist rejects newline command chains" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"git status\nunauthorized-command"}}' \
    '.decision == "deny" and (.reason | contains("oap.command_chain_unsupported"))'

run_hook "Codex shell allowlist rejects quoted command substitution" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"git \"$(unauthorized-command)\""}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_chain_unsupported"))'

run_hook "Codex shell allowlist rejects ANSI-C quote chains" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"git $'\''\\'\'''\''; unauthorized-command # '\''"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_chain_unsupported"))'

run_hook "Codex shell allowlist rejects comment-hidden newline chains" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"git # '\''\nwhoami\n# '\''"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_chain_unsupported"))'

run_hook "Codex shell allowlist rejects unquoted parentheses" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"git (touch /tmp/aport-review-marker)"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_chain_unsupported"))'

run_hook "Codex PermissionRequest deny uses decision.behavior" \
    codex "$CODEX" \
    '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"sudo reboot"}}' \
    '.hookSpecificOutput.hookEventName == "PermissionRequest" and .hookSpecificOutput.decision.behavior == "deny"'

run_hook "Codex PermissionRequest without tool name fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PermissionRequest","tool_input":{"command":"sudo reboot"}}' \
    '.hookSpecificOutput.hookEventName == "PermissionRequest" and .hookSpecificOutput.decision.behavior == "deny" and (.hookSpecificOutput.decision.message | contains("oap.missing_tool_name"))'

run_hook "Codex rejects unknown hook event names" \
    codex "$CODEX" \
    '{"hook_event_name":"BeforePrompt","tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unknown_hook_event"))'

run_hook "Gemini rejects unknown hook event names" \
    gemini "$GEMINI" \
    '{"hook_event_name":"AfterTool","tool_name":"run_shell_command","tool_input":{"command":"ls -la"}}' \
    '.decision == "deny" and (.reason | contains("oap.unknown_hook_event"))'

run_hook "Goose rejects unknown hook event names" \
    goose "$GOOSE" \
    '{"hook_event_name":"PostToolUse","tool_name":"developer__shell","tool_input":{"command":"ls -la"}}' \
    '.decision == "block" and (.reason | contains("oap.unknown_hook_event"))'

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
run_hook "Codex warn mode allows with additionalContext" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.systemMessage
      and .hookSpecificOutput.additionalContext
      and (.systemMessage | contains("report-only mode allowed"))
      and (.systemMessage | contains("Evidence:"))
      and (.systemMessage | contains("audit.log"))
      and (.systemMessage | contains("session-decisions.jsonl"))
      and ((.systemMessage | contains("decision.json")) | not)
      and (.systemMessage | contains("mode codex --enforcement=enforce"))
      and ((.systemMessage | contains("Review or update the hosted passport")) | not)'

run_hook "Codex warn mode keeps shell parser ambiguity blocking" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status; unauthorized-command"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.command_chain_unsupported"))'

STALE_DECISION_BASE="$TEST_DIR/aport/stale-decision.json"
STALE_DECISION_OUT="$TEST_DIR/stale-decision-out.json"
STALE_DECISION_ERR="$TEST_DIR/stale-decision-err.txt"
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_API_URL=http://127.0.0.1:9
APORT_AGENT_ID=ap_unreachable_test
APORT_ENFORCEMENT=warn
EOF
set +e
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}' \
    | OPENCLAW_DECISION_FILE="$STALE_DECISION_BASE" bash -c '
        stale="${OPENCLAW_DECISION_FILE%.json}-$$.json"
        printf "%s" "{\"allow\":true,\"policy_id\":\"system.command.execute.v1\",\"reasons\":[{\"code\":\"oap.allowed\",\"message\":\"stale\"}]}" > "$stale"
        exec "$1"
    ' _ "$CODEX" > "$STALE_DECISION_OUT" 2> "$STALE_DECISION_ERR"
STALE_DECISION_EXIT=$?
set -e
if [[ "$STALE_DECISION_EXIT" -ne 0 ]]; then
    echo "FAIL: stale decision regression exited $STALE_DECISION_EXIT" >&2
    cat "$STALE_DECISION_OUT" >&2 || true
    cat "$STALE_DECISION_ERR" >&2 || true
    exit 1
fi
jq -e '.hookSpecificOutput.permissionDecision == "deny" and ((.hookSpecificOutput.permissionDecisionReason | contains("oap.evaluator_failed")) or (.hookSpecificOutput.permissionDecisionReason | contains("oap.evaluation_error")))' "$STALE_DECISION_OUT" > /dev/null || {
    echo "FAIL: stale decision file must not downgrade evaluator failure in warn mode" >&2
    cat "$STALE_DECISION_OUT" >&2
    cat "$STALE_DECISION_ERR" >&2
    exit 1
}
echo "  ✅ Stale decision files are cleared before evaluator execution"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_command_timeout_limit",
  "agent_id": "ap_command_timeout_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "system.command.execute"}],
  "limits": {
    "system.command.execute": {
      "allowed_commands": ["git"],
      "max_execution_time": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex shell enforces configured timeout when supplied" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"git status","timeoutMs":2000}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.timeout_exceeded"))'

# exec_command is a unified-exec session: the process outlives the call, so there is no bound and no default.
# Without timeout evidence it stays denied when the passport sets max_execution_time.
run_hook "Codex exec_command without a timeout is unbounded and still requires timeout evidence" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"git status"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'

# The legacy shell tool kills at DEFAULT_EXEC_COMMAND_TIMEOUT_MS (10000 ms), so that is the timeout evidence the
# hook supplies for it. Against max_execution_time 1 it must be denied as exceeded, never as missing.
run_hook "Codex shell without a timeout is judged by the Codex default against max_execution_time" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"shell","tool_input":{"command":"git status"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.timeout_exceeded"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_command_timeout_limit_30",
  "agent_id": "ap_command_timeout_limit_30",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "system.command.execute"}],
  "limits": {
    "system.command.execute": {
      "allowed_commands": ["git"],
      "max_execution_time": 30
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex shell without a timeout is allowed under a limit above the Codex default and records 10s" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"shell","tool_input":{"command":"git status"}}' \
    '. == {}'
jq -e '.guardrail_tool == "bash" and .context.timeout == 10' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Codex shell without a timeout should record the 10s default, got:" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Codex shell without a timeout carries the 10s Codex default"

cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"

DIRECT_ARGS_OUT="$TEST_DIR/direct-shell-args-object-out.txt"
DIRECT_ARGS_ERR="$TEST_DIR/direct-shell-args-object-err.txt"
set +e
"$REPO_ROOT/bin/aport-guardrail-bash.sh" bash '{"args":{"0":"ls"}}' > "$DIRECT_ARGS_OUT" 2> "$DIRECT_ARGS_ERR"
DIRECT_ARGS_EXIT=$?
set -e
if [[ "$DIRECT_ARGS_EXIT" -eq 0 ]]; then
    echo "FAIL: direct local evaluator must reject non-array shell args" >&2
    cat "$DIRECT_ARGS_OUT" >&2 || true
    cat "$DIRECT_ARGS_ERR" >&2 || true
    exit 1
fi
jq -e '.allow == false and (.reasons[0].code == "oap.invalid_tool_arguments")' "$TEST_DIR/aport/decision.json" > /dev/null || {
    echo "FAIL: direct local evaluator should report invalid_tool_arguments for non-array shell args" >&2
    cat "$TEST_DIR/aport/decision.json" >&2
    exit 1
}
echo "  ✅ Direct shell evaluator rejects non-array args"

if command -v mkfifo > /dev/null 2>&1; then
    cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_read_fifo_size_limit",
  "agent_id": "ap_read_fifo_size_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.read"}],
  "limits": {
    "data.file.read": {
      "allowed_paths": ["*"],
      "max_file_size_bytes": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
    FIFO_PATH="$TEST_DIR/read-fifo"
    rm -f "$FIFO_PATH"
    mkfifo "$FIFO_PATH"
    FIFO_OUT="$TEST_DIR/read-fifo-out.txt"
    FIFO_ERR="$TEST_DIR/read-fifo-err.txt"
    FIFO_CONTEXT="$(jq -n -c --arg file "$FIFO_PATH" '{file_path:$file}')"
    set +e
    "$REPO_ROOT/bin/aport-guardrail-bash.sh" read "$FIFO_CONTEXT" > "$FIFO_OUT" 2> "$FIFO_ERR"
    FIFO_EXIT=$?
    set -e
    if [[ "$FIFO_EXIT" -eq 0 ]]; then
        echo "FAIL: non-regular file reads with size limits must fail closed" >&2
        cat "$FIFO_OUT" >&2 || true
        cat "$FIFO_ERR" >&2 || true
        exit 1
    fi
    jq -e '.allow == false and (.reasons[0].code == "oap.missing_required_context")' "$TEST_DIR/aport/decision.json" > /dev/null || {
        echo "FAIL: FIFO read should fail with missing_required_context" >&2
        cat "$TEST_DIR/aport/decision.json" >&2
        exit 1
    }
    echo "  ✅ Non-regular file reads with size limits fail closed"
    cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
else
    echo "  ⚠️  mkfifo unavailable; skipping non-regular file-read size-limit test"
fi

run_hook "Gemini run_shell_command deny uses Gemini decision JSON" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.decision == "deny" and (.reason | contains("APort denied"))'

run_hook "Gemini valid shell allow returns allow JSON" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls -la"}}' \
    '.decision == "allow"'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_gemini_replace_size_limit",
  "agent_id": "ap_gemini_replace_size_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["*"],
      "max_file_size_bytes": 15
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
GEMINI_REPLACE_FILE="$TEST_DIR/gemini-replace-size.txt"
printf 'aa' > "$GEMINI_REPLACE_FILE"
run_hook "Gemini replace expected_replacements contributes to resulting size" \
    gemini "$GEMINI" \
    "{\"hook_event_name\":\"BeforeTool\",\"tool_name\":\"replace\",\"tool_input\":{\"file_path\":\"$GEMINI_REPLACE_FILE\",\"old_string\":\"a\",\"new_string\":\"bbbbbbbbbb\",\"expected_replacements\":2}}" \
    '.decision == "deny" and (.reason | contains("oap.file_too_large"))'

cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"

run_hook "Gemini list_directory fails closed as metadata enumeration" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"list_directory","tool_input":{"dir_path":"/tmp/.ssh"}}' \
    '.decision == "deny" and (.reason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Gemini list_directory with broad root fails closed as metadata enumeration" \
    gemini "$GEMINI" \
    "{\"hook_event_name\":\"BeforeTool\",\"tool_name\":\"list_directory\",\"tool_input\":{\"dir_path\":\"$TEST_DIR\"}}" \
    '.decision == "deny" and (.reason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Gemini read_many_files denies multi-target reads" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_many_files","tool_input":{"include":["README.md","docs/guide.md"]}}' \
    '.decision == "deny" and (.reason | contains("oap.multi_path_read_unsupported"))'

run_hook "Gemini read_many_files rejects conflicting path aliases" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_many_files","tool_input":{"paths":["/tmp/.ssh/id_rsa"],"file_path":"/tmp/readme.txt"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

run_hook "Gemini read_many_files rejects conflicting path containers" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_many_files","tool_input":{"paths":["/tmp/.ssh/id_rsa"]},"input":{"file_path":"/tmp/readme.txt"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

run_hook "Gemini read_many_files rejects conflicting include aliases" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_many_files","tool_input":{"path":"/tmp/allowed.txt","include":["/tmp/.env"]}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

run_hook "Gemini read_many_files rejects dir_path plus include targets" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_many_files","tool_input":{"dir_path":"/tmp","include":["/etc/passwd","/tmp/.env"]}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

run_hook "Gemini read_many_files denies glob-expanded single target" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_many_files","tool_input":{"include":["/home/user/**"]}}' \
    '.decision == "deny" and (.reason | contains("oap.glob_read_unsupported"))'

run_hook "Gemini read_many_files denies brace-expanded single target" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_many_files","tool_input":{"include":["/tmp/{README.md,.env}"]}}' \
    '.decision == "deny" and (.reason | contains("oap.glob_read_unsupported"))'

GEMINI_READ_MANY_SINGLE="$TEST_DIR/gemini-read-many-single.txt"
printf 'single read fixture\n' > "$GEMINI_READ_MANY_SINGLE"
run_hook "Gemini read_many_files allows include-only single target" \
    gemini "$GEMINI" \
    "{\"hook_event_name\":\"BeforeTool\",\"tool_name\":\"read_many_files\",\"tool_input\":{\"include\":[\"$GEMINI_READ_MANY_SINGLE\"]}}" \
    '.decision == "allow"'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_read_size_limit",
  "agent_id": "ap_read_size_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.read"}],
  "limits": {
    "data.file.read": {
      "allowed_paths": ["*"],
      "max_file_size_bytes": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
READ_TOO_LARGE_FILE="$TEST_DIR/read-too-large.txt"
printf 'xx' > "$READ_TOO_LARGE_FILE"
run_hook "Gemini file read enforces configured max file size" \
    gemini "$GEMINI" \
    "{\"hook_event_name\":\"BeforeTool\",\"tool_name\":\"read_file\",\"tool_input\":{\"file_path\":\"$READ_TOO_LARGE_FILE\"}}" \
    '.decision == "deny" and (.reason | contains("oap.file_too_large"))'

FAKE_STAT_DIR="$TEST_DIR/fake-stat"
mkdir -p "$FAKE_STAT_DIR"
cat > "$FAKE_STAT_DIR/stat" << 'EOF'
#!/bin/sh
if [ "$1" = "-f" ]; then
    printf '  File: "%s"\n' "${3:-}"
    exit 1
fi
if [ "$1" = "-c" ]; then
    wc -c < "${3:-}"
    exit $?
fi
command -p stat "$@"
EOF
chmod +x "$FAKE_STAT_DIR/stat"
ORIGINAL_PATH="$PATH"
PATH="$FAKE_STAT_DIR:$PATH" run_hook "Gemini file read ignores nonnumeric BSD stat fallback output" \
    gemini "$GEMINI" \
    "{\"hook_event_name\":\"BeforeTool\",\"tool_name\":\"read_file\",\"tool_input\":{\"file_path\":\"$READ_TOO_LARGE_FILE\"}}" \
    '.decision == "deny" and (.reason | contains("oap.file_too_large"))'
PATH="$ORIGINAL_PATH"

run_hook "Gemini file read rejects non-string file_path" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"read_file","tool_input":{"file_path":123}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

run_hook "Gemini file write rejects non-string file_path" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"write_file","tool_input":{"file_path":123,"content":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_read_bad_limits",
  "agent_id": "ap_read_bad_limits",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.read"}],
  "limits": {
    "data.file.read": {
      "allowed_paths": "*"
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini file read rejects malformed configured path lists" \
    gemini "$GEMINI" \
    "{\"hook_event_name\":\"BeforeTool\",\"tool_name\":\"read_file\",\"tool_input\":{\"file_path\":\"$READ_TOO_LARGE_FILE\"}}" \
    '.decision == "deny" and (.reason | contains("oap.invalid_limit"))'

cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"

run_hook "Gemini grep_search denies recursive directory search" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"grep_search","tool_input":{"pattern":"SECRET","dir_path":"/tmp/project"}}' \
    '.decision == "deny" and (.reason | contains("oap.recursive_search_unsupported"))'

run_hook "Gemini grep_search denies serialized recursive directory search" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"grep_search","tool_input":"{\"pattern\":\"SECRET\",\"dir_path\":\"/tmp/project\"}"}' \
    '.decision == "deny" and (.reason | contains("oap.recursive_search_unsupported"))'

run_hook "Gemini glob enumeration fails closed" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"glob","tool_input":{"path":"/tmp/not-yet-expanded","pattern":"**/.env*"}}' \
    '.decision == "deny" and (.reason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Codex glob with serialized tool_input fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"glob","tool_input":"{\"pattern\":\"**/*\",\"path\":\"/tmp/restricted\"}"}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.metadata_enumeration_unsupported"))'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Gemini MCP shorthand routes to MCP policy" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp_stripe_create_refund","tool_input":{"amount":1000}}' \
    '.decision == "allow"'
jq -e '.guardrail_tool == "mcp.tool" and (.context | has("timeout") | not) and (.context.parameters | type == "object")' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: MCP calls without timeout must omit the optional timeout field" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Gemini MCP no-timeout context remains schema-compatible"

run_hook "Gemini malformed serialized MCP args fail closed" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp__github__issues_list","tool_input":"{broken"}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Gemini mcp_context routes to MCP policy before built-in names" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"github__create_issue","mcp_context":{"server_name":"github","tool_name":"create_issue"},"tool_input":{"title":"test"}}' \
    '.decision == "allow"'
jq -e '.guardrail_tool == "mcp.tool" and .context.mcp_server == "github" and .context.mcp_tool == "create_issue"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Gemini mcp_context should force MCP policy mapping" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Gemini mcp_context maps to MCP policy"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Gemini MCP URL routing strips credentials before audit" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://user:password@github/tools?token=secret","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'
if grep -q 'password\|token=secret\|user:' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: MCP server context must not persist URL credentials" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.guardrail_tool == "mcp.tool" and .context.mcp_server == "https://github" and .context.mcp_tool == "issues.list"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: MCP URL routing should strip secrets while preserving only the URL origin" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ MCP URL routing strips credentials before audit"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Gemini MCP bare routing drops query and fragment data before audit" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"server_name":"mcp.example/path?token=supersecret#frag","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_mcp_server"))'
if grep -q 'supersecret\|#frag' "$TEST_DIR/aport/session-decisions.jsonl" 2> /dev/null; then
    echo "FAIL: bare MCP routing values must not persist query or fragment data" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
echo "  ✅ Bare MCP routing drops query and fragment data before audit"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_url_mcp_allowlist",
  "agent_id": "ap_url_mcp_allowlist",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["https://mcp.github.com"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP URL allowlist preserves host compatibility" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://user:password@mcp.github.com/tools?token=secret","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_scheme_mcp_allowlist",
  "agent_id": "ap_scheme_mcp_allowlist",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["mcp://github"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP scheme allowlist normalizes safely" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github/tools","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'
run_hook "Gemini MCP scheme allowlist preserves bare server compatibility" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp__github__issues.list","tool_input":{"id":"x"}}' \
    '.decision == "allow"'
run_hook "Gemini MCP scheme allowlist rejects different server" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://evil/tools","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_scheme_mcp_wildcard_allowlist",
  "agent_id": "ap_scheme_mcp_wildcard_allowlist",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["mcp://github*"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex MCP scheme wildcard preserves bare server compatibility" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"mcp__github-prod__issues.list","tool_input":{"id":"x"}}' \
    '. == {}'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_url_mcp_path_scope",
  "agent_id": "ap_url_mcp_path_scope",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["https://example.com:8443/trusted"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP URL allowlist preserves port and path boundaries" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"http://example.com:9999/untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP URL allowlist rejects ambiguous authority backslash" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://evil.com\\@example.com:8443/trusted/issues","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_mcp_server"))'
run_hook "Gemini MCP URL allowlist rejects dot-segment path traversal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/../untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP URL allowlist rejects encoded separator traversal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/..%2funtrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP URL allowlist rejects control-character path normalization" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/.\t./untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_mcp_server"))'
run_hook "Gemini MCP URL allowlist rejects backslash path traversal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/..\\untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_mcp_server"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_url_mcp_trailing_path_scope",
  "agent_id": "ap_url_mcp_trailing_path_scope",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["https://example.com:8443/trusted/"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP URL path-scoped allowlist fails closed after path redaction" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://example.com:8443/trusted/issues","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_mcp_scheme_path_scope",
  "agent_id": "ap_mcp_scheme_path_scope",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["mcp://github/trusted"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP scoped scheme allowlist fails closed after path redaction" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github/trusted/issues","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP scoped scheme allowlist rejects bare server fallback" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp__github__issues.list","tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP scoped scheme allowlist rejects other schemes" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://github/untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'
run_hook "Gemini MCP scoped scheme allowlist rejects dot-segment traversal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github/trusted/../untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_scoped_mcp_glob",
  "agent_id": "ap_scoped_mcp_glob",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["https://mcp.example/trusted/**"],
      "allowed_tools": ["issues.list"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP scoped glob rejects dot-segment traversal before glob match" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"https://mcp.example/trusted/../untrusted","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

write_restricted_local_hooks_passport() {
    cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_restricted_local_hooks",
  "agent_id": "ap_restricted_local_hooks",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [
    {"id": "mcp.tool.execute"},
    {"id": "web.fetch"},
    {"id": "data.file.read"},
    {"id": "data.file.write"}
  ],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"],
      "allowed_tools": ["issues.*"]
    },
    "web.fetch": {
      "allowed_domains": ["*"],
      "blocked_domains": ["evil.test"],
      "allowed_methods": ["GET", "POST"]
    },
    "data.file.read": {
      "allowed_paths": ["*"]
    },
    "data.file.write": {
      "allowed_paths": ["*"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
}

write_restricted_local_hooks_passport

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_flat_mcp_limit_absent_keys",
  "agent_id": "ap_flat_mcp_limit_absent_keys",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "allowed_servers": ["*"]
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP flat limits preserve absent optional keys" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp__github__issues_list","tool_input":{"id":"x"}}' \
    '.decision == "allow"'

write_restricted_local_hooks_passport

run_hook "Gemini MCP denies disallowed local server" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"evil__steal","mcp_context":{"server_name":"evil","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_server_not_allowed"))'

run_hook "Gemini MCP denies disallowed local tool" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"github__chat_postMessage","mcp_context":{"server_name":"github","tool_name":"chat.postMessage"},"tool_input":{"channel":"secrets"}}' \
    '.decision == "deny" and (.reason | contains("oap.mcp_tool_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_mcp_timeout_limit",
  "agent_id": "ap_mcp_timeout_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"],
      "allowed_tools": ["issues.*"],
      "max_timeout": 30
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP denies missing timeout when max is configured" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"github__issues.list","mcp_context":{"server_name":"github","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.missing_required_context"))'

run_hook "Gemini MCP denies malformed timeout when max is configured" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"github__issues.list","mcp_context":{"server_name":"github","tool_name":"issues.list"},"tool_input":{"timeout":"later","id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.missing_required_context"))'

run_hook "Gemini MCP denies timeout above local max" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"github__issues.list","mcp_context":{"server_name":"github","tool_name":"issues.list"},"tool_input":{"timeout":60,"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.timeout_exceeded"))'

run_hook "Gemini MCP allows timeout within local max" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"github__issues.list","mcp_context":{"server_name":"github","tool_name":"issues.list"},"tool_input":{"timeout":30,"id":"x"}}' \
    '.decision == "allow"'

run_hook "Codex MCP converts timeout_ms before max timeout enforcement" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"call_mcp_tool","tool_input":{"server":"github","tool":"issues.list","timeout_ms":1000}}' \
    '. == {}'

run_hook "Codex MCP converts timeoutMs before max timeout denial" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"call_mcp_tool","tool_input":{"server":"github","tool":"issues.list","timeoutMs":31000}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.timeout_exceeded"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_mcp_malformed_allowlists",
  "agent_id": "ap_mcp_malformed_allowlists",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": "github",
      "allowed_tools": "issues.list"
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP rejects malformed configured allowlists" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp__evil__delete_all","tool_input":{}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_limit"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_mcp_malformed_timeout",
  "agent_id": "ap_mcp_malformed_timeout",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"],
      "allowed_tools": ["issues.list"],
      "max_timeout": false
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex MCP rejects malformed configured timeout limit" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"call_mcp_tool","tool_input":{"server":"github","tool":"issues.list","timeout":1}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_limit"))'

write_restricted_local_hooks_passport

run_hook "Codex MCP denies server spoofed through tool input" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"mcp__evil__issues_list","tool_input":{"server":"github","tool":"issues.list","id":"x"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.mcp_server_not_allowed"))'

run_hook "Codex MCP strips functions namespace before server parsing" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"functions.mcp__github__issues.list","tool_input":{"id":"x"}}' \
    '. == {}'

run_hook "Codex generic MCP wrapper preserves routing server" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"CallMcpTool","tool_input":{"server":"github","mcp_tool":"issues.list","id":"x"}}' \
    '. == {}'

run_hook "Codex generic MCP wrapper rejects conflicting routing containers" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"CallMcpTool","tool_input":{"server":"evil","tool":"issues.list","id":"x"},"input":{"server":"github","tool":"issues.list"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_tool_arguments"))'

run_hook "Codex generic MCP wrapper permits URL parameters as tool data" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"CallMcpTool","mcp_context":{"server_name":"github","tool_name":"issues.list"},"tool_input":{"url":"https://docs.example.com/search?q=aport","id":"x"}}' \
    '. == {}'

run_hook "Goose MCP denies server spoofed through tool input" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"evil__issues_list","tool_input":{"server":"github","tool":"issues.list","id":"x"}}' \
    '.decision == "block" and (.reason | contains("oap.mcp_server_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_restricted_mcp_server_only",
  "agent_id": "ap_restricted_mcp_server_only",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini MCP does not infer ambiguous single-underscore server" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"mcp_github_internal_delete_issue","tool_input":{"id":"x"}}' \
    '.decision == "deny" and (.reason | contains("oap.missing_required_context"))'
write_restricted_local_hooks_passport

run_hook "Gemini MCP bare allowlist permits unscoped mcp URL identifier" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'
run_hook "Gemini MCP bare allowlist permits scoped mcp URL after path redaction" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"CallMcpTool","mcp_context":{"url":"mcp://github/tools","tool_name":"issues.list"},"tool_input":{"id":"x"}}' \
    '.decision == "allow"'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_restricted_mcp_server_only",
  "agent_id": "ap_restricted_mcp_server_only",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF

run_hook "Codex MCP resource read uses routing server instead of URI authority" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"ReadMcpResourceTool","tool_input":{"server":"evil","tool":"resources.read","uri":"mcp://github/repo/README.md"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.mcp_server_not_allowed"))'

run_hook "Codex read_mcp_resource reads server evidence from tool input" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"read_mcp_resource","tool_input":{"server":"github","uri":"repo://github/README.md"}}' \
    '. == {}'

run_hook "Codex list_mcp_resources reads server evidence from tool input" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"list_mcp_resources","tool_input":{"server":"github"}}' \
    '. == {}'

run_hook "Codex list_mcp_resource_templates reads server evidence from tool input" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"list_mcp_resource_templates","tool_input":{"server":"github"}}' \
    '. == {}'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_case_sensitive_mcp",
  "agent_id": "ap_case_sensitive_mcp",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["github"],
      "allowed_tools": ["chat.postMessage", "resources.read"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF

run_hook "Codex MCP preserves case-sensitive qualified tool names" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"mcp__github__chat.postMessage","tool_input":{"channel":"general"}}' \
    '. == {}'

run_hook "Codex MCP resource read defaults to resources.read" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"ReadMcpResourceTool","tool_input":{"server":"github","uri":"repo://github/README.md"}}' \
    '. == {}'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_case_sensitive_mcp_server",
  "agent_id": "ap_case_sensitive_mcp_server",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "mcp.tool.execute"}],
  "limits": {
    "mcp.tool.execute": {
      "allowed_servers": ["GitHub"],
      "allowed_tools": ["resources.read"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex MCP preserves case-sensitive bare server names" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"ReadMcpResourceTool","tool_input":{"server":"github","uri":"repo://github/README.md"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.mcp_server_not_allowed"))'

write_restricted_local_hooks_passport

run_hook "Gemini web_fetch denies blocked local domain" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://evil.test/collect","method":"POST"}}' \
    '.decision == "deny" and (.reason | contains("oap.domain_blocked"))'

run_hook "Gemini web_fetch denies userinfo-obfuscated blocked domain" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://user@evil.test/collect","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.domain_blocked"))'

run_hook "Gemini web_fetch rejects backslash-obfuscated URL authority" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://evil.test\\@example.com/collect","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_url"))'

run_hook "Gemini web_fetch rejects percent-encoded URL authority" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://127%2e0%2e0%2e1/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_url"))'

run_hook "Gemini web_fetch rejects Unicode-normalized loopback hostname" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://１２７.０.０.１/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_url"))'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Gemini web_fetch rejects malformed URL without recording secrets" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":" https://user:password@example.com/path?token=secret#private","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_url"))'
if [[ -f "$TEST_DIR/aport/session-decisions.jsonl" ]] && grep -Eq 'user:|password|token=secret|#private' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: malformed URL context must not persist credentials, query tokens, or fragments" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
echo "  ✅ Malformed web URL does not persist secrets"

run_hook "Gemini web_fetch denies private metadata IP" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://169.254.169.254/latest/meta-data","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies multicast IPv4 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://224.0.0.1/","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies limited-broadcast IPv4 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://255.255.255.255/","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies documentation IPv4 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://192.0.2.1/","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies shortened loopback IPv4 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://127.1/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies integer loopback IPv4 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://2130706433/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies IPv4-mapped private IPv6 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://[::ffff:127.0.0.1]/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies hex IPv4-mapped private IPv6 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://[::ffff:7f00:1]/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies compressed IPv6 loopback literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://[0:0:0:0:0:0::1]/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies link-local IPv6 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://[fe90::1]/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies multicast IPv6 literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://[ff02::1]/admin","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

run_hook "Gemini web_fetch denies private IPv6 domain literal" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"domain":"fd00::1","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.private_network_destination"))'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Gemini domain-only web_fetch normalizes host before recording" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"domain":"https://user:password@example.com/path?token=secret#frag","method":"GET"}}' \
    '.decision == "allow"'
if grep -Eq 'user:|password|token=secret|#frag' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: domain-only web context must not persist credentials, query tokens, or fragments" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.guardrail_tool == "websearch" and .decision.policy_id == "web.fetch.v1" and .context.url == "" and .context.domain == "example.com"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: domain-only web context should record only normalized host" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Domain-only web fetch records normalized host"

run_hook "Gemini web_fetch rejects domain spoofing when URL is present" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://evil.test/collect","domain":"example.com","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

run_hook "Gemini web_fetch rejects conflicting URL containers" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"http://169.254.169.254/latest/meta-data"},"input":{"url":"https://example.com/"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

run_hook "Gemini web_fetch rejects conflicting method containers" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/resource","method":"DELETE"},"input":{"url":"https://example.com/resource","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_tool_arguments"))'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Gemini web_fetch strips credential-bearing URL paths before recording" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://hooks.slack.com/services/T000/B000/SECRET?signature=hidden","method":"POST"}}' \
    '.decision == "allow"'
if grep -Eq 'SECRET|signature=hidden|/services/' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: web context must not persist credential-bearing URL paths, query tokens, or fragments" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.guardrail_tool == "websearch" and .decision.policy_id == "web.fetch.v1" and .context.url == "https://hooks.slack.com" and .context.domain == "hooks.slack.com"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: web context should record only URL origin and normalized host" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Web fetch strips credential-bearing paths before audit"

run_hook "Gemini web_fetch denies disallowed local method" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/resource","method":"DELETE"}}' \
    '.decision == "deny" and (.reason | contains("oap.method_not_allowed"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_flat_web_limit_absent_keys",
  "agent_id": "ap_flat_web_limit_absent_keys",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "web.fetch"}],
  "limits": {
    "allowed_domains": ["*"]
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini web_fetch flat limits preserve absent optional keys" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/resource","method":"GET"}}' \
    '.decision == "allow"'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_web_malformed_limits",
  "agent_id": "ap_web_malformed_limits",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "web.fetch"}],
  "limits": {
    "web.fetch": {
      "allowed_domains": "example.com",
      "allowed_methods": "GET"
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Gemini web_fetch rejects malformed configured allowlists" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://evil.test/data","method":"DELETE"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_limit"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_web_rate_limit",
  "agent_id": "ap_web_rate_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "web.fetch"}],
  "limits": {
    "web.fetch": {
      "allowed_domains": ["example.com"],
      "allowed_methods": ["GET"],
      "max_requests_per_min": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/web-rate-state.json"
rm -f "$TEST_DIR/aport/web-rate-state.json.initialized"
rm -rf "$TEST_DIR/aport/web-rate-state.json.lock" "$TEST_DIR/aport/web-rate-state.json.lock.recover"
run_hook "Gemini web_fetch first request respects local rate limit" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/first","method":"GET"}}' \
    '.decision == "allow"'
run_hook "Gemini web_fetch second request exceeds local rate limit" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/second","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.rate_limit_exceeded"))'
rm -f "$TEST_DIR/aport/web-rate-state.json"
rm -rf "$TEST_DIR/aport/web-rate-state.json.lock" "$TEST_DIR/aport/web-rate-state.json.lock.recover"
run_hook "Gemini web_fetch deleted local rate state fails closed after initialization" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/deleted-state","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.rate_state_unavailable"))'
rm -f "$TEST_DIR/aport/web-rate-state.json.initialized"

rm -f "$TEST_DIR/aport/web-rate-state.json"
rm -rf "$TEST_DIR/aport/web-rate-state.json.lock" "$TEST_DIR/aport/web-rate-state.json.lock.recover"
RATE_MARKER_TARGET="$TEST_DIR/rate-marker-target.txt"
printf 'do-not-truncate\n' > "$RATE_MARKER_TARGET"
ln -s "$RATE_MARKER_TARGET" "$TEST_DIR/aport/web-rate-state.json.initialized"
run_hook "Gemini web_fetch symlinked rate marker fails closed" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/symlink-marker","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.rate_state_unavailable"))'
if [ "$(cat "$RATE_MARKER_TARGET")" != "do-not-truncate" ]; then
    echo "FAIL: rate marker symlink target must not be truncated" >&2
    exit 1
fi
rm -f "$TEST_DIR/aport/web-rate-state.json.initialized" "$RATE_MARKER_TARGET"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
printf 'not-json\n' > "$TEST_DIR/aport/web-rate-state.json"
run_hook "Gemini web_fetch corrupt local rate state stays blocking in warn mode" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/corrupt-state","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.rate_state_unavailable"))'
printf '{}\n' > "$TEST_DIR/aport/web-rate-state.json"
run_hook "Gemini web_fetch missing rate state schema stays blocking in warn mode" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/missing-state-schema","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.rate_state_unavailable"))'
printf '{"requests":["bad"]}\n' > "$TEST_DIR/aport/web-rate-state.json"
run_hook "Gemini web_fetch malformed rate entries stay blocking in warn mode" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/malformed-rate-entry","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.rate_state_unavailable"))'
rm -f "$TEST_DIR/aport/web-rate-state.json" "$TEST_DIR/proof"
rm -rf "$TEST_DIR/aport/web-rate-state.json.lock" "$TEST_DIR/aport/web-rate-state.json.lock.recover"
mkdir "$TEST_DIR/aport/web-rate-state.json.lock"
printf '999999 x[$(touch %s/proof)]\n' "$TEST_DIR" > "$TEST_DIR/aport/web-rate-state.json.lock/owner"
run_hook "Gemini web_fetch malformed rate lock owner fails closed without execution" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/malformed-lock","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.rate_state_unavailable"))'
if [[ -f "$TEST_DIR/proof" ]]; then
    echo "FAIL: malformed rate lock timestamp must not execute shell substitutions" >&2
    exit 1
fi
rm -rf "$TEST_DIR/aport/web-rate-state.json.lock" "$TEST_DIR/aport/web-rate-state.json.lock.recover"
mkdir "$TEST_DIR/aport/web-rate-state.json.lock" "$TEST_DIR/aport/web-rate-state.json.lock.recover"
printf '99999999 %s\n' "$(date +%s)" > "$TEST_DIR/aport/web-rate-state.json.lock/owner"
printf '%s %s\n' "$$" "$(date +%s)" > "$TEST_DIR/aport/web-rate-state.json.lock.recover/owner"
APORT_SESSION_LOCK_RETRIES=0 APORT_SESSION_LOCK_RETRY_DELAY=0 run_hook "Gemini web_fetch live recovery lock fails closed without hanging" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/live-recovery-lock","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.rate_state_unavailable"))'
rm -rf "$TEST_DIR/aport/web-rate-state.json.lock" "$TEST_DIR/aport/web-rate-state.json.lock.recover"
rm -rf "$TEST_DIR/aport/web-rate-state.json"
mkdir "$TEST_DIR/aport/web-rate-state.json"
run_hook "Gemini web_fetch directory rate state path fails closed" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/directory-state","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.rate_state_unavailable"))'
if find "$TEST_DIR/aport/web-rate-state.json" -mindepth 1 -print -quit | grep -q .; then
    echo "FAIL: directory rate state target must not receive moved temporary state files" >&2
    find "$TEST_DIR/aport/web-rate-state.json" -mindepth 1 -maxdepth 1 >&2
    exit 1
fi
rm -rf "$TEST_DIR/aport/web-rate-state.json"
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_web_invalid_rate_limit",
  "agent_id": "ap_web_invalid_rate_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "web.fetch"}],
  "limits": {
    "web.fetch": {
      "allowed_domains": ["example.com"],
      "allowed_methods": ["GET"],
      "max_requests_per_min": 0
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/web-rate-state.json"
rm -rf "$TEST_DIR/aport/web-rate-state.json.lock" "$TEST_DIR/aport/web-rate-state.json.lock.recover"
run_hook "Gemini web_fetch rejects invalid configured local rate limit" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_name":"web_fetch","tool_input":{"url":"https://example.com/invalid-limit","method":"GET"}}' \
    '.decision == "deny" and (.reason | contains("oap.invalid_limit"))'
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_web_rate_limit",
  "agent_id": "ap_web_rate_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "web.fetch"}],
  "limits": {
    "web.fetch": {
      "allowed_domains": ["example.com"],
      "allowed_methods": ["GET"],
      "max_requests_per_min": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex web_fetch missing context stays blocking in warn mode" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"WebFetch","tool_input":{}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
rm -f "$TEST_DIR/aport/web-rate-state.json"
rm -rf "$TEST_DIR/aport/web-rate-state.json.lock" "$TEST_DIR/aport/web-rate-state.json.lock.recover"

cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"

run_hook "Gemini missing tool_name fails closed" \
    gemini "$GEMINI" \
    '{"hook_event_name":"BeforeTool","tool_input":{"command":"ls -la"}}' \
    '.decision == "deny" and (.reason | contains("oap.missing_tool_name"))'

run_hook "Goose shell deny uses block decision" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__shell","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.decision == "block" and (.reason | contains("APort denied"))'

run_hook "Goose missing tool_name fails closed" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_input":{"command":"ls -la"}}' \
    '.decision == "block" and (.reason | contains("oap.missing_tool_name"))'

run_hook "Goose clean allow stays silent" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__shell","tool_input":{"command":"ls -la"}}' \
    'empty'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
GOOSE_READ_IMAGE="$TEST_DIR/goose-diagram.png"
printf 'not really png\n' > "$GOOSE_READ_IMAGE"
run_hook "Goose read_image local source maps to file read" \
    goose "$GOOSE" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"developer__read_image\",\"tool_input\":{\"source\":\"$GOOSE_READ_IMAGE\"}}" \
    'empty'
jq -e --arg file "$GOOSE_READ_IMAGE" '.guardrail_tool == "read" and .decision.policy_id == "data.file.read.v1" and .context.file_path == $file' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Goose local read_image should map source to data.file.read context" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Goose local read_image maps to file read"

run_hook "Goose read_image rejects conflicting source and path" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__read_image","tool_input":{"source":"/tmp/.env","path":"/tmp/public.png"}}' \
    '.decision == "block" and (.reason | contains("oap.invalid_tool_arguments"))'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Goose read_image URL source maps to web access" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__read_image","tool_input":{"source":"https://example.com/diagram.png"}}' \
    'empty'
jq -e '.guardrail_tool == "websearch" and .decision.policy_id == "web.fetch.v1" and .context.url == "https://example.com" and .context.domain == "example.com"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Goose URL read_image should map source to web context" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Goose URL read_image maps to web access"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Goose web fetch strips URL credentials from recorded context" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__fetch","tool_input":{"url":"https://user:password@example.com/file?token=secret#frag","method":"GET"}}' \
    'empty'
if grep -Eq 'password|token=secret|#frag' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: web context must not persist URL credentials, query tokens, or fragments" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.guardrail_tool == "websearch" and .decision.policy_id == "web.fetch.v1" and .context.url == "https://example.com" and .context.domain == "example.com"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Goose web fetch should record sanitized URL context" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Goose web fetch strips URL credentials"

run_hook "Goose text_editor view routes through read policy" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__text_editor","tool_input":{"command":"view","path":"/tmp/.ssh/id_rsa"}}' \
    '.decision == "block" and (.reason | contains("oap.blocked_pattern"))'

run_hook "Goose text_editor view rejects directory targets" \
    goose "$GOOSE" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"developer__text_editor\",\"tool_input\":{\"command\":\"view\",\"path\":\"$TEST_DIR\"}}" \
    '.decision == "block" and (.reason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Goose tree with broad root fails closed as metadata enumeration" \
    goose "$GOOSE" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"developer__tree\",\"tool_input\":{\"path\":\"$TEST_DIR\"}}" \
    '.decision == "block" and (.reason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Goose text_editor missing command fails closed" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__text_editor","tool_input":{"path":"/tmp/file.txt"}}' \
    '.decision == "block" and (.reason | contains("oap.missing_editor_command"))'

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
run_hook "Goose warn mode allows with reason" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__shell","tool_input":{"command":"rm -rf /tmp/x"}}' \
    '.decision == "allow"
      and (.reason | contains("APort Warning"))
      and (.reason | contains("Evidence:"))
      and (.reason | contains("mode goose --enforcement=enforce"))
      and ((.reason | contains("Review or update the hosted passport")) | not)'

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_goose_write_size_limit",
  "agent_id": "ap_goose_write_size_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["*"],
      "max_file_size_bytes": 1000
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
GOOSE_REPLACE_FILE="$TEST_DIR/goose-replace-size.txt"
GOOSE_INSERT_FILE="$TEST_DIR/goose-insert-size.txt"
awk 'BEGIN { for (i = 0; i < 991; i++) printf "a" }' > "$GOOSE_REPLACE_FILE"
awk 'BEGIN { for (i = 0; i < 995; i++) printf "a" }' > "$GOOSE_INSERT_FILE"
GOOSE_LARGE_TEXT="$(awk 'BEGIN { for (i = 0; i < 1001; i++) printf "b" }')"
GOOSE_WRITE_INPUT="$(jq -n -c --arg text "$GOOSE_LARGE_TEXT" '{hook_event_name:"PreToolUse",tool_name:"developer__text_editor",tool_input:{command:"write",path:"/tmp/goose-large.txt",file_text:$text}}')"
run_hook "Goose text_editor write uses file_text size" \
    goose "$GOOSE" \
    "$GOOSE_WRITE_INPUT" \
    '.decision == "block" and (.reason | contains("oap.file_too_large"))'

run_hook "Goose text_editor str_replace uses new_str and old_str size" \
    goose "$GOOSE" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"developer__text_editor\",\"tool_input\":{\"command\":\"str_replace\",\"path\":\"$GOOSE_REPLACE_FILE\",\"old_str\":\"a\",\"new_str\":\"bbbbbbbbbbbbbbbbbbbb\"}}" \
    '.decision == "block" and (.reason | contains("oap.file_too_large"))'

run_hook "Goose text_editor insert computes resulting file size" \
    goose "$GOOSE" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"developer__text_editor\",\"tool_input\":{\"command\":\"insert\",\"path\":\"$GOOSE_INSERT_FILE\",\"new_str\":\"bbbbbbbbbb\"}}" \
    '.decision == "block" and (.reason | contains("oap.file_too_large"))'

run_hook "Goose text_editor undo_edit requires resulting size when limited" \
    goose "$GOOSE" \
    '{"hook_event_name":"PreToolUse","tool_name":"developer__text_editor","tool_input":{"command":"undo_edit","path":"/tmp/test.txt"}}' \
    '.decision == "block" and (.reason | contains("oap.missing_required_context"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_root_path_block",
  "agent_id": "ap_root_path_block",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["*"],
      "blocked_paths": ["/"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex write respects root blocked path" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"write","tool_input":{"file_path":"/tmp/review.txt","content":"x"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.path_blocked"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_home_path_patterns",
  "agent_id": "ap_home_path_patterns",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["~/aport-allowed"],
      "blocked_paths": ["~/aport-blocked"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex write respects home-relative allowed path" \
    codex "$CODEX" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"write\",\"tool_input\":{\"file_path\":\"$HOME/aport-allowed/file.txt\",\"content\":\"x\"}}" \
    '. == {}'
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_home_blocked_path_patterns",
  "agent_id": "ap_home_blocked_path_patterns",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["*"],
      "blocked_paths": ["~/aport-blocked"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex write respects home-relative blocked path" \
    codex "$CODEX" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"write\",\"tool_input\":{\"file_path\":\"$HOME/aport-blocked/file.txt\",\"content\":\"x\"}}" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.path_blocked"))'
newline_blocked_path_payload="$(jq -nc --arg file_path "$HOME/aport-blocked/file
with-newline.txt" '{hook_event_name:"PreToolUse",tool_name:"write",tool_input:{file_path:$file_path,content:"x"}}')"
run_hook "Codex write rejects control-char path before wildcard allow" \
    codex "$CODEX" \
    "$newline_blocked_path_payload" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_file_path"))'

mkdir -p "$TEST_DIR/allowed"
cat > "$TEST_DIR/aport/passport.json" << EOF
{
  "passport_id": "ap_control_char_path_patterns",
  "agent_id": "ap_control_char_path_patterns",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["$TEST_DIR/allowed/**"]
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
newline_path_payload="$(jq -nc --arg file_path "$TEST_DIR/unapproved
$TEST_DIR/allowed/note.txt" '{hook_event_name:"PreToolUse",tool_name:"write",tool_input:{file_path:$file_path,content:"x"}}')"
run_hook "Codex write rejects newline path glob bypass" \
    codex "$CODEX" \
    "$newline_path_payload" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_file_path"))'

cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex file write strips raw content from recorded context" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: /tmp/aport-test.txt\n+secret_token=should_not_leave\n*** End Patch","content":"secret_token=should_not_leave"}}' \
    '. == {}'

if grep -q 'should_not_leave' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: session decision context must not contain raw file contents" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.context.file_path == "/tmp/aport-test.txt" and (.context.content_length | type == "number")' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: file-write context should include path and content length" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ File-write context is minimized"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_write_size_limit",
  "agent_id": "ap_write_size_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["*"],
      "max_file_size_mb": 0.000001
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex file write enforces local max size" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/aport-large.txt","content":"abcdefghi"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.file_too_large"))'

run_hook "Codex new file write under max size does not require existing file" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/aport-small.txt","content":"a"}}' \
    '. == {}'

printf '1234567890' > "$TEST_DIR/aport-existing-edit.txt"
run_hook "Codex edit enforces resulting file size" \
    codex "$CODEX" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"edit\",\"tool_input\":{\"file_path\":\"$TEST_DIR/aport-existing-edit.txt\",\"old_string\":\"0\",\"new_string\":\"abcdefghij\"}}" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.file_too_large"))'

run_hook "Codex file write enforces UTF-8 byte size" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/aport-emoji.txt","content":"😀"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.file_too_large"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_write_invalid_size_limit",
  "agent_id": "ap_write_invalid_size_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["*"],
      "max_file_size_mb": "invalid"
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex file write rejects invalid configured max size" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/aport-invalid-size.txt","content":"abc"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_limit"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_write_size_limit",
  "agent_id": "ap_write_size_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["*"],
      "max_file_size_mb": 0.000001
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
run_hook "Codex apply_patch enforces patch payload size" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: /tmp/aport-large-patch.txt\n+abcdefghi\n*** End Patch"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.file_too_large"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_patch_update_size_limit",
  "agent_id": "ap_patch_update_size_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "data.file.write"}],
  "limits": {
    "data.file.write": {
      "allowed_paths": ["*"],
      "max_file_size_bytes": 1000
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
PATCH_NEAR_LIMIT_FILE="$TEST_DIR/aport-near-limit-patch.txt"
awk 'BEGIN { for (i = 0; i < 991; i++) printf "a" }' > "$PATCH_NEAR_LIMIT_FILE"
PATCH_UPDATE_INPUT="$(
    jq -n -c --arg patch "*** Begin Patch
*** Update File: $PATCH_NEAR_LIMIT_FILE
@@
+bbbbbbbbbbbbbbbbbbbb
*** End Patch" \
        '{hook_event_name:"PreToolUse",tool_name:"apply_patch",tool_input:{command:$patch}}'
)"
run_hook "Codex apply_patch update enforces resulting file size" \
    codex "$CODEX" \
    "$PATCH_UPDATE_INPUT" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.file_too_large"))'

PATCH_TOLERANT_FILE="$TEST_DIR/aport-tolerant-patch.txt"
printf 'abc\n' > "$PATCH_TOLERANT_FILE"
PATCH_TOLERANT_DELETE_LINE="-abc$(printf '%100s' '')"
PATCH_TOLERANT_ADD_LINE="+$(awk 'BEGIN { for (i = 0; i < 1000; i++) printf "x" }')"
PATCH_TOLERANT_INPUT="$(
    jq -n -c \
        --arg path "$PATCH_TOLERANT_FILE" \
        --arg delete_line "$PATCH_TOLERANT_DELETE_LINE" \
        --arg add_line "$PATCH_TOLERANT_ADD_LINE" \
        '{hook_event_name:"PreToolUse",tool_name:"apply_patch",tool_input:{patch:("*** Begin Patch\n*** Update File: " + $path + "\n@@\n" + $delete_line + "\n" + $add_line + "\n*** End Patch")}}'
)"
run_hook "Codex apply_patch update with deletions uses conservative resulting size" \
    codex "$CODEX" \
    "$PATCH_TOLERANT_INPUT" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.file_too_large"))'

cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"

run_hook "Codex multi-file apply_patch fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: /tmp/allowed.txt\n+ok\n*** Add File: /tmp/forbidden.txt\n+secret\n*** End Patch"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.multi_path_write_unsupported"))'

run_hook "Codex Grep routes through file-read policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Grep","tool_input":{"pattern":"SECRET","path":"/tmp/.ssh"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.blocked_pattern"))'

mkdir -p "$TEST_DIR/search-root"
run_hook "Codex Grep rejects directory-scoped search" \
    codex "$CODEX" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"SECRET\",\"path\":\"$TEST_DIR/search-root\"}}" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.recursive_search_unsupported"))'

run_hook "Codex Glob with concrete sensitive path fails closed as metadata enumeration" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Glob","tool_input":{"pattern":"*","path":"/home/user/.ssh"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Codex Glob with broad allowed root still fails closed as metadata enumeration" \
    codex "$CODEX" \
    "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Glob\",\"tool_input\":{\"pattern\":\"**/.env\",\"path\":\"$TEST_DIR\"}}" \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Codex Glob with empty path still denies nonempty pattern enumeration" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Glob","tool_input":{"path":"","pattern":"**/.env"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.metadata_enumeration_unsupported"))'

run_hook "Codex LS without target fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"LS","tool_input":{}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_file_path"))'

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex WebSearch without destination fails closed through web policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"WebSearch","tool_input":{"query":"APort guardrails"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'
if [[ -f "$TEST_DIR/aport/session-decisions.jsonl" ]] && grep -q 'APort guardrails' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: Codex WebSearch must not persist raw search queries when destination context is missing" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
echo "  ✅ Codex WebSearch without destination fails closed before verifier"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_AGENT_ID=ap_test_web_search
EOF
run_hook "Codex web.run search-only payload fails closed before hosted API validation" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"web.run","tool_input":{"search_query":[{"q":"secret search query should not persist"}]}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context")) and ((.hookSpecificOutput.permissionDecisionReason | contains("secret search")) | not)'
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
echo "  ✅ Codex hosted web.run search-only payload fails before API call"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex spawn_agent maps to session policy" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","tool_call_id":"map-spawn-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex send_message maps to session update" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.send_message","tool_input":{"id":"child-1","message":"continue"}}' \
    '. == {}'
run_hook "Codex followup_task maps to session update" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.followup_task","tool_input":{"id":"child-1","prompt":"continue"}}' \
    '. == {}'
run_hook "Codex wait_agent maps to session status" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.wait_agent","tool_input":{"id":"child-1"}}' \
    '. == {}'
run_hook "Codex interrupt_agent maps to session update" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.interrupt_agent","tool_input":{"id":"child-1"}}' \
    '. == {}'
jq -e '.guardrail_tool == "session.create" and .decision.policy_id == "agent.session.create.v1"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: Codex spawn_agent should map to agent.session.create" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Codex collaboration tools map to session policy"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_invalid_session_limit",
  "agent_id": "ap_invalid_session_limit",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 0
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session rejects invalid configured local concurrency limit" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"id":"invalid-limit-child","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.invalid_limit"))'

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_sessions",
  "agent_id": "ap_limited_sessions",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 2
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock"
mkdir "$TEST_DIR/aport/session-state.json.lock"
printf '999999 1\n' > "$TEST_DIR/aport/session-state.json.lock/owner"
run_hook "Codex session recovers stale local lock" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"stale-lock-call","tool_input":{"id":"stale-lock-child","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock"
echo "  ✅ Codex session stale lock recovery works"
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
mkdir "$TEST_DIR/aport/session-state.json.lock"
printf '%s 1\n' "$$" > "$TEST_DIR/aport/session-state.json.lock/owner"
APORT_SESSION_LOCK_STALE_SECONDS=0 run_hook "Codex session recovers stale local lock when PID was reused" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"stale-reused-pid-lock-call","tool_input":{"id":"stale-reused-pid-child","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
echo "  ✅ Codex session stale lock recovery handles PID reuse"
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
mkdir "$TEST_DIR/aport/session-state.json.lock"
APORT_SESSION_LOCK_OWNERLESS_STALE_SECONDS=0 run_hook "Codex session recovers ownerless local lock" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"ownerless-lock-call","tool_input":{"id":"ownerless-lock-child","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
echo "  ✅ Codex session ownerless lock recovery works"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
mkdir "$TEST_DIR/aport/session-state.json.lock"
printf '%s %s\n' "$$" "$(date +%s)" > "$TEST_DIR/aport/session-state.json.lock/owner"
export APORT_SESSION_LOCK_RETRIES=0
export APORT_SESSION_LOCK_RETRY_DELAY=0
run_hook "Codex session fails closed on live local lock" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"live-lock-call","tool_input":{"id":"live-lock-child","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
unset APORT_SESSION_LOCK_RETRIES APORT_SESSION_LOCK_RETRY_DELAY
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
echo "  ✅ Codex session live lock contention fails closed"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"
mkdir "$TEST_DIR/aport/session-state.json.lock"
printf '%s %s\n' "$$" "$(date +%s)" > "$TEST_DIR/aport/session-state.json.lock/owner"
export APORT_SESSION_LOCK_RETRIES=0
export APORT_SESSION_LOCK_RETRY_DELAY=0
run_hook "Codex session state failure remains blocking in warn mode" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"warn-lock-call","tool_input":{"id":"warn-lock-child","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
unset APORT_SESSION_LOCK_RETRIES APORT_SESSION_LOCK_RETRY_DELAY
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"

cat > "$TEST_DIR/aport/session-state.json" << 'EOF'
{"leases":[{"session_id":"locked-close-child","session_call_id":"locked-close-call","expires_at_epoch":4102444800,"synthetic":false}]}
EOF
mkdir "$TEST_DIR/aport/session-state.json.lock"
printf '%s %s\n' "$$" "$(date +%s)" > "$TEST_DIR/aport/session-state.json.lock/owner"
export APORT_SESSION_LOCK_RETRIES=0
export APORT_SESSION_LOCK_RETRY_DELAY=0
run_hook "Codex post-tool close fails closed when session state lock is live" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_call_id":"locked-close-call","tool_input":{"id":"locked-close-child"},"tool_response":{"success":true}}' \
    '.hookSpecificOutput.hookEventName == "PostToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
unset APORT_SESSION_LOCK_RETRIES APORT_SESSION_LOCK_RETRY_DELAY
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json.lock" "$TEST_DIR/aport/session-state.json.lock.recover"

printf 'not-json\n' > "$TEST_DIR/aport/session-state.json"
run_hook "Codex close fails closed when session state is corrupt" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_call_id":"corrupt-close-call","tool_input":{"id":"corrupt-child"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
if [[ "$(cat "$TEST_DIR/aport/session-state.json")" != "not-json" ]]; then
    echo "FAIL: corrupt session state must not be replaced with an empty lease list" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
fi
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"

printf '{}\n' > "$TEST_DIR/aport/session-state.json"
run_hook "Codex missing session state schema fails closed before pruning" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_call_id":"missing-schema-call","tool_input":{"prompt":"review"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
if [[ "$(cat "$TEST_DIR/aport/session-state.json")" != "{}" ]]; then
    echo "FAIL: missing session state schema should be preserved for operator repair" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
fi
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"

printf '{"leases":[{"session_id":"still-running"}]}\n' > "$TEST_DIR/aport/session-state.json"
run_hook "Codex malformed session lease fails closed before pruning" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_call_id":"malformed-lease-call","tool_input":{"prompt":"review"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
if [[ "$(cat "$TEST_DIR/aport/session-state.json")" != '{"leases":[{"session_id":"still-running"}]}' ]]; then
    echo "FAIL: malformed session state should be preserved for operator repair" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
fi
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
rm -rf "$TEST_DIR/aport/session-state.json"
mkdir "$TEST_DIR/aport/session-state.json"
run_hook "Codex directory session state path fails closed before lease write" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_call_id":"directory-state-call","tool_input":{"prompt":"review"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.session_state_unavailable"))'
if find "$TEST_DIR/aport/session-state.json" -mindepth 1 -print -quit | grep -q .; then
    echo "FAIL: directory session state target must not receive moved temporary state files" >&2
    find "$TEST_DIR/aport/session-state.json" -mindepth 1 -maxdepth 1 >&2
    exit 1
fi
rm -rf "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
echo "  ✅ Codex session state failures remain blocking in warn mode"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_single_session",
  "agent_id": "ap_single_session",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 1,
      "local_lease_ttl_seconds": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
jq '.limits["agent.session.create"].local_lease_ttl_seconds = 60' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
run_hook "Codex ordinary spawn fills single session capacity before namespaced spawn" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"spawn_agent","session_id":"parent-session","tool_call_id":"multi-agent-baseline-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex namespaced spawn_agent respects max_concurrent" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"multi_agent_v1.spawn_agent","session_id":"parent-session","tool_call_id":"multi-agent-namespaced-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
jq '.limits["agent.session.create"].local_lease_ttl_seconds = 1' "$TEST_DIR/aport/passport.json" > "$TEST_DIR/aport/passport.updated.json"
mv "$TEST_DIR/aport/passport.updated.json" "$TEST_DIR/aport/passport.json"
echo "  ✅ Codex namespaced multi-agent spawn consumes session capacity"

run_hook "Codex spawn_agent without per-call id fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'
if [[ -f "$TEST_DIR/aport/session-state.json" ]]; then
    echo "FAIL: missing per-call session id must not create local session state" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
fi
echo "  ✅ Codex spawn_agent without per-call id fails closed"

run_hook "Codex provisional session lease reserves capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"no-id-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex failed spawn output without session id releases provisional lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"no-id-call","tool_response":{"success":false}}' \
    '. == {}'
run_hook "Codex session lease after no-id spawn output is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-no-id-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex failed no-id spawn output releases provisional lease"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex provisional session lease reserves capacity before ambiguous success" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"ambiguous-success-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex successful spawn without session id fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"ambiguous-success-call","tool_response":{"success":true}}' \
    '.hookSpecificOutput.hookEventName == "PostToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'
run_hook "Codex ambiguous successful spawn preserves reserved capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-ambiguous-success-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
sleep 2
run_hook "Codex ambiguous successful spawn remains reserved after lease ttl" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-ambiguous-success-ttl-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
echo "  ✅ Codex successful no-id spawn output preserves provisional lease"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex provisional session lease reserves capacity before unknown output" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"unknown-output-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex unknown spawn output without session id fails closed" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"unknown-output-call","tool_response":{}}' \
    '.hookSpecificOutput.hookEventName == "PostToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'
run_hook "Codex unknown spawn output preserves reserved capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-unknown-output-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
echo "  ✅ Codex unknown no-id spawn output preserves provisional lease"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex interrupt lifecycle starts tracked session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"spawn_agent","session_id":"parent-session","tool_call_id":"interrupt-live-create","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex interrupt lifecycle reconciles tracked session" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"spawn_agent","session_id":"parent-session","tool_call_id":"interrupt-live-create","tool_response":{"success":true,"agent_id":"interrupt-live-child"}}' \
    '. == {}'
run_hook "Codex interrupt_agent does not close tracked session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"interrupt_agent","session_id":"parent-session","tool_call_id":"interrupt-live-interrupt","tool_input":{"id":"interrupt-live-child"}}' \
    '. == {}'
run_hook "Codex post-tool interrupt keeps tracked session open" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"interrupt_agent","session_id":"parent-session","tool_call_id":"interrupt-live-interrupt","tool_input":{"id":"interrupt-live-child"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex send_input can still target interrupted session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"send_input","session_id":"parent-session","tool_call_id":"interrupt-live-send","tool_input":{"id":"interrupt-live-child","message":"continue"}}' \
    '. == {}'
run_hook "Codex interrupted session still counts against concurrency" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"spawn_agent","session_id":"parent-session","tool_call_id":"after-interrupt-live","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
echo "  ✅ Codex interrupt keeps live sessions counted"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_sessions",
  "agent_id": "ap_limited_sessions",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 2
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"

"$REPO_ROOT/bin/aport-guardrail-bash.sh" "session.create" '{"session_operation":"other","description_length":12}' > /dev/null
jq -e '.allow == true and .policy_id == "agent.session.create.v1"' "$TEST_DIR/aport/decision.json" > /dev/null || {
    echo "FAIL: non-spawning session bookkeeping should still authorize under session policy" >&2
    cat "$TEST_DIR/aport/decision.json" >&2
    exit 1
}
if [[ -f "$TEST_DIR/aport/session-state.json" ]] && ! jq -e '.leases | length == 0' "$TEST_DIR/aport/session-state.json" > /dev/null; then
    echo "FAIL: non-spawning session bookkeeping should not consume a concurrency lease" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
fi
echo "  ✅ Session bookkeeping does not consume session capacity"

"$REPO_ROOT/bin/aport-guardrail-bash.sh" "session.create" '{"session_tracking":"host_active_count","session_operation":"create","description_length":12,"active_session_count":0}' > /dev/null
if [[ -f "$TEST_DIR/aport/session-state.json" ]] && ! jq -e '.leases | length == 0' "$TEST_DIR/aport/session-state.json" > /dev/null; then
    echo "FAIL: host-active-count session tracking should not create persistent leases" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
fi
echo "  ✅ Host-count session tracking avoids stale local leases"

run_hook "Codex session first lease is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"session-first-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex session second lease is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"session-second-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex session third lease respects max_concurrent" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"session-third-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex unmatched close does not release synthetic session lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"not-running"}}' \
    '. == {}'
run_hook "Codex session remains capped after unmatched close" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"session-after-unmatched-close-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
jq -e '.leases | length == 2' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: session limiter should retain only the two allowed leases" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
echo "  ✅ Codex session max_concurrent is enforced locally"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session ignores model-supplied tool_input call id" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"tool_call_id":"attacker-reused","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'
run_hook "Codex session does not dedupe on model-supplied tool_input call id" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"tool_call_id":"attacker-reused","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'
run_hook "Codex session repeated model-supplied call id still fails missing context" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_input":{"tool_call_id":"attacker-reused","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.missing_required_context"))'
if [[ -f "$TEST_DIR/aport/session-state.json" ]]; then
    echo "FAIL: session limiter must not create leases from model-supplied tool_input.tool_call_id" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
fi
echo "  ✅ Codex session ignores model-controlled call IDs"

cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_session_lifecycle",
  "agent_id": "ap_limited_session_lifecycle",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session pre-tool reserves by tool_use_id" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-1","tool_input":{"id":"spoof-child-1","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "call:lease-call-1"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: pre-tool session create should reserve by tool_use_id, not model-supplied child id" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
run_hook "Codex duplicate model-supplied child id cannot bypass concurrency" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-2","tool_input":{"id":"spoof-child-1","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_session_short_duration",
  "agent_id": "ap_limited_session_short_duration",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 1,
      "max_session_duration": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex rejects unsupported local max session duration limit" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"short-duration-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.unsupported_limit"))'
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_session_live_ttl",
  "agent_id": "ap_limited_session_live_ttl",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 1,
      "local_lease_ttl_seconds": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session starts live-ttl test child" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"live-ttl-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex session reconciles live-ttl test child" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"live-ttl-call","tool_response":{"success":true,"id":"live-ttl-child"}}' \
    '. == {}'
sleep 2
run_hook "Codex live session lease survives local TTL expiry" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-live-ttl-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex close live-ttl child is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_call_id":"close-live-ttl-call","tool_input":{"id":"live-ttl-child"}}' \
    '. == {}'
run_hook "Codex post-tool close releases live-ttl child" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_call_id":"close-live-ttl-call","tool_input":{"id":"live-ttl-child"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex session lease after live-ttl close is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-live-ttl-close-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex live session leases survive local TTL expiry until explicit close"
cat > "$TEST_DIR/aport/passport.json" << 'EOF'
{
  "passport_id": "ap_limited_session_lifecycle",
  "agent_id": "ap_limited_session_lifecycle",
  "spec_version": "oap/1.0",
  "owner_id": "user@example.com",
  "assurance_level": "L2",
  "status": "active",
  "capabilities": [{"id": "agent.session.create"}],
  "limits": {
    "agent.session.create": {
      "max_concurrent": 1
    }
  },
  "regions": ["US"],
  "never_expires": true
}
EOF
rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session pre-tool reserves lifecycle lease after short-duration test" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-1","tool_input":{"id":"spoof-child-1","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool spawn reconciles tool_use_id lease to child id" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-1","tool_response":{"success":true,"id":"child-1"}}' \
    '. == {}'
run_hook "Codex close_agent keeps lease before tool succeeds" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"child-pre-release-call","tool_input":{"id":"child-pre-release","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex post-tool close releases matching child lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex session lease after close is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-3","tool_input":{"id":"spoof-child-2","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool spawn reconciles second tool_use_id lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_use_id":"lease-call-3","tool_response":{"success":true,"id":"child-2"}}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "child-2"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: session close should release the matching child lease" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
echo "  ✅ Codex session close releases child leases"
run_hook "Codex post-tool close releases previous_status child lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-2"},"tool_response":{"previous_status":{"completed":"done"}}}' \
    '. == {}'
jq -e '.leases | length == 0' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: previous_status close should release the matching child lease" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
echo "  ✅ Codex previous_status close releases child leases"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session lease reserves by tool call before child id exists" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"call-1","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool reconciles session lease to child id" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"call-1","tool_response":{"id":"child-1"}}' \
    '. == {}'
run_hook "Codex close_agent releases reconciled child lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"}}' \
    '. == {}'
run_hook "Codex nested-error post-tool close keeps reconciled lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":{"error":"close failed"}}' \
    '. == {}'
run_hook "Codex spawn remains capped after nested-error close" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"child-denied-nested-error-call","tool_input":{"id":"child-denied-nested-error","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex failed post-tool close keeps reconciled lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"result":{"success":false}}' \
    '. == {}'
run_hook "Codex spawn remains capped after failed close" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"child-denied-after-failed-close-call","tool_input":{"id":"child-denied","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex unstructured post-tool close keeps reconciled lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":"agent close failed"}' \
    '. == {}'
run_hook "Codex spawn remains capped after unstructured close" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"child-denied-after-unstructured-close-call","tool_input":{"id":"child-denied-unstructured","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex post-tool close releases reconciled child lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex session lease after reconciled close is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"call-2","tool_input":{"id":"spoof-child-2","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool reconciles second child lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"call-2","tool_response":{"id":"child-2"}}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "child-2"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: post-tool reconciliation should let close release the child lease" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
echo "  ✅ Codex PostToolUse reconciles session leases"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session lease reserves before string response id exists" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"string-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex post-tool parses string response session id" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"string-call","success":true,"tool_response":"{\"id\":\"child-string\"}"}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "child-string"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: string-valued Codex PostToolUse output should reconcile the reserved lease" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
run_hook "Codex string-response session remains capped" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"child-denied-after-string-call","tool_input":{"id":"child-denied-after-string","prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
run_hook "Codex post-tool close releases string-response lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-string"},"success":true}' \
    '. == {}'
echo "  ✅ Codex PostToolUse handles string-valued responses"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex failed spawn reserves before execution" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"failed-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex failed post-tool spawn releases reserved capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"failed-call","success":false}' \
    '. == {}'
run_hook "Codex session lease after failed spawn is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-failure-call","tool_input":{"id":"child-after-failure","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex failed session creation releases reserved capacity"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex failed string-response spawn reserves before execution" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"failed-string-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex failed string-response spawn releases reserved capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"failed-string-call","tool_response":"{\"success\":false}"}' \
    '. == {}'
run_hook "Codex session lease after failed string-response spawn is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-string-failure-call","tool_input":{"id":"child-after-string-failure","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex failed string response releases reserved capacity"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex successful resume preserves target session id" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_use_id":"resume-call","tool_input":{"id":"child-1"}}' \
    '. == {}'
jq -e '.leases | length == 1 and .[0].session_id == "child-1" and .[0].session_call_id == "resume-call"' "$TEST_DIR/aport/session-state.json" > /dev/null || {
    echo "FAIL: resume should reserve the target session id with the host call id" >&2
    cat "$TEST_DIR/aport/session-state.json" >&2
    exit 1
}
run_hook "Codex status-only resume output keeps releaseable target id" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_use_id":"resume-call","tool_input":{"id":"child-1"},"tool_response":{"status":"running"}}' \
    '. == {}'
run_hook "Codex close after status-only resume releases lease" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_input":{"id":"child-1"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex spawn after status-only resume close is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-successful-resume-close","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex successful resume leases remain releaseable"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex failed live-resume test starts tracked session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"live-resume-spawn","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex failed live-resume test reconciles tracked session" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"live-resume-spawn","tool_response":{"success":true,"id":"live-resume-child"}}' \
    '. == {}'
run_hook "Codex failed live-resume attempt is allowed pre-tool" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"failed-live-resume","tool_input":{"id":"live-resume-child"}}' \
    '. == {}'
run_hook "Codex failed live-resume completion does not release live child" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"failed-live-resume","tool_input":{"id":"live-resume-child"},"success":false}' \
    '. == {}'
run_hook "Codex live child remains capped after failed resume" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-failed-live-resume","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
echo "  ✅ Codex failed resume does not release existing live sessions"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex overlap test starts tracked session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"overlap-spawn","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
run_hook "Codex overlap test reconciles tracked session" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"overlap-spawn","tool_response":{"id":"child-overlap"}}' \
    '. == {}'
run_hook "Codex overlap close marks the active session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_call_id":"overlap-close","tool_input":{"id":"child-overlap"}}' \
    '. == {}'
run_hook "Codex overlap resume preserves the active session" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"overlap-resume","tool_input":{"id":"child-overlap"}}' \
    '. == {}'
run_hook "Codex stale close completion does not clear resumed session" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.close_agent","session_id":"parent-session","tool_call_id":"overlap-close","tool_input":{"id":"child-overlap"},"tool_response":{"success":true}}' \
    '. == {}'
run_hook "Codex overlap resume completion keeps session active" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"overlap-resume","tool_input":{"id":"child-overlap"},"tool_response":{"status":"running"}}' \
    '. == {}'
run_hook "Codex spawn remains capped after close-resume overlap" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-overlap-call","tool_input":{"prompt":"review this","agent_type":"reviewer"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
echo "  ✅ Codex overlapping close/resume keeps session capacity"

rm -f "$TEST_DIR/aport/session-state.json" "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex failed resume reserves before execution" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"failed-resume","tool_input":{"id":"missing-child"}}' \
    '. == {}'
run_hook "Codex failed post-tool resume releases reserved capacity" \
    codex "$CODEX" \
    '{"hook_event_name":"PostToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"failed-resume","tool_input":{"id":"missing-child"},"success":false}' \
    '. == {}'
run_hook "Codex session lease after failed resume is allowed" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.spawn_agent","session_id":"parent-session","tool_call_id":"after-failed-resume-call","tool_input":{"id":"child-after-failed-resume","prompt":"review this","agent_type":"reviewer"}}' \
    '. == {}'
echo "  ✅ Codex failed resume releases reserved capacity"

run_hook "Codex resume_agent is blocked when concurrency is full" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"collaboration.resume_agent","session_id":"parent-session","tool_call_id":"resume-while-full-call","tool_input":{"id":"child-1"}}' \
    '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("oap.concurrent_limit_exceeded"))'
echo "  ✅ Codex resume_agent respects session concurrency"
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
rm -f "$TEST_DIR/aport/session-state.json"

rm -f "$TEST_DIR/aport/session-decisions.jsonl"
run_hook "Codex session context strips raw prompt text" \
    codex "$CODEX" \
    '{"hook_event_name":"PreToolUse","tool_name":"Task","tool_call_id":"context-minimized-call","tool_input":{"prompt":"customer token secret_should_not_leave","subagent_type":"reviewer"}}' \
    '. == {}'

if grep -q 'secret_should_not_leave' "$TEST_DIR/aport/session-decisions.jsonl"; then
    echo "FAIL: session decision context must not contain raw prompts" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
fi
jq -e '.context.description_length > 0 and .context.subagent_type == "reviewer"' "$TEST_DIR/aport/session-decisions.jsonl" > /dev/null || {
    echo "FAIL: session context should include length and subagent type only" >&2
    cat "$TEST_DIR/aport/session-decisions.jsonl" >&2
    exit 1
}
echo "  ✅ Session context is minimized"

cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
APORT_ENFORCEMENT=warn
EOF
OUT_TOO_LARGE="$TEST_DIR/gemini-too-large.json"
set +e
printf '%s' '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls -la"}}' \
    | APORT_HOOK_STDIN_MAX_BYTES=20 "$GEMINI" > "$OUT_TOO_LARGE" 2> /dev/null
TOO_LARGE_EXIT=$?
set -e
[[ "$TOO_LARGE_EXIT" -eq 0 ]] || {
    echo "FAIL: oversized Gemini payload should produce host JSON" >&2
    exit 1
}
jq -e '.decision == "deny" and (.reason | contains("oap.input_too_large"))' "$OUT_TOO_LARGE" > /dev/null || {
    echo "FAIL: oversized Gemini payload should fail closed even in warn mode" >&2
    cat "$OUT_TOO_LARGE" >&2
    exit 1
}
echo "  ✅ Oversized Gemini payload fails closed"

echo ""
echo "  Shared command-hook adapter tests passed."

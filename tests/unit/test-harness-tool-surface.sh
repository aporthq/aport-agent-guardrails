#!/bin/bash
# Contract test for the declared hook tool surface across supported harnesses.
# This is the PR/pre-push gate that catches newly documented expected tools
# that would otherwise fail closed as oap.unknown_tool.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "$0")/../setup.sh"

SURFACE_FILE="$REPO_ROOT/tests/fixtures/harness-tool-surface.json"
READ_FILE="$TEST_DIR/read-target.txt"
WRITE_FILE="$TEST_DIR/write-target.txt"
IMAGE_FILE="$TEST_DIR/source-image.png"

mkdir -p "$TEST_DIR/aport"
cp "$FIXTURE_PASSPORT" "$TEST_DIR/aport/passport.json"
cat > "$TEST_DIR/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=local
EOF
printf 'read target\n' > "$READ_FILE"
printf 'existing write target\n' > "$WRITE_FILE"
printf 'not really an image; policy only sees the path\n' > "$IMAGE_FILE"

export OPENCLAW_CONFIG_DIR="$TEST_DIR"
export OPENCLAW_PASSPORT_FILE="$TEST_DIR/aport/passport.json"
export OPENCLAW_DECISION_FILE="$TEST_DIR/aport/decision.json"
export OPENCLAW_AUDIT_LOG="$TEST_DIR/aport/audit.log"

hook_for_framework() {
    case "$1" in
        codex) printf '%s/bin/aport-codex-hook.sh' "$REPO_ROOT" ;;
        gemini-cli) printf '%s/bin/aport-gemini-cli-hook.sh' "$REPO_ROOT" ;;
        goose) printf '%s/bin/aport-goose-hook.sh' "$REPO_ROOT" ;;
        claude-code) printf '%s/bin/aport-claude-code-hook.sh' "$REPO_ROOT" ;;
        cursor) printf '%s/bin/aport-cursor-hook.sh' "$REPO_ROOT" ;;
        *) return 1 ;;
    esac
}

base_event_for_framework() {
    case "$1" in
        codex | claude-code) printf 'PreToolUse' ;;
        gemini-cli) printf 'BeforeTool' ;;
        goose | cursor) printf 'PreToolUse' ;;
        *) printf 'PreToolUse' ;;
    esac
}

payload_for_case() {
    local framework="$1" tool="$2" kind="$3"
    local event call_id

    event="$(base_event_for_framework "$framework")"
    call_id="surface-${framework}-${kind}-${RANDOM}"

    case "$kind" in
        shell)
            jq -nc --arg event "$event" --arg tool "$tool" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-shell",tool_input:{command:"ls -la"}}'
            ;;
        file_read)
            jq -nc --arg event "$event" --arg tool "$tool" --arg path "$READ_FILE" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-read",tool_input:{file_path:$path,path:$path,source:$path}}'
            ;;
        file_write)
            jq -nc --arg event "$event" --arg tool "$tool" --arg path "$WRITE_FILE" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-write",tool_input:{file_path:$path,path:$path,content:"surface write content",new_string:"surface write content"}}'
            ;;
        web)
            jq -nc --arg event "$event" --arg tool "$tool" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-web",tool_input:{url:"https://example.com/surface",method:"GET"}}'
            ;;
        browser)
            jq -nc --arg event "$event" --arg tool "$tool" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-browser",tool_input:{url:"https://example.com/surface",action:"open"}}'
            ;;
        browser_unsupported)
            jq -nc --arg event "$event" --arg tool "$tool" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-browser-unsupported",tool_input:{url:"https://example.com/surface",action:"type",text:"secret text must not be forwarded"}}'
            ;;
        mcp)
            jq -nc --arg event "$event" --arg tool "$tool" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-mcp",mcp_context:{server_name:"github",tool_name:"issues.list"},tool_input:{id:"surface"}}'
            ;;
        session)
            jq -nc --arg event "$event" --arg tool "$tool" --arg call_id "$call_id" '{hook_event_name:$event,tool_name:$tool,tool_call_id:$call_id,session_id:"surface-parent",active_session_count:0,tool_input:{id:"surface-child",prompt:"review this",task:"review this",message:"continue",agent_type:"reviewer",subagent_type:"reviewer"}}'
            ;;
        passthrough)
            jq -nc --arg event "$event" --arg tool "$tool" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-passthrough",tool_input:{plan:[{step:"surface",status:"pending"}],question:"continue?",query:"surface"}}'
            ;;
        image_generation)
            jq -nc --arg event "$event" --arg tool "$tool" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-image",tool_input:{prompt:"surface prompt must not be persisted",num_last_images_to_include:0}}'
            ;;
        image_read_file)
            jq -nc --arg event "$event" --arg tool "$tool" --arg path "$IMAGE_FILE" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-image-read",tool_input:{source:$path,file_path:$path,path:$path}}'
            ;;
        image_read_url)
            jq -nc --arg event "$event" --arg tool "$tool" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-image-read-url",tool_input:{source:"https://example.com/source.png",url:"https://example.com/source.png",method:"GET"}}'
            ;;
        write_stdin)
            jq -nc --arg event "$event" --arg tool "$tool" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-stdin",tool_input:{session_id:"surface-shell",chars:"ls -la\n"}}'
            ;;
        metadata_unsupported)
            jq -nc --arg event "$event" --arg tool "$tool" --arg path "$READ_FILE" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-metadata",tool_input:{path:$path,file_path:$path,pattern:"*"}}'
            ;;
        goose_text_read)
            jq -nc --arg event "$event" --arg tool "$tool" --arg path "$READ_FILE" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-goose-read",tool_input:{command:"view",path:$path,file_path:$path}}'
            ;;
        goose_text_write)
            jq -nc --arg event "$event" --arg tool "$tool" --arg path "$WRITE_FILE" '{hook_event_name:$event,tool_name:$tool,tool_call_id:"surface-goose-write",tool_input:{command:"str_replace",path:$path,file_path:$path,old_string:"existing",new_string:"updated"}}'
            ;;
        cursor_before_read_file)
            jq -nc --arg path "$READ_FILE" '{hook_event_name:"beforeReadFile",file_path:$path,content:"content must not be forwarded"}'
            ;;
        cursor_before_tab_file_read)
            jq -nc --arg path "$READ_FILE" '{hook_event_name:"beforeTabFileRead",file_path:$path,content:"content must not be forwarded"}'
            ;;
        cursor_before_shell)
            jq -nc '{hook_event_name:"beforeShellExecution",command:"ls -la"}'
            ;;
        cursor_before_mcp)
            jq -nc '{hook_event_name:"beforeMCPExecution",tool_name:"issues.list",mcp_server_name:"github",tool_input:{id:"surface"}}'
            ;;
        cursor_subagent_start)
            jq -nc '{hook_event_name:"subagentStart",subagent_id:"surface-child",task:"review this",subagent_type:"reviewer",active_session_count:0}'
            ;;
        *)
            return 1
            ;;
    esac
}

assert_surface_result() {
    local framework="$1" tool="$2" kind="$3" expect_code="$4" out="$5" err="$6" exit_code="$7"

    if [ -s "$out" ]; then
        jq -e . "$out" > /dev/null || {
            echo "FAIL: $framework $tool stdout must be valid JSON" >&2
            cat "$out" >&2
            cat "$err" >&2 || true
            exit 1
        }
    fi

    if grep -E 'oap\.unknown_tool|oap\.missing_tool_name|Unknown (Codex|Gemini CLI|Goose|tool)' "$out" "$err" > /dev/null 2>&1; then
        echo "FAIL: $framework $tool ($kind) is in the declared surface but mapped as unknown" >&2
        cat "$out" >&2 || true
        cat "$err" >&2 || true
        exit 1
    fi

    if [ -n "$expect_code" ]; then
        grep -q "$expect_code" "$out" "$err" || {
            echo "FAIL: $framework $tool ($kind) should produce $expect_code" >&2
            cat "$out" >&2 || true
            cat "$err" >&2 || true
            exit 1
        }
        return 0
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo "FAIL: $framework $tool ($kind) exited $exit_code" >&2
        cat "$out" >&2 || true
        cat "$err" >&2 || true
        exit 1
    fi
}

echo ""
echo "  Unit — declared harness tool surface"
echo ""

chmod +x "$REPO_ROOT"/bin/aport-{codex,gemini-cli,goose,claude-code,cursor}-hook.sh 2> /dev/null || true

while IFS=$'\t' read -r framework tool kind expect_code; do
    hook_script="$(hook_for_framework "$framework")"
    payload="$(payload_for_case "$framework" "$tool" "$kind")"
    out="$TEST_DIR/surface-${framework}-${RANDOM}.json"
    err="$TEST_DIR/surface-${framework}-${RANDOM}.err"

    set +e
    printf '%s' "$payload" | "$hook_script" > "$out" 2> "$err"
    exit_code=$?
    set -e

    assert_surface_result "$framework" "$tool" "$kind" "$expect_code" "$out" "$err" "$exit_code"
done < <(
    jq -r '
      .frameworks
      | to_entries[]
      | .key as $framework
      | .value[]
      | [$framework, .tool, .kind, (.expect_code // "")]
      | @tsv
    ' "$SURFACE_FILE"
)

echo "  ✅ Declared harness tool surface is mapped"

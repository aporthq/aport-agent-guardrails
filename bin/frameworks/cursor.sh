#!/usr/bin/env bash
# Cursor framework installer/setup.
# Runs passport wizard and writes ~/.cursor/hooks.json pointing at the APort hook script.
# Same hook script works for Cursor and VS Code/Copilot-style hook payloads.

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$LIB/common.sh"
# shellcheck source=../lib/passport.sh
source "$LIB/passport.sh"
# shellcheck source=../lib/config.sh
source "$LIB/config.sh"
# shellcheck source=../lib/framework-setup.sh
source "$LIB/framework-setup.sh"
# shellcheck source=../lib/guardrail-mode.sh
source "$LIB/guardrail-mode.sh"
# shellcheck source=../lib/runtime.sh
source "$LIB/runtime.sh"
# shellcheck source=../lib/quick-hosted.sh
source "$LIB/quick-hosted.sh"

APORT_HOOK_MARKER="__aport_hook"
# Cursor reads "timeout" in seconds. failClosed: true makes crashes, timeouts and
# non-2 exit codes block instead of Cursor's default fail-open. The budget follows the
# evaluator's request bound (APORT_API_TIMEOUT, default 15 s, src/evaluator.js) plus a
# 15 s margin for node startup and the audit write, so a slow hosted evaluator is
# reported as oap.evaluation_error with a reason instead of a bare hook timeout.
APORT_HOOK_TIMEOUT="${APORT_HOOK_TIMEOUT:-$((${APORT_API_TIMEOUT:-15} + 15))}"

# beforeTabFileRead gates file reads made by Tab (inline completions), not by
# the Agent. It is opt-in because it runs the evaluator on every Tab file read
# and a passport without data.file.read would block completions entirely.
# Set APORT_CURSOR_TAB_READ_HOOK=1 at install time to register it.
aport_cursor_tab_read_hook_enabled() {
    case "${APORT_CURSOR_TAB_READ_HOOK:-}" in
        1 | true | yes | on) return 0 ;;
        *) return 1 ;;
    esac
}

run_setup() {
    parse_guardrail_mode_args "$@"

    log_info "Setting up APort guardrails for Cursor..."
    # Passport and data live under Cursor's config dir (~/.cursor/aport/ by default).
    config_dir="$(ensure_aport_dir_secure cursor)"

    export APORT_FRAMEWORK=cursor

    local hosted_agent_id=""
    if [[ -n "${APORT_HOSTED_AGENT_ID_CLI:-}" ]]; then
        hosted_agent_id="$APORT_HOSTED_AGENT_ID_CLI"
        export APORT_AGENT_ID="$hosted_agent_id"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    elif aport_maybe_configure_hosted_passport "cursor" "$config_dir"; then
        hosted_agent_id="$APORT_AGENT_ID"
        log_info "Using hosted passport (agent_id: $hosted_agent_id) — skipping wizard."
    else
        # Check AGENTS.md for enforcement config — skip wizard if already configured
        # shellcheck source=../lib/agentsmd.sh
        source "$LIB/agentsmd.sh"
        setup_from_agentsmd_or_wizard ${APORT_FRAMEWORK_ARGS[@]+"${APORT_FRAMEWORK_ARGS[@]}"}
    fi

    # Harden permissions on passport (contains policy/capabilities)
    secure_framework_passport_file_if_present "$config_dir"

    if [[ -z "$hosted_agent_id" && -n "${APORT_AGENT_ID:-}" ]]; then
        hosted_agent_id="$APORT_AGENT_ID"
    fi

    select_guardrail_mode "cursor" "$hosted_agent_id"
    select_guardrail_api_url "$APORT_SELECTED_GUARDRAIL_MODE"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        export APORT_API_URL="${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    select_guardrail_enforcement
    MODE_FILE="$(write_guardrail_mode_file "$config_dir" "$APORT_SELECTED_GUARDRAIL_MODE" "${APORT_SELECTED_API_URL:-}" "$hosted_agent_id" "$APORT_SELECTED_ENFORCEMENT")"

    install_runtime_tree "$config_dir"

    # Resolve absolute path to hook script. By default this points at the stable
    # per-framework runtime copy, so one-shot npx setup does not depend on an
    # evictable package cache path.
    HOOK_SCRIPT="$(resolve_hook_script_path "${APORT_CURSOR_HOOK_SCRIPT:-$config_dir/aport/runtime/bin/aport-cursor-hook.sh}" "aport-cursor-hook.sh" "$LIB")"
    if [ ! -f "$HOOK_SCRIPT" ]; then
        log_warn "Hook script not found at $HOOK_SCRIPT; hooks.json will reference it (create the file for hooks to work)."
    else
        HOOK_SCRIPT="$(cd "$(dirname "$HOOK_SCRIPT")" && pwd)/$(basename "$HOOK_SCRIPT")"
    fi

    # Write Cursor hooks config: every permission hook runs the same script.
    # Cursor loads ~/.cursor/hooks.json (user), <project>/.cursor/hooks.json
    # (project) and enterprise-managed files; cloud agents read only project,
    # team and enterprise hooks, never the user file written here.
    CURSOR_HOOKS_DIR="${CURSOR_HOOKS_DIR:-$HOME/.cursor}"
    CURSOR_HOOKS_FILE="$CURSOR_HOOKS_DIR/hooks.json"
    mkdir -p "$CURSOR_HOOKS_DIR"
    local tab_json=false
    aport_cursor_tab_read_hook_enabled && tab_json=true

    # Merge with existing hooks.json if present; otherwise create new.
    if [ -f "$CURSOR_HOOKS_FILE" ]; then
        if ! command -v jq &> /dev/null; then
            log_error "Cannot merge existing Cursor hooks without jq: $CURSOR_HOOKS_FILE"
            exit 1
        fi
        if ! jq -e . "$CURSOR_HOOKS_FILE" > /dev/null 2>&1; then
            log_error "Refusing to overwrite invalid Cursor hooks JSON: $CURSOR_HOOKS_FILE"
            exit 1
        fi
        # Add APort hook to all supported permission events.
        # Replace marker-owned or legacy APort entries, preserve non-APort hooks.
        # beforeTabFileRead is only written when opted in; otherwise any APort
        # entry left there by an earlier opt-in install is removed.
        NEW_HOOKS=$(jq -c --arg cmd "$HOOK_SCRIPT" --arg marker "$APORT_HOOK_MARKER" --argjson timeout "$APORT_HOOK_TIMEOUT" --argjson tab "$tab_json" '
        def aport_hook($cmd; $marker; $timeout):
          { "command": $cmd, ($marker): true, "timeout": $timeout, "failClosed": true };
        def is_aport_cursor_hook:
          (.[$marker] == true) or (((.command // "") | tostring) | test("(^|/)aport-cursor-hook\\.sh($|[[:space:]])"));
        def strip_hook:
          (. // []) | map(select(is_aport_cursor_hook | not));
        def upsert_hook:
          strip_hook | . + [aport_hook($cmd; $marker; $timeout)];
        .version = (.version // 1) |
        .hooks = (.hooks // {}) |
        .hooks.beforeShellExecution = ((.hooks.beforeShellExecution // []) | upsert_hook) |
        .hooks.preToolUse = ((.hooks.preToolUse // []) | upsert_hook) |
        .hooks.beforeMCPExecution = ((.hooks.beforeMCPExecution // []) | upsert_hook) |
        .hooks.beforeReadFile = ((.hooks.beforeReadFile // []) | upsert_hook) |
        .hooks.subagentStart = ((.hooks.subagentStart // []) | upsert_hook) |
        .hooks.beforeTabFileRead = ((.hooks.beforeTabFileRead // []) | strip_hook | if $tab then . + [aport_hook($cmd; $marker; $timeout)] else . end) |
        if (.hooks.beforeTabFileRead | length) == 0 then del(.hooks.beforeTabFileRead) else . end
      ' "$CURSOR_HOOKS_FILE")
        cp "$CURSOR_HOOKS_FILE" "${CURSOR_HOOKS_FILE}.bak"
        echo "$NEW_HOOKS" > "$CURSOR_HOOKS_FILE"
    else
        _write_cursor_hooks_file "$CURSOR_HOOKS_FILE" "$HOOK_SCRIPT"
    fi
    chmod 600 "$CURSOR_HOOKS_FILE"

    echo ""
    echo "  Next steps (Cursor):"
    echo "  ────────────────────"
    echo "  1. Hooks config written to: $CURSOR_HOOKS_FILE"
    echo "  2. Hook script: $HOOK_SCRIPT"
    echo "  3. Guardrail mode: $APORT_SELECTED_GUARDRAIL_MODE"
    echo "     Enforcement: $APORT_SELECTED_ENFORCEMENT"
    if [[ "$APORT_SELECTED_GUARDRAIL_MODE" = "api" ]]; then
        echo "     API URL: ${APORT_SELECTED_API_URL:-$DEFAULT_APORT_API_URL}"
    fi
    echo "  4. Mode config: $MODE_FILE"
    echo "  5. Restart Cursor (or reload window) so hooks are picked up."
    echo "  6. Shell commands and tool use will be checked by APort policy (exit 2 = block)."
    if aport_cursor_tab_read_hook_enabled; then
        echo "  7. beforeTabFileRead is registered: Tab completion file reads are checked too."
    else
        echo "  7. Tab completion file reads are not checked. Re-run with APORT_CURSOR_TAB_READ_HOOK=1 to add beforeTabFileRead."
    fi
    echo ""
    echo "  For other frameworks like Claude Code, use the dedicated integration: docs/frameworks"
    echo ""
}

_write_cursor_hooks_file() {
    local file="$1"
    local cmd="$2"
    local tab_json=false
    aport_cursor_tab_read_hook_enabled && tab_json=true
    if command -v jq &> /dev/null; then
        jq -n -c --arg cmd "$cmd" --arg marker "$APORT_HOOK_MARKER" --argjson timeout "$APORT_HOOK_TIMEOUT" --argjson tab "$tab_json" '
    def aport_hook: { command: $cmd, ($marker): true, timeout: $timeout, failClosed: true };
    {
      version: 1,
      hooks: ({
        beforeShellExecution: [aport_hook],
        preToolUse: [aport_hook],
        beforeMCPExecution: [aport_hook],
        beforeReadFile: [aport_hook],
        subagentStart: [aport_hook]
      } + (if $tab then { beforeTabFileRead: [aport_hook] } else {} end))
    }' > "$file"
    else
        # One hook entry, built once, so the timeout here and in the jq path are the same value.
        local escaped_cmd entry tab_entry=""
        escaped_cmd="$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        entry="{\"command\": \"${escaped_cmd}\", \"${APORT_HOOK_MARKER}\": true, \"timeout\": ${APORT_HOOK_TIMEOUT}, \"failClosed\": true}"
        if [[ "$tab_json" = true ]]; then
            tab_entry=",
    \"beforeTabFileRead\": [${entry}]"
        fi
        cat > "$file" << EOF
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [${entry}],
    "preToolUse": [${entry}],
    "beforeMCPExecution": [${entry}],
    "beforeReadFile": [${entry}],
    "subagentStart": [${entry}]${tab_entry}
  }
}
EOF
    fi
}

run_setup "$@"

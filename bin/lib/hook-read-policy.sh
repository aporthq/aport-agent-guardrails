# Shared path-based read tool handling for Claude Code and Cursor hooks.
# shellcheck shell=bash
#
# Usage (after defining safe_jq in the hook):
#   aport_hook_try_read_evaluation "$TOOL_NORM" "$TOOL_INPUT"
# On success: sets GUARDRAIL_TOOL=read and CONTEXT_JSON with file_path; returns 0.
# On skip (no path / not a path-based read tool): returns 1 — caller may allow without evaluator.

aport_hook_read_tools_with_path() {
    case "$1" in
        read | readfile | semanticsearch) return 0 ;;
        *) return 1 ;;
    esac
}

aport_hook_read_context_json() {
    local file_path="$1"
    jq -n -c --arg file_path "$file_path" '{file_path: $file_path}' 2> /dev/null
}

aport_hook_try_read_evaluation() {
    local tool_norm="$1"
    local tool_input="$2"
    local file_path context

    if ! aport_hook_read_tools_with_path "$tool_norm"; then
        return 1
    fi

    file_path="$(echo "$tool_input" | jq -r '.file_path // .path // ""' 2> /dev/null || true)"
    if [ -z "$file_path" ]; then
        return 1
    fi

    context="$(aport_hook_read_context_json "$file_path")"
    if [ -z "$context" ]; then
        return 1
    fi

    GUARDRAIL_TOOL="read"
    CONTEXT_JSON="$context"
    return 0
}

aport_hook_try_read_evaluation_from_file_path() {
    local file_path="$1"
    local context

    if [ -z "$file_path" ]; then
        return 1
    fi

    context="$(aport_hook_read_context_json "$file_path")"
    if [ -z "$context" ]; then
        return 1
    fi

    GUARDRAIL_TOOL="read"
    CONTEXT_JSON="$context"
    return 0
}

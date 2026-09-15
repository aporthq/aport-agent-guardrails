# Shared path-based read tool handling for Claude Code and Cursor hooks.
# shellcheck shell=bash
#
# Usage (after defining safe_jq in the hook):
#   aport_hook_try_read_evaluation "$TOOL_NORM" "$TOOL_INPUT"
# On success: sets GUARDRAIL_TOOL=read and CONTEXT_JSON with file_path; returns 0.
# On skip (no path / not a path-based read tool): returns 1 — caller may allow without evaluator.

aport_hook_read_tools_with_path() {
    case "$1" in
        read | readfile | read_file | semanticsearch | presentfile | present_file | viewimage | view_image | grep | grepsearch | grep_search) return 0 ;;
        *) return 1 ;;
    esac
}

aport_hook_read_context_json() {
    local file_path="$1"
    jq -n -c --arg file_path "$file_path" '{file_path: $file_path}' 2> /dev/null
}

aport_hook_read_set_error() {
    APORT_HOOK_READ_ERROR_CODE="$1"
    APORT_HOOK_READ_ERROR_MESSAGE="$2"
}

aport_hook_read_clear_error() {
    APORT_HOOK_READ_ERROR_CODE=""
    APORT_HOOK_READ_ERROR_MESSAGE=""
}

aport_hook_is_search_tool() {
    case "$1" in
        grep | grepsearch | grep_search | semanticsearch) return 0 ;;
        *) return 1 ;;
    esac
}

aport_hook_try_read_evaluation() {
    local tool_norm="$1"
    local tool_input="$2"
    local file_path used_dir_path context
    aport_hook_read_clear_error

    if ! aport_hook_read_tools_with_path "$tool_norm"; then
        return 1
    fi

    file_path="$(echo "$tool_input" | jq -r '.file_path // .path // .dir_path // .args.file_path // .args.path // .args.dir_path // ""' 2> /dev/null || true)"
    used_dir_path="$(echo "$tool_input" | jq -r '((.dir_path // .args.dir_path // "") != "")' 2> /dev/null || echo false)"
    if [ -z "$file_path" ]; then
        return 1
    fi
    if aport_hook_is_search_tool "$tool_norm" && { [ "$used_dir_path" = "true" ] || [ -d "$file_path" ] || [[ "$file_path" == */ ]]; }; then
        aport_hook_read_set_error "oap.recursive_search_unsupported" "This hook cannot safely authorize recursive content searches; pass an explicit file path instead"
        return 2
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

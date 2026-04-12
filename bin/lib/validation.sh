#!/bin/bash
# validation.sh - Input validation functions for security
# Used to prevent command injection, path traversal, and other injection attacks

# Validate command string for dangerous injection patterns.
# Returns 0 if safe, 1 if contains dangerous patterns.
# NOTE: Pipes (|), chains (&&/||), redirects (>), and variable refs ($) are legitimate
# shell syntax used by Claude Code, Cursor, and other AI tools. We block dangerous
# OPERATIONS (handled by built-in security patterns and blocked_patterns in the evaluator),
# not normal shell syntax. This function catches injection-specific patterns only.
validate_command_string() {
    local cmd="$1"

    # Block backtick command substitution (injection vector; $() is caught by patterns below)
    if echo "$cmd" | grep -qF '`'; then
        return 1
    fi

    # Block $( ) command substitution containing dangerous commands
    if echo "$cmd" | grep -qE '\$\([^)]*\b(rm|dd|mkfs|curl|wget|chmod|chown|sudo|kill|nc|netcat)\b'; then
        return 1
    fi

    # Block null bytes (string termination attack)
    if printf '%s' "$cmd" | grep -qP '\x00' 2> /dev/null; then
        return 1
    fi

    # Block control characters (except tab/newline which are normal in shell)
    if printf '%s' "$cmd" | grep -qP '[\x01-\x08\x0e-\x1f]' 2> /dev/null; then
        return 1
    fi

    return 0
}

# Validate tool name contains only safe characters
# Returns 0 if valid, 1 if invalid
# Valid pattern: alphanumeric, dot, underscore, hyphen
validate_tool_name() {
    local tool_name="$1"

    # Check for empty
    if [ -z "$tool_name" ]; then
        return 1
    fi

    # Check length (max 128 characters)
    if [ ${#tool_name} -gt 128 ]; then
        return 1
    fi

    # Check pattern: only alphanumeric, dot, underscore, hyphen
    if ! echo "$tool_name" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        return 1
    fi

    return 0
}

# Validate explicit operator-provided passport paths.
# Returns 0 if the path is hygienic, 1 if it contains dangerous constructs.
validate_explicit_passport_path() {
    local path="$1"

    # Check for empty
    if [ -z "$path" ]; then
        return 1
    fi

    # Check for path traversal attempts
    if echo "$path" | grep -qE '\.\./|/\.\./|/\.\.$'; then
        return 1
    fi

    return 0
}

# Validate auto-discovered/default passport paths against trusted framework dirs.
# Returns 0 if safe, 1 if potentially dangerous.
validate_passport_path() {
    local path="$1"

    if ! validate_explicit_passport_path "$path"; then
        return 1
    fi

    # Expand to absolute path
    local abs_path
    abs_path=$(readlink -f "$path" 2> /dev/null || realpath "$path" 2> /dev/null || echo "$path")

    # Allowed base directories for auto-discovery
    local allowed_bases=(
        "$HOME/.openclaw"
        "$HOME/.aport"
        "$HOME/.claude"
        "$HOME/.cursor"
        "$HOME/.n8n"
        "/tmp/aport-"
    )

    local is_allowed=false
    for base in "${allowed_bases[@]}"; do
        case "$abs_path" in
            "$base"*)
                is_allowed=true
                break
                ;;
            "/private$base"*)
                is_allowed=true
                break
                ;;
        esac
    done

    if [ "$is_allowed" = false ]; then
        return 1
    fi

    return 0
}

# Validate JSON structure doesn't exceed size limits
# Returns 0 if valid, 1 if too large or invalid
validate_json_size() {
    local json="$1"
    local max_bytes="${2:-102400}" # Default: 100KB

    # Check size
    local size=${#json}
    if [ "$size" -gt "$max_bytes" ]; then
        return 1
    fi

    # Basic JSON syntax check (can be parsed by jq)
    if ! echo "$json" | jq empty 2> /dev/null; then
        return 1
    fi

    return 0
}

# Validate agent ID format
# Returns 0 if valid, 1 if invalid
validate_agent_id() {
    local agent_id="$1"

    # Check for empty
    if [ -z "$agent_id" ]; then
        return 1
    fi

    # Check length (max 128 characters)
    if [ ${#agent_id} -gt 128 ]; then
        return 1
    fi

    # Check pattern: ap_ prefix followed by alphanumeric/underscore
    if ! echo "$agent_id" | grep -qE '^ap_[a-zA-Z0-9_]+$'; then
        return 1
    fi

    return 0
}

# Safe pattern matching for blocked patterns.
# Returns 0 if pattern matches, 1 if no match.
# Usage: safe_pattern_match "string" "pattern"
#
# Matching strategy:
# - Multi-word patterns (e.g. "rm -rf"): substring match (grep -F)
#   because word boundary alone would miss "rm -rf /"
# - Single-word patterns (e.g. "sudo"): word boundary match (grep -w)
#   to avoid false positives like "test_sudo_check" or "pseudocode"
safe_pattern_match() {
    local string="$1"
    local pattern="$2"
    local pattern_escaped

    # Escape regex metacharacters for safe ERE matching.
    pattern_escaped="$(printf '%s' "$pattern" | sed -E 's/[][(){}.^$*+?|\\-]/\\&/g')"

    if [[ "$pattern" == *" "* ]]; then
        # Multi-word: case-insensitive substring match (the space makes it specific enough)
        echo "$string" | grep -qiF "$pattern"
    else
        # Single-word: case-insensitive boundary-aware regex (portable on GNU/BSD grep)
        echo "$string" | grep -qiE "(^|[^[:alnum:]_])${pattern_escaped}([^[:alnum:]_]|$)"
    fi
}

# Safe prefix matching (for allowed commands)
# Returns 0 if string starts with prefix, 1 otherwise
safe_prefix_match() {
    local string="$1"
    local prefix="$2"

    # Handle wildcard case
    if [ "$prefix" = "*" ]; then
        return 0
    fi

    # Use parameter expansion for safe prefix check
    if [ "${string#"$prefix"}" != "$string" ]; then
        return 0
    fi

    return 1
}

# Sanitize sensitive values for logging
# Usage: sanitize_log_value "value" "field_name"
sanitize_log_value() {
    local value="$1"
    local field_name="${2:-}"

    # Check if value is empty
    if [ -z "$value" ]; then
        echo "$value"
        return 0
    fi

    # Check for API key patterns (aprt_, sk_, pk_, Bearer)
    if echo "$value" | grep -qE '^(aprt_|sk_|pk_)'; then
        echo "${value:0:4}****"
        return 0
    fi

    if echo "$value" | grep -qiE '^Bearer '; then
        echo "Bearer ****"
        return 0
    fi

    # Check if field name indicates sensitive data
    if echo "$field_name" | grep -qiE '(password|passwd|pwd|secret|token|key|api)'; then
        echo "[REDACTED]"
        return 0
    fi

    # Truncate very long values (max 200 chars)
    if [ ${#value} -gt 200 ]; then
        echo "${value:0:200}..."
        return 0
    fi

    echo "$value"
}

#!/bin/bash
# constants.sh - Configuration constants and defaults for APort guardrails
# All magic numbers and hardcoded values should be defined here

# ============================================================================
# TIMEOUTS (seconds)
# ============================================================================

# Default timeout for subprocess guardrail script execution
readonly DEFAULT_SUBPROCESS_TIMEOUT="${APORT_SUBPROCESS_TIMEOUT:-30}"

# Default timeout for API requests
readonly DEFAULT_API_TIMEOUT="${APORT_API_TIMEOUT:-15}"

# Timeout for loading policy packs
readonly DEFAULT_POLICY_LOAD_TIMEOUT="${APORT_POLICY_LOAD_TIMEOUT:-5}"

# ============================================================================
# SIZE LIMITS
# ============================================================================

# Maximum tool name length (characters)
readonly MAX_TOOL_NAME_LENGTH="${APORT_MAX_TOOL_NAME_LENGTH:-128}"

# Maximum agent ID length (characters)
readonly MAX_AGENT_ID_LENGTH="${APORT_MAX_AGENT_ID_LENGTH:-128}"

# Maximum policy pack ID length (characters)
readonly MAX_POLICY_PACK_ID_LENGTH="${APORT_MAX_POLICY_PACK_ID_LENGTH:-128}"

# Maximum context JSON size (bytes) - default 100KB
readonly MAX_CONTEXT_SIZE_BYTES="${APORT_MAX_CONTEXT_SIZE:-102400}"

# Maximum passport file size (bytes) - default 1MB
readonly MAX_PASSPORT_SIZE_BYTES="${APORT_MAX_PASSPORT_SIZE:-1048576}"

# Maximum policy pack file size (bytes) - default 10MB
readonly MAX_POLICY_PACK_SIZE_BYTES="${APORT_MAX_POLICY_PACK_SIZE:-10485760}"

# Maximum log message length (characters)
readonly MAX_LOG_MESSAGE_LENGTH="${APORT_MAX_LOG_MESSAGE_LENGTH:-200}"

# ============================================================================
# RATE LIMITING
# ============================================================================

# Default requests per minute
readonly DEFAULT_RATE_LIMIT_RPM="${APORT_RATE_LIMIT_REQUESTS_PER_MINUTE:-60}"

# Default burst allowance
readonly DEFAULT_RATE_LIMIT_BURST="${APORT_RATE_LIMIT_BURST:-10}"

# ============================================================================
# RETRY LOGIC
# ============================================================================

# Maximum API retry attempts
readonly MAX_API_RETRIES="${APORT_MAX_API_RETRIES:-3}"

# API retry backoff (milliseconds)
readonly API_RETRY_BACKOFF_MS="${APORT_API_RETRY_BACKOFF_MS:-1000}"

# ============================================================================
# CACHING
# ============================================================================

# Passport file cache TTL (seconds)
readonly PASSPORT_CACHE_TTL_SECONDS="${APORT_PASSPORT_CACHE_TTL:-60}"

# Policy pack cache TTL (seconds)
readonly POLICY_CACHE_TTL_SECONDS="${APORT_POLICY_CACHE_TTL:-60}"

# Config file cache TTL (seconds)
readonly CONFIG_CACHE_TTL_SECONDS="${APORT_CONFIG_CACHE_TTL:-300}"

# ============================================================================
# API CONFIGURATION
# ============================================================================

# Default API URL
readonly DEFAULT_API_URL="${APORT_API_URL:-https://api.aport.io}"

# ============================================================================
# PATHS
# ============================================================================

# Allowed base directories for passport files (for validation)
readonly ALLOWED_PASSPORT_BASE_DIRS=(
    "$HOME/.openclaw"
    "$HOME/.aport"
    "/tmp/aport-"
)

# ============================================================================
# VALIDATION PATTERNS
# ============================================================================

# Tool name validation pattern (grep -E compatible)
readonly TOOL_NAME_PATTERN='^[a-zA-Z0-9._-]+$'

# Agent ID validation pattern (grep -E compatible)
readonly AGENT_ID_PATTERN='^ap_[a-zA-Z0-9_]+$'

# Policy pack ID validation pattern (grep -E compatible)
readonly POLICY_PACK_ID_PATTERN='^[a-zA-Z0-9._-]+$'

# ============================================================================
# LOGGING
# ============================================================================

# Log level (DEBUG, INFO, WARN, ERROR)
readonly LOG_LEVEL="${APORT_LOG_LEVEL:-INFO}"

# Log format (text, json)
readonly LOG_FORMAT="${APORT_LOG_FORMAT:-text}"

# ============================================================================
# SECURITY
# ============================================================================

# Sensitive field patterns for log redaction (space-separated)
readonly SENSITIVE_FIELD_PATTERNS="password passwd pwd secret token key api bearer"

# API key prefix patterns (space-separated)
readonly API_KEY_PREFIXES="aprt_ sk_ pk_"

# ============================================================================
# PERFORMANCE
# ============================================================================

# Slow operation threshold (milliseconds)
readonly SLOW_OPERATION_THRESHOLD_MS="${APORT_SLOW_OPERATION_THRESHOLD_MS:-200}"

# ============================================================================
# FEATURE FLAGS
# ============================================================================

# Enable policy caching (1=enabled, 0=disabled)
readonly ENABLE_POLICY_CACHING="${APORT_ENABLE_POLICY_CACHING:-1}"

# Enable passport caching (1=enabled, 0=disabled)
readonly ENABLE_PASSPORT_CACHING="${APORT_ENABLE_PASSPORT_CACHING:-1}"

# ============================================================================
# VERSION
# ============================================================================

# APort specification version
readonly OAP_SPEC_VERSION="oap/1.0"

# Client library version
readonly CLIENT_VERSION="1.0.8"

# ============================================================================
# MISC
# ============================================================================

# Audit log file name
readonly AUDIT_LOG_FILENAME="audit.log"

# Chain state file name
readonly CHAIN_STATE_FILENAME="chain-state.json"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get numeric constant with validation
# Usage: get_numeric_constant "var_name" "default_value" "min" "max"
get_numeric_constant() {
    local var_name="$1"
    local default_value="$2"
    local min_value="${3:-1}"
    local max_value="${4:-999999}"

    local value="${!var_name:-$default_value}"

    # Validate it's a number
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$default_value"
        return 1
    fi

    # Validate range
    if [ "$value" -lt "$min_value" ] || [ "$value" -gt "$max_value" ]; then
        echo "$default_value"
        return 1
    fi

    echo "$value"
    return 0
}

# Check if feature is enabled
# Usage: if is_feature_enabled "ENABLE_POLICY_CACHING"; then ...
is_feature_enabled() {
    local feature_var="$1"
    local value="${!feature_var:-0}"

    case "$value" in
        1 | true | TRUE | yes | YES | on | ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get log level priority (for filtering)
# Returns: 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
get_log_level_priority() {
    local level="${1:-INFO}"

    case "$level" in
        DEBUG) echo 0 ;;
        INFO) echo 1 ;;
        WARN) echo 2 ;;
        ERROR) echo 3 ;;
        *) echo 1 ;; # Default to INFO
    esac
}

# Check if should log at level
# Usage: if should_log "DEBUG"; then ...
should_log() {
    local message_level="$1"
    local current_priority=$(get_log_level_priority "$LOG_LEVEL")
    local message_priority=$(get_log_level_priority "$message_level")

    [ "$message_priority" -ge "$current_priority" ]
}

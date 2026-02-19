#!/bin/bash
# error.sh - Standardized error handling for APort guardrails
# Provides consistent error codes, messages, and response formatting

# Error codes (see docs/development/ERROR_CODES.md)
readonly ERROR_INVALID_TOOL_NAME="oap.invalid_input.tool_name"
readonly ERROR_CONTEXT_TOO_LARGE="oap.invalid_input.context_too_large"
readonly ERROR_INVALID_AGENT_ID="oap.invalid_input.agent_id"
readonly ERROR_PATH_NOT_ALLOWED="oap.path.not_allowed"
readonly ERROR_PATH_TRAVERSAL="oap.path.traversal_attempt"
readonly ERROR_PATH_INVALID_CHARS="oap.path.invalid_characters"
readonly ERROR_PASSPORT_NOT_FOUND="oap.passport.not_found"
readonly ERROR_PASSPORT_INVALID="oap.passport.invalid_format"
readonly ERROR_PASSPORT_EXPIRED="oap.passport.expired"
readonly ERROR_PASSPORT_REVOKED="oap.passport.revoked"
readonly ERROR_PASSPORT_MISSING_CAP="oap.passport.missing_capability"
readonly ERROR_POLICY_NOT_FOUND="oap.policy.not_found"
readonly ERROR_POLICY_INVALID="oap.policy.invalid_format"
readonly ERROR_POLICY_EVAL_FAILED="oap.policy.evaluation_failed"
readonly ERROR_POLICY_TIMEOUT="oap.policy.evaluation_timeout"
readonly ERROR_POLICY_DENIED="oap.policy.denied"
readonly ERROR_API_CONNECTION="oap.api.connection_failed"
readonly ERROR_API_AUTH="oap.api.authentication_failed"
readonly ERROR_API_RATE_LIMIT="oap.api.rate_limit_exceeded"
readonly ERROR_API_TIMEOUT="oap.api.timeout"
readonly ERROR_API_ERROR="oap.api.error"
readonly ERROR_CONFIG_NOT_FOUND="oap.config.not_found"
readonly ERROR_CONFIG_INVALID="oap.config.invalid_format"
readonly ERROR_EVALUATOR_ERROR="oap.system.evaluator_error"
readonly ERROR_COMMAND_INJECTION="oap.system.command_injection_detected"
readonly ERROR_DEPENDENCY_MISSING="oap.system.dependency_missing"
readonly ERROR_MISCONFIGURED="oap.misconfigured"

# Generate unique request ID
generate_request_id() {
    local timestamp=$(date +%s%3N 2> /dev/null || date +%s)
    local random=$(openssl rand -hex 3 2> /dev/null || echo "$RANDOM")
    echo "req_${timestamp}_${random}"
}

# Generate ISO 8601 timestamp
generate_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2> /dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Format error as JSON decision
# Usage: format_error_json "error_code" "message" ["details_json"] ["resolution"]
format_error_json() {
    local code="$1"
    local message="$2"
    local details="${3:-}"
    local resolution="${4:-}"
    local request_id="${5:-$(generate_request_id)}"
    local timestamp=$(generate_timestamp)

    local reason_json
    reason_json=$(
        cat << EOF
{
  "code": "$code",
  "message": "$message"
}
EOF
    )

    # Add details if provided
    if [ -n "$details" ]; then
        reason_json=$(echo "$reason_json" | jq -c --argjson d "$details" '. + {details: $d}')
    fi

    # Add resolution if provided
    if [ -n "$resolution" ]; then
        reason_json=$(echo "$reason_json" | jq -c --arg r "$resolution" '. + {resolution: $r}')
    fi

    # Create full response
    cat << EOF
{
  "allow": false,
  "reasons": [$reason_json],
  "request_id": "$request_id",
  "timestamp": "$timestamp"
}
EOF
}

# Format error as plain text
# Usage: format_error_text "error_code" "message" ["details"] ["resolution"]
format_error_text() {
    local code="$1"
    local message="$2"
    local details="${3:-}"
    local resolution="${4:-}"
    local request_id="${5:-$(generate_request_id)}"

    echo "ERROR: $code"
    echo "$message"

    if [ -n "$details" ]; then
        echo "Details: $details"
    fi

    if [ -n "$resolution" ]; then
        echo ""
        echo "Resolution:"
        echo "$resolution"
    fi

    echo ""
    echo "Request ID: $request_id"
}

# Write error to stderr in text format
# Usage: error_log "error_code" "message" ["details"]
error_log() {
    local code="$1"
    local message="$2"
    local details="${3:-}"

    format_error_text "$code" "$message" "$details" >&2
}

# Write deny decision to decision file
# Usage: write_deny_decision "error_code" "message" ["details"] ["resolution"]
write_deny_decision() {
    local code="$1"
    local message="$2"
    local details="${3:-}"
    local resolution="${4:-}"

    if [ -z "$DECISION_FILE" ]; then
        error_log "oap.system.evaluator_error" "DECISION_FILE not set"
        return 1
    fi

    format_error_json "$code" "$message" "$details" "$resolution" > "$DECISION_FILE" 2> /dev/null || true
}

# Write allow decision to decision file
# Usage: write_allow_decision "message" ["policy_id"]
write_allow_decision() {
    local message="${1:-All policy checks passed}"
    local policy_id="${2:-}"
    local request_id=$(generate_request_id)
    local timestamp=$(generate_timestamp)

    if [ -z "$DECISION_FILE" ]; then
        error_log "oap.system.evaluator_error" "DECISION_FILE not set"
        return 1
    fi

    local decision_json
    decision_json=$(
        cat << EOF
{
  "allow": true,
  "reasons": [{"message": "$message"}],
  "request_id": "$request_id",
  "timestamp": "$timestamp"
}
EOF
    )

    # Add policy_id if provided
    if [ -n "$policy_id" ]; then
        decision_json=$(echo "$decision_json" | jq -c --arg p "$policy_id" '. + {policy_id: $p}')
    fi

    echo "$decision_json" > "$DECISION_FILE" 2> /dev/null || true
}

# Get standard resolution message for error code
# Usage: resolution=$(get_resolution "error_code")
get_resolution() {
    local code="$1"

    case "$code" in
        "$ERROR_INVALID_TOOL_NAME")
            echo "Use only alphanumeric characters, dots, underscores, and hyphens in tool names. Keep tool names under 128 characters."
            ;;
        "$ERROR_CONTEXT_TOO_LARGE")
            echo "Reduce context data size by removing unnecessary fields or summarizing large data. Default limit: 100KB."
            ;;
        "$ERROR_PATH_NOT_ALLOWED")
            echo "Use standard APort directories: ~/.openclaw/, ~/.aport/, or /tmp/aport-*. Contact administrator to add custom allowed directories."
            ;;
        "$ERROR_PATH_TRAVERSAL")
            echo "Use absolute paths without parent directory references (../ or /..). This is a security feature to prevent path traversal attacks."
            ;;
        "$ERROR_PASSPORT_NOT_FOUND")
            echo "Create a passport by running: npx @aporthq/agent-guardrails openclaw. See: https://github.com/aporthq/agent-guardrails#passport-setup"
            ;;
        "$ERROR_PASSPORT_MISSING_CAP")
            echo "Request capability be added to passport or generate new passport with required capabilities."
            ;;
        "$ERROR_POLICY_NOT_FOUND")
            echo "Verify policy pack ID is correct and update policy submodule: git submodule update --init --recursive"
            ;;
        "$ERROR_API_CONNECTION")
            echo "Check internet connectivity, verify API URL (APORT_API_URL), and check firewall allows outbound HTTPS."
            ;;
        "$ERROR_API_AUTH")
            echo "Verify API key is set (APORT_API_KEY) and generate new API key if needed from APort dashboard."
            ;;
        "$ERROR_API_RATE_LIMIT")
            echo "Wait for rate limit to reset, reduce request frequency, or use local evaluation mode instead of API mode."
            ;;
        "$ERROR_MISCONFIGURED")
            echo "Run setup: npx @aporthq/agent-guardrails <framework>. Check passport exists at ~/.openclaw/passport.json"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Helper: Write error and exit
# Usage: die "error_code" "message" ["details"]
die() {
    local code="$1"
    local message="$2"
    local details="${3:-}"
    local resolution=$(get_resolution "$code")

    write_deny_decision "$code" "$message" "$details" "$resolution"
    error_log "$code" "$message" "$details"
    exit 1
}

# Validate required command exists
# Usage: require_command "jq"
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command -v "$cmd" > /dev/null 2>&1; then
        local details="{\"command\":\"$cmd\"}"
        local message="Required command not found: $cmd"

        if [ -n "$install_hint" ]; then
            message="$message. Install with: $install_hint"
        fi

        die "$ERROR_DEPENDENCY_MISSING" "$message" "$details"
    fi
}

# Check if decision file is writable
# Usage: check_decision_file_writable
check_decision_file_writable() {
    if [ -z "$DECISION_FILE" ]; then
        error_log "oap.system.evaluator_error" "DECISION_FILE not set"
        return 1
    fi

    local decision_dir=$(dirname "$DECISION_FILE")

    if [ ! -d "$decision_dir" ]; then
        error_log "oap.system.insufficient_permissions" "Decision directory does not exist: $decision_dir"
        return 1
    fi

    if [ ! -w "$decision_dir" ]; then
        error_log "oap.system.insufficient_permissions" "Cannot write to decision directory: $decision_dir"
        return 1
    fi

    return 0
}

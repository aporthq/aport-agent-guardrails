#!/bin/bash
# APort API policy evaluator — calls APort API with agent_id (cloud) or passport (local)
# Supports: APORT_AGENT_ID (registry lookup) or local passport file (sent in request, not stored)
# Usage: aport-guardrail-api.sh <tool_name> '<context_json>'
#
# Endpoint (self-hosted / private instance):
#   export APORT_API_URL="https://api.aport.io"   # default; or your self-hosted API
#   export APORT_API_URL="https://api.aport.io"    # default cloud
#   export APORT_API_URL="https://your-private.aport.example"

set -e

# Trap any unhandled error so the caller hook can include the reason in the
# user-facing deny message instead of seeing an empty stderr.
# shellcheck disable=SC2317
__aport_api_crash_handler() {
    local exit_code="$?"
    local line_no="$1"
    echo "APort API guardrail crashed (exit=${exit_code} at aport-guardrail-api.sh:${line_no})." >&2
    exit 1
}
trap '__aport_api_crash_handler "$LINENO"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolve paths: config_dir/aport/ (new) or config_dir (legacy); same as bash guardrail
# shellcheck source=bin/aport-resolve-paths.sh
. "${SCRIPT_DIR}/bin/aport-resolve-paths.sh"
# shellcheck source=bin/lib/tool-mapping.sh
. "${SCRIPT_DIR}/bin/lib/tool-mapping.sh"
# shellcheck source=bin/lib/validation.sh
. "${SCRIPT_DIR}/bin/lib/validation.sh"

NODE_EVALUATOR="$SCRIPT_DIR/src/evaluator.js"

TOOL_NAME="$1"
DEFAULT_CONTEXT='{}'
CONTEXT_JSON="${2:-$DEFAULT_CONTEXT}"

# DEBUG: Print received arguments
if [ -n "$DEBUG_APORT" ]; then
    echo "DEBUG: TOOL_NAME=$TOOL_NAME" >&2
    echo "DEBUG: CONTEXT_JSON=$(sanitize_log_value "$CONTEXT_JSON" context)" >&2
fi

# Ensure APort data dir exists (for decision, audit)
mkdir -p "$(dirname "$AUDIT_LOG")"

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo "Error: node is required but not installed. Install with: brew install node" >&2
    exit 1
fi

# Check if evaluator exists
if [ ! -f "$NODE_EVALUATOR" ]; then
    echo "Error: Node.js evaluator not found at $NODE_EVALUATOR" >&2
    exit 1
fi

# Passport handling for hosted/API mode:
#   - Cloud mode (APORT_AGENT_ID set): API fetches the passport by agent_id from
#     the registry. NO local passport file is required or read.
#   - Local-in-request mode (passport sent in body): require the local passport
#     file so evaluator.js can include it in the request body.
# Do NOT require both. The previous behavior demanded a local passport even
# when running purely against the hosted API, which forced every cloud-mode
# user to create a local file they did not actually need.
if [ -n "$APORT_AGENT_ID" ]; then
    # Cloud mode: passport is server-side, nothing to check locally.
    :
elif [ -f "$PASSPORT_FILE" ]; then
    # Local-in-request mode: passport will be loaded by evaluator.js.
    :
else
    echo "Error: Hosted/API guardrail requires either APORT_AGENT_ID (cloud mode, recommended for hosted) or a local passport at $PASSPORT_FILE (local-in-request mode). Neither is configured. To use hosted mode without a local passport, export APORT_AGENT_ID. To use local-in-request mode, run aport-create-passport.sh." >&2
    exit 1
fi

# Map tool to policy pack ID from the shared JSON source of truth.
POLICY_ID="$(resolve_policy_id_from_tool_name "$TOOL_NAME" || true)"
if [[ -z "$POLICY_ID" ]]; then
    echo "Error: Tool '$TOOL_NAME' is not mapped to a policy pack" >&2
    exit 1
fi

# Call Node.js evaluator with API
if [ -n "$DEBUG_APORT" ]; then
    echo "DEBUG: Calling Node.js evaluator with policy $POLICY_ID" >&2
fi

# Export environment variables for evaluator (APORT_API_URL, APORT_AGENT_ID, APORT_API_KEY passed through)
export APORT_PASSPORT_FILE="$PASSPORT_FILE"
export APORT_DECISION_FILE="$DECISION_FILE"
export OPENCLAW_PASSPORT_FILE="$PASSPORT_FILE"
export OPENCLAW_DECISION_FILE="$DECISION_FILE"

# Call evaluator and capture exit code. A non-zero exit is the expected deny/API
# failure signal and must not trigger the ERR trap before audit/reason handling.
set +e
trap - ERR
node "$NODE_EVALUATOR" "$POLICY_ID" "$CONTEXT_JSON"
EXIT_CODE=$?
set -e
trap '__aport_api_crash_handler "$LINENO"' ERR

# Log to audit trail (include deny message so audit.log is debuggable on its own)
if [ -f "$DECISION_FILE" ]; then
    DECISION_ID=$(jq -r '.decision_id // "unknown"' "$DECISION_FILE" 2> /dev/null || echo "unknown")
    ALLOW=$(jq -r '.allow // false' "$DECISION_FILE" 2> /dev/null || echo "false")
    DENY_CODE=$(jq -r '.reasons[0].code // "unknown"' "$DECISION_FILE" 2> /dev/null || echo "unknown")
    DENY_MSG=$(jq -r '.reasons[0].message // ""' "$DECISION_FILE" 2> /dev/null | tr '\n' ' ' | head -c 200 | sed 's/"/\\"/g')
    DENY_MSG="$(sanitize_log_value "$DENY_MSG" reason)"
    AUDIT_LINE="[$(date -u +%Y-%m-%d\ %H:%M:%S)] tool=$TOOL_NAME decision_id=$DECISION_ID allow=$ALLOW policy=$POLICY_ID code=$DENY_CODE"
    [ -n "$DENY_MSG" ] && AUDIT_LINE="${AUDIT_LINE} reason=\"$DENY_MSG\""
    echo "$AUDIT_LINE" >> "$AUDIT_LOG" 2> /dev/null || true
fi

# Surface the deny reason on stderr so the caller hook can include it in the
# user-facing message. Without this, hooks that captured stderr saw nothing
# meaningful when the API denied the action.
if [ "$EXIT_CODE" -ne 0 ] && [ -f "$DECISION_FILE" ]; then
    REASON_MSG=$(jq -r '.reasons[0].message // empty' "$DECISION_FILE" 2> /dev/null)
    REASON_CODE=$(jq -r '.reasons[0].code // empty' "$DECISION_FILE" 2> /dev/null)
    if [ -n "$REASON_MSG" ] || [ -n "$REASON_CODE" ]; then
        echo "APort deny ($(sanitize_log_value "${REASON_CODE:-unknown}" code)): $(sanitize_log_value "${REASON_MSG:-no message}" reason)" >&2
    fi
fi

exit $EXIT_CODE

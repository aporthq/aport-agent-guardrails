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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolve paths: config_dir/aport/ (new) or config_dir (legacy); same as bash guardrail
# shellcheck source=bin/aport-resolve-paths.sh
. "${SCRIPT_DIR}/bin/aport-resolve-paths.sh"
# shellcheck source=bin/lib/tool-mapping.sh
. "${SCRIPT_DIR}/bin/lib/tool-mapping.sh"

NODE_EVALUATOR="$SCRIPT_DIR/src/evaluator.js"

TOOL_NAME="$1"
DEFAULT_CONTEXT='{}'
CONTEXT_JSON="${2:-$DEFAULT_CONTEXT}"

# DEBUG: Print received arguments
if [ -n "$DEBUG_APORT" ]; then
    echo "DEBUG: TOOL_NAME=$TOOL_NAME" >&2
    echo "DEBUG: CONTEXT_JSON=$CONTEXT_JSON" >&2
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

# Passport required only for local mode (passport in request). Cloud mode uses APORT_AGENT_ID.
if [ -z "$APORT_AGENT_ID" ] && [ ! -f "$PASSPORT_FILE" ]; then
    echo "Error: Passport file not found at $PASSPORT_FILE. Create one with aport-create-passport.sh, or set APORT_AGENT_ID for cloud mode." >&2
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
export OPENCLAW_PASSPORT_FILE="$PASSPORT_FILE"
export OPENCLAW_DECISION_FILE="$DECISION_FILE"

# Call evaluator and capture exit code
node "$NODE_EVALUATOR" "$POLICY_ID" "$CONTEXT_JSON"
EXIT_CODE=$?

# Log to audit trail
if [ -f "$DECISION_FILE" ]; then
    DECISION_ID=$(jq -r '.decision_id // "unknown"' "$DECISION_FILE")
    ALLOW=$(jq -r '.allow // false' "$DECISION_FILE")
    DENY_CODE=$(jq -r '.reasons[0].code // "unknown"' "$DECISION_FILE")
    echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] tool=$TOOL_NAME decision_id=$DECISION_ID allow=$ALLOW policy=$POLICY_ID code=$DENY_CODE" >> "$AUDIT_LOG"
fi

exit $EXIT_CODE

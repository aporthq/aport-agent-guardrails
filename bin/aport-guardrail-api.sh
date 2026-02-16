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

PASSPORT_FILE="${OPENCLAW_PASSPORT_FILE:-$HOME/.openclaw/passport.json}"
DECISION_FILE="${OPENCLAW_DECISION_FILE:-$HOME/.openclaw/decision.json}"
AUDIT_LOG="${OPENCLAW_AUDIT_LOG:-$HOME/.openclaw/audit.log}"
KILL_SWITCH="${OPENCLAW_KILL_SWITCH:-$HOME/.openclaw/kill-switch}"

# Get script directory to find Node.js evaluator
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_EVALUATOR="$SCRIPT_DIR/src/evaluator.js"

TOOL_NAME="$1"
DEFAULT_CONTEXT='{}'
CONTEXT_JSON="${2:-$DEFAULT_CONTEXT}"

# DEBUG: Print received arguments
if [ -n "$DEBUG_APORT" ]; then
    echo "DEBUG: TOOL_NAME=$TOOL_NAME" >&2
    echo "DEBUG: CONTEXT_JSON=$CONTEXT_JSON" >&2
fi

# Ensure audit log directory exists
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

# Check kill switch first (highest priority)
if [ -f "$KILL_SWITCH" ]; then
    echo "Error: Global kill switch is active. Remove $KILL_SWITCH to resume." >&2
    exit 1
fi

# Passport required only for local mode (passport in request). Cloud mode uses APORT_AGENT_ID.
if [ -z "$APORT_AGENT_ID" ] && [ ! -f "$PASSPORT_FILE" ]; then
    echo "Error: Passport file not found at $PASSPORT_FILE. Create one with aport-create-passport.sh, or set APORT_AGENT_ID for cloud mode." >&2
    exit 1
fi

# Map tool to policy pack ID
POLICY_ID=""
case "$TOOL_NAME" in
    git.create_pr|git.merge|git.push|git.*)
        POLICY_ID="code.repository.merge.v1"
        ;;
    exec.run|exec.*|system.command.*|system.*)
        POLICY_ID="system.command.execute.v1"
        ;;
    message.send|message.*|messaging.*)
        POLICY_ID="messaging.message.send.v1"
        ;;
    mcp.tool.*|mcp.*)
        POLICY_ID="mcp.tool.execute.v1"
        ;;
    agent.session.*|session.create|session.*)
        POLICY_ID="agent.session.create.v1"
        ;;
    agent.tool.*|tool.register|tool.*)
        POLICY_ID="agent.tool.register.v1"
        ;;
    payment.refund|payment.*|finance.payment.refund)
        POLICY_ID="finance.payment.refund.v1"
        ;;
    payment.charge|finance.payment.charge)
        POLICY_ID="finance.payment.charge.v1"
        ;;
    database.write|database.*|data.export)
        POLICY_ID="data.export.create.v1"
        ;;
    *)
        echo "Error: Tool '$TOOL_NAME' is not mapped to a policy pack" >&2
        exit 1
        ;;
esac

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

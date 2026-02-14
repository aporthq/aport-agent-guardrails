#!/bin/bash
# APort Local Policy Evaluator for OpenClaw
# Evaluates OAP v1.0 policies locally without cloud API
# Usage: aport-guardrail.sh <tool_name> '<context_json>'

set -e

PASSPORT_FILE="${OPENCLAW_PASSPORT_FILE:-$HOME/.openclaw/passport.json}"
DECISION_FILE="${OPENCLAW_DECISION_FILE:-$HOME/.openclaw/decision.json}"
AUDIT_LOG="${OPENCLAW_AUDIT_LOG:-$HOME/.openclaw/audit.log}"
KILL_SWITCH="${OPENCLAW_KILL_SWITCH:-$HOME/.openclaw/kill-switch}"

TOOL_NAME="$1"
CONTEXT_JSON="${2:-{}}"

# Ensure audit log directory exists
mkdir -p "$(dirname "$AUDIT_LOG")"

# Function to write decision and exit
write_decision() {
    local allow="$1"
    local reason="$2"
    local message="${3:-}"
    local decision_id=$(uuidgen 2>/dev/null || date +%s)
    
    local decision="{\"allow\": $allow, \"decision_id\": \"$decision_id\", \"reason\": \"$reason\""
    if [ -n "$message" ]; then
        decision="$decision, \"message\": $(echo "$message" | jq -R .)"
    fi
    decision="$decision}"
    
    echo "$decision" | jq . > "$DECISION_FILE"
    
    # Log to audit trail
    echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] tool=$TOOL_NAME decision_id=$decision_id allow=$allow reason=$reason" >> "$AUDIT_LOG"
    
    if [ "$allow" = "true" ]; then
        exit 0
    else
        exit 1
    fi
}

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Install with: brew install jq" >&2
    write_decision false "missing_dependency" "jq not found"
fi

# Check kill switch first (highest priority)
if [ -f "$KILL_SWITCH" ]; then
    write_decision false "kill_switch_active" "Global kill switch is active. Remove $KILL_SWITCH to resume."
fi

# Load passport
if [ ! -f "$PASSPORT_FILE" ]; then
    write_decision false "passport_not_found" "Passport file not found at $PASSPORT_FILE. Create one with aport-create-passport.sh"
fi

PASSPORT=$(cat "$PASSPORT_FILE")

# Validate passport JSON
if ! echo "$PASSPORT" | jq . > /dev/null 2>&1; then
    write_decision false "passport_invalid" "Passport file contains invalid JSON"
fi

# Check passport status
STATUS=$(echo "$PASSPORT" | jq -r '.status // "unknown"')
if [ "$STATUS" != "active" ]; then
    write_decision false "passport_suspended" "Passport status is '$STATUS', not 'active'"
fi

# Check spec version
SPEC_VERSION=$(echo "$PASSPORT" | jq -r '.spec_version // "unknown"')
if [ "$SPEC_VERSION" != "oap/1.0" ]; then
    write_decision false "passport_version_mismatch" "Passport spec version is '$SPEC_VERSION', expected 'oap/1.0'"
fi

# Map tool to policy pack
POLICY=""
case "$TOOL_NAME" in
    git.create_pr|git.merge|git.push)
        POLICY="code.repository.merge"
        ;;
    exec.run|exec.*|system.*)
        POLICY="system.command.execute"
        ;;
    message.send|message.*|messaging.*)
        POLICY="messaging.message.send"
        ;;
    payment.*|finance.*)
        POLICY="finance.payment.refund"
        ;;
    database.write|database.insert|database.update|database.delete|data.export)
        POLICY="data.export"
        ;;
    *)
        # Unknown tool - deny by default for security
        write_decision false "unknown_tool" "Tool '$TOOL_NAME' is not mapped to a policy pack"
        ;;
esac

# Check if capability exists
HAS_CAPABILITY=false
CAPABILITIES=$(echo "$PASSPORT" | jq -r '.capabilities[]?.id // empty')
for cap in $CAPABILITIES; do
    if [[ "$cap" == "$POLICY"* ]] || [[ "$cap" == *"$POLICY"* ]]; then
        HAS_CAPABILITY=true
        break
    fi
done

if [ "$HAS_CAPABILITY" = false ]; then
    write_decision false "missing_capability" "Passport does not have required capability for policy '$POLICY'"
fi

# Get policy limits
LIMITS=$(echo "$PASSPORT" | jq ".limits.\"$POLICY\" // {}")

# Evaluate policy-specific limits
if [ "$POLICY" = "code.repository.merge" ]; then
    FILES_CHANGED=$(echo "$CONTEXT_JSON" | jq -r '.files_changed // .files // 0')
    MAX_FILES=$(echo "$LIMITS" | jq -r '.max_pr_size_kb // 500')
    
    if [ "$FILES_CHANGED" -gt "$MAX_FILES" ]; then
        write_decision false "limit_exceeded" "PR size $FILES_CHANGED exceeds limit of $MAX_FILES files"
    fi
    
    # Check allowed repos
    REPO=$(echo "$CONTEXT_JSON" | jq -r '.repo // .repository // ""')
    if [ -n "$REPO" ]; then
        ALLOWED_REPOS=$(echo "$LIMITS" | jq -r '.allowed_repos[]? // empty')
        REPO_ALLOWED=false
        for pattern in $ALLOWED_REPOS; do
            if [[ "$REPO" == $pattern ]] || [[ "$REPO" == */$pattern ]] || [[ "$pattern" == "*" ]]; then
                REPO_ALLOWED=true
                break
            fi
        done
        if [ "$REPO_ALLOWED" = false ] && [ -n "$ALLOWED_REPOS" ]; then
            write_decision false "repo_not_allowed" "Repository '$REPO' is not in allowed list"
        fi
    fi
    
    # Check allowed branches
    BRANCH=$(echo "$CONTEXT_JSON" | jq -r '.branch // ""')
    if [ -n "$BRANCH" ]; then
        ALLOWED_BRANCHES=$(echo "$LIMITS" | jq -r '.allowed_base_branches[]? // empty')
        BRANCH_ALLOWED=false
        for pattern in $ALLOWED_BRANCHES; do
            if [[ "$BRANCH" == $pattern ]] || [[ "$pattern" == "*" ]]; then
                BRANCH_ALLOWED=true
                break
            fi
        done
        if [ "$BRANCH_ALLOWED" = false ] && [ -n "$ALLOWED_BRANCHES" ]; then
            write_decision false "branch_not_allowed" "Branch '$BRANCH' is not in allowed list"
        fi
    fi
fi

if [ "$POLICY" = "system.command.execute" ]; then
    COMMAND=$(echo "$CONTEXT_JSON" | jq -r '.command // .cmd // ""')
    if [ -z "$COMMAND" ]; then
        # Try to extract from args
        COMMAND=$(echo "$CONTEXT_JSON" | jq -r '.args[0] // ""')
    fi
    
    if [ -n "$COMMAND" ]; then
        # Check allowed commands
        ALLOWED=$(echo "$LIMITS" | jq -r '.allowed_commands[]? // empty')
        COMMAND_ALLOWED=false
        for allowed_cmd in $ALLOWED; do
            if [[ "$COMMAND" == "$allowed_cmd"* ]] || [[ "$allowed_cmd" == "*" ]]; then
                COMMAND_ALLOWED=true
                break
            fi
        done
        
        if [ "$COMMAND_ALLOWED" = false ] && [ -n "$ALLOWED" ]; then
            write_decision false "command_not_allowed" "Command '$COMMAND' is not in allowed list"
        fi
        
        # Check blocked patterns
        BLOCKED=$(echo "$LIMITS" | jq -r '.blocked_patterns[]? // empty')
        for pattern in $BLOCKED; do
            if [[ "$COMMAND" == *"$pattern"* ]]; then
                write_decision false "blocked_pattern" "Command contains blocked pattern: $pattern"
            fi
        done
    fi
fi

if [ "$POLICY" = "messaging.message.send" ]; then
    RECIPIENT=$(echo "$CONTEXT_JSON" | jq -r '.recipient // .to // ""')
    if [ -n "$RECIPIENT" ]; then
        ALLOWED_RECIPIENTS=$(echo "$LIMITS" | jq -r '.allowed_recipients[]? // empty')
        RECIPIENT_ALLOWED=false
        for allowed in $ALLOWED_RECIPIENTS; do
            if [ "$RECIPIENT" = "$allowed" ] || [[ "$allowed" == "*" ]]; then
                RECIPIENT_ALLOWED=true
                break
            fi
        done
        if [ "$RECIPIENT_ALLOWED" = false ] && [ -n "$ALLOWED_RECIPIENTS" ]; then
            write_decision false "recipient_not_allowed" "Recipient '$RECIPIENT' is not in allowed list"
        fi
    fi
fi

# All checks passed - allow
DECISION_ID=$(uuidgen 2>/dev/null || echo "local-$(date +%s)")
echo "{\"allow\": true, \"decision_id\": \"$DECISION_ID\", \"policy\": \"$POLICY\", \"tool\": \"$TOOL_NAME\"}" | jq . > "$DECISION_FILE"

# Log to audit trail
echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] tool=$TOOL_NAME decision_id=$DECISION_ID allow=true policy=$POLICY" >> "$AUDIT_LOG"

exit 0

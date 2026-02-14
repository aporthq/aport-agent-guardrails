#!/bin/bash
# APort Local Policy Evaluator for OpenClaw
# Evaluates OAP v1.0 policies locally without cloud API
# Usage: aport-guardrail.sh <tool_name> '<context_json>'

set -e

PASSPORT_FILE="${OPENCLAW_PASSPORT_FILE:-$HOME/.openclaw/passport.json}"
DECISION_FILE="${OPENCLAW_DECISION_FILE:-$HOME/.openclaw/decision.json}"
AUDIT_LOG="${OPENCLAW_AUDIT_LOG:-$HOME/.openclaw/audit.log}"
KILL_SWITCH="${OPENCLAW_KILL_SWITCH:-$HOME/.openclaw/kill-switch}"

# Get script directory to find submodules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICIES_DIR="$SCRIPT_DIR/policies-upstream"
LOCAL_POLICIES_DIR="$SCRIPT_DIR/local-overrides/policies"

TOOL_NAME="$1"
CONTEXT_JSON="${2:-{}}"

# Ensure audit log directory exists
mkdir -p "$(dirname "$AUDIT_LOG")"

# Function to load policy from upstream or local-overrides
load_policy() {
    local policy_id="$1"
    local policy_file=""

    # Try official policy from submodule first
    if [ -f "$POLICIES_DIR/${policy_id}.v1/policy.json" ]; then
        policy_file="$POLICIES_DIR/${policy_id}.v1/policy.json"
    elif [ -f "$LOCAL_POLICIES_DIR/${policy_id}.v1.json" ]; then
        policy_file="$LOCAL_POLICIES_DIR/${policy_id}.v1.json"
    fi

    if [ -n "$policy_file" ] && [ -f "$policy_file" ]; then
        cat "$policy_file"
    else
        echo "{}"
    fi
}

# Function to compute JCS-canonicalized SHA-256 digest
compute_passport_digest() {
    local passport_file="$1"
    echo "sha256:$(jq --sort-keys -c . "$passport_file" | shasum -a 256 | awk '{print $1}')"
}

# Function to build OAP v1.0 compliant decision and exit
write_decision() {
    local allow="$1"
    local policy_id="${2:-unknown}"
    local deny_code="${3:-oap.policy_error}"
    local deny_message="${4:-Policy evaluation failed}"

    local decision_id=$(uuidgen 2>/dev/null || echo "local-$(date +%s)")
    local passport_id=$(jq -r '.passport_id // "unknown"' "$PASSPORT_FILE")
    local owner_id=$(jq -r '.owner_id // "unknown"' "$PASSPORT_FILE")
    local assurance_level=$(jq -r '.assurance_level // "L0"' "$PASSPORT_FILE")
    local passport_digest=$(compute_passport_digest "$PASSPORT_FILE")
    local issued_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local expires_at=$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)

    # Build reasons array per OAP v1.0 spec
    local reasons
    if [ "$allow" = "true" ]; then
        reasons='[{"code": "oap.allowed", "message": "All policy checks passed"}]'
    else
        reasons="[{\"code\": \"$deny_code\", \"message\": \"$deny_message\"}]"
    fi

    # Build OAP v1.0 compliant decision object
    cat > "$DECISION_FILE" <<EOF
{
  "decision_id": "$decision_id",
  "policy_id": "$policy_id",
  "passport_id": "$passport_id",
  "owner_id": "$owner_id",
  "assurance_level": "$assurance_level",
  "allow": $allow,
  "reasons": $reasons,
  "issued_at": "$issued_at",
  "expires_at": "$expires_at",
  "passport_digest": "$passport_digest",
  "signature": "ed25519:local-unsigned",
  "kid": "oap:local:dev-key"
}
EOF

    # Log to audit trail
    echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] tool=$TOOL_NAME decision_id=$decision_id allow=$allow policy=$policy_id code=$deny_code" >> "$AUDIT_LOG"

    if [ "$allow" = "true" ]; then
        exit 0
    else
        exit 1
    fi
}

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Install with: brew install jq" >&2
    write_decision false "unknown" "oap.missing_dependency" "jq not found"
fi

# Check kill switch first (highest priority)
if [ -f "$KILL_SWITCH" ]; then
    write_decision false "unknown" "oap.kill_switch_active" "Global kill switch is active. Remove $KILL_SWITCH to resume."
fi

# Load passport
if [ ! -f "$PASSPORT_FILE" ]; then
    write_decision false "unknown" "oap.passport_not_found" "Passport file not found at $PASSPORT_FILE. Create one with aport-create-passport.sh"
fi

PASSPORT=$(cat "$PASSPORT_FILE")

# Validate passport JSON
if ! echo "$PASSPORT" | jq . > /dev/null 2>&1; then
    write_decision false "unknown" "oap.passport_invalid" "Passport file contains invalid JSON"
fi

# Check passport status
STATUS=$(echo "$PASSPORT" | jq -r '.status // "unknown"')
if [ "$STATUS" != "active" ]; then
    write_decision false "unknown" "oap.passport_suspended" "Passport status is '$STATUS', not 'active'"
fi

# Check spec version
SPEC_VERSION=$(echo "$PASSPORT" | jq -r '.spec_version // "unknown"')
if [ "$SPEC_VERSION" != "oap/1.0" ]; then
    write_decision false "unknown" "oap.passport_version_mismatch" "Passport spec version is '$SPEC_VERSION', expected 'oap/1.0'"
fi

# Map tool to policy pack ID
POLICY_ID=""
case "$TOOL_NAME" in
    git.create_pr|git.merge|git.push)
        POLICY_ID="code.repository.merge.v1"
        ;;
    exec.run|exec.*|system.*)
        POLICY_ID="system.command.execute.v1"
        ;;
    message.send|message.*|messaging.*)
        POLICY_ID="messaging.message.send.v1"
        ;;
    payment.*|finance.*)
        POLICY_ID="finance.payment.refund.v1"
        ;;
    database.write|database.insert|database.update|database.delete|data.export)
        POLICY_ID="data.export.v1"
        ;;
    *)
        # Unknown tool - deny by default for security
        write_decision false "unknown" "oap.unknown_capability" "Tool '$TOOL_NAME' is not mapped to a policy pack"
        ;;
esac

# Load policy definition
POLICY_DEF=$(load_policy "$(echo "$POLICY_ID" | sed 's/\.v[0-9]*$//')")

# Check if capability exists in passport
HAS_CAPABILITY=false
CAPABILITIES=$(echo "$PASSPORT" | jq -r '.capabilities[]?.id // empty')
REQUIRED_CAP=$(echo "$POLICY_ID" | sed 's/\.v[0-9]*$//')
for cap in $CAPABILITIES; do
    if [[ "$cap" == "$REQUIRED_CAP"* ]] || [[ "$cap" == *"$REQUIRED_CAP"* ]]; then
        HAS_CAPABILITY=true
        break
    fi
done

if [ "$HAS_CAPABILITY" = false ]; then
    write_decision false "$POLICY_ID" "oap.unknown_capability" "Passport does not have required capability for policy '$POLICY_ID'"
fi

# Get policy limits from passport
POLICY_BASE=$(echo "$POLICY_ID" | sed 's/\.v[0-9]*$//')
LIMITS=$(echo "$PASSPORT" | jq ".limits.\"$POLICY_BASE\" // {}")

# Evaluate policy-specific limits
if [[ "$POLICY_ID" == "code.repository.merge"* ]]; then
    FILES_CHANGED=$(echo "$CONTEXT_JSON" | jq -r '.files_changed // .files // 0')
    MAX_FILES=$(echo "$LIMITS" | jq -r '.max_pr_size_kb // 500')

    if [ "$FILES_CHANGED" -gt "$MAX_FILES" ]; then
        write_decision false "$POLICY_ID" "oap.limit_exceeded" "PR size $FILES_CHANGED exceeds limit of $MAX_FILES files"
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
            write_decision false "$POLICY_ID" "oap.repo_not_allowed" "Repository '$REPO' is not in allowed list"
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
            write_decision false "$POLICY_ID" "oap.branch_not_allowed" "Branch '$BRANCH' is not in allowed list"
        fi
    fi
fi

if [[ "$POLICY_ID" == "system.command.execute"* ]]; then
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
            write_decision false "$POLICY_ID" "oap.command_not_allowed" "Command '$COMMAND' is not in allowed list"
        fi

        # Check blocked patterns
        BLOCKED=$(echo "$LIMITS" | jq -r '.blocked_patterns[]? // empty')
        for pattern in $BLOCKED; do
            if [[ "$COMMAND" == *"$pattern"* ]]; then
                write_decision false "$POLICY_ID" "oap.blocked_pattern" "Command contains blocked pattern: $pattern"
            fi
        done
    fi
fi

if [[ "$POLICY_ID" == "messaging.message.send"* ]]; then
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
            write_decision false "$POLICY_ID" "oap.recipient_not_allowed" "Recipient '$RECIPIENT' is not in allowed list"
        fi
    fi
fi

# All checks passed - allow
write_decision true "$POLICY_ID" "oap.allowed" "All policy checks passed"

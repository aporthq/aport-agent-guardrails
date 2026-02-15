#!/bin/bash
# APort built-in local policy evaluator (bash, no API)
# Evaluates OAP v1.0 policies locally without any network call
# Usage: aport-guardrail-bash.sh <tool_name> '<context_json>'

set -e

PASSPORT_FILE="${OPENCLAW_PASSPORT_FILE:-$HOME/.openclaw/passport.json}"
DECISION_FILE="${OPENCLAW_DECISION_FILE:-$HOME/.openclaw/decision.json}"
AUDIT_LOG="${OPENCLAW_AUDIT_LOG:-$HOME/.openclaw/audit.log}"
KILL_SWITCH="${OPENCLAW_KILL_SWITCH:-$HOME/.openclaw/kill-switch}"

# Get script directory to find submodules (external/ per GIT_SUBMODULES_EXPLAINED.md)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICIES_DIR="$SCRIPT_DIR/external/aport-policies"
LOCAL_POLICIES_DIR="$SCRIPT_DIR/local-overrides/policies"

TOOL_NAME="$1"
# Default empty object via variable to avoid bash parsing ${2:-{}} as ${2:-{ + literal }
DEFAULT_CONTEXT='{}'
CONTEXT_JSON="${2:-$DEFAULT_CONTEXT}"

# DEBUG: Print received arguments
if [ -n "$DEBUG_APORT" ]; then
    echo "DEBUG: TOOL_NAME=$TOOL_NAME" >&2
    echo "DEBUG: CONTEXT_JSON=$CONTEXT_JSON" >&2
    echo "DEBUG: CONTEXT length=${#CONTEXT_JSON}" >&2
fi

# Ensure audit log directory exists
mkdir -p "$(dirname "$AUDIT_LOG")"

# Function to load policy from upstream or local-overrides
load_policy() {
    local policy_base="$1"
    local policy_file=""

    # Try official policy from submodule first (with .v1, .v2, etc)
    for version_dir in "$POLICIES_DIR/${policy_base}".v*/; do
        if [ -f "${version_dir}policy.json" ]; then
            policy_file="${version_dir}policy.json"
            break
        fi
    done

    # Fallback to local overrides
    if [ -z "$policy_file" ] || [ ! -f "$policy_file" ]; then
        for local_file in "$LOCAL_POLICIES_DIR/${policy_base}".v*.json; do
            if [ -f "$local_file" ]; then
                policy_file="$local_file"
                break
            fi
        done
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

# Function to build OAP v1.0 compliant decision and exit.
# Adds content_hash (tamper-resistant) and optional chain (prev_decision_id, prev_content_hash).
# If a decision file is edited or the chain is reordered, content_hash verification fails.
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

    # Chain state: last decision id and hash for tamper-resistant chain
    local decisions_dir
    decisions_dir="$(dirname "$DECISION_FILE")"
    local chain_state="$decisions_dir/.chain-state.json"
    local prev_decision_id=""
    local prev_content_hash=""
    if [ -f "$chain_state" ]; then
        prev_decision_id=$(jq -r '.last_decision_id // ""' "$chain_state" 2>/dev/null || true)
        prev_content_hash=$(jq -r '.last_content_hash // ""' "$chain_state" 2>/dev/null || true)
    fi

    # Build base decision JSON (no content_hash yet)
    local base_json
    base_json=$(jq -n -c --sort-keys \
        --arg decision_id "$decision_id" \
        --arg policy_id "$policy_id" \
        --arg passport_id "$passport_id" \
        --arg owner_id "$owner_id" \
        --arg assurance_level "$assurance_level" \
        --argjson allow "$allow" \
        --argjson reasons "$reasons" \
        --arg issued_at "$issued_at" \
        --arg expires_at "$expires_at" \
        --arg passport_digest "$passport_digest" \
        --arg prev_decision_id "$prev_decision_id" \
        --arg prev_content_hash "$prev_content_hash" \
        '{
            decision_id: $decision_id,
            policy_id: $policy_id,
            passport_id: $passport_id,
            owner_id: $owner_id,
            assurance_level: $assurance_level,
            allow: $allow,
            reasons: $reasons,
            issued_at: $issued_at,
            expires_at: $expires_at,
            passport_digest: $passport_digest,
            signature: "ed25519:local-unsigned",
            kid: "oap:local:dev-key",
            prev_decision_id: (if $prev_decision_id == "" then null else $prev_decision_id end),
            prev_content_hash: (if $prev_content_hash == "" then null else $prev_content_hash end)
        }')

    # Content hash over canonical form (without content_hash field) — tamper-resistant
    local content_hash
    content_hash="sha256:$(printf '%s' "$base_json" | shasum -a 256 | awk '{print $1}')"

    # Add content_hash and write final decision (critical path — plugin reads this)
    local final_json
    final_json=$(echo "$base_json" | jq -c --arg h "$content_hash" '. + {content_hash: $h}')
    echo "$final_json" > "$DECISION_FILE"

    # Update chain state for next decision (best-effort; do not block or fail the script)
    echo "{\"last_decision_id\":\"$decision_id\",\"last_content_hash\":\"$content_hash\"}" > "$chain_state" 2>/dev/null || true

    # Audit trail is non-core: append in background so it never blocks the tool call
    ( echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] tool=$TOOL_NAME decision_id=$decision_id allow=$allow policy=$policy_id code=$deny_code" >> "$AUDIT_LOG" ) 2>/dev/null &

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

# Check if all required capabilities exist in passport
REQUIRED_CAPS=$(echo "$POLICY_DEF" | jq -r '.requires_capabilities[]? // empty')
PASSPORT_CAPS=$(echo "$PASSPORT" | jq -r '.capabilities[]?.id // empty')

# If policy has required capabilities, check them all
# (Alias: policy "messaging.send" is satisfied by passport "messaging.message.send")
if [ -n "$REQUIRED_CAPS" ]; then
    for req_cap in $REQUIRED_CAPS; do
        HAS_CAP=false
        for passport_cap in $PASSPORT_CAPS; do
            if [ "$passport_cap" = "$req_cap" ]; then
                HAS_CAP=true
                break
            fi
            if [ "$req_cap" = "messaging.send" ] && [ "$passport_cap" = "messaging.message.send" ]; then
                HAS_CAP=true
                break
            fi
        done
        if [ "$HAS_CAP" = false ]; then
            write_decision false "$POLICY_ID" "oap.unknown_capability" "Passport does not have required capability '$req_cap' for policy '$POLICY_ID'"
        fi
    done
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

    # Check allowed repos (use while-read to avoid glob expansion when pattern is *)
    REPO=$(echo "$CONTEXT_JSON" | jq -r '.repo // .repository // ""')
    if [ -n "$REPO" ]; then
        REPO_ALLOWED=false
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            if [[ "$REPO" == "$pattern" ]] || [[ "$REPO" == */$pattern ]] || [[ "$pattern" == "*" ]]; then
                REPO_ALLOWED=true
                break
            fi
        done < <(echo "$LIMITS" | jq -r '.allowed_repos[]? // empty')
        HAS_ALLOWED_REPOS=$(echo "$LIMITS" | jq -r '.allowed_repos | length')
        if [ "$REPO_ALLOWED" = false ] && [ "$HAS_ALLOWED_REPOS" -gt 0 ] 2>/dev/null; then
            write_decision false "$POLICY_ID" "oap.repo_not_allowed" "Repository '$REPO' is not in allowed list"
        fi
    fi

    # Check allowed branches (use while-read to avoid glob expansion when pattern is *)
    BRANCH=$(echo "$CONTEXT_JSON" | jq -r '.branch // ""')
    if [ -n "$BRANCH" ]; then
        BRANCH_ALLOWED=false
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            if [[ "$BRANCH" == "$pattern" ]] || [[ "$pattern" == "*" ]]; then
                BRANCH_ALLOWED=true
                break
            fi
        done < <(echo "$LIMITS" | jq -r '.allowed_base_branches[]? // empty')
        HAS_ALLOWED_BRANCHES=$(echo "$LIMITS" | jq -r '.allowed_base_branches | length')
        if [ "$BRANCH_ALLOWED" = false ] && [ "$HAS_ALLOWED_BRANCHES" -gt 0 ] 2>/dev/null; then
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
        # Check allowed commands (use while-read so "*" is not glob-expanded)
        COMMAND_ALLOWED=false
        while IFS= read -r allowed_cmd; do
            [ -z "$allowed_cmd" ] && continue
            if [[ "$COMMAND" == "$allowed_cmd"* ]] || [[ "$allowed_cmd" == "*" ]]; then
                COMMAND_ALLOWED=true
                break
            fi
        done < <(echo "$LIMITS" | jq -r '.allowed_commands[]? // empty')
        HAS_ALLOWED=$(echo "$LIMITS" | jq -r '.allowed_commands | length')
        if [ "$COMMAND_ALLOWED" = false ] && [ "${HAS_ALLOWED:-0}" -gt 0 ] 2>/dev/null; then
            write_decision false "$POLICY_ID" "oap.command_not_allowed" "Command '$COMMAND' is not in allowed list"
        fi

        # Check blocked patterns (use while-read so patterns are not glob-expanded)
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            if [[ "$COMMAND" == *"$pattern"* ]]; then
                write_decision false "$POLICY_ID" "oap.blocked_pattern" "Command contains blocked pattern: $pattern"
                break
            fi
        done < <(echo "$LIMITS" | jq -r '.blocked_patterns[]? // empty')
    fi
fi

if [[ "$POLICY_ID" == "messaging.message.send"* ]]; then
    RECIPIENT=$(echo "$CONTEXT_JSON" | jq -r '.recipient // .to // ""')
    if [ -n "$RECIPIENT" ]; then
        RECIPIENT_ALLOWED=false
        while IFS= read -r allowed; do
            [ -z "$allowed" ] && continue
            if [ "$RECIPIENT" = "$allowed" ] || [ "$allowed" = "*" ]; then
                RECIPIENT_ALLOWED=true
                break
            fi
        done < <(echo "$LIMITS" | jq -r '.allowed_recipients[]? // empty')
        HAS_ALLOWED=$(echo "$LIMITS" | jq -r '.allowed_recipients | length')
        if [ "$RECIPIENT_ALLOWED" = false ] && [ "${HAS_ALLOWED:-0}" -gt 0 ] 2>/dev/null; then
            write_decision false "$POLICY_ID" "oap.recipient_not_allowed" "Recipient '$RECIPIENT' is not in allowed list"
        fi
    fi
fi

# All checks passed - allow
write_decision true "$POLICY_ID" "oap.allowed" "All policy checks passed"

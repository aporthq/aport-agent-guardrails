#!/bin/bash
# APort built-in local policy evaluator (bash, no API)
# Evaluates OAP v1.0 policies locally without any network call
# Usage: aport-guardrail-bash.sh <tool_name> '<context_json>'

set -e

# Trap unexpected exits so the caller never sees a silent failure. Writes a
# minimal decision file (best-effort) and emits the reason on stderr so the
# Claude Code / Cursor hook can include it in the user-facing deny message.
# shellcheck disable=SC2317
__aport_bash_crash_handler() {
    local exit_code="$?"
    local line_no="$1"
    local script_name
    script_name="$(basename "${BASH_SOURCE[0]:-aport-guardrail-bash}")"
    local message="APort local evaluator crashed (exit=${exit_code} at ${script_name}:${line_no})."
    echo "$message" >&2
    if [ -n "${DECISION_FILE:-}" ] && command -v jq > /dev/null 2>&1; then
        local fallback
        fallback="$(jq -n --arg msg "$message" \
            '{decision_id:"local-crash",allow:false,reasons:[{code:"oap.evaluator_crash",message:$msg}]}' 2> /dev/null)"
        [ -n "$fallback" ] && printf '%s' "$fallback" > "$DECISION_FILE" 2> /dev/null || true
    fi
    exit 1
}
trap '__aport_bash_crash_handler "$LINENO"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolve paths: config_dir/aport/ (new) or config_dir (legacy)
# shellcheck source=bin/aport-resolve-paths.sh
. "${SCRIPT_DIR}/bin/aport-resolve-paths.sh"

# Source validation library for input sanitization
# shellcheck source=bin/lib/validation.sh
. "${SCRIPT_DIR}/bin/lib/validation.sh"
# shellcheck source=bin/lib/tool-mapping.sh
. "${SCRIPT_DIR}/bin/lib/tool-mapping.sh"

# Get script directory to find submodules (external/ per GIT_SUBMODULES_EXPLAINED.md)
POLICIES_DIR="$SCRIPT_DIR/external/aport-policies"
LOCAL_POLICIES_DIR="$SCRIPT_DIR/local-overrides/policies"

TOOL_NAME="$1"
# Default empty object via variable to avoid bash parsing ${2:-{}} as ${2:-{ + literal }
DEFAULT_CONTEXT='{}'
CONTEXT_JSON="${2:-$DEFAULT_CONTEXT}"

# SECURITY: Validate tool name to prevent injection attacks
if ! validate_tool_name "$TOOL_NAME"; then
    echo '{"allow":false,"reasons":[{"code":"oap.invalid_tool_name","message":"Tool name contains invalid characters or format"}]}' > "$DECISION_FILE" 2> /dev/null || true
    exit 1
fi

# SECURITY: Validate JSON context size to prevent DoS
if ! validate_json_size "$CONTEXT_JSON"; then
    echo '{"allow":false,"reasons":[{"code":"oap.context_too_large","message":"Context JSON exceeds maximum size"}]}' > "$DECISION_FILE" 2> /dev/null || true
    exit 1
fi

# DEBUG: Print received arguments (sanitized to prevent leaking sensitive data)
if [ -n "$DEBUG_APORT" ]; then
    echo "DEBUG: TOOL_NAME=$TOOL_NAME" >&2
    # SECURITY: Sanitize context JSON to prevent logging sensitive data
    SANITIZED_CONTEXT=$(sanitize_log_value "$CONTEXT_JSON" "context")
    echo "DEBUG: CONTEXT_JSON=$SANITIZED_CONTEXT" >&2
    echo "DEBUG: CONTEXT length=${#CONTEXT_JSON}" >&2
fi

# Ensure APort data dir exists (for decision.json, audit.log) with restricted permissions
mkdir -p "$(dirname "$AUDIT_LOG")"
chmod 700 "$(dirname "$AUDIT_LOG")" 2> /dev/null || true

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

    local decision_id=$(uuidgen 2> /dev/null || echo "local-$(date +%s)")
    local passport_id=$(jq -r '.passport_id // .agent_id // "unknown"' "$PASSPORT_FILE")
    local agent_id=$(jq -r '.agent_id // .passport_id // "unknown"' "$PASSPORT_FILE")
    local owner_id=$(jq -r '.owner_id // "unknown"' "$PASSPORT_FILE")
    local assurance_level=$(jq -r '.assurance_level // "L0"' "$PASSPORT_FILE")
    local passport_digest=$(compute_passport_digest "$PASSPORT_FILE")
    local issued_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local created_at="$issued_at"
    local expires_in=3600
    local expires_at=$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ 2> /dev/null || date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)

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
        prev_decision_id=$(jq -r '.last_decision_id // ""' "$chain_state" 2> /dev/null || true)
        prev_content_hash=$(jq -r '.last_content_hash // ""' "$chain_state" 2> /dev/null || true)
    fi

    # Build base decision JSON (no content_hash yet)
    local base_json
    base_json=$(jq -n -c --sort-keys \
        --arg decision_id "$decision_id" \
        --arg policy_id "$policy_id" \
        --arg passport_id "$passport_id" \
        --arg agent_id "$agent_id" \
        --arg owner_id "$owner_id" \
        --arg assurance_level "$assurance_level" \
        --argjson allow "$allow" \
        --argjson reasons "$reasons" \
        --arg issued_at "$issued_at" \
        --arg created_at "$created_at" \
        --arg expires_at "$expires_at" \
        --argjson expires_in "$expires_in" \
        --arg passport_digest "$passport_digest" \
        --arg prev_decision_id "$prev_decision_id" \
        --arg prev_content_hash "$prev_content_hash" \
        '{
            decision_id: $decision_id,
            policy_id: $policy_id,
            passport_id: $passport_id,
            agent_id: $agent_id,
            owner_id: $owner_id,
            assurance_level: $assurance_level,
            allow: $allow,
            reasons: $reasons,
            issued_at: $issued_at,
            created_at: $created_at,
            expires_at: $expires_at,
            expires_in: $expires_in,
            passport_digest: $passport_digest,
            signature: "local-unsigned",
            kid: "oap:local:dev-key",
            verification_mode: "local",
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
    chmod 600 "$DECISION_FILE" 2> /dev/null || true

    # Update chain state for next decision (best-effort; do not block or fail the script)
    echo "{\"last_decision_id\":\"$decision_id\",\"last_content_hash\":\"$content_hash\"}" > "$chain_state" 2> /dev/null || true
    chmod 600 "$chain_state" 2> /dev/null || true

    audit_context=""
    if [ -n "${CONTEXT_SUMMARY:-}" ]; then
        audit_context=" context=\"${CONTEXT_SUMMARY}\""
    fi
    audit_entry="[$(date -u +%Y-%m-%d\ %H:%M:%S)] tool=$TOOL_NAME decision_id=$decision_id allow=$allow policy=$policy_id code=$deny_code${audit_context}"

    if [ "$allow" = "false" ]; then
        echo "$audit_entry" >> "$AUDIT_LOG" 2> /dev/null || true
    else
        (echo "$audit_entry" >> "$AUDIT_LOG") 2> /dev/null &
    fi

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

# Load passport (source of truth; status checked first below)
if [ ! -f "$PASSPORT_FILE" ]; then
    write_decision false "unknown" "oap.passport_not_found" "Passport file not found at $PASSPORT_FILE. Create one with aport-create-passport.sh"
fi

PASSPORT=$(cat "$PASSPORT_FILE")

# Validate passport JSON
if ! echo "$PASSPORT" | jq . > /dev/null 2>&1; then
    write_decision false "unknown" "oap.passport_invalid" "Passport file contains invalid JSON"
fi

# Check passport status first (kill switch = suspended/revoked; passport is source of truth per OAP spec)
STATUS=$(echo "$PASSPORT" | jq -r '.status // "unknown"')
if [ "$STATUS" != "active" ]; then
    write_decision false "unknown" "oap.passport_suspended" "Passport status is '$STATUS', not 'active'. Agent suspended."
fi

# Check spec version
SPEC_VERSION=$(echo "$PASSPORT" | jq -r '.spec_version // "unknown"')
if [ "$SPEC_VERSION" != "oap/1.0" ]; then
    write_decision false "unknown" "oap.passport_version_mismatch" "Passport spec version is '$SPEC_VERSION', expected 'oap/1.0'"
fi

# Map tool to policy pack ID from the shared JSON source of truth.
POLICY_ID="$(resolve_policy_id_from_tool_name "$TOOL_NAME" || true)"
if [[ -z "$POLICY_ID" ]]; then
    # Unknown tool - deny by default for security.
    write_decision false "unknown" "oap.unknown_capability" "Tool '$TOOL_NAME' is not mapped to a policy pack"
fi

# Capability-specific context summary for audit log (command, recipient, repo/branch, file_path, etc.)
CONTEXT_SUMMARY=""
if [ -n "$CONTEXT_JSON" ] && [ "$CONTEXT_JSON" != "{}" ]; then
    if [[ "$POLICY_ID" == "system.command.execute"* ]]; then
        CONTEXT_SUMMARY=$(echo "$CONTEXT_JSON" | jq -r '.command // .cmd // .args[0] // ""' 2> /dev/null || true)
    elif [[ "$POLICY_ID" == "messaging.message.send"* ]]; then
        CONTEXT_SUMMARY=$(echo "$CONTEXT_JSON" | jq -r '.recipient // .to // ""' 2> /dev/null || true)
    elif [[ "$POLICY_ID" == "code.repository.merge"* ]]; then
        REPO=$(echo "$CONTEXT_JSON" | jq -r '.repo // .repository // ""' 2> /dev/null || true)
        BRANCH=$(echo "$CONTEXT_JSON" | jq -r '.branch // ""' 2> /dev/null || true)
        [ -n "$REPO" ] && CONTEXT_SUMMARY="$REPO"
        [ -n "$BRANCH" ] && CONTEXT_SUMMARY="${CONTEXT_SUMMARY:+$CONTEXT_SUMMARY }$BRANCH"
    elif [[ "$POLICY_ID" == "data.file.read.v1" ]] || [[ "$POLICY_ID" == "data.file.write.v1" ]]; then
        CONTEXT_SUMMARY=$(echo "$CONTEXT_JSON" | jq -r '.file_path // .path // ""' 2> /dev/null || true)
    elif [[ "$POLICY_ID" == "web.fetch.v1" ]]; then
        CONTEXT_SUMMARY=$(echo "$CONTEXT_JSON" | jq -r '.url // ""' 2> /dev/null || true)
    elif [[ "$POLICY_ID" == "web.browser.v1" ]]; then
        ACTION=$(echo "$CONTEXT_JSON" | jq -r '.action // ""' 2> /dev/null || true)
        URL=$(echo "$CONTEXT_JSON" | jq -r '.url // ""' 2> /dev/null || true)
        [ -n "$ACTION" ] && CONTEXT_SUMMARY="$ACTION"
        [ -n "$URL" ] && CONTEXT_SUMMARY="${CONTEXT_SUMMARY:+$CONTEXT_SUMMARY }$URL"
    elif [[ "$POLICY_ID" == "agent.session.create.v1" ]]; then
        CONTEXT_SUMMARY=$(echo "$CONTEXT_JSON" | jq -r '.session_id // .agent_id // ""' 2> /dev/null || true)
    fi
    # Sanitize for one-line audit: no newlines, truncate, escape double quotes
    if [ -n "$CONTEXT_SUMMARY" ]; then
        CONTEXT_SUMMARY=$(printf '%s' "$CONTEXT_SUMMARY" | tr '\n' ' ' | head -c 120 | sed 's/"/\\"/g')
    fi
fi

# Load policy definition
POLICY_DEF=$(load_policy "$(echo "$POLICY_ID" | sed 's/\.v[0-9]*$//')")

# Check required capabilities. Repository policy is action-dependent: merge
# requires repo.merge, while create/update/push use repo.pr.create. The local
# evaluator stays simple and mirrors hosted semantics without implementing the
# full hosted verifier.
if [[ "$POLICY_ID" == "code.repository.merge"* ]]; then
    _repo_action="$(echo "$CONTEXT_JSON" | jq -r '.action // ""' 2> /dev/null || true)"
    if [ -z "$_repo_action" ]; then
        case "$TOOL_NAME" in
            git.push | *.git.push | *push*) _repo_action="repo.push" ;;
            git.merge | *.git.merge | *merge*) _repo_action="pr.merge" ;;
            *update*) _repo_action="pr.update" ;;
            *) _repo_action="pr.create" ;;
        esac
    fi
    case "$_repo_action" in
        pr.merge | pr.merged | repo.merge) REQUIRED_CAPS="repo.merge" ;;
        *) REQUIRED_CAPS="repo.pr.create" ;;
    esac
else
    REQUIRED_CAPS=$(echo "$POLICY_DEF" | jq -r '.requires_capabilities[]? // empty')
fi
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
            if [ "$req_cap" = "repo.release" ] && [ "$passport_cap" = "release" ]; then
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
# Messaging: API/verifier use flat keys at limits top level; accept nested limits["messaging.message.send"] or flat
if [[ "$POLICY_ID" == "messaging.message.send"* ]]; then
    LIMITS=$(echo "$PASSPORT" | jq '.limits | if .["messaging.message.send"] then .["messaging.message.send"] else {msgs_per_min, msgs_per_day, allowed_recipients, approval_required} end')
elif [[ "$POLICY_ID" == "code.repository.merge"* ]]; then
    LIMITS=$(echo "$PASSPORT" | jq '.limits | if .["code.repository.merge"] then .["code.repository.merge"] else {max_prs_per_day, max_merges_per_day, max_pr_size_kb, allowed_repos, allowed_base_branches, allowed_paths, require_review, daily_repo_pushes} end')
elif [[ "$POLICY_ID" == "code.release.publish"* ]]; then
    LIMITS=$(echo "$PASSPORT" | jq '.limits | if .["code.release.publish"] then .["code.release.publish"] else {allowed_repos, allowed_extensions} end')
else
    LIMITS=$(echo "$PASSPORT" | jq ".limits.\"$POLICY_BASE\" // {}")
fi

is_default_sensitive_read_path() {
    local path_lower
    path_lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$path_lower" in
        .env* | */.env* | .aws/* | */.aws/* | .ssh/* | */.ssh/* | *credentials* | *id_rsa* | *id_dsa* | *id_ecdsa* | *id_ed25519* | *.pem | *.key | *password* | .gnupg/* | */.gnupg/* | .kube/* | */.kube/*)
            return 0
            ;;
    esac
    return 1
}

safe_glob_match_full() {
    local pattern="$1"
    local value="$2"
    local regex

    [ "$pattern" = "*" ] && return 0
    [ -z "$pattern" ] && return 1
    [ -z "$value" ] && return 1

    regex="$(glob_to_regex "$pattern")"
    printf '%s\n' "$value" | grep -qiE "^${regex}$"
}

context_repo_action() {
    local action
    action="$(echo "$CONTEXT_JSON" | jq -r '.action // ""' 2> /dev/null || true)"
    case "$action" in
        repo.push | push | branch.create | branch.delete)
            echo "repo.push"
            ;;
        pr.merge | pr.merged | repo.merge)
            echo "pr.merge"
            ;;
        pr.update | pull_request.update)
            echo "pr.update"
            ;;
        pr.create | pull_request.create)
            echo "pr.create"
            ;;
        "")
            case "$TOOL_NAME" in
                git.push | *.git.push | *push*) echo "repo.push" ;;
                git.merge | *.git.merge | *merge*) echo "pr.merge" ;;
                *update*) echo "pr.update" ;;
                *) echo "pr.create" ;;
            esac
            ;;
        *)
            echo "pr.create"
            ;;
    esac
}

json_array_length_or_number() {
    local key1="$1"
    local key2="$2"
    echo "$CONTEXT_JSON" | jq -r --arg key1 "$key1" --arg key2 "$key2" '
        .[$key1] as $primary
        | .[$key2] as $secondary
        | if ($primary | type) == "array" then ($primary | length)
          elif ($secondary | type) == "array" then ($secondary | length)
          else ($primary // $secondary // 0)
          end
    ' 2> /dev/null || echo "0"
}

is_allowed_by_patterns() {
    local value="$1"
    local patterns_json="$2"
    local pattern

    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if safe_glob_match_full "$pattern" "$value"; then
            return 0
        fi
    done < <(echo "$patterns_json" | jq -r '.[]? // empty' 2> /dev/null)

    return 1
}

pattern_count() {
    echo "$1" | jq -r 'if type == "array" then length else 0 end' 2> /dev/null || echo "0"
}

assurance_rank() {
    case "${1:-L0}" in
        L0) echo 0 ;;
        L1) echo 1 ;;
        L2) echo 2 ;;
        L3) echo 3 ;;
        L4) echo 4 ;;
        L5) echo 5 ;;
        *) echo 0 ;;
    esac
}

passport_meets_assurance() {
    local actual required
    actual="$(jq -r '.assurance_level // "L0"' "$PASSPORT_FILE")"
    required="$1"
    [ "$(assurance_rank "$actual")" -ge "$(assurance_rank "$required")" ]
}

is_sensitive_release_file() {
    local value
    value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$value" in
        .env | .env.* | */.env | */.env.* | .aws/* | */.aws/* | .ssh/* | */.ssh/* | *credentials* | *id_rsa* | *id_dsa* | *id_ecdsa* | *id_ed25519* | *.pem | *.key)
            return 0
            ;;
    esac
    return 1
}

# Evaluate policy-specific limits
if [[ "$POLICY_ID" == "code.repository.merge"* ]]; then
    REPO_ACTION="$(context_repo_action)"
    FILES_CHANGED=$(json_array_length_or_number "files_changed" "files")
    MAX_PR_SIZE_KB=$(echo "$LIMITS" | jq -r '.max_pr_size_kb // 500')
    LINES_ADDED=$(echo "$CONTEXT_JSON" | jq -r '.lines_added // .additions // 0' 2> /dev/null || echo "0")
    LINES_REMOVED=$(echo "$CONTEXT_JSON" | jq -r '.lines_removed // .deletions // 0' 2> /dev/null || echo "0")
    case "$LINES_ADDED" in '' | *[!0-9]*) LINES_ADDED=0 ;; esac
    case "$LINES_REMOVED" in '' | *[!0-9]*) LINES_REMOVED=0 ;; esac
    case "$MAX_PR_SIZE_KB" in '' | *[!0-9]*) MAX_PR_SIZE_KB=500 ;; esac
    TOTAL_LINES=$((LINES_ADDED + LINES_REMOVED))
    if [ "$TOTAL_LINES" -gt 0 ] 2> /dev/null; then
        ESTIMATED_SIZE_KB=$(((TOTAL_LINES + 9) / 10))
        if [ "$ESTIMATED_SIZE_KB" -gt "$MAX_PR_SIZE_KB" ]; then
            write_decision false "$POLICY_ID" "oap.limit_exceeded" "PR size exceeds limit: ${ESTIMATED_SIZE_KB}KB > ${MAX_PR_SIZE_KB}KB (${TOTAL_LINES} lines)"
        fi
    elif [ "$FILES_CHANGED" -gt "$MAX_PR_SIZE_KB" ]; then
        write_decision false "$POLICY_ID" "oap.limit_exceeded" "PR file count $FILES_CHANGED exceeds fallback limit of $MAX_PR_SIZE_KB"
    fi

    # Check allowed repos
    REPO=$(echo "$CONTEXT_JSON" | jq -r '.repo // .repository // ""')
    if [ -n "$REPO" ]; then
        ALLOWED_REPOS_JSON=$(echo "$LIMITS" | jq -c '.allowed_repos // []')
        HAS_ALLOWED_REPOS=$(pattern_count "$ALLOWED_REPOS_JSON")
        if ! is_allowed_by_patterns "$REPO" "$ALLOWED_REPOS_JSON" && [ "$HAS_ALLOWED_REPOS" -gt 0 ] 2> /dev/null; then
            write_decision false "$POLICY_ID" "oap.repo_not_allowed" "Repository '$REPO' is not in allowed list"
        fi
    fi

    # Check allowed branches. PR actions evaluate base_branch when present;
    # repo.push evaluates the target branch.
    if [ "$REPO_ACTION" = "repo.push" ]; then
        BRANCH=$(echo "$CONTEXT_JSON" | jq -r '.branch // ""')
    else
        BRANCH=$(echo "$CONTEXT_JSON" | jq -r '.base_branch // .branch // ""')
    fi
    if [ -n "$BRANCH" ]; then
        ALLOWED_BRANCHES_JSON=$(echo "$LIMITS" | jq -c '.allowed_base_branches // []')
        HAS_ALLOWED_BRANCHES=$(pattern_count "$ALLOWED_BRANCHES_JSON")
        if ! is_allowed_by_patterns "$BRANCH" "$ALLOWED_BRANCHES_JSON" && [ "$HAS_ALLOWED_BRANCHES" -gt 0 ] 2> /dev/null; then
            write_decision false "$POLICY_ID" "oap.branch_not_allowed" "Branch '$BRANCH' is not in allowed list"
        fi
    fi

    # Check allowed changed paths when configured.
    ALLOWED_PATHS_JSON=$(echo "$LIMITS" | jq -c '.allowed_paths // []')
    HAS_ALLOWED_PATHS=$(pattern_count "$ALLOWED_PATHS_JSON")
    if [ "$HAS_ALLOWED_PATHS" -gt 0 ] 2> /dev/null; then
        while IFS= read -r changed_path; do
            [ -z "$changed_path" ] && continue
            if ! is_allowed_by_patterns "$changed_path" "$ALLOWED_PATHS_JSON"; then
                write_decision false "$POLICY_ID" "oap.path_not_allowed" "File path '$changed_path' is not in allowed list"
            fi
        done < <(echo "$CONTEXT_JSON" | jq -r '(.files_changed // .files // []) | if type == "array" then .[] else empty end' 2> /dev/null)
    fi

    # Lightweight local GitHub integration allowlists. Hosted OIDC and server
    # facts remain hosted-only; local mode only enforces explicit context values.
    GITHUB_CFG=$(echo "$PASSPORT" | jq -c '.integrations.github // {}')
    GITHUB_ACTOR=$(echo "$CONTEXT_JSON" | jq -r '.github_actor // .actor // ""')
    GITHUB_APP=$(echo "$CONTEXT_JSON" | jq -r '.github_app // .github_app_slug // .github_app_id // ""')
    WORKFLOW_REF=$(echo "$CONTEXT_JSON" | jq -r '.workflow_ref // ""')
    JOB_WORKFLOW_REF=$(echo "$CONTEXT_JSON" | jq -r '.job_workflow_ref // ""')

    for check in \
        "allowed_repositories:$REPO:oap.repo_not_allowed:Repository '$REPO' is not allowed by GitHub integration settings" \
        "allowed_actors:$GITHUB_ACTOR:oap.actor_not_allowed:GitHub actor '$GITHUB_ACTOR' is not allowed" \
        "allowed_apps:$GITHUB_APP:oap.app_not_allowed:GitHub app '$GITHUB_APP' is not allowed" \
        "allowed_workflow_refs:$WORKFLOW_REF:oap.workflow_not_allowed:GitHub workflow_ref '$WORKFLOW_REF' is not allowed" \
        "allowed_job_workflow_refs:$JOB_WORKFLOW_REF:oap.workflow_not_allowed:GitHub job_workflow_ref '$JOB_WORKFLOW_REF' is not allowed"; do
        IFS=':' read -r key value code message <<< "$check"
        [ -z "$value" ] && continue
        PATTERNS_JSON=$(echo "$GITHUB_CFG" | jq -c --arg key "$key" '.[$key] // []')
        HAS_PATTERNS=$(pattern_count "$PATTERNS_JSON")
        if ! is_allowed_by_patterns "$value" "$PATTERNS_JSON" && [ "$HAS_PATTERNS" -gt 0 ] 2> /dev/null; then
            write_decision false "$POLICY_ID" "$code" "$message"
        fi
    done
fi

if [[ "$POLICY_ID" == "code.release.publish"* ]]; then
    if ! passport_meets_assurance "L3"; then
        CURRENT_ASSURANCE="$(jq -r '.assurance_level // "L0"' "$PASSPORT_FILE")"
        write_decision false "$POLICY_ID" "oap.assurance_insufficient" "Required assurance level L3 not met (current: $CURRENT_ASSURANCE)"
    fi

    REPO=$(echo "$CONTEXT_JSON" | jq -r '.repo // .repository // ""')
    if [ -z "$REPO" ]; then
        write_decision false "$POLICY_ID" "oap.missing_required_context" "Release context must include repository"
    fi

    VERSION=$(echo "$CONTEXT_JSON" | jq -r '.version // ""')
    if [ -z "$VERSION" ]; then
        write_decision false "$POLICY_ID" "oap.missing_required_context" "Release context must include version"
    fi
    if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?(\+[A-Za-z0-9.-]+)?$'; then
        write_decision false "$POLICY_ID" "oap.format_unsupported" "Version '$VERSION' does not follow semantic versioning"
    fi

    RELEASE_FILE_COUNT=$(echo "$CONTEXT_JSON" | jq -r 'if (.files | type) == "array" then (.files | length) else 0 end' 2> /dev/null || echo "0")
    if [ "${RELEASE_FILE_COUNT:-0}" -eq 0 ] 2> /dev/null; then
        write_decision false "$POLICY_ID" "oap.missing_required_context" "Release context must include at least one file"
    fi
    while IFS= read -r release_file; do
        [ -z "$release_file" ] && continue
        if is_sensitive_release_file "$release_file"; then
            write_decision false "$POLICY_ID" "oap.file_forbidden" "Release file '$release_file' is sensitive and cannot be published by default"
        fi
    done < <(echo "$CONTEXT_JSON" | jq -r '(.files // []) | if type == "array" then .[] else empty end' 2> /dev/null)

    ALLOWED_REPOS_JSON=$(echo "$LIMITS" | jq -c '.allowed_repos // []')
    HAS_ALLOWED_REPOS=$(pattern_count "$ALLOWED_REPOS_JSON")
    if ! is_allowed_by_patterns "$REPO" "$ALLOWED_REPOS_JSON" && [ "$HAS_ALLOWED_REPOS" -gt 0 ] 2> /dev/null; then
        write_decision false "$POLICY_ID" "oap.repo_not_allowed" "Repository '$REPO' is not in allowed release list"
    fi

    ALLOWED_EXTENSIONS_JSON=$(echo "$LIMITS" | jq -c '.allowed_extensions // []')
    HAS_ALLOWED_EXTENSIONS=$(pattern_count "$ALLOWED_EXTENSIONS_JSON")
    if [ "$HAS_ALLOWED_EXTENSIONS" -gt 0 ] 2> /dev/null; then
        while IFS= read -r release_file; do
            [ -z "$release_file" ] && continue
            file_ext=""
            case "$release_file" in
                *.*) file_ext=".${release_file##*.}" ;;
            esac
            if { [ -z "$file_ext" ] || ! is_allowed_by_patterns "$file_ext" "$ALLOWED_EXTENSIONS_JSON"; } && ! is_allowed_by_patterns "$release_file" "$ALLOWED_EXTENSIONS_JSON"; then
                write_decision false "$POLICY_ID" "oap.file_forbidden" "Release file '$release_file' has a forbidden extension"
            fi
        done < <(echo "$CONTEXT_JSON" | jq -r '(.files // []) | if type == "array" then .[] else empty end' 2> /dev/null)
    fi
fi

if [[ "$POLICY_ID" == "system.command.execute"* ]]; then
    COMMAND=$(echo "$CONTEXT_JSON" | jq -r '.command // .cmd // ""')
    if [ -z "$COMMAND" ]; then
        # Try to extract from args
        COMMAND=$(echo "$CONTEXT_JSON" | jq -r '.args[0] // ""')
    fi

    if [ -n "$COMMAND" ]; then
        # SECURITY: Validate command doesn't contain injection characters
        if ! validate_command_string "$COMMAND"; then
            write_decision false "$POLICY_ID" "oap.command_injection_detected" "Command contains potentially dangerous characters"
        fi

        # Check allowed commands using safe prefix matching
        COMMAND_ALLOWED=false
        while IFS= read -r allowed_cmd; do
            [ -z "$allowed_cmd" ] && continue
            # Use safe_prefix_match instead of bash glob patterns
            if safe_prefix_match "$COMMAND" "$allowed_cmd"; then
                COMMAND_ALLOWED=true
                break
            fi
        done < <(echo "$LIMITS" | jq -r '.allowed_commands[]? // empty')
        HAS_ALLOWED=$(echo "$LIMITS" | jq -r '.allowed_commands | length')
        if [ "$COMMAND_ALLOWED" = false ] && [ "${HAS_ALLOWED:-0}" -gt 0 ] 2> /dev/null; then
            write_decision false "$POLICY_ID" "oap.command_not_allowed" "Command '$COMMAND' is not in allowed list"
        fi

        # Check built-in security patterns (surgical - dangerous operations only)
        # These are always enforced to prevent catastrophic damage
        if [[ "$COMMAND" =~ rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f[^[:space:]]*[[:space:]]+/[[:space:]]*$ ]] \
            || [[ "$COMMAND" =~ rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f[^[:space:]]+/\* ]]; then
            write_decision false "$POLICY_ID" "oap.dangerous_operation" "Destructive file operation: rm -rf / or rm -rf /*"
        fi
        if [[ "$COMMAND" =~ dd[[:space:]]+if=/dev/ ]]; then
            write_decision false "$POLICY_ID" "oap.dangerous_operation" "Dangerous disk operation: dd if=/dev/"
        fi
        if [[ "$COMMAND" =~ mkfs\. ]]; then
            write_decision false "$POLICY_ID" "oap.dangerous_operation" "Filesystem creation: mkfs"
        fi
        if [[ "$COMMAND" =~ (curl|wget)[[:space:]][^\|]*\|[[:space:]]*(bash|sh|zsh|python|node) ]]; then
            write_decision false "$POLICY_ID" "oap.dangerous_operation" "Download-and-execute pattern detected"
        fi
        if [[ "$COMMAND" =~ :\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:[[:space:]]*\&[[:space:]]*\} ]] || [[ "$COMMAND" =~ fork\(\) ]]; then
            write_decision false "$POLICY_ID" "oap.dangerous_operation" "Fork bomb detected"
        fi

        # Check user-defined blocked patterns using safe pattern matching
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            # Use safe_pattern_match instead of bash glob patterns
            if safe_pattern_match "$COMMAND" "$pattern"; then
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
        if [ "$RECIPIENT_ALLOWED" = false ] && [ "${HAS_ALLOWED:-0}" -gt 0 ] 2> /dev/null; then
            write_decision false "$POLICY_ID" "oap.recipient_not_allowed" "Recipient '$RECIPIENT' is not in allowed list"
        fi
    fi
fi

# File read policy evaluation
if [[ "$POLICY_ID" == "data.file.read.v1" ]]; then
    FILE_PATH=$(echo "$CONTEXT_JSON" | jq -r '.file_path // .path // ""')
    if [ -n "$FILE_PATH" ]; then
        if is_default_sensitive_read_path "$FILE_PATH"; then
            write_decision false "$POLICY_ID" "oap.blocked_pattern" "File path matches default sensitive read pattern"
        fi

        # Check allowed paths
        PATH_ALLOWED=false
        while IFS= read -r allowed_path; do
            [ -z "$allowed_path" ] && continue
            # Use safe prefix matching
            if [[ "$FILE_PATH" == "$allowed_path"* ]] || [ "$allowed_path" = "*" ]; then
                PATH_ALLOWED=true
                break
            fi
        done < <(echo "$LIMITS" | jq -r '.allowed_paths[]? // empty')

        HAS_ALLOWED=$(echo "$LIMITS" | jq -r '.allowed_paths | length' 2> /dev/null || echo "0")
        if [ "$PATH_ALLOWED" = false ] && [ "${HAS_ALLOWED:-0}" -gt 0 ] 2> /dev/null; then
            write_decision false "$POLICY_ID" "oap.path_not_allowed" "File path '$FILE_PATH' is not in allowed list"
        fi

        # Check blocked patterns (SSH keys, credentials, .env files)
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            # Simple glob-style matching for blocked patterns
            if [[ "$FILE_PATH" == *"$pattern"* ]] || [[ "$FILE_PATH" == $pattern ]]; then
                write_decision false "$POLICY_ID" "oap.blocked_pattern" "File path matches blocked pattern: $pattern"
            fi
        done < <(echo "$LIMITS" | jq -r '.blocked_patterns[]? // empty')
    fi
fi

# File write policy evaluation
if [[ "$POLICY_ID" == "data.file.write.v1" ]]; then
    FILE_PATH=$(echo "$CONTEXT_JSON" | jq -r '.file_path // .path // ""')
    if [ -n "$FILE_PATH" ]; then
        # Check allowed paths
        PATH_ALLOWED=false
        while IFS= read -r allowed_path; do
            [ -z "$allowed_path" ] && continue
            # Use safe prefix matching
            if [[ "$FILE_PATH" == "$allowed_path"* ]] || [ "$allowed_path" = "*" ]; then
                PATH_ALLOWED=true
                break
            fi
        done < <(echo "$LIMITS" | jq -r '.allowed_paths[]? // empty')

        HAS_ALLOWED=$(echo "$LIMITS" | jq -r '.allowed_paths | length' 2> /dev/null || echo "0")
        if [ "$PATH_ALLOWED" = false ] && [ "${HAS_ALLOWED:-0}" -gt 0 ] 2> /dev/null; then
            write_decision false "$POLICY_ID" "oap.path_not_allowed" "File path '$FILE_PATH' is not in allowed list"
        fi

        # Check blocked paths (system directories)
        while IFS= read -r blocked_path; do
            [ -z "$blocked_path" ] && continue
            # Prefix match for blocked system dirs
            if [[ "$FILE_PATH" == "$blocked_path"* ]]; then
                write_decision false "$POLICY_ID" "oap.path_blocked" "Writing to system directory is not allowed: $blocked_path"
            fi
        done < <(echo "$LIMITS" | jq -r '.blocked_paths[]? // empty')

        # Check allowed extensions (only when the list has entries)
        _ext_count="$(echo "$LIMITS" | jq -r 'if .allowed_extensions then (.allowed_extensions | length) else 0 end' 2> /dev/null || echo "0")"
        if [ "$_ext_count" -gt 0 ] 2> /dev/null; then
            FILE_EXT=$(echo "$FILE_PATH" | grep -o '\.[^.]*$' | tr '[:upper:]' '[:lower:]')
            if [ -n "$FILE_EXT" ]; then
                EXT_ALLOWED=false
                while IFS= read -r allowed_ext; do
                    [ -z "$allowed_ext" ] && continue
                    if [ "$FILE_EXT" = "$allowed_ext" ]; then
                        EXT_ALLOWED=true
                        break
                    fi
                done < <(echo "$LIMITS" | jq -r '.allowed_extensions[]? // empty')

                if [ "$EXT_ALLOWED" = false ]; then
                    write_decision false "$POLICY_ID" "oap.extension_not_allowed" "File extension $FILE_EXT is not allowed"
                fi
            fi
        fi
    fi
fi

# All checks passed - allow
write_decision true "$POLICY_ID" "oap.allowed" "All policy checks passed"

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
        reasons="$(jq -cn '[{code:"oap.allowed", message:"All policy checks passed"}]')"
    else
        reasons="$(jq -cn --arg code "$deny_code" --arg message "$deny_message" '[{code:$code, message:$message}]')"
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
        repo.push | push | branch.create | branch.delete) REQUIRED_CAPS="repo.push" ;;
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
    LIMITS=$(echo "$PASSPORT" | jq '.limits | if .["messaging.message.send"] then .["messaging.message.send"] else ({msgs_per_min, msgs_per_day, allowed_recipients, approval_required} | with_entries(select(.value != null))) end')
elif [[ "$POLICY_ID" == "code.repository.merge"* ]]; then
    LIMITS=$(echo "$PASSPORT" | jq '.limits | if .["code.repository.merge"] then .["code.repository.merge"] else ({max_prs_per_day, max_merges_per_day, max_pr_size_kb, allowed_repos, allowed_base_branches, allowed_paths, require_review, daily_repo_pushes} | with_entries(select(.value != null))) end')
elif [[ "$POLICY_ID" == "code.release.publish"* ]]; then
    LIMITS=$(echo "$PASSPORT" | jq '.limits | if .["code.release.publish"] then .["code.release.publish"] else ({allowed_repos, allowed_extensions} | with_entries(select(.value != null))) end')
elif [[ "$POLICY_ID" == "mcp.tool.execute"* ]]; then
    LIMITS=$(echo "$PASSPORT" | jq '.limits | if .["mcp.tool.execute"] then .["mcp.tool.execute"] else ({allowed_servers, allowed_tools, allowed_tool_prefixes, max_timeout} | with_entries(select(.value != null))) end')
elif [[ "$POLICY_ID" == "web.fetch"* ]]; then
    LIMITS=$(echo "$PASSPORT" | jq '.limits | if .["web.fetch"] then .["web.fetch"] else ({allowed_domains, blocked_domains, allowed_methods, max_requests_per_min, max_requests_per_minute} | with_entries(select(.value != null))) end')
else
    LIMITS=$(echo "$PASSPORT" | jq ".limits.\"$POLICY_BASE\" // {}")
fi

is_default_sensitive_read_path() {
    local path_lower
    path_lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$path_lower" in
        .env* | */.env* | .aws | */.aws | .aws/* | */.aws/* | .ssh | */.ssh | .ssh/* | */.ssh/* | *credentials* | *id_rsa* | *id_dsa* | *id_ecdsa* | *id_ed25519* | *.pem | *.key | *password* | .gnupg | */.gnupg | .gnupg/* | */.gnupg/* | .kube | */.kube | .kube/* | */.kube/*)
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
    if contains_control_chars "$pattern" || contains_control_chars "$value"; then
        return 1
    fi

    regex="$(glob_to_regex "$pattern")"
    printf '%s' "$value" | grep -qE "^${regex}$"
}

repo_allowed_by_patterns() {
    local repo="$1"
    local patterns_json="$2"
    local repo_name="${repo##*/}"
    local pattern

    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if safe_glob_match_full "$pattern" "$repo"; then
            return 0
        fi
        case "$pattern" in
            */* | *\** | *\?*) ;;
            *)
                if [ "$repo_name" = "$pattern" ]; then
                    return 0
                fi
                ;;
        esac
    done < <(echo "$patterns_json" | jq -r '.[]? // empty' 2> /dev/null)

    return 1
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

has_restrictive_patterns() {
    echo "$1" | jq -e 'type == "array" and length > 0 and (index("*") == null)' > /dev/null 2>&1
}

has_restrictive_limit_array() {
    echo "$1" | jq -e 'type == "array" and length > 0 and (index("*") == null)' > /dev/null 2>&1
}

validate_string_array_limit() {
    local limit_key="$1"
    if echo "$LIMITS" | jq -e --arg key "$limit_key" 'has($key) and ((.[$key] | type) != "array" or any(.[$key][]; type != "string"))' > /dev/null 2>&1; then
        write_decision false "$POLICY_ID" "oap.invalid_limit" "$limit_key must be an array of strings when configured"
    fi
}

validate_string_array_limits() {
    local limit_key
    for limit_key in "$@"; do
        validate_string_array_limit "$limit_key"
    done
}

configured_file_size_limit_bytes() {
    local bytes_raw mb_raw
    bytes_raw="$(echo "$LIMITS" | jq -c 'if has("max_file_size_bytes") then .max_file_size_bytes elif has("max_size_bytes") then .max_size_bytes else empty end' 2> /dev/null || true)"
    mb_raw="$(echo "$LIMITS" | jq -c 'if has("max_file_size_mb") then .max_file_size_mb elif has("max_size_mb") then .max_size_mb else empty end' 2> /dev/null || true)"
    if [ -n "$bytes_raw" ]; then
        if ! jq -en --argjson max "$bytes_raw" '
            if ($max | type) == "number" then ($max > 0 and ($max | floor) == $max)
            elif ($max | type) == "string" then ($max | test("^[1-9][0-9]*$"))
            else false
            end
        ' > /dev/null 2>&1; then
            printf '%s' "__APORT_INVALID_LIMIT__:max_file_size_bytes must be a positive integer when configured"
            return 0
        fi
        jq -nr --argjson max "$bytes_raw" 'if ($max | type) == "number" then ($max | floor | tostring) else $max end'
        return 0
    fi
    if [ -n "$mb_raw" ]; then
        if ! jq -en --argjson max "$mb_raw" '
            if ($max | type) == "number" then $max > 0
            elif ($max | type) == "string" then ($max | test("^[0-9]+(\\.[0-9]+)?$") and ($max | tonumber) > 0)
            else false
            end
        ' > /dev/null 2>&1; then
            printf '%s' "__APORT_INVALID_LIMIT__:max_file_size_mb must be a positive number when configured"
            return 0
        fi
        jq -nr --argjson max "$mb_raw" '($max | tonumber) * 1048576 | floor'
    fi
}

reject_invalid_file_size_limit() {
    local value="${1:-}"
    case "$value" in
        __APORT_INVALID_LIMIT__:*)
            write_decision false "$POLICY_ID" "oap.invalid_limit" "${value#__APORT_INVALID_LIMIT__:}"
            ;;
    esac
}

portable_file_size_bytes() {
    local path="$1"
    local size=""
    size="$(stat -f %z "$path" 2> /dev/null || true)"
    case "$size" in "" | *[!0-9]*) size="" ;; esac
    if [ -z "$size" ]; then
        size="$(stat -c %s "$path" 2> /dev/null || true)"
    fi
    case "$size" in "" | *[!0-9]*) size="" ;; esac
    if [ -z "$size" ]; then
        size="$(wc -c < "$path" 2> /dev/null | tr -d '[:space:]' || true)"
    fi
    case "$size" in
        "" | *[!0-9]*) return 1 ;;
    esac
    printf '%s' "$size"
}

contains_control_chars() {
    local LC_ALL=C
    case "$1" in
        *[$'\001'-$'\037'$'\177']*) return 0 ;;
        *) return 1 ;;
    esac
}

session_state_file_path() {
    local data_dir
    data_dir="$(dirname "$DECISION_FILE")"
    printf '%s' "${APORT_SESSION_STATE_FILE:-$data_dir/session-state.json}"
}

web_rate_state_file_path() {
    local data_dir
    data_dir="$(dirname "$DECISION_FILE")"
    printf '%s' "${APORT_WEB_RATE_STATE_FILE:-$data_dir/web-rate-state.json}"
}

web_rate_state_marker_path() {
    local state_file
    state_file="$(web_rate_state_file_path)"
    printf '%s' "${APORT_WEB_RATE_STATE_MARKER_FILE:-$state_file.initialized}"
}

state_target_is_regular_or_absent() {
    local state_file="$1"
    [ -L "$state_file" ] && return 1
    [ ! -e "$state_file" ] || [ -f "$state_file" ]
}

prune_session_state() {
    local state_json="$1"
    local now="$2"
    printf '%s' "$state_json" | jq -c --argjson now "$now" '
        {
          leases: ((.leases // []) | map(select(
            ((.synthetic // false) == false) or ((.expires_at_epoch // 0) > $now)
          )))
        }
    '
}

validate_session_state_json() {
    local state_json="$1"
    printf '%s' "$state_json" | jq -e '
      (.leases | type) == "array" and
      all(.leases[]; (
        (.session_id | type) == "string" and (.session_id | length) > 0 and
        (.expires_at_epoch | type) == "number" and
        ((.created_at_epoch // 0) | type) == "number" and
        ((.synthetic // false) | type) == "boolean" and
        ((.session_call_id // "") | type) == "string" and
        ((.parent_session_id // "") | type) == "string"
      ))
    ' > /dev/null 2>&1
}

validate_web_rate_state_json() {
    local state_json="$1"
    printf '%s' "$state_json" | jq -e '
      (.requests | type) == "array" and
      all(.requests[]; (type == "number"))
    ' > /dev/null 2>&1
}

portable_file_mtime_epoch() {
    local path="$1"
    local mtime=""
    if mtime="$(stat -f %m "$path" 2> /dev/null)"; then
        printf '%s' "$mtime"
        return 0
    fi
    if mtime="$(stat -c %Y "$path" 2> /dev/null)"; then
        printf '%s' "$mtime"
        return 0
    fi
    return 1
}

process_id_is_absent() {
    local pid="$1"
    case "$pid" in
        "" | *[!0-9]*) return 1 ;;
    esac
    if kill -0 "$pid" 2> /dev/null; then
        return 1
    fi
    if ps -p "$pid" > /dev/null 2>&1; then
        return 1
    fi
    return 0
}

is_lock_timestamp() {
    case "${1:-}" in
        "" | *[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

acquire_session_state_lock() {
    local lock_dir="$1"
    local retries="${APORT_SESSION_LOCK_RETRIES:-20}"
    local delay="${APORT_SESSION_LOCK_RETRY_DELAY:-0.05}"
    local stale_after="${APORT_SESSION_LOCK_STALE_SECONDS:-30}"
    local ownerless_stale_after="${APORT_SESSION_LOCK_OWNERLESS_STALE_SECONDS:-5}"
    local recovery_lock="${lock_dir}.recover"
    local attempt=0
    local owner_pid owner_time now age lock_mtime recovery_pid recovery_time recovery_age recovered_lock

    case "$retries" in
        "" | *[!0-9]*) retries=20 ;;
    esac
    case "$stale_after" in
        "" | *[!0-9]*) stale_after=30 ;;
    esac
    case "$ownerless_stale_after" in
        "" | *[!0-9]*) ownerless_stale_after=5 ;;
    esac

    while [ "$attempt" -le "$retries" ]; do
        if mkdir "$lock_dir" 2> /dev/null; then
            printf '%s %s\n' "$$" "$(date +%s)" > "$lock_dir/owner" 2> /dev/null || {
                rmdir "$lock_dir" 2> /dev/null || true
                return 1
            }
            return 0
        fi
        if mkdir "$recovery_lock" 2> /dev/null; then
            printf '%s %s\n' "$$" "$(date +%s)" > "$recovery_lock/owner" 2> /dev/null || true
            recovered_lock=0
            now="$(date +%s)"
            if [ -f "$lock_dir/owner" ]; then
                owner_pid=""
                owner_time=""
                read -r owner_pid owner_time < "$lock_dir/owner" 2> /dev/null || true
                is_lock_timestamp "$owner_time" || return 1
                age=$((now - owner_time))
                if process_id_is_absent "$owner_pid" || [ "$age" -ge "$stale_after" ] 2> /dev/null; then
                    rm -f "$lock_dir/owner" 2> /dev/null || true
                    if rmdir "$lock_dir" 2> /dev/null; then
                        recovered_lock=1
                    fi
                fi
            elif [ -d "$lock_dir" ]; then
                lock_mtime="$(portable_file_mtime_epoch "$lock_dir" || printf '%s' "$now")"
                is_lock_timestamp "$lock_mtime" || return 1
                age=$((now - lock_mtime))
                if [ "$age" -ge "$ownerless_stale_after" ] 2> /dev/null; then
                    if rmdir "$lock_dir" 2> /dev/null; then
                        recovered_lock=1
                    fi
                fi
            fi
            rm -f "$recovery_lock/owner" 2> /dev/null || true
            rmdir "$recovery_lock" 2> /dev/null || true
            if [ "$recovered_lock" -eq 1 ]; then
                continue
            fi
        fi
        if [ -d "$recovery_lock" ]; then
            now="$(date +%s)"
            if [ -f "$recovery_lock/owner" ]; then
                recovery_pid=""
                recovery_time=""
                read -r recovery_pid recovery_time < "$recovery_lock/owner" 2> /dev/null || true
                is_lock_timestamp "$recovery_time" || return 1
                recovery_age=$((now - recovery_time))
                if process_id_is_absent "$recovery_pid" || [ "$recovery_age" -ge "$stale_after" ] 2> /dev/null; then
                    rm -f "$recovery_lock/owner" 2> /dev/null || true
                    rmdir "$recovery_lock" 2> /dev/null || true
                fi
            else
                lock_mtime="$(portable_file_mtime_epoch "$recovery_lock" || printf '%s' "$now")"
                is_lock_timestamp "$lock_mtime" || return 1
                recovery_age=$((now - lock_mtime))
                if [ "$recovery_age" -ge "$ownerless_stale_after" ] 2> /dev/null; then
                    rmdir "$recovery_lock" 2> /dev/null || true
                fi
            fi
        fi
        if [ -f "$lock_dir/owner" ]; then
            read -r owner_pid owner_time < "$lock_dir/owner" 2> /dev/null || true
            if process_id_is_absent "$owner_pid"; then
                # Another process may currently hold the recovery lock. Count
                # this attempt so a live recovery owner cannot make hooks hang.
                :
            fi
        fi
        attempt=$((attempt + 1))
        sleep "$delay" 2> /dev/null || sleep 1
    done
    return 1
}

release_session_state_lock() {
    local lock_dir="$1"
    [ -n "$lock_dir" ] || return 0
    rm -f "$lock_dir/owner" 2> /dev/null || true
    rmdir "$lock_dir" 2> /dev/null || true
}

read_session_state_for_update() {
    local state_file="$1"
    local state_json
    if [ -f "$state_file" ]; then
        state_json="$(jq -c 'if (.leases | type) == "array" then {leases:.leases} else error("invalid session state") end' "$state_file" 2> /dev/null)" || return 1
    else
        state_json='{"leases":[]}'
    fi
    validate_session_state_json "$state_json" || return 1
    printf '%s' "$state_json"
}

cleanup_closed_session_lease() {
    local session_id="$1"
    local close_call_id="${2:-}"
    local state_file state_dir lock_dir current_state next_state tmp

    [ -n "$session_id" ] || return 0
    state_file="$(session_state_file_path)"
    [ -f "$state_file" ] || return 0
    state_dir="$(dirname "$state_file")"
    lock_dir="${state_file}.lock"

    mkdir -p "$state_dir" 2> /dev/null || return 1
    acquire_session_state_lock "$lock_dir" || return 1
    if ! current_state="$(read_session_state_for_update "$state_file")"; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    next_state="$(
        printf '%s' "$current_state" | jq -c --arg id "$session_id" --arg call "$close_call_id" '
          {
            leases: ((.leases // []) | map(select(
              if $call == "" then
                .session_id != $id
              else
                (.session_id != $id) or ((.closing_call_id // "") != $call)
              end
            )))
          }
        ' 2> /dev/null || printf '%s' "$current_state"
    )"
    tmp="$(mktemp "${state_dir}/session-state.XXXXXX" 2> /dev/null || true)"
    if [ -z "$tmp" ]; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    if ! { printf '%s\n' "$next_state" > "$tmp" 2> /dev/null && mv "$tmp" "$state_file" 2> /dev/null; }; then
        rm -f "$tmp" 2> /dev/null || true
        release_session_state_lock "$lock_dir"
        return 1
    fi
    chmod 600 "$state_file" 2> /dev/null || true
    release_session_state_lock "$lock_dir"
}

mark_closing_session_lease() {
    local session_id="$1"
    local close_call_id="$2"
    local state_file state_dir lock_dir current_state next_state tmp now

    [ -n "$session_id" ] && [ -n "$close_call_id" ] || return 0
    state_file="$(session_state_file_path)"
    [ -f "$state_file" ] || return 0
    state_dir="$(dirname "$state_file")"
    lock_dir="${state_file}.lock"

    mkdir -p "$state_dir" 2> /dev/null || return 1
    acquire_session_state_lock "$lock_dir" || return 1
    now="$(date +%s)"
    if ! current_state="$(read_session_state_for_update "$state_file")"; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    next_state="$(
        printf '%s' "$current_state" | jq -c --arg id "$session_id" --arg call "$close_call_id" --argjson now "$now" '
          {
            leases: ((.leases // []) | map(
              if (.session_id // "") == $id then
                . + {closing_call_id:$call, closing_at_epoch:$now}
              else
                .
              end
            ))
          }
        ' 2> /dev/null || printf '%s' "$current_state"
    )"
    tmp="$(mktemp "${state_dir}/session-state.XXXXXX" 2> /dev/null || true)"
    if [ -z "$tmp" ]; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    if ! { printf '%s\n' "$next_state" > "$tmp" 2> /dev/null && mv "$tmp" "$state_file" 2> /dev/null; }; then
        rm -f "$tmp" 2> /dev/null || true
        release_session_state_lock "$lock_dir"
        return 1
    fi
    chmod 600 "$state_file" 2> /dev/null || true
    release_session_state_lock "$lock_dir"
}

cleanup_failed_session_lease() {
    local session_id="$1"
    local session_call_id="$2"
    local state_file state_dir lock_dir current_state next_state tmp

    [ -n "$session_call_id" ] || return 0
    state_file="$(session_state_file_path)"
    [ -f "$state_file" ] || return 0
    state_dir="$(dirname "$state_file")"
    lock_dir="${state_file}.lock"

    mkdir -p "$state_dir" 2> /dev/null || return 1
    acquire_session_state_lock "$lock_dir" || return 1
    if ! current_state="$(read_session_state_for_update "$state_file")"; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    next_state="$(
        printf '%s' "$current_state" | jq -c --arg id "$session_id" --arg call "$session_call_id" '
		  {
		    leases: ((.leases // []) | map(select(
		      (
		        ((.session_call_id // "") == $call and ($id == "" or (.session_id // "") == $id)) or
		        (.session_id // "") == ("call:" + $call)
		      ) | not
		    )))
		  }
		' 2> /dev/null || printf '%s' "$current_state"
    )"
    tmp="$(mktemp "${state_dir}/session-state.XXXXXX" 2> /dev/null || true)"
    if [ -z "$tmp" ]; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    if ! { printf '%s\n' "$next_state" > "$tmp" 2> /dev/null && mv "$tmp" "$state_file" 2> /dev/null; }; then
        rm -f "$tmp" 2> /dev/null || true
        release_session_state_lock "$lock_dir"
        return 1
    fi
    chmod 600 "$state_file" 2> /dev/null || true
    release_session_state_lock "$lock_dir"
}

reconcile_session_lease() {
    local session_id="$1"
    local session_call_id="$2"
    local state_file state_dir lock_dir current_state next_state tmp

    [ -n "$session_id" ] && [ -n "$session_call_id" ] || return 0
    state_file="$(session_state_file_path)"
    [ -f "$state_file" ] || return 0
    state_dir="$(dirname "$state_file")"
    lock_dir="${state_file}.lock"

    mkdir -p "$state_dir" 2> /dev/null || return 1
    acquire_session_state_lock "$lock_dir" || return 1
    if ! current_state="$(read_session_state_for_update "$state_file")"; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    next_state="$(
        printf '%s' "$current_state" | jq -c --arg id "$session_id" --arg call "$session_call_id" '
          {
            leases: ((.leases // []) | map(
              if ((.session_call_id // "") == $call or (.session_id // "") == ("call:" + $call)) then
                (. + {
                  session_id: $id,
                  session_call_id: (if $call == "" then (.session_call_id // null) else $call end),
                  synthetic: false
                } | del(.closing_call_id, .closing_at_epoch))
              else
                .
              end
            ))
          }
        ' 2> /dev/null || printf '%s' "$current_state"
    )"
    tmp="$(mktemp "${state_dir}/session-state.XXXXXX" 2> /dev/null || true)"
    if [ -z "$tmp" ]; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    if ! { printf '%s\n' "$next_state" > "$tmp" 2> /dev/null && mv "$tmp" "$state_file" 2> /dev/null; }; then
        rm -f "$tmp" 2> /dev/null || true
        release_session_state_lock "$lock_dir"
        return 1
    fi
    chmod 600 "$state_file" 2> /dev/null || true
    release_session_state_lock "$lock_dir"
}

mark_unresolved_session_lease() {
    local session_call_id="$1"
    local state_file state_dir lock_dir current_state next_state tmp

    [ -n "$session_call_id" ] || return 0
    state_file="$(session_state_file_path)"
    [ -f "$state_file" ] || return 0
    state_dir="$(dirname "$state_file")"
    lock_dir="${state_file}.lock"

    mkdir -p "$state_dir" 2> /dev/null || return 1
    acquire_session_state_lock "$lock_dir" || return 1
    if ! current_state="$(read_session_state_for_update "$state_file")"; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    next_state="$(
        printf '%s' "$current_state" | jq -c --arg call "$session_call_id" '
          {
            leases: ((.leases // []) | map(
              if ((.session_call_id // "") == $call or (.session_id // "") == ("call:" + $call)) then
                (. + {
                  session_call_id: (if $call == "" then (.session_call_id // null) else $call end),
                  synthetic: false,
                  unresolved: true
                } | del(.closing_call_id, .closing_at_epoch))
              else
                .
              end
            ))
          }
        ' 2> /dev/null || printf '%s' "$current_state"
    )"
    tmp="$(mktemp "${state_dir}/session-state.XXXXXX" 2> /dev/null || true)"
    if [ -z "$tmp" ]; then
        release_session_state_lock "$lock_dir"
        return 1
    fi
    if ! { printf '%s\n' "$next_state" > "$tmp" 2> /dev/null && mv "$tmp" "$state_file" 2> /dev/null; }; then
        rm -f "$tmp" 2> /dev/null || true
        release_session_state_lock "$lock_dir"
        return 1
    fi
    chmod 600 "$state_file" 2> /dev/null || true
    release_session_state_lock "$lock_dir"
}

enforce_agent_session_concurrency() {
    local max_session_duration_raw max_concurrent_raw max_concurrent session_operation session_tracking hook_event active_count session_id parent_session_id state_file state_dir lock_dir synthetic_lease
    local session_call_id now ttl current_state pruned_state lease_count has_existing expires_at next_state tmp

    max_session_duration_raw="$(echo "$LIMITS" | jq -c 'if has("max_session_duration") then .max_session_duration elif has("max_session_duration_seconds") then .max_session_duration_seconds else empty end' 2> /dev/null || true)"
    if [ -n "$max_session_duration_raw" ]; then
        write_decision false "$POLICY_ID" "oap.unsupported_limit" "Local session verification cannot safely enforce max_session_duration; use hosted verification or remove this local-only limit"
    fi

    max_concurrent_raw="$(echo "$LIMITS" | jq -c 'if has("max_concurrent") then .max_concurrent elif has("max_concurrent_sessions") then .max_concurrent_sessions else empty end' 2> /dev/null || true)"
    [ -n "$max_concurrent_raw" ] || return 0
    if ! jq -en --argjson max "$max_concurrent_raw" '
        if ($max | type) == "number" then ($max > 0 and ($max | floor) == $max)
        elif ($max | type) == "string" then ($max | test("^[1-9][0-9]*$"))
        else false
        end
    ' > /dev/null 2>&1; then
        write_decision false "$POLICY_ID" "oap.invalid_limit" "max_concurrent must be a positive integer when configured"
    fi
    max_concurrent="$(jq -nr --argjson max "$max_concurrent_raw" 'if ($max | type) == "number" then ($max | floor | tostring) else $max end')"

    session_operation="$(echo "$CONTEXT_JSON" | jq -r '.session_operation // "create"' 2> /dev/null || echo "create")"
    session_tracking="$(echo "$CONTEXT_JSON" | jq -r '.session_tracking // "host_active_count"' 2> /dev/null || echo "host_active_count")"
    hook_event="$(echo "$CONTEXT_JSON" | jq -r '.hook_event // "" | ascii_downcase' 2> /dev/null || true)"
    session_id="$(echo "$CONTEXT_JSON" | jq -r '.session_id // ""' 2> /dev/null || true)"
    parent_session_id="$(echo "$CONTEXT_JSON" | jq -r '.parent_session_id // ""' 2> /dev/null || true)"
    session_call_id="$(echo "$CONTEXT_JSON" | jq -r '.session_call_id // ""' 2> /dev/null || true)"
    case "$session_operation" in
        release_failed_create)
            [ "$session_tracking" = "persistent" ] || return 0
            cleanup_failed_session_lease "$session_id" "$session_call_id" \
                || write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state could not release failed session lease"
            return 0
            ;;
        reconcile)
            [ "$session_tracking" = "persistent" ] || return 0
            reconcile_session_lease "$session_id" "$session_call_id" \
                || write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state could not reconcile session lease"
            return 0
            ;;
        mark_unresolved)
            [ "$session_tracking" = "persistent" ] || return 0
            mark_unresolved_session_lease "$session_call_id" \
                || write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state could not preserve unresolved session lease"
            return 0
            ;;
        close | stop | delete)
            if [ "$session_tracking" = "persistent" ]; then
                if [ "$hook_event" = "posttooluse" ]; then
                    cleanup_closed_session_lease "$session_id" "$session_call_id" \
                        || write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state could not release closed session lease"
                else
                    mark_closing_session_lease "$session_id" "$session_call_id" \
                        || write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state could not mark closing session lease"
                fi
            fi
            return 0
            ;;
        list | status | history | update | send | other)
            return 0
            ;;
    esac

    active_count="$(echo "$CONTEXT_JSON" | jq -r '.active_session_count // empty | if type == "number" then tostring elif type == "string" then . else empty end' 2> /dev/null || true)"
    case "$active_count" in
        "" | *[!0-9]*)
            if [ "$session_tracking" != "persistent" ]; then
                write_decision false "$POLICY_ID" "oap.missing_required_context" "Active session count is required when max_concurrent is configured"
            fi
            ;;
        *)
            if [ "$active_count" -ge "$max_concurrent" ] 2> /dev/null; then
                write_decision false "$POLICY_ID" "oap.concurrent_limit_exceeded" "Active session count $active_count exceeds max_concurrent $max_concurrent"
            fi
            ;;
    esac

    [ "$session_tracking" = "persistent" ] || return 0
    case "$session_operation" in
        create | resume)
            if [ -z "$session_call_id" ]; then
                write_decision false "$POLICY_ID" "oap.missing_required_context" "Persistent session tracking requires a per-call tool identifier when max_concurrent is configured"
            fi
            ;;
    esac

    state_file="$(session_state_file_path)"
    state_dir="$(dirname "$state_file")"
    if ! state_target_is_regular_or_absent "$state_file"; then
        write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state path is not a regular file"
    fi
    if ! mkdir -p "$state_dir" 2> /dev/null; then
        write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state cannot be created"
    fi
    chmod 700 "$state_dir" 2> /dev/null || true

    lock_dir="${state_file}.lock"
    if ! acquire_session_state_lock "$lock_dir"; then
        write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state is locked"
    fi
    if ! state_target_is_regular_or_absent "$state_file"; then
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state path is not a regular file"
    fi

    now="$(date +%s)"
    ttl="$(echo "$LIMITS" | jq -r '(.local_lease_ttl_seconds // .lease_ttl_seconds // empty) | if type == "number" then tostring elif type == "string" then . else empty end' 2> /dev/null || true)"
    if [ -z "$ttl" ]; then
        ttl="${APORT_LOCAL_SESSION_LEASE_TTL_SECONDS:-86400}"
    fi
    case "$ttl" in
        "" | *[!0-9]*) ttl=3600 ;;
    esac
    [ "$ttl" -gt 0 ] 2> /dev/null || ttl=3600
    expires_at=$((now + ttl))

    if [ -f "$state_file" ]; then
        if ! current_state="$(jq -c 'if (.leases | type) == "array" then {leases:.leases} else error("invalid session state") end' "$state_file" 2> /dev/null)"; then
            release_session_state_lock "$lock_dir"
            write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state is invalid"
        fi
    else
        current_state='{"leases":[]}'
    fi
    if ! validate_session_state_json "$current_state"; then
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state contains malformed leases"
    fi
    if ! pruned_state="$(prune_session_state "$current_state" "$now" 2> /dev/null)"; then
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state could not be evaluated"
    fi

    if [ -z "$session_id" ]; then
        if [ -n "$session_call_id" ]; then
            session_id="call:$session_call_id"
        else
            session_id="$(uuidgen 2> /dev/null || printf 'session-%s-%s' "$now" "$$")"
        fi
        synthetic_lease=true
    else
        synthetic_lease=false
    fi

    has_existing="$(printf '%s' "$pruned_state" | jq -r --arg id "$session_id" '.leases | any(.session_id == $id)' 2> /dev/null || echo false)"
    if [ "$has_existing" = "true" ]; then
        next_state="$(printf '%s' "$pruned_state" | jq -c --arg id "$session_id" --arg call "$session_call_id" --arg operation "$session_operation" --argjson expires "$expires_at" '{
          leases: (.leases | map(
            if .session_id == $id then
              (. + {
                expires_at_epoch:$expires,
                session_call_id: (if $operation == "resume" or $call == "" then (.session_call_id // null) else $call end),
                synthetic:false
              } | del(.closing_call_id, .closing_at_epoch))
            else
              .
            end
          ))
        }' 2> /dev/null)" || next_state=""
    else
        lease_count="$(printf '%s' "$pruned_state" | jq -r '.leases | length' 2> /dev/null || echo 0)"
        case "$lease_count" in
            "" | *[!0-9]*) lease_count=0 ;;
        esac
        if [ "$lease_count" -ge "$max_concurrent" ] 2> /dev/null; then
            release_session_state_lock "$lock_dir"
            write_decision false "$POLICY_ID" "oap.concurrent_limit_exceeded" "Active session leases $lease_count exceed max_concurrent $max_concurrent"
        fi
        next_state="$(printf '%s' "$pruned_state" | jq -c --arg id "$session_id" --arg parent "$parent_session_id" --arg call "$session_call_id" --argjson synthetic "$synthetic_lease" --argjson now "$now" --argjson expires "$expires_at" '{
          leases: (.leases + [{session_id:$id, parent_session_id:(if $parent == "" then null else $parent end), session_call_id:(if $call == "" then null else $call end), synthetic:$synthetic, created_at_epoch:$now, expires_at_epoch:$expires}])
        }' 2> /dev/null)" || next_state=""
    fi

    if [ -z "$next_state" ]; then
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state could not be updated"
    fi

    tmp="$(mktemp "${state_dir}/session-state.XXXXXX" 2> /dev/null || true)"
    if [ -z "$tmp" ] || ! printf '%s\n' "$next_state" > "$tmp" 2> /dev/null || ! state_target_is_regular_or_absent "$state_file" || ! mv "$tmp" "$state_file" 2> /dev/null; then
        [ -n "$tmp" ] && rm -f "$tmp" 2> /dev/null || true
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.session_state_unavailable" "Local session limit state could not be written"
    fi
    chmod 600 "$state_file" 2> /dev/null || true
    release_session_state_lock "$lock_dir"
}

enforce_web_fetch_rate_limit() {
    local max_requests_raw max_requests state_file marker_file state_dir lock_dir now current_state next_state allowed_count tmp marker_tmp

    max_requests_raw="$(echo "$LIMITS" | jq -c 'if has("max_requests_per_min") then .max_requests_per_min elif has("max_requests_per_minute") then .max_requests_per_minute else empty end' 2> /dev/null || true)"
    [ -n "$max_requests_raw" ] || return 0
    if ! jq -en --argjson max "$max_requests_raw" '
        if ($max | type) == "number" then ($max > 0 and ($max | floor) == $max)
        elif ($max | type) == "string" then ($max | test("^[1-9][0-9]*$"))
        else false
        end
    ' > /dev/null 2>&1; then
        write_decision false "$POLICY_ID" "oap.invalid_limit" "max_requests_per_min must be a positive integer when configured"
    fi
    max_requests="$(jq -nr --argjson max "$max_requests_raw" 'if ($max | type) == "number" then ($max | floor | tostring) else $max end')"

    state_file="$(web_rate_state_file_path)"
    marker_file="$(web_rate_state_marker_path)"
    state_dir="$(dirname "$state_file")"
    if ! state_target_is_regular_or_absent "$state_file"; then
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit state path is not a regular file"
    fi
    if ! state_target_is_regular_or_absent "$marker_file"; then
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit marker path is not a regular file"
    fi
    if ! mkdir -p "$state_dir" 2> /dev/null; then
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit state cannot be created"
    fi
    chmod 700 "$state_dir" 2> /dev/null || true

    lock_dir="${state_file}.lock"
    if ! acquire_session_state_lock "$lock_dir"; then
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit state is locked"
    fi
    if ! state_target_is_regular_or_absent "$state_file"; then
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit state path is not a regular file"
    fi
    if [ ! -f "$state_file" ] && [ -f "$marker_file" ]; then
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit state is missing after initialization"
    fi

    now="$(date +%s)"
    if [ -f "$state_file" ]; then
        if ! current_state="$(jq -c 'if (.requests | type) == "array" then {requests:.requests} else error("invalid web rate state") end' "$state_file" 2> /dev/null)"; then
            release_session_state_lock "$lock_dir"
            write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit state is invalid"
        fi
    else
        current_state='{"requests":[]}'
    fi
    if ! validate_web_rate_state_json "$current_state"; then
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit state contains malformed entries"
    fi

    next_state="$(
        printf '%s' "$current_state" | jq -c --argjson now "$now" --argjson max "$max_requests" '
          ((.requests // []) | map(select((type == "number") and (. > ($now - 60))))) as $recent
          | if ($recent | length) >= $max then
              {allowed:false, count:($recent | length), requests:$recent}
            else
              {allowed:true, count:(($recent | length) + 1), requests:($recent + [$now])}
            end
        ' 2> /dev/null
    )" || next_state=""

    if [ -z "$next_state" ]; then
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit state could not be evaluated"
    fi

    if [ "$(printf '%s' "$next_state" | jq -r '.allowed')" != "true" ]; then
        allowed_count="$(printf '%s' "$next_state" | jq -r '.count // 0')"
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.rate_limit_exceeded" "Web fetch rate limit exceeded: $allowed_count requests in the last minute, max $max_requests"
    fi

    tmp="$(mktemp "${state_dir}/web-rate-state.XXXXXX" 2> /dev/null || true)"
    if [ -z "$tmp" ] || ! printf '%s\n' "$next_state" | jq -c '{requests:.requests}' > "$tmp" 2> /dev/null || ! state_target_is_regular_or_absent "$state_file" || ! mv "$tmp" "$state_file" 2> /dev/null; then
        [ -n "$tmp" ] && rm -f "$tmp" 2> /dev/null || true
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit state could not be written"
    fi
    chmod 600 "$state_file" 2> /dev/null || true
    marker_tmp="$(mktemp "${state_dir}/web-rate-marker.XXXXXX" 2> /dev/null || true)"
    if [ -z "$marker_tmp" ] || ! : > "$marker_tmp" 2> /dev/null || ! chmod 600 "$marker_tmp" 2> /dev/null || ! state_target_is_regular_or_absent "$marker_file" || ! mv "$marker_tmp" "$marker_file" 2> /dev/null; then
        [ -n "$marker_tmp" ] && rm -f "$marker_tmp" 2> /dev/null || true
        release_session_state_lock "$lock_dir"
        write_decision false "$POLICY_ID" "oap.rate_state_unavailable" "Local web rate-limit marker could not be written"
    fi
    release_session_state_lock "$lock_dir"
}

normalize_mcp_server() {
    local server="${1:-}"
    local scheme rest authority tail path
    server="$(printf '%s' "$server" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$server" in
        *://*)
            case "$server" in
                *"\\"*)
                    printf ''
                    return 0
                    ;;
            esac
            if contains_control_chars "$server"; then
                printf ''
                return 0
            fi
            scheme="${server%%://*}"
            rest="${server#*://}"
            authority="${rest%%[/?#]*}"
            tail="${rest#"$authority"}"
            authority="${authority##*@}"
            path="${tail%%[\?#]*}"
            scheme="$(printf '%s' "$scheme" | tr '[:upper:]' '[:lower:]')"
            authority="$(printf '%s' "$authority" | tr '[:upper:]' '[:lower:]')"
            server="${scheme}://${authority}${path}"
            ;;
        *)
            server="${server%.}"
            ;;
    esac
    printf '%s' "$server"
}

mcp_server_authority() {
    local server="$1"
    local rest authority
    case "$server" in
        *://*)
            rest="${server#*://}"
            authority="${rest%%[/?#]*}"
            printf '%s' "$authority"
            ;;
        *)
            printf '%s' "$server"
            ;;
    esac
}

mcp_server_path() {
    local server="$1"
    local rest authority tail path
    case "$server" in
        *://*)
            rest="${server#*://}"
            authority="${rest%%[/?#]*}"
            tail="${rest#"$authority"}"
            path="${tail%%[\?#]*}"
            printf '%s' "$path"
            ;;
        *)
            printf ''
            ;;
    esac
}

mcp_path_has_dot_segment() {
    local path="$1"
    local lower
    if contains_control_chars "$path"; then
        return 0
    fi
    lower="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        *"\\"* | *"/../"* | *"/.." | *"/./"* | *"/." | *"%2e"* | *"%2f"* | *"%5c"*) return 0 ;;
    esac
    return 1
}

mcp_url_scope_allows() {
    local request="$1"
    local allowed="$2"
    local request_scheme allowed_scheme request_authority allowed_authority request_path allowed_path

    case "$request" in *://*) ;; *) return 1 ;; esac
    case "$allowed" in *://*) ;; *) return 1 ;; esac

    request_scheme="${request%%://*}"
    allowed_scheme="${allowed%%://*}"
    [ "$request_scheme" = "$allowed_scheme" ] || return 1
    request_authority="$(mcp_server_authority "$request")"
    allowed_authority="$(mcp_server_authority "$allowed")"
    [ "$request_authority" = "$allowed_authority" ] || return 1

    request_path="$(mcp_server_path "$request")"
    allowed_path="$(mcp_server_path "$allowed")"
    if mcp_path_has_dot_segment "$request_path" || mcp_path_has_dot_segment "$allowed_path"; then
        return 1
    fi
    while [ "$allowed_path" != "/" ] && [ "${allowed_path%/}" != "$allowed_path" ]; do
        allowed_path="${allowed_path%/}"
    done
    case "$allowed_path" in
        "" | "/") return 0 ;;
    esac
    [ "$request_path" = "$allowed_path" ] && return 0
    case "$request_path" in
        "$allowed_path"/*) return 0 ;;
    esac
    return 1
}

mcp_server_allowed() {
    local server="$1"
    local allowed_json="$2"
    local normalized allowed normalized_authority allowed_authority allowed_path normalized_scheme normalized_path allowed_bare
    normalized="$(normalize_mcp_server "$server")"
    normalized_authority="$(mcp_server_authority "$normalized")"
    normalized_path="$(mcp_server_path "$normalized")"
    case "$normalized" in
        *://*) normalized_scheme="${normalized%%://*}" ;;
        *) normalized_scheme="" ;;
    esac
    if [ -n "$normalized_scheme" ] && mcp_path_has_dot_segment "$normalized_path"; then
        return 1
    fi

    while IFS= read -r allowed; do
        [ -z "$allowed" ] && continue
        [ "$allowed" = "*" ] && return 0
        allowed="$(normalize_mcp_server "$allowed")"
        allowed_path="$(mcp_server_path "$allowed")"
        case "$allowed" in
            *://*)
                if mcp_path_has_dot_segment "$allowed_path"; then
                    continue
                fi
                ;;
        esac
        if [ "$normalized" = "$allowed" ] || safe_glob_match_full "$allowed" "$normalized"; then
            return 0
        fi
        if mcp_url_scope_allows "$normalized" "$allowed"; then
            return 0
        fi
        case "$allowed" in
            mcp://*)
                case "$allowed_path" in "" | "/") ;; *) continue ;; esac
                allowed_bare="${allowed#mcp://}"
                if [ -z "$normalized_scheme" ] && safe_glob_match_full "$allowed_bare" "$normalized"; then
                    return 0
                fi
                allowed_authority="$(mcp_server_authority "$allowed")"
                if [ "$normalized_authority" = "$allowed_authority" ] && { [ -z "$normalized_scheme" ] || [ "$normalized_scheme" = "mcp" ]; }; then
                    return 0
                fi
                ;;
            *://*) ;;
            *)
                allowed_authority="$(mcp_server_authority "$allowed")"
                if [ -z "$normalized_scheme" ] && [ "$normalized_authority" = "$allowed_authority" ]; then
                    return 0
                fi
                if [ "$normalized_scheme" = "mcp" ] && [ "$normalized_authority" = "$allowed_authority" ]; then
                    case "$normalized_path" in "" | "/") return 0 ;; esac
                fi
                ;;
        esac
    done < <(echo "$allowed_json" | jq -r '.[]? // empty' 2> /dev/null)

    [ "$(pattern_count "$allowed_json")" -eq 0 ] 2> /dev/null
}

mcp_tool_allowed() {
    local tool="$1"
    local limits_json="$2"
    local allowed_tools_json allowed_prefixes_json entry
    allowed_tools_json="$(echo "$limits_json" | jq -c '.allowed_tools // []' 2> /dev/null || echo "[]")"
    allowed_prefixes_json="$(echo "$limits_json" | jq -c '.allowed_tool_prefixes // []' 2> /dev/null || echo "[]")"

    if [ "$(pattern_count "$allowed_tools_json")" -eq 0 ] 2> /dev/null && [ "$(pattern_count "$allowed_prefixes_json")" -eq 0 ] 2> /dev/null; then
        return 0
    fi

    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        [ "$entry" = "*" ] && return 0
        if safe_glob_match_full "$entry" "$tool"; then
            return 0
        fi
    done < <(echo "$allowed_tools_json" | jq -r '.[]? // empty' 2> /dev/null)

    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        [ "$entry" = "*" ] && return 0
        case "$tool" in
            "$entry"*) return 0 ;;
        esac
    done < <(echo "$allowed_prefixes_json" | jq -r '.[]? // empty' 2> /dev/null)

    return 1
}

url_has_parser_hazards() {
    local value="${1:-}"
    [[ "$value" == *\\* ]] && return 0
    LC_ALL=C printf '%s' "$value" | grep -q '[[:cntrl:]]'
}

url_authority_has_percent_escape() {
    local value="${1:-}"
    local rest authority
    case "$value" in
        *://*) ;;
        *) return 1 ;;
    esac
    rest="${value#*://}"
    authority="${rest%%[/?#]*}"
    [[ "$authority" == *%* ]]
}

url_authority_has_non_ascii() {
    local value="${1:-}"
    local rest authority
    case "$value" in
        *://*) rest="${value#*://}" ;;
        *) rest="$value" ;;
    esac
    authority="${rest%%[/?#]*}"
    LC_ALL=C printf '%s' "$authority" | grep -q '[^ -~]'
}

url_host() {
    local value="${1:-}"
    local authority
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
    if url_has_parser_hazards "$value"; then
        printf ''
        return 0
    fi
    value="${value#http://}"
    value="${value#https://}"
    authority="${value%%[/?#]*}"
    if url_authority_has_non_ascii "$authority"; then
        printf ''
        return 0
    fi
    authority="${authority##*@}"
    if [[ "$authority" == *%* ]]; then
        printf ''
        return 0
    fi
    if [[ "$authority" == \[*\]* ]]; then
        value="${authority#\[}"
        value="${value%%\]*}"
    elif [[ "$authority" == *:*:* ]]; then
        # Unbracketed IPv6 literals can arrive via an explicit domain field.
        value="$authority"
    else
        value="${authority%%:*}"
    fi
    value="${value%.}"
    printf '%s' "$value"
}

is_private_ipv4_destination() {
    local host="${1:-}"
    local normalized first second third _fourth
    normalized="$(canonical_ipv4_literal "$host" 2> /dev/null)" || return 1
    IFS='.' read -r first second third _fourth <<< "$normalized"

    if [ "$first" -eq 0 ] 2> /dev/null || [ "$first" -eq 10 ] 2> /dev/null || [ "$first" -eq 127 ] 2> /dev/null; then
        return 0
    fi
    if [ "$first" -eq 169 ] 2> /dev/null && [ "$second" -eq 254 ] 2> /dev/null; then
        return 0
    fi
    if [ "$first" -eq 172 ] 2> /dev/null && [ "$second" -ge 16 ] 2> /dev/null && [ "$second" -le 31 ] 2> /dev/null; then
        return 0
    fi
    if [ "$first" -eq 192 ] 2> /dev/null && [ "$second" -eq 168 ] 2> /dev/null; then
        return 0
    fi
    if [ "$first" -eq 192 ] 2> /dev/null && [ "$second" -eq 0 ] 2> /dev/null && { [ "$third" -eq 0 ] 2> /dev/null || [ "$third" -eq 2 ] 2> /dev/null; }; then
        return 0
    fi
    if [ "$first" -eq 192 ] 2> /dev/null && [ "$second" -eq 88 ] 2> /dev/null && [ "$third" -eq 99 ] 2> /dev/null; then
        return 0
    fi
    if [ "$first" -eq 100 ] 2> /dev/null && [ "$second" -ge 64 ] 2> /dev/null && [ "$second" -le 127 ] 2> /dev/null; then
        return 0
    fi
    if [ "$first" -eq 198 ] 2> /dev/null && { [ "$second" -eq 18 ] 2> /dev/null || [ "$second" -eq 19 ] 2> /dev/null; }; then
        return 0
    fi
    if [ "$first" -eq 198 ] 2> /dev/null && [ "$second" -eq 51 ] 2> /dev/null && [ "$third" -eq 100 ] 2> /dev/null; then
        return 0
    fi
    if [ "$first" -eq 203 ] 2> /dev/null && [ "$second" -eq 0 ] 2> /dev/null && [ "$third" -eq 113 ] 2> /dev/null; then
        return 0
    fi
    if [ "$first" -ge 224 ] 2> /dev/null; then
        return 0
    fi

    return 1
}

parse_ipv4_number() {
    local value="${1:-}"
    local base=10
    local digits="$value"
    local number

    case "$digits" in
        "" | *[!0-9a-fA-FxX]*) return 1 ;;
    esac
    case "$digits" in
        0[xX]*)
            digits="${digits#0x}"
            digits="${digits#0X}"
            [ -n "$digits" ] || return 1
            case "$digits" in
                *[!0-9a-fA-F]*) return 1 ;;
            esac
            base=16
            ;;
        0[0-7]*)
            base=8
            ;;
        0)
            base=10
            ;;
        *)
            case "$digits" in
                *[!0-9]*) return 1 ;;
            esac
            base=10
            ;;
    esac

    case "$base" in
        16) number=$((16#$digits)) ;;
        8) number=$((8#$digits)) ;;
        *) number=$((10#$digits)) ;;
    esac
    [ "$number" -ge 0 ] 2> /dev/null && [ "$number" -le 4294967295 ] 2> /dev/null || return 1
    printf '%s' "$number"
}

canonical_ipv4_literal() {
    local host="${1:-}"
    local parts=()
    local numbers=()
    local part number count addr first second third fourth

    host="${host%.}"
    IFS='.' read -r -a parts <<< "$host"
    count="${#parts[@]}"
    [ "$count" -ge 1 ] && [ "$count" -le 4 ] || return 1

    for part in "${parts[@]}"; do
        [ -n "$part" ] || return 1
        number="$(parse_ipv4_number "$part")" || return 1
        numbers+=("$number")
    done

    case "$count" in
        1)
            addr="${numbers[0]}"
            ;;
        2)
            [ "${numbers[0]}" -le 255 ] 2> /dev/null && [ "${numbers[1]}" -le 16777215 ] 2> /dev/null || return 1
            addr=$(((numbers[0] << 24) + numbers[1]))
            ;;
        3)
            [ "${numbers[0]}" -le 255 ] 2> /dev/null && [ "${numbers[1]}" -le 255 ] 2> /dev/null && [ "${numbers[2]}" -le 65535 ] 2> /dev/null || return 1
            addr=$(((numbers[0] << 24) + (numbers[1] << 16) + numbers[2]))
            ;;
        4)
            for number in "${numbers[@]}"; do
                [ "$number" -le 255 ] 2> /dev/null || return 1
            done
            addr=$(((numbers[0] << 24) + (numbers[1] << 16) + (numbers[2] << 8) + numbers[3]))
            ;;
        *)
            return 1
            ;;
    esac

    first=$(((addr >> 24) & 255))
    second=$(((addr >> 16) & 255))
    third=$(((addr >> 8) & 255))
    fourth=$((addr & 255))
    printf '%s.%s.%s.%s' "$first" "$second" "$third" "$fourth"
}

ipv4_from_hex_mapped_ipv6() {
    local host="${1:-}"
    local suffix high low first second third fourth
    host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
    case "$host" in
        ::ffff:*:*)
            suffix="${host#::ffff:}"
            ;;
        0:0:0:0:0:ffff:*:*)
            suffix="${host#0:0:0:0:0:ffff:}"
            ;;
        *)
            return 1
            ;;
    esac
    case "$suffix" in
        *.* | *:*:*) return 1 ;;
    esac
    IFS=':' read -r high low <<< "$suffix"
    [ -n "$high" ] && [ -n "$low" ] || return 1
    case "$high" in *[!0-9a-f]*) return 1 ;; esac
    case "$low" in *[!0-9a-f]*) return 1 ;; esac
    high=$((16#$high))
    low=$((16#$low))
    [ "$high" -le 65535 ] 2> /dev/null && [ "$low" -le 65535 ] 2> /dev/null || return 1
    first=$(((high >> 8) & 255))
    second=$((high & 255))
    third=$(((low >> 8) & 255))
    fourth=$((low & 255))
    printf '%s.%s.%s.%s' "$first" "$second" "$third" "$fourth"
}

is_private_ipv6_destination() {
    local host="${1:-}"
    local clean first first_num
    clean="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
    clean="${clean#\[}"
    clean="${clean%\]}"
    clean="${clean%%%*}"
    [[ "$clean" == *:* ]] || return 1

    if command -v python3 > /dev/null 2>&1; then
        if python3 - "$clean" << 'PY' > /dev/null 2>&1; then
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError:
    sys.exit(1)

if address.version != 6:
    sys.exit(1)

mapped = address.ipv4_mapped
if mapped is not None:
    if not mapped.is_global:
        sys.exit(0)
    sys.exit(1)

if not address.is_global:
    sys.exit(0)

sys.exit(1)
PY
            return 0
        fi
        return 1
    fi

    case "$clean" in
        ::1 | 0:0:0:0:0:0:0:1 | 0:0:0:0:0:0::1 | 0:0:0:0:0::1 | 0:0:0:0::1 | 0:0:0::1 | 0:0::1 | 0::1)
            return 0
            ;;
    esac

    first="${clean%%:*}"
    [ -n "$first" ] || return 1
    case "$first" in *[!0-9a-f]*) return 1 ;; esac
    first_num=$((16#$first))
    if [ "$first_num" -ge $((16#fe80)) ] 2> /dev/null && [ "$first_num" -le $((16#febf)) ] 2> /dev/null; then
        return 0
    fi
    if [ "$first_num" -ge $((16#fc00)) ] 2> /dev/null && [ "$first_num" -le $((16#fdff)) ] 2> /dev/null; then
        return 0
    fi
    return 1
}

is_private_network_destination() {
    local host="${1:-}"
    local mapped_ipv4
    host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
    host="${host%.}"

    case "$host" in
        "" | localhost | *.localhost | ::1 | 0:0:0:0:0:0:0:1 | fe80:* | fc*:* | fd*:* | ff*:*)
            return 0
            ;;
    esac

    case "$host" in
        ::ffff:*.*.*.*)
            mapped_ipv4="${host#::ffff:}"
            mapped_ipv4="$(canonical_ipv4_literal "$mapped_ipv4" 2> /dev/null)" || return 1
            is_private_ipv4_destination "$mapped_ipv4"
            return $?
            ;;
        0:0:0:0:0:ffff:*.*.*.*)
            mapped_ipv4="${host#0:0:0:0:0:ffff:}"
            mapped_ipv4="$(canonical_ipv4_literal "$mapped_ipv4" 2> /dev/null)" || return 1
            is_private_ipv4_destination "$mapped_ipv4"
            return $?
            ;;
    esac
    if mapped_ipv4="$(ipv4_from_hex_mapped_ipv6 "$host" 2> /dev/null)"; then
        is_private_ipv4_destination "$mapped_ipv4"
        return $?
    fi
    if is_private_ipv6_destination "$host"; then
        return 0
    fi

    is_private_ipv4_destination "$host"
}

path_has_glob_chars() {
    case "$1" in
        *'*'* | *'?'* | *'['*) return 0 ;;
        *) return 1 ;;
    esac
}

canonical_policy_path() {
    local input="${1:-}"
    local path resolved dir suffix base
    [ -n "$input" ] || return 1
    contains_control_chars "$input" && return 1
    case "$input" in
        "~") path="$HOME" ;;
        "~/"*) path="$HOME/${input#\~/}" ;;
        *) path="$input" ;;
    esac
    case "$path" in
        /*) ;;
        *) path="$PWD/$path" ;;
    esac

    if command -v realpath > /dev/null 2>&1 && resolved="$(realpath "$path" 2> /dev/null)"; then
        printf '%s' "$resolved"
        return 0
    fi
    if command -v python3 > /dev/null 2>&1 && resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path" 2> /dev/null)"; then
        printf '%s' "$resolved"
        return 0
    fi

    dir="$path"
    suffix=""
    while [ ! -e "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
        base="$(basename "$dir")"
        suffix="/$base$suffix"
        dir="$(dirname "$dir")"
    done
    if [ -f "$dir" ]; then
        suffix="/$(basename "$dir")$suffix"
        dir="$(dirname "$dir")"
    fi
    if [ -d "$dir" ] && resolved="$(cd -P "$dir" 2> /dev/null && pwd)"; then
        printf '%s%s' "$resolved" "$suffix"
        return 0
    fi
    printf '%s' "$path"
}

normalize_path_pattern_for_match() {
    local pattern="${1:-}"
    local normalized prefix suffix base_dir base_name canon_base i ch
    contains_control_chars "$pattern" && return 1
    case "$pattern" in
        "~") normalized="$HOME" ;;
        "~/"*) normalized="$HOME/${pattern#\~/}" ;;
        /*) normalized="$pattern" ;;
        *) normalized="$PWD/$pattern" ;;
    esac
    if ! path_has_glob_chars "$normalized"; then
        canonical_policy_path "$normalized"
        return $?
    fi

    prefix=""
    suffix=""
    for ((i = 0; i < ${#normalized}; i++)); do
        ch="${normalized:i:1}"
        case "$ch" in
            '*' | '?' | '[')
                prefix="${normalized:0:i}"
                suffix="${normalized:i}"
                break
                ;;
        esac
    done
    [ -n "$suffix" ] || {
        printf '%s' "$normalized"
        return 0
    }
    if [[ "$prefix" == */ ]]; then
        canon_base="$(canonical_policy_path "${prefix%/}" 2> /dev/null)" || canon_base="${prefix%/}"
        printf '%s/%s' "$canon_base" "$suffix"
    else
        base_dir="$(dirname "$prefix")"
        base_name="$(basename "$prefix")"
        canon_base="$(canonical_policy_path "$base_dir" 2> /dev/null)" || canon_base="$base_dir"
        printf '%s/%s%s' "$canon_base" "$base_name" "$suffix"
    fi
}

path_within_or_equal() {
    local target="$1"
    local base="$2"
    if [ "$base" = "/" ]; then
        [[ "$target" = /* ]]
        return $?
    fi
    [ "$target" = "$base" ] || [[ "$target" == "$base/"* ]]
}

policy_path_matches() {
    local target_canon="$1"
    local pattern="$2"
    local normalized_pattern base_canon

    [ "$pattern" = "*" ] && return 0
    if contains_control_chars "$target_canon" || contains_control_chars "$pattern"; then
        return 1
    fi
    if path_has_glob_chars "$pattern"; then
        normalized_pattern="$(normalize_path_pattern_for_match "$pattern")"
        safe_glob_match_full "$normalized_pattern" "$target_canon"
        return $?
    fi

    base_canon="$(canonical_policy_path "$pattern" 2> /dev/null)" || return 1
    path_within_or_equal "$target_canon" "$base_canon"
}

domain_matches_pattern() {
    local host="$1"
    local pattern="$2"
    local normalized
    [ -z "$host" ] && return 1
    [ "$pattern" = "*" ] && return 0
    normalized="$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')"
    if safe_glob_match_full "$normalized" "$host"; then
        return 0
    fi
    if [ "$host" = "$normalized" ] || [[ "$host" == *".$normalized" ]]; then
        return 0
    fi
    return 1
}

domain_allowed_by_list() {
    local host="$1"
    local patterns_json="$2"
    local pattern

    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if domain_matches_pattern "$host" "$pattern"; then
            return 0
        fi
    done < <(echo "$patterns_json" | jq -r '.[]? // empty' 2> /dev/null)

    [ "$(pattern_count "$patterns_json")" -eq 0 ] 2> /dev/null
}

domain_blocked_by_list() {
    local host="$1"
    local patterns_json="$2"
    local pattern

    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if domain_matches_pattern "$host" "$pattern"; then
            return 0
        fi
    done < <(echo "$patterns_json" | jq -r '.[]? // empty' 2> /dev/null)

    return 1
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
        if ! repo_allowed_by_patterns "$REPO" "$ALLOWED_REPOS_JSON" && [ "$HAS_ALLOWED_REPOS" -gt 0 ] 2> /dev/null; then
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
    if has_restrictive_patterns "$ALLOWED_PATHS_JSON"; then
        CHANGED_PATHS_JSON=$(echo "$CONTEXT_JSON" | jq -c '
            [
              (.files_changed // []),
              (.files // []),
              (.file_paths // []),
              (.paths // [])
            ]
            | map(if type == "array" then .[] elif type == "string" then . else empty end)
        ' 2> /dev/null || echo "[]")
        CHANGED_PATH_COUNT=$(echo "$CHANGED_PATHS_JSON" | jq -r 'length' 2> /dev/null || echo "0")
        if [ "${CHANGED_PATH_COUNT:-0}" -eq 0 ] 2> /dev/null; then
            write_decision false "$POLICY_ID" "oap.missing_required_context" "Repository policy requires changed-file path evidence"
        fi
        while IFS= read -r changed_path; do
            [ -z "$changed_path" ] && continue
            if ! is_allowed_by_patterns "$changed_path" "$ALLOWED_PATHS_JSON"; then
                write_decision false "$POLICY_ID" "oap.path_not_allowed" "File path '$changed_path' is not in allowed list"
            fi
        done < <(echo "$CHANGED_PATHS_JSON" | jq -r '.[]? // empty' 2> /dev/null)
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
    if ! repo_allowed_by_patterns "$REPO" "$ALLOWED_REPOS_JSON" && [ "$HAS_ALLOWED_REPOS" -gt 0 ] 2> /dev/null; then
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
    if echo "$CONTEXT_JSON" | jq -e '
        (has("command") and (.command | type) != "string") or
        (has("cmd") and (.cmd | type) != "string") or
        (has("args") and (.args | type) != "array") or
        ((.args | type) == "array" and (.args | length) > 0 and (.args[0] | type) != "string")
    ' > /dev/null 2>&1; then
        write_decision false "$POLICY_ID" "oap.invalid_tool_arguments" "Shell command context must use string command fields"
    fi
    COMMAND=$(echo "$CONTEXT_JSON" | jq -r '.command // .cmd // ""')
    if [ -z "$COMMAND" ]; then
        # Try to extract from args
        COMMAND=$(echo "$CONTEXT_JSON" | jq -r '.args[0] // ""')
    fi
    COMMAND_TIMEOUT=$(echo "$CONTEXT_JSON" | jq -r '(.timeout // .timeout_seconds // empty) | if type == "number" then tostring elif type == "string" then . else empty end' 2> /dev/null || true)
    MAX_EXECUTION_TIME_RAW="$(echo "$LIMITS" | jq -c 'if has("max_execution_time") then .max_execution_time elif has("max_execution_time_seconds") then .max_execution_time_seconds elif has("max_timeout") then .max_timeout else empty end' 2> /dev/null || true)"
    if [ -n "$MAX_EXECUTION_TIME_RAW" ]; then
        if ! jq -en --argjson max "$MAX_EXECUTION_TIME_RAW" '
            if ($max | type) == "number" then $max > 0
            elif ($max | type) == "string" then ($max | test("^[0-9]+(\\.[0-9]+)?$") and ($max | tonumber) > 0)
            else false
            end
        ' > /dev/null 2>&1; then
            write_decision false "$POLICY_ID" "oap.invalid_limit" "max_execution_time must be a positive number when configured"
        fi
        MAX_EXECUTION_TIME="$(jq -nr --argjson max "$MAX_EXECUTION_TIME_RAW" 'if ($max | type) == "number" then ($max | tostring) else $max end')"
        if [ -z "$COMMAND_TIMEOUT" ]; then
            write_decision false "$POLICY_ID" "oap.missing_required_context" "Command timeout evidence is required when max_execution_time is configured"
        fi
        if ! jq -en --arg timeout "$COMMAND_TIMEOUT" --arg max "$MAX_EXECUTION_TIME" '
            ($timeout | test("^[0-9]+(\\.[0-9]+)?$")) and (($timeout | tonumber) <= ($max | tonumber))
        ' > /dev/null 2>&1; then
            write_decision false "$POLICY_ID" "oap.timeout_exceeded" "Command timeout exceeds max_execution_time"
        fi
    fi

    if [ -n "$COMMAND" ]; then
        # SECURITY: Validate command doesn't contain injection characters
        if ! validate_command_string "$COMMAND"; then
            write_decision false "$POLICY_ID" "oap.command_injection_detected" "Command contains potentially dangerous characters"
        fi

        # Check allowed commands using safe prefix matching. A restrictive
        # allowlist can only authorize a single executable segment locally; for
        # chained commands, hosted verification or an explicit wildcard is
        # required so later segments cannot bypass the prefix check.
        ALLOWED_COMMANDS_JSON=$(echo "$LIMITS" | jq -c '.allowed_commands // []' 2> /dev/null || echo "[]")
        HAS_ALLOWED=$(pattern_count "$ALLOWED_COMMANDS_JSON")
        if [ "${HAS_ALLOWED:-0}" -gt 0 ] 2> /dev/null && has_restrictive_limit_array "$ALLOWED_COMMANDS_JSON" && shell_command_has_unquoted_control_operator "$COMMAND"; then
            write_decision false "$POLICY_ID" "oap.command_chain_unsupported" "Command contains shell control operators that cannot be safely authorized against a local command allowlist"
        fi

        COMMAND_ALLOWED=false
        while IFS= read -r allowed_cmd; do
            [ -z "$allowed_cmd" ] && continue
            # Use safe_prefix_match instead of bash glob patterns
            if safe_prefix_match "$COMMAND" "$allowed_cmd"; then
                COMMAND_ALLOWED=true
                break
            fi
        done < <(echo "$ALLOWED_COMMANDS_JSON" | jq -r '.[]? // empty')
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

if [[ "$POLICY_ID" == "web.fetch.v1" ]]; then
    URL=$(echo "$CONTEXT_JSON" | jq -r '.url // ""' 2> /dev/null || true)
    DOMAIN_INPUT=$(echo "$CONTEXT_JSON" | jq -r '.domain // ""' 2> /dev/null || true)
    METHOD=$(echo "$CONTEXT_JSON" | jq -r '.method // "GET"' 2> /dev/null || echo "GET")
    INVALID_URL=$(echo "$CONTEXT_JSON" | jq -r '.invalid_url // false' 2> /dev/null || echo "false")
    DOMAIN_MISMATCH=$(echo "$CONTEXT_JSON" | jq -r '.domain_mismatch // false' 2> /dev/null || echo "false")
    DOMAIN=""
    if [ "$INVALID_URL" = "true" ]; then
        write_decision false "$POLICY_ID" "oap.invalid_url" "URL contains ambiguous parser characters"
    fi
    if [ "$DOMAIN_MISMATCH" = "true" ]; then
        write_decision false "$POLICY_ID" "oap.domain_mismatch" "Provided domain does not match URL host"
    fi
    if [ -n "$URL" ]; then
        case "$URL" in
            http://* | https://*) ;;
            *) write_decision false "$POLICY_ID" "oap.invalid_url" "URL must be an absolute http(s) URL" ;;
        esac
    fi
    if [ -n "$URL" ] && url_has_parser_hazards "$URL"; then
        write_decision false "$POLICY_ID" "oap.invalid_url" "URL contains ambiguous parser characters"
    fi
    if [ -n "$URL" ] && url_authority_has_percent_escape "$URL"; then
        write_decision false "$POLICY_ID" "oap.invalid_url" "URL authority contains percent escapes"
    fi
    if [ -n "$URL" ] && url_authority_has_non_ascii "$URL"; then
        write_decision false "$POLICY_ID" "oap.invalid_url" "URL authority contains non-ASCII characters that require runtime-specific hostname normalization"
    fi
    if [ -n "$DOMAIN_INPUT" ] && url_authority_has_non_ascii "$DOMAIN_INPUT"; then
        write_decision false "$POLICY_ID" "oap.invalid_url" "Domain contains non-ASCII characters that require runtime-specific hostname normalization"
    fi
    if [ -n "$URL" ]; then
        DOMAIN="$(url_host "$URL")"
        if [ -n "$DOMAIN_INPUT" ]; then
            DOMAIN_INPUT_HOST="$(url_host "$DOMAIN_INPUT")"
            if [ -n "$DOMAIN_INPUT_HOST" ] && [ "$DOMAIN_INPUT_HOST" != "$DOMAIN" ]; then
                write_decision false "$POLICY_ID" "oap.domain_mismatch" "Provided domain '$DOMAIN_INPUT_HOST' does not match URL host '$DOMAIN'"
            fi
        fi
    else
        DOMAIN="$(url_host "$DOMAIN_INPUT")"
    fi
    METHOD="$(printf '%s' "$METHOD" | tr '[:lower:]' '[:upper:]')"

    if [ -z "$URL" ] && [ -z "$DOMAIN" ]; then
        write_decision false "$POLICY_ID" "oap.missing_required_context" "Web fetch context must include url or domain for local enforcement"
    fi

    if is_private_network_destination "$DOMAIN"; then
        write_decision false "$POLICY_ID" "oap.private_network_destination" "Private network destination '$DOMAIN' is blocked"
    fi

    for limit_key in allowed_domains blocked_domains allowed_methods; do
        if echo "$LIMITS" | jq -e --arg key "$limit_key" 'has($key) and ((.[$key] | type) != "array" or any(.[$key][]; type != "string"))' > /dev/null 2>&1; then
            write_decision false "$POLICY_ID" "oap.invalid_limit" "$limit_key must be an array of strings when configured"
        fi
    done
    BLOCKED_DOMAINS_JSON=$(echo "$LIMITS" | jq -c 'if (.blocked_domains | type) == "array" then .blocked_domains else [] end' 2> /dev/null || echo "[]")
    if domain_blocked_by_list "$DOMAIN" "$BLOCKED_DOMAINS_JSON"; then
        write_decision false "$POLICY_ID" "oap.domain_blocked" "Domain '$DOMAIN' is blocked"
    fi

    ALLOWED_DOMAINS_JSON=$(echo "$LIMITS" | jq -c 'if (.allowed_domains | type) == "array" then .allowed_domains else [] end' 2> /dev/null || echo "[]")
    if ! domain_allowed_by_list "$DOMAIN" "$ALLOWED_DOMAINS_JSON"; then
        write_decision false "$POLICY_ID" "oap.domain_not_allowed" "Domain '$DOMAIN' is not in allowed list"
    fi

    ALLOWED_METHODS_JSON=$(echo "$LIMITS" | jq -c 'if (.allowed_methods | type) == "array" then .allowed_methods else [] end' 2> /dev/null || echo "[]")
    if has_restrictive_limit_array "$ALLOWED_METHODS_JSON" && ! is_allowed_by_patterns "$METHOD" "$ALLOWED_METHODS_JSON"; then
        write_decision false "$POLICY_ID" "oap.method_not_allowed" "HTTP method '$METHOD' is not in allowed list"
    fi

    enforce_web_fetch_rate_limit
fi

if [[ "$POLICY_ID" == "mcp.tool.execute.v1" ]]; then
    MCP_SERVER=$(echo "$CONTEXT_JSON" | jq -r '.server // .mcp_server // ""' 2> /dev/null || true)
    MCP_TOOL=$(echo "$CONTEXT_JSON" | jq -r '.tool // .mcp_tool // ""' 2> /dev/null || true)
    MCP_TIMEOUT=$(echo "$CONTEXT_JSON" | jq -r '.timeout // empty | if type == "number" then tostring elif type == "string" then . else empty end' 2> /dev/null || true)
    INVALID_MCP_SERVER=$(echo "$CONTEXT_JSON" | jq -r 'if .invalid_server == true then "true" else "false" end' 2> /dev/null || echo false)
    if [ "$INVALID_MCP_SERVER" = "true" ]; then
        write_decision false "$POLICY_ID" "oap.invalid_mcp_server" "MCP server contains ambiguous parser characters"
    fi
    validate_string_array_limits allowed_servers allowed_tools allowed_tool_prefixes
    ALLOWED_SERVERS_JSON=$(echo "$LIMITS" | jq -c 'if (.allowed_servers | type) == "array" then .allowed_servers else [] end' 2> /dev/null || echo "[]")
    ALLOWED_TOOLS_JSON=$(echo "$LIMITS" | jq -c 'if (.allowed_tools | type) == "array" then .allowed_tools else [] end' 2> /dev/null || echo "[]")
    ALLOWED_TOOL_PREFIXES_JSON=$(echo "$LIMITS" | jq -c 'if (.allowed_tool_prefixes | type) == "array" then .allowed_tool_prefixes else [] end' 2> /dev/null || echo "[]")
    MAX_TIMEOUT_RAW=$(echo "$LIMITS" | jq -c 'if has("max_timeout") then .max_timeout else empty end' 2> /dev/null || true)
    MAX_TIMEOUT=""
    if [ -n "$MAX_TIMEOUT_RAW" ]; then
        if ! jq -en --argjson max "$MAX_TIMEOUT_RAW" '
            if ($max | type) == "number" then $max > 0
            elif ($max | type) == "string" then ($max | test("^[0-9]+(\\.[0-9]+)?$") and ($max | tonumber) > 0)
            else false
            end
        ' > /dev/null 2>&1; then
            write_decision false "$POLICY_ID" "oap.invalid_limit" "max_timeout must be a positive number when configured"
        fi
        MAX_TIMEOUT="$(jq -nr --argjson max "$MAX_TIMEOUT_RAW" 'if ($max | type) == "number" then ($max | tostring) else $max end')"
    fi

    if [ -z "$MCP_SERVER" ] && has_restrictive_limit_array "$ALLOWED_SERVERS_JSON"; then
        write_decision false "$POLICY_ID" "oap.missing_required_context" "MCP server is required when allowed_servers is restricted"
    fi
    if [ -n "$MCP_SERVER" ] && ! mcp_server_allowed "$MCP_SERVER" "$ALLOWED_SERVERS_JSON"; then
        write_decision false "$POLICY_ID" "oap.mcp_server_not_allowed" "MCP server '$MCP_SERVER' is not in allowed list"
    fi
    if [ -z "$MCP_TOOL" ] && { has_restrictive_limit_array "$ALLOWED_TOOLS_JSON" || has_restrictive_limit_array "$ALLOWED_TOOL_PREFIXES_JSON"; }; then
        write_decision false "$POLICY_ID" "oap.missing_required_context" "MCP tool is required when allowed_tools or allowed_tool_prefixes is restricted"
    fi
    if [ -n "$MCP_TOOL" ] && ! mcp_tool_allowed "$MCP_TOOL" "$LIMITS"; then
        write_decision false "$POLICY_ID" "oap.mcp_tool_not_allowed" "MCP tool '$MCP_TOOL' is not in allowed list"
    fi
    if [ -n "$MAX_TIMEOUT" ]; then
        if [ -z "$MCP_TIMEOUT" ]; then
            write_decision false "$POLICY_ID" "oap.missing_required_context" "MCP timeout is required when max_timeout is configured"
        fi
        if ! jq -en --arg timeout "$MCP_TIMEOUT" --arg max "$MAX_TIMEOUT" '($timeout | tonumber) <= ($max | tonumber)' > /dev/null 2>&1; then
            write_decision false "$POLICY_ID" "oap.timeout_exceeded" "MCP timeout exceeds max_timeout"
        fi
    fi
fi

if [[ "$POLICY_ID" == "agent.session.create.v1" ]]; then
    enforce_agent_session_concurrency
fi

# File read policy evaluation
if [[ "$POLICY_ID" == "data.file.read.v1" ]]; then
    FILE_PATH=$(echo "$CONTEXT_JSON" | jq -r '.file_path // .path // ""')
    validate_string_array_limits allowed_paths blocked_patterns blocked_paths allowed_extensions
    MAX_FILE_SIZE_BYTES="$(configured_file_size_limit_bytes)"
    reject_invalid_file_size_limit "$MAX_FILE_SIZE_BYTES"
    if [ -z "$FILE_PATH" ]; then
        write_decision false "$POLICY_ID" "oap.missing_file_path" "File read context must include file_path"
    fi
    if [ -n "$FILE_PATH" ]; then
        if [ -d "$FILE_PATH" ] || [[ "$FILE_PATH" == */ ]]; then
            write_decision false "$POLICY_ID" "oap.metadata_enumeration_unsupported" "Directory reads cannot be safely authorized by the local file-read policy"
        fi
        if ! FILE_PATH_CANON="$(canonical_policy_path "$FILE_PATH" 2> /dev/null)"; then
            write_decision false "$POLICY_ID" "oap.invalid_file_path" "File read path could not be safely canonicalized"
        fi
        if is_default_sensitive_read_path "$FILE_PATH" || is_default_sensitive_read_path "$FILE_PATH_CANON"; then
            write_decision false "$POLICY_ID" "oap.blocked_pattern" "File path matches default sensitive read pattern"
        fi
        if [ -n "$MAX_FILE_SIZE_BYTES" ]; then
            if [ ! -f "$FILE_PATH_CANON" ]; then
                write_decision false "$POLICY_ID" "oap.missing_required_context" "File size cannot be safely measured for non-regular read targets"
            fi
            FILE_SIZE_BYTES="$(portable_file_size_bytes "$FILE_PATH_CANON" || true)"
            if [ -z "$FILE_SIZE_BYTES" ]; then
                write_decision false "$POLICY_ID" "oap.missing_required_context" "File size could not be measured for max_file_size enforcement"
            fi
            if ! jq -en --arg size "$FILE_SIZE_BYTES" --arg max "$MAX_FILE_SIZE_BYTES" '($size | tonumber) <= ($max | tonumber)' > /dev/null 2>&1; then
                write_decision false "$POLICY_ID" "oap.file_too_large" "File read target exceeds max_file_size"
            fi
        fi

        # Check allowed paths
        PATH_ALLOWED=false
        while IFS= read -r allowed_path; do
            [ -z "$allowed_path" ] && continue
            if policy_path_matches "$FILE_PATH_CANON" "$allowed_path"; then
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
            if [[ "$FILE_PATH" == *"$pattern"* ]] || [[ "$FILE_PATH" == $pattern ]] || [[ "$FILE_PATH_CANON" == *"$pattern"* ]] || [[ "$FILE_PATH_CANON" == $pattern ]]; then
                write_decision false "$POLICY_ID" "oap.blocked_pattern" "File path matches blocked pattern: $pattern"
            fi
        done < <(echo "$LIMITS" | jq -r '.blocked_patterns[]? // empty')
    fi
fi

# File write policy evaluation
if [[ "$POLICY_ID" == "data.file.write.v1" ]]; then
    FILE_PATH=$(echo "$CONTEXT_JSON" | jq -r '.file_path // .path // ""')
    validate_string_array_limits allowed_paths blocked_paths blocked_patterns allowed_extensions
    if [ -z "$FILE_PATH" ]; then
        write_decision false "$POLICY_ID" "oap.missing_file_path" "File write context must include file_path"
    fi
    if [ -n "$FILE_PATH" ]; then
        if ! FILE_PATH_CANON="$(canonical_policy_path "$FILE_PATH" 2> /dev/null)"; then
            write_decision false "$POLICY_ID" "oap.invalid_file_path" "File write path could not be safely canonicalized"
        fi
        CONTENT_LENGTH=$(echo "$CONTEXT_JSON" | jq -r '(.content_length // .content_size // empty) | if type == "number" then tostring elif type == "string" then . else empty end' 2> /dev/null || true)
        OLD_CONTENT_LENGTH=$(echo "$CONTEXT_JSON" | jq -r '.old_content_length // empty | if type == "number" then tostring elif type == "string" then . else empty end' 2> /dev/null || true)
        RESULTING_CONTENT_LENGTH=$(echo "$CONTEXT_JSON" | jq -r '.resulting_content_length // empty | if type == "number" then tostring elif type == "string" then . else empty end' 2> /dev/null || true)
        PATCH_CONTEXT=$(echo "$CONTEXT_JSON" | jq -r 'if .patch == true then "true" else "false" end' 2> /dev/null || echo "false")
        NOTEBOOK_CONTEXT=$(echo "$CONTEXT_JSON" | jq -r 'if .notebook == true then "true" else "false" end' 2> /dev/null || echo "false")
        NOTEBOOK_SOURCE_LINE_COUNT=$(echo "$CONTEXT_JSON" | jq -r '.notebook_source_line_count // 0 | if type == "number" then tostring elif type == "string" then . else "0" end' 2> /dev/null || echo "0")
        REPLACE_ALL=$(echo "$CONTEXT_JSON" | jq -r 'if .replace_all == true then "true" else "false" end' 2> /dev/null || echo "false")
        WRITE_OPERATION=$(echo "$CONTEXT_JSON" | jq -r '.write_operation // "" | tostring | ascii_downcase' 2> /dev/null || true)
        MAX_FILE_SIZE_BYTES="$(configured_file_size_limit_bytes)"
        reject_invalid_file_size_limit "$MAX_FILE_SIZE_BYTES"
        if [ -n "$MAX_FILE_SIZE_BYTES" ]; then
            case "$CONTENT_LENGTH" in "" | *[!0-9]*) CONTENT_LENGTH="" ;; esac
            case "$OLD_CONTENT_LENGTH" in "" | *[!0-9]*) OLD_CONTENT_LENGTH="" ;; esac
            case "$RESULTING_CONTENT_LENGTH" in "" | *[!0-9]*) RESULTING_CONTENT_LENGTH="" ;; esac
            case "$NOTEBOOK_SOURCE_LINE_COUNT" in "" | *[!0-9]*) NOTEBOOK_SOURCE_LINE_COUNT=0 ;; esac
            if [ "$REPLACE_ALL" = "true" ] && [ -z "$RESULTING_CONTENT_LENGTH" ]; then
                write_decision false "$POLICY_ID" "oap.missing_required_context" "replace_all file edits require resulting_content_length when max_file_size is configured"
            fi
            if [ "$PATCH_CONTEXT" = "true" ] && [ -z "$RESULTING_CONTENT_LENGTH" ]; then
                write_decision false "$POLICY_ID" "oap.missing_required_context" "Patch updates require resulting_content_length when max_file_size is configured"
            fi
            if { [ "$WRITE_OPERATION" = "undo_edit" ] || [ "$WRITE_OPERATION" = "undoedit" ]; } && [ -z "$RESULTING_CONTENT_LENGTH" ]; then
                write_decision false "$POLICY_ID" "oap.missing_required_context" "Undo edits require resulting_content_length when max_file_size is configured"
            fi
            if [ "$NOTEBOOK_CONTEXT" = "true" ] && [ -z "$RESULTING_CONTENT_LENGTH" ]; then
                if { [ "$WRITE_OPERATION" = "delete" ] || [ "$WRITE_OPERATION" = "deletecell" ]; }; then
                    CURRENT_FILE_SIZE="$(wc -c < "$FILE_PATH" 2> /dev/null | tr -d '[:space:]' || true)"
                    case "$CURRENT_FILE_SIZE" in "" | *[!0-9]*) CURRENT_FILE_SIZE="" ;; esac
                    if [ -n "$CURRENT_FILE_SIZE" ]; then
                        RESULTING_CONTENT_LENGTH="$CURRENT_FILE_SIZE"
                    else
                        write_decision false "$POLICY_ID" "oap.missing_required_context" "Notebook delete edits require resulting_content_length or a readable notebook when max_file_size is configured"
                    fi
                else
                    CURRENT_FILE_SIZE="$(wc -c < "$FILE_PATH" 2> /dev/null | tr -d '[:space:]' || true)"
                    case "$CURRENT_FILE_SIZE" in "" | *[!0-9]*) CURRENT_FILE_SIZE="" ;; esac
                    if [ -n "$CURRENT_FILE_SIZE" ] && [ -n "$CONTENT_LENGTH" ]; then
                        RESULTING_CONTENT_LENGTH=$((CURRENT_FILE_SIZE + CONTENT_LENGTH + 2048 + NOTEBOOK_SOURCE_LINE_COUNT * 8))
                    else
                        write_decision false "$POLICY_ID" "oap.missing_required_context" "Notebook edits require resulting_content_length or a readable notebook when max_file_size is configured"
                    fi
                fi
            fi
            if [ -z "$RESULTING_CONTENT_LENGTH" ] && [ "$WRITE_OPERATION" = "insert" ] && [ -n "$CONTENT_LENGTH" ]; then
                CURRENT_FILE_SIZE="$(wc -c < "$FILE_PATH" 2> /dev/null | tr -d '[:space:]' || true)"
                case "$CURRENT_FILE_SIZE" in "" | *[!0-9]*) CURRENT_FILE_SIZE="" ;; esac
                if [ -n "$CURRENT_FILE_SIZE" ]; then
                    RESULTING_CONTENT_LENGTH=$((CURRENT_FILE_SIZE + CONTENT_LENGTH))
                else
                    write_decision false "$POLICY_ID" "oap.missing_required_context" "File insert context must include resulting_content_length when max_file_size is configured"
                fi
            fi
            if [ -z "$RESULTING_CONTENT_LENGTH" ] && [ -n "$OLD_CONTENT_LENGTH" ]; then
                CURRENT_FILE_SIZE="$(wc -c < "$FILE_PATH" 2> /dev/null | tr -d '[:space:]' || true)"
                case "$CURRENT_FILE_SIZE" in "" | *[!0-9]*) CURRENT_FILE_SIZE="" ;; esac
                if [ -n "$CURRENT_FILE_SIZE" ]; then
                    RESULTING_CONTENT_LENGTH=$((CURRENT_FILE_SIZE - OLD_CONTENT_LENGTH + CONTENT_LENGTH))
                    [ "$RESULTING_CONTENT_LENGTH" -ge 0 ] 2> /dev/null || RESULTING_CONTENT_LENGTH="$CONTENT_LENGTH"
                else
                    write_decision false "$POLICY_ID" "oap.missing_required_context" "File edit context must include resulting_content_length when max_file_size is configured"
                fi
            fi
            EFFECTIVE_CONTENT_LENGTH="${RESULTING_CONTENT_LENGTH:-$CONTENT_LENGTH}"
            if [ -z "$EFFECTIVE_CONTENT_LENGTH" ]; then
                write_decision false "$POLICY_ID" "oap.missing_required_context" "File write context must include content_length when max_file_size is configured"
            fi
            if ! jq -en --arg size "$EFFECTIVE_CONTENT_LENGTH" --arg max "$MAX_FILE_SIZE_BYTES" '($size | tonumber) <= ($max | tonumber)' > /dev/null 2>&1; then
                write_decision false "$POLICY_ID" "oap.file_too_large" "File write content exceeds max_file_size"
            fi
        fi

        # Check allowed paths
        PATH_ALLOWED=false
        while IFS= read -r allowed_path; do
            [ -z "$allowed_path" ] && continue
            if policy_path_matches "$FILE_PATH_CANON" "$allowed_path"; then
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
            if policy_path_matches "$FILE_PATH_CANON" "$blocked_path"; then
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

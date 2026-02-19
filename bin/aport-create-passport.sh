#!/bin/bash
# aport-create-passport.sh
# Interactive passport creation wizard (OAP v1.0).
# Use for any framework; for OpenClaw with a custom config directory, run ./bin/openclaw instead.
#
# Usage: ./aport-create-passport.sh [--output FILE] [--non-interactive] [--framework=NAME]
#   --output FILE       Write passport to FILE (overrides framework default).
#   --non-interactive   Use defaults only; no prompts (for CI/tests). Use --output or set APORT_FRAMEWORK for default path.
#   --framework=NAME    Default passport path for this framework (cursor, openclaw, langchain, crewai, n8n).
#
# In interactive mode the first question is "Passport file path [default]:"; you can press Enter for the
# framework default or type a different path. In non-interactive mode, --output always overrides; if not
# given and APORT_FRAMEWORK is set, the framework default path is used.

set -e

PASSPORT_FILE=""
NON_INTERACTIVE=""
# Parse --output, --non-interactive, --framework=
while [ $# -gt 0 ]; do
    case "$1" in
        --output) [ -n "${2:-}" ] && PASSPORT_FILE="$2" && shift ;;
        --non-interactive) NON_INTERACTIVE=1 ;;
        --framework=*) APORT_FRAMEWORK="${1#--framework=}" ;;
    esac
    shift
done

# Repo root and lib for get_default_passport_path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/bin/lib"
if [ -f "$LIB_DIR/config.sh" ]; then
    # shellcheck source=bin/lib/config.sh
    . "$LIB_DIR/config.sh"
fi

# Default passport path: --output wins; else framework-specific default; else OpenClaw legacy path
if [ -z "$PASSPORT_FILE" ]; then
    if [ -n "${APORT_FRAMEWORK:-}" ] && type get_default_passport_path &> /dev/null; then
        PASSPORT_FILE="$(get_default_passport_path "$APORT_FRAMEWORK")"
    else
        PASSPORT_FILE="$HOME/.openclaw/aport/passport.json"
    fi
fi
PASSPORT_FILE="${PASSPORT_FILE/#\~/$HOME}"

# Config dir: from env, or derived from passport path (e.g. .../aport/passport.json -> parent of aport)
if [ -n "${OPENCLAW_CONFIG_DIR:-}" ]; then
    CONFIG_DIR="${OPENCLAW_CONFIG_DIR/#\~/$HOME}"
else
    CONFIG_DIR="$(dirname "$PASSPORT_FILE")"
    case "$PASSPORT_FILE" in
        */aport/passport.json) CONFIG_DIR="$(dirname "$CONFIG_DIR")" ;;
    esac
    CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"
fi
IDENTITY_FILE="$CONFIG_DIR/workspace/IDENTITY.md"

# Repo root for external/aport-spec submodule
SPEC_SCHEMA="$SCRIPT_DIR/external/aport-spec/oap/passport-schema.json"
# OAP spec: spec_version "oap/1.0", limits nested per capability (e.g. limits["system.command.execute"]).
# Local creation has no KYC/assurance proof → L0.
if [ -f "$SPEC_SCHEMA" ] && command -v jq &> /dev/null; then
    DEFAULT_SPEC_VERSION=$(jq -r '.properties.spec_version.const // "oap/1.0"' "$SPEC_SCHEMA")
else
    DEFAULT_SPEC_VERSION="oap/1.0"
fi
[ -z "$DEFAULT_SPEC_VERSION" ] || [ "$DEFAULT_SPEC_VERSION" = "null" ] && DEFAULT_SPEC_VERSION="oap/1.0"
DEFAULT_ASSURANCE_LEVEL="L0"

# --- Smart defaults ---
get_default_email() {
    local e
    e=$(git config user.email 2> /dev/null)
    if [ -n "$e" ]; then
        echo "$e"
        return
    fi
    if command -v gh &> /dev/null; then
        e=$(gh api user --jq '.email // .login + "@users.noreply.github.com"' 2> /dev/null)
        [ -n "$e" ] && echo "$e"
    fi
}

get_identity_name() {
    [ ! -f "$IDENTITY_FILE" ] && return
    # OpenClaw IDENTITY.md: "Name: ..." or "**Name**: ..."
    grep -iE '^\s*\*\{0,2\}Name\*\{0,2\}\s*:' "$IDENTITY_FILE" 2> /dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/^[[:space:]]*//; s/[[:space:]]*$//' | tr -d '\n' | head -c 200
}

get_identity_description() {
    [ ! -f "$IDENTITY_FILE" ] && return
    # Prefer Vibe: or Description: line (case-insensitive)
    local v
    v=$(grep -iE '^\s*\*\{0,2\}(Vibe|Description)\*\{0,2\}\s*:' "$IDENTITY_FILE" 2> /dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/^[[:space:]]*//; s/[[:space:]]*$//' | tr -d '\n')
    if [ -n "$v" ]; then
        echo "$v" | head -c 300
        return
    fi
    awk '/^#/ { next } /^[[:space:]]*$/ { next } { print; exit }' "$IDENTITY_FILE" 2> /dev/null | head -c 300
}

# Avoid set -e exit when git/gh unavailable (e.g. CI with no git user.email)
DEFAULT_EMAIL=$(get_default_email) || true
DEFAULT_EMAIL=${DEFAULT_EMAIL:-"user@example.com"}
DEFAULT_OWNER_TYPE="user"
DEFAULT_AGENT_NAME=$(get_identity_name) || true
DEFAULT_AGENT_NAME=${DEFAULT_AGENT_NAME:-"OpenClaw Agent"}
DEFAULT_AGENT_DESC=$(get_identity_description) || true
DEFAULT_AGENT_DESC=${DEFAULT_AGENT_DESC:-"Local OpenClaw AI agent with APort guardrails"}

if [ -n "$NON_INTERACTIVE" ]; then
    # CI/tests: use defaults, no prompts. Use --output or APORT_FRAMEWORK for default path. Match interactive defaults (README: messaging out of the box).
    owner_id="$DEFAULT_EMAIL"
    owner_type="$DEFAULT_OWNER_TYPE"
    agent_name="$DEFAULT_AGENT_NAME"
    agent_description="$DEFAULT_AGENT_DESC"
    pr_cap=y
    exec_cap=y
    msg_cap=y
    data_cap=n
    max_pr_size=500
    max_prs_per_day=10
    max_msgs_per_day=100
    allowed_repos_input="*"
    exec_allow_scope="*"
    should_expire=n
    never_expires="true"
    expires_at=""
    if command -v uuidgen &> /dev/null; then
        passport_id=$(uuidgen)
    else
        passport_id="local-$(date +%s)-$(openssl rand -hex 4 2> /dev/null || echo $((RANDOM)))"
    fi
else
    echo ""
    echo "  🛂 APort Passport Creation Wizard"
    echo "  ══════════════════════════════════"
    echo ""
    echo "  Creates an Open Agent Passport (OAP v1.0) for your agent."
    echo "  (Press Enter to use the default when shown in brackets.)"
    echo ""
    # First question: where to store the passport (default = framework-specific or OpenClaw path)
    read -p "  Passport file path [$PASSPORT_FILE]: " passport_input
    if [ -n "$passport_input" ]; then
        PASSPORT_FILE="${passport_input/#\~/$HOME}"
    fi
    mkdir -p "$(dirname "$PASSPORT_FILE")"
    CONFIG_DIR="$(dirname "$PASSPORT_FILE")"
    # If passport is in .../aport/passport.json, config dir is parent of aport
    case "$PASSPORT_FILE" in
        */aport/passport.json) CONFIG_DIR="$(dirname "$(dirname "$PASSPORT_FILE")")" ;;
    esac
    CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"
    IDENTITY_FILE="$CONFIG_DIR/workspace/IDENTITY.md"
    echo ""

    # Check if passport already exists
    if [ -f "$PASSPORT_FILE" ]; then
        read -p "  Passport already exists. Overwrite? [y/N]: " overwrite
        if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
            echo "  Aborting. Re-run and choose a different path, or use --output to specify a file."
            exit 1
        fi
        echo ""
    fi

    # Collect user info
    echo "  📋 Owner & agent"
    echo "  ─────────────────"
    echo "  (Press Enter to use the default when shown in brackets.)"
    echo ""
    read -p "  Your email or ID [$DEFAULT_EMAIL]: " owner_id
    owner_id=${owner_id:-"$DEFAULT_EMAIL"}

    read -p "  Owner type (user/org) [$DEFAULT_OWNER_TYPE]: " owner_type
    owner_type=${owner_type:-"$DEFAULT_OWNER_TYPE"}

    read -p "  Agent name [$DEFAULT_AGENT_NAME]: " agent_name
    agent_name=${agent_name:-"$DEFAULT_AGENT_NAME"}

    read -p "  Agent description [$DEFAULT_AGENT_DESC]: " agent_description
    agent_description=${agent_description:-"$DEFAULT_AGENT_DESC"}

    echo ""

    # Choose capabilities
    echo "  🔐 Capabilities"
    echo "  ───────────────"
    echo "  Choose what your agent can do (y/n). Defaults: PRs, exec, and messaging = yes (matches README/docs); data export = no."
    echo ""
    read -p "  • Create and merge pull requests? [Y/n]: " pr_cap
    pr_cap=${pr_cap:-y}

    read -p "  • Execute system commands (npm, git, etc.)? [Y/n]: " exec_cap
    exec_cap=${exec_cap:-y}

    read -p "  • Send messages (email, SMS, etc.)? [Y/n]: " msg_cap
    msg_cap=${msg_cap:-y}

    read -p "  • Export data (database, files, etc.)? [y/N]: " data_cap
    data_cap=${data_cap:-n}

    echo ""

    # Configure limits
    echo "  ⚙️  Limits"
    echo "  ─────────"

    if [ "$pr_cap" = "y" ] || [ "$pr_cap" = "Y" ]; then
        read -p "  Max PR size (files) [500]: " max_pr_size
        max_pr_size=${max_pr_size:-500}

        read -p "  Max PRs per day [10]: " max_prs_per_day
        max_prs_per_day=${max_prs_per_day:-10}

        read -p "  Allowed repos (comma-separated, * for all) [*]: " allowed_repos_input
        allowed_repos_input=${allowed_repos_input:-"*"}
    fi

    if [ "$exec_cap" = "y" ] || [ "$exec_cap" = "Y" ]; then
        echo "  Shell commands: default is allow any (*); blocked patterns (rm -rf, sudo, etc.) still apply."
        echo "  Press Enter or type * for allow any; type 'list' for a fixed list (ls, mkdir, npm, …)."
        read -p "  [Enter or *=allow any / list=fixed list]: " exec_allow_scope
        exec_allow_scope=${exec_allow_scope:-*}
    fi

    if [ "$msg_cap" = "y" ] || [ "$msg_cap" = "Y" ]; then
        read -p "  Max messages per day [100]: " max_msgs_per_day
        max_msgs_per_day=${max_msgs_per_day:-100}
    fi

    if [ "$data_cap" = "y" ] || [ "$data_cap" = "Y" ]; then
        read -p "  Max export rows [10000]: " max_export_rows
        max_export_rows=${max_export_rows:-10000}

        read -p "  Allow PII export? [y/N]: " allow_pii
        allow_pii=${allow_pii:-n}
        if [ "$allow_pii" = "y" ] || [ "$allow_pii" = "Y" ]; then
            allow_pii_bool="true"
        else
            allow_pii_bool="false"
        fi
    fi

    echo ""

    # Generate passport ID
    if command -v uuidgen &> /dev/null; then
        passport_id=$(uuidgen)
    else
        passport_id="local-$(date +%s)-$(openssl rand -hex 4 2> /dev/null || echo $((RANDOM)))"
    fi

    # Ask about expiration
    echo "  📅 Expiration"
    echo "  ─────────────"
    read -p "  Should this passport expire? [y/N]: " should_expire
    should_expire=${should_expire:-n}

    if [ "$should_expire" = "y" ] || [ "$should_expire" = "Y" ]; then
        read -p "  Days until expiration [30]: " expire_days
        expire_days=${expire_days:-30}

        # Calculate expiration date
        if date -v+${expire_days}d &> /dev/null 2>&1; then
            # BSD date (macOS)
            expires_at=$(date -u -v+${expire_days}d +%Y-%m-%dT%H:%M:%SZ)
        else
            # GNU date (Linux)
            expires_at=$(date -u -d "+${expire_days} days" +%Y-%m-%dT%H:%M:%SZ)
        fi
        never_expires="false"
    else
        expires_at=""
        never_expires="true"
    fi

fi
# End of interactive branch; non-interactive already set never_expires/expires_at above.

# Build capabilities array
capabilities_json="["
if [ "$pr_cap" = "y" ] || [ "$pr_cap" = "Y" ]; then
    capabilities_json="$capabilities_json{\"id\": \"repo.pr.create\"},"
    capabilities_json="$capabilities_json{\"id\": \"repo.merge\"},"
fi
if [ "$exec_cap" = "y" ] || [ "$exec_cap" = "Y" ]; then
    capabilities_json="$capabilities_json{\"id\": \"system.command.execute\"},"
fi
# Capability IDs must match agent-passport policy requires_capabilities (e.g. messaging.message.send.v1 → messaging.send)
if [ "$msg_cap" = "y" ] || [ "$msg_cap" = "Y" ]; then
    capabilities_json="$capabilities_json{\"id\": \"messaging.send\"},"
fi
if [ "$data_cap" = "y" ] || [ "$data_cap" = "Y" ]; then
    capabilities_json="$capabilities_json{\"id\": \"data.export\"},"
fi
# Remove trailing comma
capabilities_json="${capabilities_json%,}]"

# Build limits object
limits_json="{"

if [ "$pr_cap" = "y" ] || [ "$pr_cap" = "Y" ]; then
    # Parse allowed repos
    IFS=',' read -ra REPOS <<< "$allowed_repos_input"
    allowed_repos_json="["
    for repo in "${REPOS[@]}"; do
        repo=$(echo "$repo" | xargs) # trim whitespace
        allowed_repos_json="$allowed_repos_json\"$repo\","
    done
    allowed_repos_json="${allowed_repos_json%,}]"

    limits_json="$limits_json\"code.repository.merge\": {\"max_prs_per_day\": $max_prs_per_day, \"max_merges_per_day\": 5, \"max_pr_size_kb\": $max_pr_size, \"allowed_repos\": $allowed_repos_json, \"allowed_base_branches\": [\"*\"], \"require_review\": false},"
fi

if [ "$exec_cap" = "y" ] || [ "$exec_cap" = "Y" ]; then
    exec_allow_lower=$(echo "$exec_allow_scope" | tr 'A-Z' 'a-z')
    if [ "$exec_allow_lower" = "list" ]; then
        allowed_commands_json="[\"npm\", \"yarn\", \"git\", \"node\", \"pnpm\", \"npx\", \"bash\", \"sh\", \"mkdir\", \"cp\", \"ls\", \"cat\", \"echo\", \"pwd\", \"mv\", \"touch\", \"which\", \"open\"]"
    else
        # default: allow any (*); blocked_patterns still apply
        allowed_commands_json="[\"*\"]"
    fi
    limits_json="$limits_json\"system.command.execute\": {\"allowed_commands\": $allowed_commands_json, \"blocked_patterns\": [\"rm -rf\", \"sudo\", \"chmod 777\", \"dd if=\", \"mkfs\"], \"max_execution_time\": 300},"
fi

if [ "$msg_cap" = "y" ] || [ "$msg_cap" = "Y" ]; then
    # API/verifier expect flat keys at top level of limits (not nested under messaging.message.send)
    limits_json="$limits_json\"msgs_per_min\": 5, \"msgs_per_day\": $max_msgs_per_day, \"allowed_recipients\": [\"*\"], \"approval_required\": false,"
fi

if [ "$data_cap" = "y" ] || [ "$data_cap" = "Y" ]; then
    limits_json="$limits_json\"data.export\": {\"max_rows\": $max_export_rows, \"allow_pii\": $allow_pii_bool, \"allowed_collections\": [\"*\"]},"
fi

# Remove trailing comma
limits_json="${limits_json%,}}"

# Build metadata object using jq
metadata_json=$(jq -n \
    --arg name "$agent_name" \
    --arg desc "$agent_description" \
    '{
    name: $name,
    description: $desc,
    version: "1.0.0",
    created_by: "aport-create-passport.sh"
  }')

# Create passport JSON (OAP v1.0 compliant)
mkdir -p "$(dirname "$PASSPORT_FILE")"
current_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# API expects both agent_id and owner_id; use passport_id as agent_id for local passports
if [ "$never_expires" = "true" ]; then
    # Passport without expiration (assurance_level and spec_version from external/aport-spec)
    cat > "$PASSPORT_FILE.tmp" << EOF
{
  "passport_id": "$passport_id",
  "agent_id": "$passport_id",
  "kind": "template",
  "spec_version": "$DEFAULT_SPEC_VERSION",
  "owner_id": "$owner_id",
  "owner_type": "$owner_type",
  "assurance_level": "$DEFAULT_ASSURANCE_LEVEL",
  "status": "active",
  "capabilities": $capabilities_json,
  "limits": $limits_json,
  "regions": ["US", "CA"],
  "metadata": $metadata_json,
  "never_expires": true,
  "created_at": "$current_timestamp",
  "updated_at": "$current_timestamp",
  "version": "1.0.0"
}
EOF
else
    # Passport with expiration (assurance_level and spec_version from external/aport-spec)
    cat > "$PASSPORT_FILE.tmp" << EOF
{
  "passport_id": "$passport_id",
  "agent_id": "$passport_id",
  "kind": "template",
  "spec_version": "$DEFAULT_SPEC_VERSION",
  "owner_id": "$owner_id",
  "owner_type": "$owner_type",
  "assurance_level": "$DEFAULT_ASSURANCE_LEVEL",
  "status": "active",
  "capabilities": $capabilities_json,
  "limits": $limits_json,
  "regions": ["US", "CA"],
  "metadata": $metadata_json,
  "expires_at": "$expires_at",
  "created_at": "$current_timestamp",
  "updated_at": "$current_timestamp",
  "version": "1.0.0"
}
EOF
fi

# Format JSON with jq if available
if command -v jq &> /dev/null; then
    jq . "$PASSPORT_FILE.tmp" > "$PASSPORT_FILE"
    rm "$PASSPORT_FILE.tmp"
else
    mv "$PASSPORT_FILE.tmp" "$PASSPORT_FILE"
    echo "  ⚠️  jq not found; passport JSON not pretty-printed."
fi
# Restrict permissions: passport holds allowlists and identity
chmod 600 "$PASSPORT_FILE" 2> /dev/null || true

echo ""
echo "  ✅ Passport created successfully!"
echo ""
echo "  📋 Summary"
echo "  ──────────"
echo "    Location:    $PASSPORT_FILE"
echo "    Passport ID: $passport_id"
echo "    Owner:       $owner_id ($owner_type)"
echo "    Agent:       $agent_name"
echo "    Status:      active"
echo "    Spec:        oap/1.0"
if [ "$never_expires" = "true" ]; then
    echo "    Expiration:  Never"
else
    echo "    Expires:     $expires_at"
fi
echo ""
echo "  🔐 Capabilities:"
[ "$pr_cap" = "y" ] || [ "$pr_cap" = "Y" ] && echo "    • Create and merge pull requests"
[ "$exec_cap" = "y" ] || [ "$exec_cap" = "Y" ] && echo "    • Execute system commands"
[ "$msg_cap" = "y" ] || [ "$msg_cap" = "Y" ] && echo "    • Send messages"
[ "$data_cap" = "y" ] || [ "$data_cap" = "Y" ] && echo "    • Export data"
echo ""
echo "  📝 Next steps:"
echo "    • Review limits:  vim $PASSPORT_FILE"
echo "    • Test guardrail: aport-guardrail.sh system.command.execute '{\"command\":\"node --version\"}'; echo \"Exit: \$? (0=ALLOW, 1=DENY)\""
echo "    • View status:    aport-status.sh"
echo ""
if [ "$never_expires" != "true" ]; then
    echo "  💡 Passport expires in $expire_days days. Renew before then."
fi
echo ""

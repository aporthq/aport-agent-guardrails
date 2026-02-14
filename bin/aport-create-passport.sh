#!/bin/bash
# aport-create-passport.sh
# Interactive passport creation wizard for OpenClaw + APort integration
#
# Usage: ./aport-create-passport.sh [--output FILE]

set -e

PASSPORT_FILE="${1:-$HOME/.openclaw/passport.json}"

if [ "$1" = "--output" ] && [ -n "$2" ]; then
    PASSPORT_FILE="$2"
fi

echo "🛂 APort Passport Creation Wizard"
echo "=================================="
echo
echo "This wizard will create an Open Agent Passport (OAP v1.0) for your OpenClaw agent."
echo "The passport defines what your agent can do and operational limits."
echo

# Check if passport already exists
if [ -f "$PASSPORT_FILE" ]; then
    read -p "Passport already exists at $PASSPORT_FILE. Overwrite? [y/N]: " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "Aborting. Use --output to specify a different file."
        exit 1
    fi
fi

# Collect user info
echo "📋 Owner Information"
echo "--------------------"
read -p "Your email or ID: " owner_id
owner_id=${owner_id:-"user@example.com"}

read -p "Owner type (user/org) [user]: " owner_type
owner_type=${owner_type:-"user"}

read -p "Agent name [OpenClaw Agent]: " agent_name
agent_name=${agent_name:-"OpenClaw Agent"}

read -p "Agent description: " agent_description
agent_description=${agent_description:-"Local OpenClaw AI agent with APort guardrails"}

echo

# Choose capabilities
echo "🔐 Select Capabilities"
echo "----------------------"
echo "Choose what your agent can do (y/n for each):"
echo

read -p "  • Create and merge pull requests? [Y/n]: " pr_cap
pr_cap=${pr_cap:-y}

read -p "  • Execute system commands (npm, git, etc.)? [Y/n]: " exec_cap
exec_cap=${exec_cap:-y}

read -p "  • Send messages (email, SMS, etc.)? [y/N]: " msg_cap
msg_cap=${msg_cap:-n}

read -p "  • Export data (database, files, etc.)? [y/N]: " data_cap
data_cap=${data_cap:-n}

echo

# Configure limits
echo "⚙️  Configure Limits"
echo "--------------------"

if [ "$pr_cap" = "y" ] || [ "$pr_cap" = "Y" ]; then
    read -p "Max PR size (files) [500]: " max_pr_size
    max_pr_size=${max_pr_size:-500}

    read -p "Max PRs per day [10]: " max_prs_per_day
    max_prs_per_day=${max_prs_per_day:-10}

    read -p "Allowed repos (comma-separated, * for all) [*]: " allowed_repos_input
    allowed_repos_input=${allowed_repos_input:-"*"}
fi

if [ "$exec_cap" = "y" ] || [ "$exec_cap" = "Y" ]; then
    echo "  Default allowed commands: npm, yarn, git, node, pnpm"
    echo "  Default blocked patterns: rm -rf, sudo, chmod 777"
fi

if [ "$msg_cap" = "y" ] || [ "$msg_cap" = "Y" ]; then
    read -p "Max messages per day [100]: " max_msgs_per_day
    max_msgs_per_day=${max_msgs_per_day:-100}
fi

if [ "$data_cap" = "y" ] || [ "$data_cap" = "Y" ]; then
    read -p "Max export rows [10000]: " max_export_rows
    max_export_rows=${max_export_rows:-10000}

    read -p "Allow PII export? [y/N]: " allow_pii
    allow_pii=${allow_pii:-n}
    if [ "$allow_pii" = "y" ] || [ "$allow_pii" = "Y" ]; then
        allow_pii_bool="true"
    else
        allow_pii_bool="false"
    fi
fi

echo

# Generate passport ID
if command -v uuidgen &> /dev/null; then
    passport_id=$(uuidgen)
else
    passport_id="local-$(date +%s)-$(openssl rand -hex 4 2>/dev/null || echo $(( RANDOM )))"
fi

# Ask about expiration
read -p "Should this passport expire? [y/N]: " should_expire
should_expire=${should_expire:-n}

if [ "$should_expire" = "y" ] || [ "$should_expire" = "Y" ]; then
    read -p "Days until expiration [30]: " expire_days
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

# Build capabilities array
capabilities_json="["
if [ "$pr_cap" = "y" ] || [ "$pr_cap" = "Y" ]; then
    capabilities_json="$capabilities_json{\"id\": \"repo.pr.create\"},"
    capabilities_json="$capabilities_json{\"id\": \"repo.merge\"},"
fi
if [ "$exec_cap" = "y" ] || [ "$exec_cap" = "Y" ]; then
    capabilities_json="$capabilities_json{\"id\": \"system.command.execute\"},"
fi
if [ "$msg_cap" = "y" ] || [ "$msg_cap" = "Y" ]; then
    capabilities_json="$capabilities_json{\"id\": \"messaging.message.send\"},"
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
        repo=$(echo "$repo" | xargs)  # trim whitespace
        allowed_repos_json="$allowed_repos_json\"$repo\","
    done
    allowed_repos_json="${allowed_repos_json%,}]"

    limits_json="$limits_json\"code.repository.merge\": {\"max_prs_per_day\": $max_prs_per_day, \"max_merges_per_day\": 5, \"max_pr_size_kb\": $max_pr_size, \"allowed_repos\": $allowed_repos_json, \"allowed_base_branches\": [\"*\"], \"require_review\": false},"
fi

if [ "$exec_cap" = "y" ] || [ "$exec_cap" = "Y" ]; then
    limits_json="$limits_json\"system.command.execute\": {\"allowed_commands\": [\"npm\", \"yarn\", \"git\", \"node\", \"pnpm\", \"bash\", \"sh\"], \"blocked_patterns\": [\"rm -rf\", \"sudo\", \"chmod 777\", \"dd if=\", \"mkfs\"], \"max_execution_time\": 300},"
fi

if [ "$msg_cap" = "y" ] || [ "$msg_cap" = "Y" ]; then
    limits_json="$limits_json\"messaging.message.send\": {\"msgs_per_min\": 5, \"msgs_per_day\": $max_msgs_per_day, \"allowed_recipients\": [\"*\"], \"approval_required\": false},"
fi

if [ "$data_cap" = "y" ] || [ "$data_cap" = "Y" ]; then
    limits_json="$limits_json\"data.export\": {\"max_rows\": $max_export_rows, \"allow_pii\": $allow_pii_bool, \"allowed_collections\": [\"*\"]},"
fi

# Remove trailing comma
limits_json="${limits_json%,}}"

# Build metadata object
metadata_json=$(cat <<METADATA_EOF
{
  "name": $(echo "$agent_name" | jq -R .),
  "description": $(echo "$agent_description" | jq -R .),
  "version": "1.0.0",
  "created_by": "aport-create-passport.sh"
}
METADATA_EOF
)

# Create passport JSON (OAP v1.0 compliant)
current_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$never_expires" = "true" ]; then
    # Passport without expiration
    cat > "$PASSPORT_FILE.tmp" <<EOF
{
  "passport_id": "$passport_id",
  "kind": "template",
  "spec_version": "oap/1.0",
  "owner_id": "$owner_id",
  "owner_type": "$owner_type",
  "assurance_level": "L2",
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
    # Passport with expiration
    cat > "$PASSPORT_FILE.tmp" <<EOF
{
  "passport_id": "$passport_id",
  "kind": "template",
  "spec_version": "oap/1.0",
  "owner_id": "$owner_id",
  "owner_type": "$owner_type",
  "assurance_level": "L2",
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
    echo "⚠️  Warning: jq not found. Passport JSON not pretty-printed."
fi

echo "✅ Passport created successfully!"
echo
echo "📋 Passport Summary"
echo "-------------------"
echo "  Location: $PASSPORT_FILE"
echo "  Passport ID: $passport_id"
echo "  Owner: $owner_id ($owner_type)"
echo "  Agent: $agent_name"
echo "  Status: active"
echo "  Spec Version: oap/1.0"
if [ "$never_expires" = "true" ]; then
    echo "  Expiration: Never expires"
else
    echo "  Expires: $expires_at"
fi
echo
echo "🔐 Capabilities Enabled:"
[ "$pr_cap" = "y" ] || [ "$pr_cap" = "Y" ] && echo "  • Create and merge pull requests"
[ "$exec_cap" = "y" ] || [ "$exec_cap" = "Y" ] && echo "  • Execute system commands"
[ "$msg_cap" = "y" ] || [ "$msg_cap" = "Y" ] && echo "  • Send messages"
[ "$data_cap" = "y" ] || [ "$data_cap" = "Y" ] && echo "  • Export data"
echo
echo "📝 Next Steps:"
echo "  1. Review and customize limits:"
echo "     vim $PASSPORT_FILE"
echo "  2. Test policy enforcement:"
echo "     aport-guardrail.sh git.create_pr '{\"repo\":\"test\",\"files_changed\":10}'"
echo "  3. View status:"
echo "     aport-status.sh"
echo "  4. Add to AGENTS.md:"
echo "     cat docs/AGENTS.md.example >> ~/.openclaw/AGENTS.md"
echo
if [ "$never_expires" != "true" ]; then
    echo "💡 Tip: Passport expires in $expire_days days. Renew before expiration."
fi
echo

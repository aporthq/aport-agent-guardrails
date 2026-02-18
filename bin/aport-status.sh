#!/bin/bash
# aport-status.sh
# Display APort passport status and recent activity
#
# Usage: ./aport-status.sh [--passport FILE]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/aport-resolve-paths.sh
. "${SCRIPT_DIR}/bin/aport-resolve-paths.sh"

if [ "$1" = "--passport" ] && [ -n "$2" ]; then
    PASSPORT_FILE="$2"
fi

echo "🛂 APort Status Dashboard"
echo "========================="
echo

# Passport info (passport status is source of truth for suspend; no separate kill-switch file)
if [ ! -f "$PASSPORT_FILE" ]; then
    echo "❌ Passport: NOT FOUND"
    echo "   Location: $PASSPORT_FILE"
    echo "   Create one with: aport-create-passport.sh"
    echo
    exit 1
fi

echo "📋 Passport Information"
echo "   Location: $PASSPORT_FILE"

# Check jq availability
if ! command -v jq &> /dev/null; then
    echo "   ⚠️  jq not found - install with: brew install jq"
    echo
    exit 1
fi

echo "   ID: $(jq -r '.passport_id // "unknown"' $PASSPORT_FILE)"
echo "   Kind: $(jq -r '.kind // "unknown"' $PASSPORT_FILE)"
echo "   Owner: $(jq -r '.owner_id // "unknown"' $PASSPORT_FILE) ($(jq -r '.owner_type // "unknown"' $PASSPORT_FILE))"
echo "   Spec Version: $(jq -r '.spec_version // "unknown"' $PASSPORT_FILE)"
echo "   Assurance Level: $(jq -r '.assurance_level // "unknown"' $PASSPORT_FILE)"

# Status with color
status=$(jq -r '.status // "unknown"' $PASSPORT_FILE)
if [ "$status" = "active" ]; then
    echo "   Status: ✅ active"
elif [ "$status" = "suspended" ]; then
    echo "   Status: 🔴 suspended"
elif [ "$status" = "revoked" ]; then
    echo "   Status: ❌ revoked"
else
    echo "   Status: ⚠️  $status"
fi

# Display agent metadata if available
agent_name=$(jq -r '.metadata.name // ""' $PASSPORT_FILE)
if [ -n "$agent_name" ] && [ "$agent_name" != "null" ]; then
    echo "   Agent Name: $agent_name"
fi

# Expiration with warning
never_expires=$(jq -r '.never_expires // "false"' $PASSPORT_FILE)
expires_at=$(jq -r '.expires_at // "null"' $PASSPORT_FILE)

if [ "$never_expires" = "true" ]; then
    echo "   Expires: Never"
elif [ "$expires_at" != "null" ] && [ "$expires_at" != "unknown" ]; then
    echo "   Expires: $expires_at"

    # Calculate days until expiration
    if date -v+1d &> /dev/null 2>&1; then
        # BSD date (macOS)
        expires_ts=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$expires_at" +%s 2>/dev/null || echo 0)
    else
        # GNU date (Linux)
        expires_ts=$(date -d "$expires_at" +%s 2>/dev/null || echo 0)
    fi

    now_ts=$(date +%s)
    days_left=$(( ($expires_ts - $now_ts) / 86400 ))

    if [ $days_left -le 0 ]; then
        echo "   ⚠️  EXPIRED $((days_left * -1)) days ago"
    elif [ $days_left -le 7 ]; then
        echo "   ⚠️  Expires in $days_left days - renew soon!"
    else
        echo "   ✅ $days_left days until expiration"
    fi
else
    echo "   Expires: Not set"
fi

echo

# Capabilities
echo "🔐 Capabilities"
cap_count=$(jq '.capabilities | length' $PASSPORT_FILE)
if [ "$cap_count" -eq 0 ]; then
    echo "   (none configured)"
else
    jq -r '.capabilities[].id // empty' $PASSPORT_FILE | while read cap; do
        echo "   • $cap"
    done
fi

echo

# Limits summary
echo "⚙️  Limits"
jq -r '.limits | keys[]? // empty' $PASSPORT_FILE | while read policy; do
    echo "   • $policy:"
    case "$policy" in
        "code.repository.merge")
            max_prs=$(jq -r ".limits.\"$policy\".max_prs_per_day // \"unlimited\"" $PASSPORT_FILE)
            max_size=$(jq -r ".limits.\"$policy\".max_pr_size_kb // \"unlimited\"" $PASSPORT_FILE)
            echo "     - Max PRs/day: $max_prs"
            echo "     - Max PR size: $max_size files"
            ;;
        "system.command.execute")
            max_time=$(jq -r ".limits.\"$policy\".max_execution_time // \"unlimited\"" $PASSPORT_FILE)
            echo "     - Max execution time: $max_time seconds"
            blocked_count=$(jq ".limits.\"$policy\".blocked_patterns | length" $PASSPORT_FILE)
            echo "     - Blocked patterns: $blocked_count"
            ;;
        "messaging.message.send")
            msgs_per_day=$(jq -r ".limits.\"$policy\".msgs_per_day // \"unlimited\"" $PASSPORT_FILE)
            echo "     - Messages/day: $msgs_per_day"
            ;;
        "data.export")
            max_rows=$(jq -r ".limits.\"$policy\".max_rows // \"unlimited\"" $PASSPORT_FILE)
            allow_pii=$(jq -r ".limits.\"$policy\".allow_pii // false" $PASSPORT_FILE)
            echo "     - Max rows: $max_rows"
            echo "     - PII export: $allow_pii"
            ;;
    esac
done

echo

# Latest decision (OAP v1.0 format)
if [ -f "$DECISION_FILE" ]; then
    echo "🔍 Latest Decision"
    allow=$(jq -r '.allow // "unknown"' $DECISION_FILE)
    decision_id=$(jq -r '.decision_id // "unknown"' $DECISION_FILE)
    policy_id=$(jq -r '.policy_id // "unknown"' $DECISION_FILE)

    if [ "$allow" = "true" ]; then
        echo "   ✅ ALLOW"
    else
        echo "   ❌ DENY"
    fi
    echo "   Decision ID: $decision_id"
    echo "   Policy ID: $policy_id"

    # Display OAP v1.0 reasons array
    reasons_count=$(jq '.reasons | length' $DECISION_FILE 2>/dev/null || echo 0)
    if [ "$reasons_count" -gt 0 ]; then
        echo "   Reasons:"
        jq -r '.reasons[] | "     - [\(.code)] \(.message)"' $DECISION_FILE
    fi

    # Display issued_at and expires_at
    issued_at=$(jq -r '.issued_at // "unknown"' $DECISION_FILE)
    expires_at_decision=$(jq -r '.expires_at // "unknown"' $DECISION_FILE)
    if [ "$issued_at" != "unknown" ]; then
        echo "   Issued: $issued_at"
    fi
    if [ "$expires_at_decision" != "unknown" ]; then
        echo "   Expires: $expires_at_decision"
    fi

    # Display signature info
    kid=$(jq -r '.kid // "unknown"' $DECISION_FILE)
    if [ "$kid" != "unknown" ]; then
        echo "   Key ID: $kid"
    fi
    # Show capability context from last audit line (command, recipient, repo/branch)
    if [ -f "$AUDIT_LOG" ] && [ -s "$AUDIT_LOG" ]; then
        last_context=$(tail -1 "$AUDIT_LOG" | sed -n 's/.*context="\([^"]*\)".*/\1/p')
        if [ -n "$last_context" ]; then
            echo "   Context: $last_context"
        fi
    fi
    echo
fi

# Recent activity
echo "📊 Recent Activity (last 10)"
if [ -f "$AUDIT_LOG" ] && [ -s "$AUDIT_LOG" ]; then
    tail -10 "$AUDIT_LOG" | while IFS= read -r line; do
        # Parse log line: [timestamp] tool=X decision_id=Y allow=Z ... context="..." (optional)
        timestamp=$(echo "$line" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
        tool=$(echo "$line" | sed -n 's/.*tool=\([^ ]*\).*/\1/p')
        allow=$(echo "$line" | sed -n 's/.*allow=\([^ ]*\).*/\1/p')
        context=$(echo "$line" | sed -n 's/.*context="\([^"]*\)".*/\1/p')
        timestamp=${timestamp:-unknown}
        tool=${tool:-unknown}
        allow=${allow:-unknown}

        short_time=$(echo "$timestamp" | cut -d' ' -f1-2 | cut -d'.' -f1)
        # Show capability + context when present (e.g. "exec.run | cat test.md"); truncate long context
        if [ -n "$context" ]; then
            context_show=$(printf '%.80s' "$context")
            [ "${#context}" -gt 80 ] && context_show="${context_show}..."
            detail="$tool | $context_show"
        else
            detail="$tool"
        fi

        if [ "$allow" = "true" ]; then
            printf "   ✅ %s | %s\n" "$short_time" "$detail"
        else
            printf "   ❌ %s | %s\n" "$short_time" "$detail"
        fi
    done
else
    echo "   (no activity yet)"
fi

echo

# Usage statistics (sanitize numbers for macOS/BSD)
if [ -f "$AUDIT_LOG" ] && [ -s "$AUDIT_LOG" ]; then
    echo "📈 Statistics (all time)"
    total_actions=$(wc -l < "$AUDIT_LOG" | tr -d '[:space:]')
    total_actions=${total_actions:-0}
    allowed=$(grep -c "allow=true" "$AUDIT_LOG" 2>/dev/null || true)
    allowed=$(echo "$allowed" | tr -d '[:space:]')
    allowed=${allowed:-0}
    denied=$(grep -c "allow=false" "$AUDIT_LOG" 2>/dev/null || true)
    denied=$(echo "$denied" | tr -d '[:space:]')
    denied=${denied:-0}

    echo "   Total actions: $total_actions"
    echo "   Allowed: $allowed"
    echo "   Denied: $denied"

    if [ -n "$total_actions" ] && [ "$total_actions" -gt 0 ] 2>/dev/null; then
        allow_pct=$(( 100 * allowed / total_actions ))
        echo "   Allow rate: ${allow_pct}%"
    fi
    echo
fi

# Commands
echo "💡 Useful Commands"
echo "   • View full audit log: tail -f $AUDIT_LOG"
echo "   • Edit passport: vim $PASSPORT_FILE"
echo "   • Test policy: aport-guardrail.sh <tool_name> '<context_json>'"
echo "   • Suspend agent (local): set passport status to \"suspended\" in $PASSPORT_FILE (edit with jq or editor)"
echo "   • Resume: set status back to \"active\""
echo

# Upgrade hint (show once per day)
HINT_FILE="$HOME/.openclaw/.last-status-upgrade-hint"
if [ ! -f "$HINT_FILE" ] || [ $(( $(date +%s) - $(stat -f %m "$HINT_FILE" 2>/dev/null || stat -c %Y "$HINT_FILE" 2>/dev/null || echo 0) )) -gt 86400 ]; then
    echo "💰 Upgrade to APort Cloud?"
    echo "   You're using APort Local (free tier) - perfect for individual developers!"
    echo
    echo "   Upgrade to APort Cloud for teams:"
    echo "   • Multi-machine sync (passport changes propagate <15s)"
    echo "   • Global suspend (remote passports): log in at aport.io and suspend passport; all agents using it deny in <30s"
    echo "   • Ed25519 signed audit logs (court-admissible, SOC 2/IIROC compliant)"
    echo "   • Team collaboration (shared passports, role-based policies)"
    echo "   • Analytics dashboard (usage metrics, risk scoring, anomaly detection)"
    echo
    echo "   Pricing: $99/user/month (Pro) | $149/user/month (Enterprise)"
    echo "   Free trial: https://aport.io/trial"
    echo "   Learn more: https://aport.io/upgrade"
    echo

    touch "$HINT_FILE"
fi

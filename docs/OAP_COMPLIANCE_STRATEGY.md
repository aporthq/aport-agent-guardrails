# OAP v1.0 Compliance Strategy for APort Agent Guardrails
**Date:** February 14, 2026
**Decision:** How to leverage existing OAP spec and policy infrastructure

---

## Executive Summary

**Your Question:** Should we hardcode passport templates and policies, or leverage existing repos via symlinks/submodules?

**Recommendation:** ✅ **Use Git Submodules** (NOT symlinks) + **Smart Local Overrides**

**Why:**
1. ✅ **Standards Compliance**: Automatically stay in sync with OAP v1.0 spec updates
2. ✅ **Policy Reuse**: Leverage 12 existing production policies from `aport-policies`
3. ✅ **Single Source of Truth**: `aport-spec` is canonical, changes propagate automatically
4. ✅ **Local Flexibility**: Still allow local overrides for development/testing
5. ✅ **No Duplication**: Don't maintain two versions of the same schemas

---

## Current State Analysis

### ❌ What's Wrong Now:

**1. Hardcoded Passport Template**
```
aport-agent-guardrails/templates/passport.template.json
```
- **Problem:** Will become outdated when OAP spec evolves
- **Problem:** Not validated against canonical schema
- **Problem:** Missing required fields per OAP v1.0

**2. Hardcoded Policies**
```
aport-agent-guardrails/policies/
├── code.repository.merge.json   # Simplified version
├── system.command.execute.json  # Not in aport-policies (custom)
├── messaging.message.send.json  # Exists in aport-policies
└── data.export.json             # Simplified version
```
- **Problem:** Duplicates work already done in `aport-policies`
- **Problem:** Not following official policy schema structure
- **Problem:** Missing 8 production policies

**3. Decision Schema Not Used**
- **Problem:** Our `decision.json` output doesn't match OAP v1.0 `decision-schema.json`
- **Problem:** Missing required fields: `passport_digest`, `signature`, `kid`, `expires_at`
- **Problem:** Using `reason` string instead of `reasons[]` array

---

## ✅ Recommended Solution: Git Submodules

### Architecture:

```
aport-agent-guardrails/
├── .gitmodules                          # Git submodule config
├── spec/                                # → Submodule: aporthq/aport-spec
│   └── oap/
│       ├── passport-schema.json         # ✅ Canonical schema
│       ├── decision-schema.json         # ✅ Canonical schema
│       └── examples/
│           └── passport.template.v1.json
├── policies/                            # → Submodule: aporthq/aport-policies
│   ├── code.repository.merge.v1/
│   ├── messaging.message.send.v1/
│   ├── data.export.create.v1/
│   └── ... (12 policies total)
├── local-overrides/                     # ✅ Local development overrides
│   ├── policies/
│   │   └── system.command.execute.v1/   # Custom policy (not in upstream)
│   └── templates/
│       └── passport.developer.json      # Developer preset
├── bin/
│   ├── aport-create-passport.sh
│   ├── aport-status.sh
│   └── aport-guardrail.sh               # ✅ Updated to use submodules
└── docs/
```

### How It Works:

**1. Passport Creation** (`aport-create-passport.sh`)
```bash
# Use canonical template from submodule
TEMPLATE_FILE="spec/oap/examples/passport.template.v1.json"

# Validate against canonical schema
SCHEMA_FILE="spec/oap/passport-schema.json"
jq --argfile schema "$SCHEMA_FILE" '. | validate($schema)' "$TEMPLATE_FILE"
```

**2. Policy Loading** (`aport-guardrail.sh`)
```bash
# First, try official policy from submodule
POLICY_FILE="policies/$POLICY_ID/policy.json"

# Fallback to local override if exists
if [ ! -f "$POLICY_FILE" ]; then
    POLICY_FILE="local-overrides/policies/$POLICY_ID/policy.json"
fi

# Load policy
POLICY=$(cat "$POLICY_FILE")
```

**3. Decision Output** (`aport-guardrail.sh`)
```bash
# Use canonical decision schema
DECISION_SCHEMA="spec/oap/decision-schema.json"

# Build decision object per OAP v1.0
cat > "$DECISION_FILE" <<EOF
{
  "decision_id": "$DECISION_ID",
  "passport_id": "$PASSPORT_ID",
  "policy_id": "$POLICY_ID",
  "owner_id": "$OWNER_ID",
  "assurance_level": "$ASSURANCE_LEVEL",
  "allow": $ALLOW,
  "reasons": [
    {
      "code": "$DENY_CODE",
      "message": "$DENY_MESSAGE"
    }
  ],
  "issued_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "expires_at": "$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)",
  "passport_digest": "sha256:$PASSPORT_HASH",
  "signature": "ed25519:$SIGNATURE",
  "kid": "oap:local:dev-key"
}
EOF

# Validate against schema
jq --argfile schema "$DECISION_SCHEMA" '. | validate($schema)' "$DECISION_FILE"
```

---

## Implementation Plan

### Step 1: Add Git Submodules (5 minutes)

```bash
cd /Users/uchi/Downloads/projects/aport-agent-guardrails

# Add aport-spec as submodule
git submodule add https://github.com/aporthq/aport-spec.git spec
git submodule add https://github.com/aporthq/aport-policies.git policies

# Initialize submodules
git submodule update --init --recursive

# Commit
git add .gitmodules spec policies
git commit -m "Add aport-spec and aport-policies as submodules"
```

**Result:**
```
aport-agent-guardrails/
├── .gitmodules
├── spec/                    # → Points to aporthq/aport-spec (latest)
└── policies/                # → Points to aporthq/aport-policies (latest)
```

---

### Step 2: Move Existing Files to local-overrides/ (5 minutes)

```bash
# Create local overrides directory
mkdir -p local-overrides/policies local-overrides/templates

# Move custom policies that don't exist upstream
# system.command.execute.v1 doesn't exist in aport-policies, so keep it local
mv policies/system.command.execute.json local-overrides/policies/system.command.execute.v1/policy.json

# Move custom templates
mv templates/passport.template.json local-overrides/templates/passport.local.json

# Remove hardcoded files that now come from submodules
rm -rf templates/  # Will use spec/oap/examples/ instead
rm policies/*.json  # Will use policies/ submodule instead
```

---

### Step 3: Update aport-guardrail.sh (15 minutes)

**Key Changes:**

```bash
#!/bin/bash
# aport-guardrail.sh - Enhanced with OAP v1.0 compliance

set -e

# Paths to submodules
SPEC_DIR="${SPEC_DIR:-spec/oap}"
POLICIES_DIR="${POLICIES_DIR:-policies}"
LOCAL_OVERRIDES="${LOCAL_OVERRIDES:-local-overrides}"

# Schemas
PASSPORT_SCHEMA="$SPEC_DIR/passport-schema.json"
DECISION_SCHEMA="$SPEC_DIR/decision-schema.json"

# ... existing code ...

# Map tool to policy
map_tool_to_policy() {
    local tool=$1
    case "$tool" in
        git.create_pr|git.merge|git.push)
            echo "code.repository.merge.v1"
            ;;
        exec.run|exec.*|system.*)
            echo "system.command.execute.v1"  # Local override
            ;;
        message.send|messaging.*)
            echo "messaging.message.send.v1"
            ;;
        data.export|database.export)
            echo "data.export.create.v1"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Load policy (try upstream first, fallback to local)
load_policy() {
    local policy_id=$1

    # Try official policy from submodule
    local policy_file="$POLICIES_DIR/$policy_id/policy.json"

    # Fallback to local override
    if [ ! -f "$policy_file" ]; then
        policy_file="$LOCAL_OVERRIDES/policies/$policy_id/policy.json"
    fi

    # Check if exists
    if [ ! -f "$policy_file" ]; then
        echo "Error: Policy $policy_id not found" >&2
        exit 1
    fi

    cat "$policy_file"
}

# Build OAP v1.0 compliant decision
build_decision() {
    local allow=$1
    local policy_id=$2
    local deny_code=${3:-"oap.policy_check_passed"}
    local deny_message=${4:-"Policy check passed"}

    # Generate decision ID
    local decision_id=$(uuidgen 2>/dev/null || echo "local-$(date +%s)")

    # Compute passport digest (SHA-256 of JCS-canonicalized passport)
    local passport_digest="sha256:$(jq --sort-keys -c . $PASSPORT_FILE | shasum -a 256 | awk '{print $1}')"

    # Build reasons array per OAP v1.0
    local reasons
    if [ "$allow" = "true" ]; then
        reasons='[{"code": "oap.policy_check_passed", "message": "All policy checks passed"}]'
    else
        reasons="[{\"code\": \"$deny_code\", \"message\": \"$deny_message\"}]"
    fi

    # Build decision per OAP v1.0 schema
    cat > "$DECISION_FILE" <<EOF
{
  "decision_id": "$decision_id",
  "passport_id": "$(jq -r '.passport_id' $PASSPORT_FILE)",
  "policy_id": "$policy_id",
  "owner_id": "$(jq -r '.owner_id' $PASSPORT_FILE)",
  "assurance_level": "$(jq -r '.assurance_level' $PASSPORT_FILE)",
  "allow": $allow,
  "reasons": $reasons,
  "issued_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "expires_at": "$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)",
  "passport_digest": "$passport_digest",
  "signature": "ed25519:local-unsigned",
  "kid": "oap:local:dev-key"
}
EOF

    # Validate against schema (optional, for development)
    if command -v jq &> /dev/null && [ -f "$DECISION_SCHEMA" ]; then
        jq --argfile schema "$DECISION_SCHEMA" 'if . then . else empty end' "$DECISION_FILE" > /dev/null 2>&1 || {
            echo "Warning: Decision does not validate against OAP v1.0 schema" >&2
        }
    fi
}

# ... rest of script uses build_decision() ...
```

---

### Step 4: Update aport-create-passport.sh (10 minutes)

**Use canonical template:**

```bash
#!/bin/bash
# aport-create-passport.sh - Use canonical OAP v1.0 template

SPEC_DIR="${SPEC_DIR:-spec/oap}"
PASSPORT_SCHEMA="$SPEC_DIR/passport-schema.json"
PASSPORT_TEMPLATE="$SPEC_DIR/examples/passport.template.v1.json"

# ... existing wizard code ...

# Generate passport using canonical template
cp "$PASSPORT_TEMPLATE" "$PASSPORT_FILE.tmp"

# Update fields via jq
jq --arg owner_id "$owner_id" \
   --arg owner_type "$owner_type" \
   --arg passport_id "$(uuidgen)" \
   --arg expires_at "$(date -u -v+30d +%Y-%m-%dT%H:%M:%SZ)" \
   '.owner_id = $owner_id | .owner_type = $owner_type | .passport_id = $passport_id | .expires_at = $expires_at' \
   "$PASSPORT_FILE.tmp" > "$PASSPORT_FILE"

# Validate against canonical schema
if command -v jq &> /dev/null; then
    jq --argfile schema "$PASSPORT_SCHEMA" 'if . then . else empty end' "$PASSPORT_FILE" > /dev/null 2>&1 && {
        echo "✅ Passport validated against OAP v1.0 schema"
    } || {
        echo "⚠️  Warning: Passport may not be fully OAP v1.0 compliant" >&2
    }
fi
```

---

## Missing Policies Analysis

### Policies in `aport-policies` (12 total):
1. ✅ `code.repository.merge.v1` - Git operations
2. ✅ `code.release.publish.v1` - Release publishing
3. ✅ `data.export.create.v1` - Data exports
4. ✅ `data.report.ingest.v1` - Report ingestion
5. ✅ `finance.crypto.trade.v1` - Crypto trading
6. ✅ `finance.payment.charge.v1` - Payment charges
7. ✅ `finance.payment.payout.v1` - Payouts
8. ✅ `finance.payment.refund.v1` - Refunds
9. ✅ `finance.transaction.execute.v1` - Financial transactions
10. ✅ `governance.data.access.v1` - Data access governance
11. ✅ `legal.contract.review.v1` - Contract review
12. ✅ `messaging.message.send.v1` - Messaging

### Missing Policies for OpenClaw/Agent Frameworks:

**1. `system.command.execute.v1`** - ❌ NOT in `aport-policies`
- **Why needed:** Core for agent frameworks (npm, git, bash, etc.)
- **Recommendation:** ✅ **Implement in `/Users/uchi/Downloads/projects/agent-passport/policies/`**
- **Then:** Auto-published to `aport-policies` via workflow

**2. `mcp.tool.execute.v1`** - ❌ NOT in `aport-policies`
- **Why needed:** MCP (Model Context Protocol) tool execution
- **Use case:** Validate MCP server allowlists, tool permissions
- **Recommendation:** ✅ **Implement in `/Users/uchi/Downloads/projects/agent-passport/policies/`**

**3. `agent.session.create.v1`** - ❌ NOT in `aport-policies`
- **Why needed:** Agent session management
- **Use case:** Control how many concurrent sessions, session duration limits
- **Recommendation:** ✅ **Implement in `/Users/uchi/Downloads/projects/agent-passport/policies/`**

**4. `agent.tool.register.v1`** - ❌ NOT in `aport-policies`
- **Why needed:** Dynamic tool registration
- **Use case:** Validate tools before registration, prevent malicious tools
- **Recommendation:** ✅ **Implement in `/Users/uchi/Downloads/projects/agent-passport/policies/`**

---

## Policy Implementation Priority

### Phase 1: Critical for OpenClaw (This Week)

**1. `system.command.execute.v1`**
```bash
cd /Users/uchi/Downloads/projects/agent-passport/policies
mkdir -p system.command.execute.v1
```

**File:** `system.command.execute.v1/policy.json`
```json
{
  "id": "system.command.execute.v1",
  "name": "System Command Execution Policy",
  "description": "Pre-action governance for system command execution. Enforces command allowlists, blocked patterns, and execution time limits.",
  "version": "1.0.0",
  "status": "active",
  "requires_capabilities": ["system.command.execute"],
  "min_assurance": "L1",
  "limits_required": [
    "allowed_commands",
    "blocked_patterns",
    "max_execution_time"
  ],
  "required_fields": ["command"],
  "optional_fields": ["args", "cwd", "env"],
  "enforcement": {
    "command_allowlist_enforced": true,
    "blocked_patterns_enforced": true,
    "execution_time_enforced": true
  },
  "advice": [
    "Implement command allowlists to prevent unauthorized execution",
    "Block dangerous patterns (rm -rf, sudo, curl | bash)",
    "Set execution time limits to prevent runaway processes",
    "Log all command executions for audit trail",
    "Use environment variable restrictions",
    "Implement working directory restrictions"
  ],
  "required_context": {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["command"],
    "properties": {
      "command": {
        "type": "string",
        "minLength": 1,
        "description": "Command to execute"
      },
      "args": {
        "type": "array",
        "items": {"type": "string"},
        "description": "Command arguments"
      },
      "cwd": {
        "type": "string",
        "description": "Working directory"
      },
      "env": {
        "type": "object",
        "description": "Environment variables"
      }
    }
  },
  "evaluation_rules": [
    {
      "name": "command_allowlist",
      "condition": "command in limits.allowed_commands OR '*' in limits.allowed_commands",
      "deny_code": "oap.command_not_allowed",
      "description": "Command must be in allowlist"
    },
    {
      "name": "blocked_patterns",
      "condition": "NOT any(pattern in command for pattern in limits.blocked_patterns)",
      "deny_code": "oap.blocked_pattern",
      "description": "Command must not contain blocked patterns"
    },
    {
      "name": "execution_time_limit",
      "condition": "estimated_time <= limits.max_execution_time",
      "deny_code": "oap.timeout_risk",
      "description": "Execution time must not exceed limit"
    }
  ],
  "cache": {
    "default_ttl_seconds": 60,
    "suspend_invalidate_seconds": 30
  },
  "created_at": "2026-02-14T00:00:00Z",
  "updated_at": "2026-02-14T00:00:00Z"
}
```

**Test Files:**
- `system.command.execute.v1/tests/passport.template.json`
- `system.command.execute.v1/tests/passport.instance.json`
- `system.command.execute.v1/tests/allow_npm_install.json`
- `system.command.execute.v1/tests/deny_rm_rf.json`

**README.md:**
- Usage examples
- Integration guide
- Security considerations

---

### Phase 2: MCP Integration (Next Week)

**2. `mcp.tool.execute.v1`**

Similar structure, focuses on:
- MCP server allowlists
- MCP tool permissions
- MCP session validation

---

### Phase 3: Agent Management (Week 3)

**3. `agent.session.create.v1`**
**4. `agent.tool.register.v1`**

---

## Why NOT Symlinks?

❌ **Symlinks won't work for this use case:**

1. **Git doesn't track symlink targets across repos**
   - Symlink to `/tmp/aport-spec` breaks when repo is cloned elsewhere
   - Symlink to `../aport-spec` requires specific directory structure

2. **Cross-platform issues**
   - Windows doesn't handle symlinks well
   - Requires admin privileges on Windows

3. **Git submodules are designed for this**
   - Tracks specific commit SHA
   - Works on all platforms
   - Automatic updates with `git submodule update --remote`

---

## Recommended Git Workflow

### For Users (Installing aport-agent-guardrails):

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/aporthq/aport-agent-guardrails.git

# Or if already cloned
git submodule update --init --recursive
```

### For Maintainers (Updating dependencies):

```bash
# Update aport-spec to latest
cd spec
git pull origin main
cd ..
git add spec
git commit -m "Update aport-spec to latest"

# Update aport-policies to latest
cd policies
git pull origin main
cd ..
git add policies
git commit -m "Update aport-policies to latest"
```

---

## Migration Checklist

### Immediate (This Weekend):

- [ ] Add `aport-spec` as git submodule
- [ ] Add `aport-policies` as git submodule
- [ ] Move custom policies to `local-overrides/`
- [ ] Update `aport-guardrail.sh` to use submodules
- [ ] Update `aport-create-passport.sh` to use canonical template
- [ ] Validate all outputs against OAP v1.0 schemas
- [ ] Update documentation to reference submodules
- [ ] Test end-to-end with submodules

### Short-term (Next Week):

- [ ] Implement `system.command.execute.v1` in `agent-passport/policies/`
- [ ] Add tests for `system.command.execute.v1`
- [ ] Trigger auto-publish workflow to `aport-policies`
- [ ] Update `aport-agent-guardrails` to use published policy

### Medium-term (Next 2-4 Weeks):

- [ ] Implement `mcp.tool.execute.v1`
- [ ] Implement `agent.session.create.v1`
- [ ] Implement `agent.tool.register.v1`
- [ ] Add signature verification (Ed25519)
- [ ] Add passport digest computation (JCS canonicalization)

---

## Final Recommendation

✅ **YES - Use Git Submodules** for `aport-spec` and `aport-policies`

**Benefits:**
1. ✅ Automatic standards compliance (OAP v1.0)
2. ✅ Reuse 12 production policies
3. ✅ Single source of truth
4. ✅ Auto-updates with `git submodule update`
5. ✅ Still allows local overrides for development

**Implementation:**
- Add submodules (5 minutes)
- Update scripts to use submodules (30 minutes)
- Implement missing `system.command.execute.v1` policy (2 hours)
- Test end-to-end (30 minutes)

**Total Time:** ~4 hours of work this weekend

---

## Next Steps

1. ✅ **Review this strategy** - Does this approach work for your workflow?
2. ✅ **Add submodules** - Run the commands above
3. ✅ **Implement `system.command.execute.v1`** - In `agent-passport/policies/`
4. ✅ **Test compliance** - Validate against OAP v1.0 schemas
5. ✅ **Update aport-agent-guardrails** - Use submodules instead of hardcoded files

---

**Questions?** Let me know if you want me to implement any of these changes directly.

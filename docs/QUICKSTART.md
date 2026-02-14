# Quick Start Guide
**Get Started with APort Agent Guardrails in 5 Minutes**

---

## Prerequisites

- ✅ OpenClaw installed (or any compatible agent framework)
- ✅ `jq` installed (`brew install jq` on macOS)
- ✅ bash shell

---

## Step 1: Install APort Agent Guardrails (30 seconds)

```bash
cd /Users/uchi/Downloads/projects/aport-agent-guardrails
make install
```

**What this does:**
- Copies CLI scripts to `~/.openclaw/.skills/`
- Makes them executable
- Ready to use!

**Verify installation:**
```bash
ls -la ~/.openclaw/.skills/aport-*.sh
```

You should see:
```
aport-create-passport.sh
aport-guardrail.sh
aport-status.sh
```

---

## Step 2: Create Your First Passport (1 minute)

```bash
~/.openclaw/.skills/aport-create-passport.sh
```

**Interactive prompts will guide you through:**
1. Your email/ID (e.g., `uchi@aport.io`)
2. Owner type (user/team/org) - Choose `user`
3. Capabilities:
   - Create and merge PRs? → `y`
   - Execute system commands? → `y`
   - Send messages? → `n` (for now)
   - Export data? → `n` (for now)
4. Limits:
   - Max PR size: `500` (files)
   - Max PRs per day: `10`
   - Allowed repos: `*` (all repos)

**Result:** Passport created at `~/.openclaw/passport.json`

**Verify:**
```bash
cat ~/.openclaw/passport.json | jq '.passport_id, .status, .expires_at'
```

You should see:
```json
"550e8400-e29b-41d4-a716-446655440000"
"active"
"2026-03-16T00:00:00Z"
```

---

## Step 3: Check Status (10 seconds)

```bash
~/.openclaw/.skills/aport-status.sh
```

**You'll see:**
```
🛂 APort Status Dashboard
=========================

🟢 Kill Switch: inactive

📋 Passport Information
   Location: /Users/uchi/.openclaw/passport.json
   ID: 550e8400-e29b-41d4-a716-446655440000
   Owner: uchi@aport.io
   Type: user
   Status: ✅ active
   Expires: 2026-03-16T00:00:00Z
   ✅ 30 days until expiration

🔐 Capabilities
  • repo.pr.create
  • repo.merge
  • system.command.execute

⚙️  Limits
  • code.repository.merge:
    - Max PRs/day: 10
    - Max PR size: 500 files

📊 Recent Activity (last 10)
  (no activity yet)

💡 Useful Commands
  • View full audit log: tail -f /Users/uchi/.openclaw/audit.log
  • Edit passport: vim /Users/uchi/.openclaw/passport.json
  • Verify passport: aport-verify-passport.sh
  • Activate kill switch: touch /Users/uchi/.openclaw/kill-switch
```

---

## Step 4: Test Policy Evaluation (1 minute)

### Test 1: Allow a small PR (should PASS)

```bash
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{
  "repo": "aport-agent-guardrails",
  "branch": "feature/test",
  "base_branch": "main",
  "files_changed": 10
}'
```

**Expected output:**
```json
{
  "allow": true,
  "decision_id": "550e8400-...",
  "policy": "code.repository.merge",
  "tool": "git.create_pr"
}
```

**Check decision:**
```bash
cat ~/.openclaw/decision.json | jq .
```

**Check audit log:**
```bash
tail -1 ~/.openclaw/audit.log
```

---

### Test 2: Deny a large PR (should FAIL)

```bash
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{
  "repo": "aport-agent-guardrails",
  "branch": "feature/large",
  "files_changed": 1000
}'
```

**Expected output:**
```json
{
  "allow": false,
  "decision_id": "660f9500-...",
  "reason": "limit_exceeded",
  "message": "PR size 1000 exceeds limit of 500 files"
}
```

**Check decision:**
```bash
cat ~/.openclaw/decision.json | jq .
```

You should see `"allow": false` with deny reason.

---

### Test 3: Block dangerous command (should FAIL)

```bash
~/.openclaw/.skills/aport-guardrail.sh exec.run '{
  "command": "rm -rf /tmp/test"
}'
```

**Expected output:**
```json
{
  "allow": false,
  "decision_id": "770g0600-...",
  "reason": "blocked_pattern",
  "message": "Command contains blocked pattern: rm -rf"
}
```

---

## Step 5: Test Kill Switch (30 seconds)

### Activate kill switch:
```bash
touch ~/.openclaw/kill-switch
```

### Try any action (should be blocked):
```bash
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{
  "repo": "test",
  "files_changed": 1
}'
```

**Expected output:**
```json
{
  "allow": false,
  "decision_id": "880h0700-...",
  "reason": "kill_switch_active",
  "message": "Global kill switch is active. Remove /Users/uchi/.openclaw/kill-switch to resume."
}
```

### Deactivate kill switch:
```bash
rm ~/.openclaw/kill-switch
```

### Verify it works again:
```bash
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{
  "repo": "test",
  "files_changed": 1
}'
```

Should see `"allow": true` now.

---

## Step 6: View Activity Dashboard (10 seconds)

```bash
~/.openclaw/.skills/aport-status.sh
```

**You'll now see:**
```
📊 Recent Activity (last 10)
  ✅ 2026-02-14 17:00:00 | git.create_pr
  ❌ 2026-02-14 17:01:00 | git.create_pr
  ❌ 2026-02-14 17:02:00 | exec.run
  ❌ 2026-02-14 17:03:00 | git.create_pr

📈 Statistics (all time)
  Total actions: 4
  Allowed: 1
  Denied: 3
  Allow rate: 25%
```

---

## 🎉 Success! You've tested all core features

**What you've verified:**
- ✅ Passport creation (interactive wizard)
- ✅ Status dashboard (health checks)
- ✅ Policy evaluation (allow/deny based on rules)
- ✅ Kill switch (global emergency stop)
- ✅ Audit logging (tamper-evident trail)

---

## Step 7: Integrate with Your OpenClaw Instance (5 minutes)

### Option A: Add to AGENTS.md (Recommended)

**1. Locate your OpenClaw AGENTS.md:**
```bash
# Find your OpenClaw installation
find ~ -name "AGENTS.md" -path "*/.openclaw/*" | head -1
```

**2. Add APort section:**
```bash
# Copy template
cat /Users/uchi/Downloads/projects/aport-agent-guardrails/docs/AGENTS.md.example >> ~/.openclaw/AGENTS.md
```

**3. Verify:**
```bash
cat ~/.openclaw/AGENTS.md | grep "Pre-Action Authorization"
```

---

### Option B: Manual Integration (Advanced)

**In your OpenClaw agent code, before any tool execution:**

```python
import subprocess
import json

def execute_tool(tool_name, params):
    # 1. Pre-action verification
    result = subprocess.run([
        '~/.openclaw/.skills/aport-guardrail.sh',
        tool_name,
        json.dumps(params)
    ], capture_output=True, text=True)

    # 2. Read decision
    with open(os.path.expanduser('~/.openclaw/decision.json')) as f:
        decision = json.load(f)

    # 3. Check if allowed
    if not decision.get('allow'):
        raise PermissionError(f"Policy denied: {decision.get('message')}")

    # 4. Execute tool (if allowed)
    return actual_tool_execution(tool_name, params)
```

---

## Step 8: Customize Your Passport (Optional)

### Edit passport directly:
```bash
vim ~/.openclaw/passport.json
```

### Common customizations:

**1. Change PR size limit:**
```json
{
  "limits": {
    "code.repository.merge": {
      "max_pr_size_kb": 1000  // Increase from 500 to 1000
    }
  }
}
```

**2. Add allowed repos (restrict to specific repos):**
```json
{
  "limits": {
    "code.repository.merge": {
      "allowed_repos": ["aporthq/*", "my-org/*"]  // Only these repos
    }
  }
}
```

**3. Add blocked commands:**
```json
{
  "limits": {
    "system.command.execute": {
      "blocked_patterns": ["rm -rf", "sudo", "curl | bash", "dd if="]
    }
  }
}
```

**After editing, verify:**
```bash
jq . ~/.openclaw/passport.json > /dev/null && echo "✅ Valid JSON" || echo "❌ Invalid JSON"
```

---

## Troubleshooting

### Problem: "jq not found"
```bash
brew install jq  # macOS
apt-get install jq  # Linux
```

### Problem: "Permission denied"
```bash
chmod +x ~/.openclaw/.skills/aport-*.sh
```

### Problem: "Passport not found"
```bash
# Recreate passport
~/.openclaw/.skills/aport-create-passport.sh
```

### Problem: "All actions denied"
```bash
# Check passport status
jq '.status' ~/.openclaw/passport.json
# Should be "active"

# Check kill switch
ls ~/.openclaw/kill-switch
# If exists, remove it: rm ~/.openclaw/kill-switch

# Check expiration
jq '.expires_at' ~/.openclaw/passport.json
# If expired, update it
```

### Problem: "Decision file not created"
```bash
# Check script permissions
ls -la ~/.openclaw/.skills/aport-guardrail.sh
# Should be -rwxr-xr-x (executable)

# Make executable
chmod +x ~/.openclaw/.skills/aport-guardrail.sh
```

---

## Next Steps

### For Testing:
1. ✅ **Create more test scenarios** - Try different policy violations
2. ✅ **Test rate limiting** - Create 11 PRs in a day (should deny 11th)
3. ✅ **Test expiration** - Set expiration to past date, verify it denies

### For Integration:
1. ✅ **Add to OpenClaw AGENTS.md** - Make it automatic
2. ✅ **Create custom policy packs** - Add policies for your use case
3. ✅ **Set up recurring passport renewal** - Cron job to renew every 30 days

### For Production:
1. ✅ **Upgrade to APort Cloud** - Get global kill switch, Ed25519 signatures
2. ✅ **Set up team passports** - Share policies across team
3. ✅ **Enable audit log monitoring** - Alert on policy violations

---

## Resources

- [Full Documentation](APORT_OPENCLAW_INTEGRATION_PROPOSAL.md)
- [Policy Pack Guide](POLICY_PACK_GUIDE.md)
- [Upgrade to Cloud](UPGRADE_TO_CLOUD.md)
- [Contributing Guidelines](../CONTRIBUTING.md)

---

## Get Help

- **GitHub Issues:** https://github.com/aporthq/aport-agent-guardrails/issues
- **Discussions:** https://github.com/aporthq/aport-agent-guardrails/discussions
- **Email:** support@aport.io

---

**Total Time:** ~5 minutes to get started, 30 minutes to fully integrate

**You're now running policy-enforced AI agents! 🎉**

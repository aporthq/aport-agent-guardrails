# Quick Start Guide
**Get started with APort Agent Guardrails in 5 minutes**

---

## Recommended: one command (npm, no clone)

```bash
npx @aporthq/agent-guardrails
```

If you have an agent_id from aport.io, run `npx @aporthq/agent-guardrails <agent_id>` to use a hosted passport (no local file). See [HOSTED_PASSPORT_SETUP.md](HOSTED_PASSPORT_SETUP.md).

This uses the [npm package](https://www.npmjs.com/package/@aporthq/agent-guardrails): downloads the package, runs the setup wizard, installs the plugin and wrappers, and runs a smoke test.

**Alternative: from the repo** (if you cloned the repo):

```bash
make openclaw-setup
```

Or:

```bash
./bin/openclaw
```

The script will:

1. **Prompt for your OpenClaw config directory** — default `~/.openclaw`; you can use a different path (e.g. your project’s `.openclaw`).
2. **Run the passport wizard** — guided by the OAP spec (`external/aport-spec`); you choose capabilities and limits.
3. **Install wrappers** in your config dir (`.skills/`) so OpenClaw can call the guardrail with the correct passport/decision paths.
4. **Update your passport** — the installer sets `allowed_commands: ["*"]` automatically (no manual editing needed); then runs a self-check and exits with a clear error if the check is denied.
5. **Install the APort skill** in `~/.openclaw/skills/aport-guardrail/` so OpenClaw loads it; the agent knows to call the guardrail before effectful actions.
6. **Print the tool → policy mapping** so you see how tool names map to policy packs in `external/aport-policies`. Full table: [TOOL_POLICY_MAPPING.md](TOOL_POLICY_MAPPING.md). If you have a workspace, the script saves an AGENTS.md snippet you can merge.

Then test with the path it showed (e.g. `~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"ls"}'`).

For **OpenClaw + API** (self-hosted or cloud), see [OpenClaw Local Integration](OPENCLAW_LOCAL_INTEGRATION.md).

---

## Copy-paste (no wizard)

If you prefer a single block with no prompts (e.g. for automation or a different config dir):

```bash
git clone https://github.com/aporthq/aport-agent-guardrails.git && cd aport-agent-guardrails
mkdir -p ~/.openclaw
# Create minimal passport (see README for full JSON)
make install
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"ls"}'
```

Note: `make install` copies scripts to `~/.openclaw/.skills`; the guardrail will look for policies in the **repo** (so run from repo or use `./bin/openclaw` for path-aware wrappers that point to the repo).

---

## Prerequisites

- `jq` (`brew install jq` on macOS)
- Bash shell

---

## Step 1: Install (if not using openclaw script)

From the repo root:

```bash
make install
```

This copies scripts to `~/.openclaw/.skills/`. For a **configurable path** and wrappers that always use this repo’s policies, use `./bin/openclaw` instead.

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

Scripts exit **0** = allow, **1** = deny. The decision is written to `~/.openclaw/decision.json` (not printed to stdout).

### Test 1: Allow a small PR (should PASS)

```bash
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{
  "repo": "aport-agent-guardrails",
  "branch": "feature/test",
  "base_branch": "main",
  "files_changed": 10
}'
echo "Exit: $? (0 = ALLOW)"
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
echo "Exit: $? (1 = DENY)"
cat ~/.openclaw/decision.json | jq '.allow, .reasons'
```

You should see `"allow": false` and a deny reason.

---

### Test 3: Block dangerous command (should FAIL)

```bash
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"rm -rf /tmp/test"}'
echo "Exit: $? (1 = DENY)"
cat ~/.openclaw/decision.json | jq '.allow, .reasons[0].message'
```

---

## Step 5: Test Kill Switch (30 seconds)

### Activate kill switch:
```bash
touch ~/.openclaw/kill-switch
```

### Try any action (should be blocked):
```bash
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{"repo": "test", "files_changed": 1}'
cat ~/.openclaw/decision.json | jq '.allow, .reasons[0].code'
```
You should see `allow: false` and a kill_switch reason.

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

**2. Add APort section:** From the repo root:
```bash
cat docs/AGENTS.md.example >> ~/.openclaw/AGENTS.md
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

### Problem: "Command must be in allowed list" (oap.command_not_allowed)
The guardrail is blocking **exec** because the command (e.g. `mkdir`, `ls`) is not in your passport’s **allowed_commands**. OpenClaw uses **exec** for both guardrail invocations and real shell commands; we check real commands against the passport.

**Fix:** The installer sets `allowed_commands: ["*"]` by default; this usually appears only if you intentionally tightened the allowlist. Re-add the commands you need to `limits.system.command.execute.allowed_commands`, or set `["*"]` (blocked patterns still apply). Alternatively, set **mapExecToPolicy: false** in the plugin config so exec is never checked (no command allowlist; use only if you rely on other controls). See [OPENCLAW_TOOLS_AND_POLICIES.md](OPENCLAW_TOOLS_AND_POLICIES.md).

### Problem: "Missing required capabilities: messaging.send"
If you see `oap.unknown_capability: Missing required capabilities: messaging.send`, your passport was created with the old capability/limits keys. Align with APort:

- In `capabilities`, use `"id": "messaging.send"` (not `messaging.message.send`).
- In `limits`, use the key `"messaging"` (not `messaging.message.send`) for `msgs_per_min`, `msgs_per_day`, etc.

Re-run the passport wizard to create a new passport, or edit `~/.openclaw/passport.json` and fix those two places.

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

- [OpenClaw Local Integration](OPENCLAW_LOCAL_INTEGRATION.md) — Full OpenClaw + API setup
- [QuickStart: OpenClaw Plugin](QUICKSTART_OPENCLAW_PLUGIN.md) — Plugin setup
- [Tool / Policy Mapping](TOOL_POLICY_MAPPING.md)
- [Contributing](../CONTRIBUTING.md)

---

## Get Help

- **GitHub Issues:** https://github.com/aporthq/aport-agent-guardrails/issues
- **Discussions:** https://github.com/aporthq/aport-agent-guardrails/discussions
- **Email:** uchi@aport.io

---

**Total Time:** ~5 minutes to get started, 30 minutes to fully integrate

**You're now running policy-enforced AI agents! 🎉**

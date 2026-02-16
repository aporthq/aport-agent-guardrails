# Using Hosted Passports with OpenClaw

**For users who created a passport at [aport.io/builder/create](https://aport.io/builder/create)**

---

## Overview

You have two options when using APort guardrails with OpenClaw:

1. **Local Passport** (Default): Create passport with CLI wizard → stored at `~/.openclaw/passport.json`
2. **Hosted Passport** (This Guide): Create passport at aport.io → Use `agent_id` only, no download needed

**Why Hosted?**
- ✅ **Global Kill Switch**: Suspend passport instantly from dashboard (all agents stop < 15s)
- ✅ **No JSON Management**: No local file to lose or back up
- ✅ **Team Sync**: Share policies across team members
- ✅ **Web Dashboard**: View activity, audit logs, analytics
- ✅ **Automatic Updates**: Edit limits in dashboard → takes effect immediately

---

## Quick Start (Hosted Passport)

**Step 1: Create Passport at aport.io**

1. Visit [https://aport.io/builder/create](https://aport.io/builder/create)
2. Select framework: **OpenClaw**
3. Fill agent name and limits, then click "Create Passport"
4. On the success page you’ll see an **agent_id** (e.g. `ap_abc123def456...`) and often a ready-to-run command.

**Step 2: Install Guardrails**

**Option A — One command (if you have your agent_id):**

```bash
npx @aporthq/agent-guardrails <agent_id>
```

Example: `npx @aporthq/agent-guardrails ap_fa2f6d53bb5b4c98b9af0124285b6e0f`. The CLI skips the passport wizard and configures the plugin to use your hosted passport.

**Option B — Interactive:**

```bash
npx @aporthq/agent-guardrails
```

When prompted for passport, choose "Use hosted passport (agent_id only)" and paste your `agent_id`. Config directory default: `~/.openclaw`. Plugin mode will be API (required for hosted).

**Step 3: Start OpenClaw**

```bash
openclaw gateway start --config ~/.openclaw/config.yaml
```

**Done!** The plugin will fetch your passport from APort API on every tool call.

---

## How It Works (Hosted Passport)

```
User → OpenClaw: "Create a file"
         ↓
    OpenClaw: Tool call → before_tool_call hook
         ↓
 APort Plugin: Reads config → sees agent_id (no local passport file)
         ↓
 APort Plugin: POST to api.aport.io/api/verify/policy/system.command.execute.v1
                Body: { "context": { "agent_id": "ap_abc123...", "command": "touch test.txt" } }
         ↓
    APort API: Fetches passport from registry by agent_id
         ↓
    APort API: Evaluates policy → Returns ALLOW/DENY
         ↓
 APort Plugin: ✅ ALLOW → Tool runs
              ❌ DENY → Tool blocked
```

**Key Point:** Your passport stays in APort's registry. The plugin sends `agent_id` + context, API fetches passport, evaluates policy, returns decision. **No passport file stored locally.**

---

## Configuration (Hosted Passport)

### Option A: During Setup (Automatic)

Run `npx @aporthq/agent-guardrails` and follow prompts. The setup script will create `~/.openclaw/config.yaml`:

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: api
        agentId: ap_abc123def456...  # Your hosted passport ID
        apiUrl: https://api.aport.io
        failClosed: true
```

**Note:** When `agentId` is set, the plugin uses it instead of reading `passportFile`.

### Option B: Manual Configuration

If you already have a config, edit `~/.openclaw/config.yaml`:

**Add or replace the APort plugin section:**

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        # Use API mode (required for hosted passports)
        mode: api

        # Hosted passport: provide agent_id instead of passportFile
        agentId: ap_abc123def456...  # REPLACE with your agent_id from aport.io

        # API endpoint
        apiUrl: https://api.aport.io

        # Optional: API key if your organization requires it
        # (Set APORT_API_KEY in environment; do NOT put in config file)

        # Fail-closed: block on error (default: true)
        failClosed: true

        # Allow unmapped tools (custom skills/ClawHub)
        allowUnmappedTools: true
```

**Then restart OpenClaw:**

```bash
openclaw gateway restart
```

---

## Testing Your Setup

### Test 1: Verify Plugin Loaded

```bash
openclaw plugins list | grep openclaw-aport
# Should show: openclaw-aport (enabled)
```

### Test 2: Try a Safe Command

Ask your OpenClaw agent:
```
"Create a directory called test"
```

**Expected:** ✅ Command allowed, directory created

### Test 3: Try a Dangerous Command

Ask your OpenClaw agent:
```
"Run rm -rf /"
```

**Expected:** ❌ Command blocked with reason: "Blocked pattern: rm -rf"

### Test 4: Check Dashboard

1. Visit [https://aport.io/passports](https://aport.io/passports)
2. Click your passport
3. View activity log → Should see recent tool calls (ALLOW/DENY)

---

## Switching Between Local and Hosted

### From Local → Hosted

1. Create hosted passport at aport.io/builder/create
2. Copy `agent_id`
3. Edit `~/.openclaw/config.yaml`:
   ```yaml
   config:
     mode: api
     agentId: ap_your_new_agent_id  # ADD THIS
     # passportFile: ~/.openclaw/passport.json  # REMOVE OR COMMENT OUT
     apiUrl: https://api.aport.io
   ```
4. Restart: `openclaw gateway restart`

### From Hosted → Local

1. Download passport JSON from dashboard (if available) OR create new local passport:
   ```bash
   ./bin/aport-create-passport.sh --output ~/.openclaw/passport.json
   ```
2. Edit `~/.openclaw/config.yaml`:
   ```yaml
   config:
     mode: local  # OR api (both work with local file)
     passportFile: ~/.openclaw/passport.json  # ADD THIS
     # agentId: ap_...  # REMOVE OR COMMENT OUT
     guardrailScript: ~/.openclaw/.skills/aport-guardrail-bash.sh
   ```
3. Restart: `openclaw gateway restart`

---

## Managing Your Hosted Passport

### Update Limits

1. Visit [https://aport.io/passports](https://aport.io/passports)
2. Click your passport → "Edit"
3. Update limits (e.g., change `max_files` from 500 → 1000)
4. Click "Save"
5. **Takes effect immediately** (no restart needed)

### Suspend Passport (Kill Switch)

1. Visit passport dashboard
2. Click "Suspend"
3. **All agents using this passport stop within 15 seconds**
4. To resume: Click "Activate"

### View Activity

1. Passport dashboard → "Activity" tab
2. See all tool calls: timestamp, tool name, decision (ALLOW/DENY), reason

### Download Passport (Backup)

1. Passport dashboard → "Download JSON"
2. Save to `~/.openclaw/passport.json` (optional local backup)

---

## Troubleshooting

### Error: "Failed to fetch passport from API"

**Cause:** Invalid `agent_id` or API unreachable

**Fix:**
1. Verify `agent_id` in config matches dashboard (no typos)
2. Check API reachable: `curl -sf https://api.aport.io/api/status`
3. If behind firewall, check network access to `api.aport.io`

### Error: "API key required"

**Cause:** Your organization requires authentication

**Fix:**
1. Get API key from team admin or dashboard
2. Set in environment (NOT in config):
   ```bash
   export APORT_API_KEY="your-api-key-here"
   openclaw gateway restart
   ```
3. For permanent: Add to `~/.bashrc` or `~/.zshrc`

### Plugin Not Checking

**Cause:** Plugin not loaded or config incorrect

**Fix:**
1. Check plugin enabled: `openclaw plugins list`
2. Check config: `cat ~/.openclaw/config.yaml | grep -A 10 openclaw-aport`
3. Check logs: `openclaw logs | grep APort`
4. Reinstall plugin:
   ```bash
   openclaw plugins uninstall openclaw-aport
   npx @aporthq/agent-guardrails
   ```

### Passport Suspended But Agent Still Running

**Cause:** Kill switch delay (< 15s) or API mode not enabled

**Fix:**
1. Wait 15 seconds (API checks every 10s)
2. Verify mode is `api` in config (local mode has no kill switch)
3. Force restart: `openclaw gateway restart`

---

## API Mode vs. Local Mode (With Hosted Passport)

| Feature | API Mode (Hosted) | Local Mode |
|---------|-------------------|------------|
| **Passport storage** | APort registry | Local file |
| **agent_id only** | ✅ Yes | ❌ No - needs file |
| **Global kill switch** | ✅ < 15s | ❌ Local file only |
| **Network required** | ✅ Yes | ❌ No |
| **Policy updates** | ✅ Instant | Manual file edit |
| **Team sync** | ✅ Yes | Manual file sharing |
| **Audit log** | ✅ Cloud dashboard | Local file only |

**Recommendation:** Use **API mode** with hosted passports for global kill switch and team sync.

---

## Advanced: Self-Hosted API

If you're running the APort API yourself (e.g., on-prem or private cloud):

**Config:**
```yaml
config:
  mode: api
  agentId: ap_your_agent_id
  apiUrl: https://your-aport-api.company.com  # YOUR API
  failClosed: true
```

**Deploy APort API:**
1. See [agent-passport repo](https://github.com/aporthq/agent-passport) functions/api
2. Deploy to Cloudflare Workers, Vercel, or your infra
3. Point `apiUrl` to your deployed API

---

## FAQ

**Q: Can I use hosted passport with local mode?**
A: No. Local mode requires a passport file. Use API mode with hosted passports.

**Q: What if API goes down?**
A: With `failClosed: true` (default), all tool calls are blocked. Set `failClosed: false` to allow on error (NOT RECOMMENDED for security).

**Q: Can I create multiple hosted passports?**
A: Yes! Free tier: 1 passport. Beta/Pro: Unlimited. Each passport has unique `agent_id`.

**Q: How do I migrate from CLI-created to hosted?**
A: Create hosted passport at aport.io → Update config with `agentId` → Restart. Old local file can stay (ignored when `agentId` set).

**Q: Can I download my hosted passport?**
A: Yes, dashboard → "Download JSON". But you don't need to - `agent_id` is enough.

---

## Next Steps

- ✅ **Setup complete?** Test with safe + dangerous commands
- 📖 **Learn more:** [QUICKSTART_OPENCLAW_PLUGIN.md](QUICKSTART_OPENCLAW_PLUGIN.md)
- 🛠️ **Customize policies:** Edit passport limits in dashboard
- 👥 **Team setup:** Invite team members at [aport.io/organizations](https://aport.io/organizations)
- 📊 **Monitor usage:** View activity logs in dashboard

---

## See Also

- [QUICKSTART_OPENCLAW_PLUGIN.md](QUICKSTART_OPENCLAW_PLUGIN.md) - Plugin setup (local passport)
- [VERIFICATION_METHODS.md](VERIFICATION_METHODS.md) - API vs. local mode comparison
- [OPENCLAW_TOOLS_AND_POLICIES.md](OPENCLAW_TOOLS_AND_POLICIES.md) - Tool → policy mapping
- [test-remote-passport-api.sh](../tests/test-remote-passport-api.sh) - Test script for hosted passports

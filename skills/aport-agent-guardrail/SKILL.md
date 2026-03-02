---
name: aport-agent-guardrail
description: Pre-action authorization for AI agents. Enforces policies before tools execute—blocks unauthorized commands, data exfiltration, and malicious actions. Works with OpenClaw, IronClaw, PicoClaw via before_tool_call hook. Deterministic enforcement the agent cannot bypass. Optional API mode (APORT_API_URL, APORT_AGENT_ID, APORT_API_KEY) for hosted passports and signed decisions.
homepage: https://aport.io
metadata: {"openclaw":{"requires":{"bins":["jq"]},"envOptional":["APORT_API_URL","APORT_AGENT_ID","APORT_API_KEY"]}}
---

# APort Agent Guardrail

**Skill identifier:** `aport-agent-guardrail` · **Category:** Security / Infrastructure

---

## 🛡️ What This Skill Does

**Pre-action authorization for AI agents.** Every tool call is evaluated against a passport (identity + capabilities + limits) and policy **before** it executes. If denied, the tool never runs.

**Key features:**
- ✅ **Deterministic enforcement** – Runs in `before_tool_call` hook; agent cannot bypass
- ✅ **Blocks malicious actions** – Unauthorized commands, data exfiltration, API abuse prevented
- ✅ **Structured policies** – Based on [Open Agent Passport (OAP) v1.0](https://github.com/aporthq/aport-spec/tree/main)
- ✅ **Fail-closed by default** – Errors deny tool execution (security over availability)
- ✅ **Audit trail** – Every decision logged with tamper-evident hashes
- ✅ **Framework-agnostic** – OpenClaw, IronClaw, PicoClaw, and compatible runtimes

**How it protects you:**
- Prompt injection → Agent cannot bypass hook-based enforcement
- Malicious skills → All tool calls checked regardless of source
- Unauthorized commands → Allowlist + 40+ blocked patterns (rm -rf, sudo, etc.)
- Data exfiltration → File access, messaging, web requests controlled
- Resource exhaustion → Rate limits, size caps enforced

**Install once, protected forever.** The plugin runs automatically on every tool call.

---

## ⚡ Quick Start

```bash
# Install APort guardrails (one-time setup)
npx @aporthq/aport-agent-guardrails

# Follow wizard to create passport and configure policies
# Plugin auto-registers with OpenClaw

# Now your agent is protected
# All tool calls checked before execution
```

**With hosted passport (optional):**
```bash
# Get agent_id from aport.io
npx @aporthq/aport-agent-guardrails <agent_id>
```

**Requirements:** Node 18+, jq

---

## 📦 Installation

### Option 1: npm (recommended)

```bash
npx @aporthq/aport-agent-guardrails
```

**The wizard will:**
1. Create or load passport (local file or hosted from aport.io)
2. Configure capabilities and limits
3. Install OpenClaw plugin automatically
4. Set up wrapper scripts

**After install:** Plugin enforces before every tool call. No further action needed.

### Option 2: With hosted passport

```bash
npx @aporthq/aport-agent-guardrails <agent_id>
```

Get `agent_id` at [aport.io](https://aport.io/builder/create/) for:
- Cryptographically signed decisions
- Global suspend (<200ms across all systems)
- Centralized audit and compliance dashboards
- Team collaboration

### Option 3: From source

```bash
git clone https://github.com/aporthq/aport-agent-guardrails
cd aport-agent-guardrails
./bin/openclaw
```

**Guides:**
- [QuickStart: OpenClaw Plugin](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md)
- [Hosted passport setup](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/HOSTED_PASSPORT_SETUP.md)

---

## 🚀 Usage

### Automatic enforcement (default)

**After installation, the plugin runs automatically:**

```bash
# Your agent uses tools normally
agent> run git status
# ✅ APort: passport checked → policy evaluated → ALLOW → tool executes

agent> run rm -rf /
# ❌ APort: passport checked → blocked pattern detected → DENY → tool blocked
```

**You do nothing.** The plugin enforces on every tool call in the background.

### Testing the guardrail (optional)

**Direct script calls for testing or automation:**

```bash
# Test allowed command
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"ls"}'
# Exit 0 = ALLOW

# Test blocked command
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"rm -rf /"}'
# Exit 1 = DENY

# Test messaging
~/.openclaw/.skills/aport-guardrail.sh messaging.message.send '{"channel":"whatsapp","to":"+15551234567"}'
```

**Exit codes:**
- `0` = ALLOW (tool may proceed)
- `1` = DENY (reason in decision.json)

**Decision logs:**
- Latest: `~/.openclaw/aport/decision.json`
- Audit trail: `~/.openclaw/aport/audit.log`
- API mode: Signed receipts via APort API

---

## 🔍 How It Works

### Pre-Action Authorization Flow

```
User Request → Agent Decision → APort Check → [ALLOW/DENY] → Tool Execution
                                     ↑
                              Policy + Passport
```

1. **User makes request** (e.g., "Deploy to production")
2. **Agent decides to use tool** (e.g., exec.run with git push)
3. **OpenClaw fires hook** (`before_tool_call`)
4. **APort evaluates:**
   - Load passport (identity, capabilities, limits)
   - Map tool → policy (exec → system.command.execute.v1)
   - Check allowlist, blocked patterns, rate limits
5. **Decision:** ALLOW or DENY
6. **Audit:** Log decision with timestamp, policy, reason codes

**Agent cannot bypass.** Hook is registered by OpenClaw, not controlled by prompts.

### What Gets Installed

**Plugin registration:**
- OpenClaw plugin added to config (enforces before_tool_call)
- TypeScript/JavaScript plugin loaded on OpenClaw start

**Files created (under ~/.openclaw/):**
- `config.yaml` or `openclaw.json` – Plugin configuration
- `.skills/aport-guardrail*.sh` – Wrapper scripts for local/API evaluation
- `aport/passport.json` – Your agent passport (local mode only)
- `aport/decision.json` – Latest decision (runtime)
- `aport/audit.log` – Audit trail (runtime)

**Total disk usage:** ~100KB scripts + your passport/decisions

**Review code:** [GitHub repository](https://github.com/aporthq/aport-agent-guardrails)

---

## 🌐 Network and Privacy

### Local Mode (Default)

**Zero network calls:**
- ✅ All evaluation on your machine
- ✅ Passport stored locally
- ✅ Decisions stay local
- ✅ Full privacy
- ✅ Works offline

**Perfect for:** Development, personal use, air-gapped environments

### API Mode (Optional)

**Network usage:**
- Tool name + context → APort API for policy evaluation
- Hosted passport fetched from registry (if using agent_id)
- Signed decisions returned (Ed25519 cryptographic signatures)

**Benefits:**
- ✅ Cryptographically signed decisions
- ✅ Court-admissible audit trail
- ✅ Global suspend across all systems
- ✅ Centralized compliance dashboards
- ✅ No local passport tampering possible

**API endpoint:** `https://api.aport.io` (or custom via APORT_API_URL)

**Data sent:**
- Tool name (e.g., "system.command.execute")
- Context (e.g., {"command": "ls"})
- Passport (if local) or agent_id (if hosted)

**Data NOT sent:**
- File contents
- Environment variables
- API keys or credentials
- Unrelated system information

**To verify:** Use local mode (no network) or inspect open-source code.

---

## ⚙️ Environment Variables

| Variable | When Used | Purpose |
|----------|-----------|---------|
| `APORT_API_URL` | API mode | Override endpoint (default: `https://api.aport.io`). Use for self-hosted or custom API. |
| `APORT_AGENT_ID` | Hosted passport | Passport ID from aport.io. API fetches passport from registry. |
| `APORT_API_KEY` | If API requires auth | Authentication token. Set in environment (not config files). |

**Local mode:** No environment variables needed. Passport read from `~/.openclaw/aport/passport.json`.

**Hosted mode:** Pass `agent_id` to installer or set APORT_AGENT_ID.

---

## 🔧 Tool Name Mapping

| When agent calls… | Tool name | Policy |
|------------------|-----------|--------|
| Shell commands | `system.command.execute` | Allowlist, blocked patterns |
| WhatsApp/Email/Slack | `messaging.message.send` | Rate limits, recipient allowlist |
| Create/merge PRs | `git.create_pr`, `git.merge` | PR size, branch restrictions |
| MCP tools | `mcp.tool.execute` | Server/tool allowlist |
| Data export | `data.export` | Row limits, PII filtering |
| File read/write | `data.file.read`, `data.file.write` | Path restrictions |
| Web requests | `web.fetch`, `web.browser` | Domain allowlist, SSRF protection |

**Context format:** Valid JSON, e.g., `'{"command":"ls"}'` or `'{"channel":"whatsapp","to":"+1..."}'`

---

## 📋 Out-of-the-Box Protections

**Shell commands (system.command.execute.v1):**
- Allowlist enforcement (only specified commands run)
- 40+ blocked patterns: `rm -rf`, `sudo`, `chmod 777`, `dd if=`, `mkfs`, etc.
- Interpreter bypasses blocked: `python -c`, `node -e`, `base64` encoding
- Command injection patterns detected

**Messaging (messaging.message.send.v1):**
- Rate limits (msgs_per_min, msgs_per_day)
- Recipient allowlist
- Channel restrictions

**File access (data.file.read/write.v1):**
- Path restrictions (block /etc, /bin, system directories)
- Prevent .env, SSH key theft

**Web requests (web.fetch/browser.v1):**
- Domain allowlist
- SSRF protection (block private IPs)
- Rate limiting

**Git operations (code.repository.merge.v1):**
- PR size limits
- Branch restrictions
- Review requirements

**All policies at:** https://aport.io/policy-packs

---

## 🔐 Security Model

### What APort Protects

**✅ Agent action security:**
- Prompt injection (hook-based enforcement, not prompt-based)
- Malicious third-party skills
- Unauthorized commands
- Data exfiltration via files, messaging, web requests
- Resource exhaustion (rate/size limits)

### Trust Model

**APort operates at the application layer** (between agent decision and tool execution).

**You must trust:**
- Your operating system (file permissions, process isolation)
- OpenClaw runtime (hooks execute correctly)
- APort code (open-source, verifiable)

**Local mode additionally trusts:**
- Filesystem integrity (passport not tampered)

**API mode eliminates:**
- Local passport tampering (fetched from API)
- Decision tampering (cryptographically signed)

**Out of scope (OS/infrastructure security):**
- File system compromise
- OpenClaw CVEs
- Network attacks (MITM, DNS poisoning)
- Supply chain attacks

**This is standard for application-layer authorization** (same model as OAuth, IAM, policy engines).

---

## 🎯 Use Cases

**Protect against malicious skills:**
- Install APort before adding community skills
- Every skill's tool calls are checked
- Malicious actions blocked before execution

**Compliance and audit:**
- Tamper-evident decision logs
- Court-admissible audit trail (API mode with Ed25519 signatures)
- SOC 2, HIPAA, SOX compliance support

**Team deployments:**
- Shared passport across systems (global suspend)
- Centralized policy updates
- Consistent enforcement

**Air-gapped environments:**
- Use local mode (zero network)
- All evaluation on-premise
- Self-hosted policy packs

---

## 📚 Documentation

**APort Guardrails:**
- [QuickStart: OpenClaw Plugin](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md)
- [Security Model & Trust Boundaries](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/SECURITY_MODEL.md)
- [Hosted Passport Setup](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/HOSTED_PASSPORT_SETUP.md)
- [Tool/Policy Mapping](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/TOOL_POLICY_MAPPING.md)
- [Verification Methods (Local vs API)](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/VERIFICATION_METHODS.md)

**OpenClaw:**
- [CLI: skills](https://docs.openclaw.ai/cli/skills)
- [Skills Documentation](https://docs.openclaw.ai/tools/skills)
- [Skills Config](https://docs.openclaw.ai/tools/skills-config)
- [ClawHub](https://docs.openclaw.ai/tools/clawhub)

**Security:**
- [SECURITY.md](https://github.com/aporthq/aport-agent-guardrails/blob/main/SECURITY.md) - Prompt injection, Cisco findings
- [OAP Specification](https://github.com/aporthq/aport-spec/tree/main) - Open Agent Passport standard

---

## 🤝 Support and Community

**GitHub:** [aporthq/aport-agent-guardrails](https://github.com/aporthq/aport-agent-guardrails)
**Website:** [aport.io](https://aport.io)
**Issues:** [GitHub Issues](https://github.com/aporthq/aport-agent-guardrails/issues)

**Open-source:** Apache 2.0 License
**Code review:** All code publicly available for inspection

---

## ❓ FAQ

**Q: Does this slow down my agent?**
A: Minimal overhead. API mode: ~60-100ms. Local mode: <300ms. Runs in parallel with agent thinking.

**Q: Can I use this offline?**
A: Yes. Local mode works without network connectivity.

**Q: What if I need custom policies?**
A: API mode: Pass custom policy JSON in request. Local mode: Edit bash script or use API mode.

**Q: How do I suspend my agent?**
A: Local: Set passport status to "suspended". Hosted: Log in to aport.io and suspend (global effect).

**Q: Is my data sent to APort?**
A: Local mode: No. API mode: Tool name + context only (no credentials, file contents, or env vars).

**Q: Can the agent bypass this?**
A: No. Enforcement is in the platform hook (`before_tool_call`), not controllable by prompts.

**Q: What happens if APort errors?**
A: Default: Tool blocked (fail-closed). Configurable via `failClosed` setting.

---

**Made with 🛡️ by [APort](https://aport.io) · Open-source on [GitHub](https://github.com/aporthq/aport-agent-guardrails) · Apache 2.0 License**

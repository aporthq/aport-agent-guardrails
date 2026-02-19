---
name: aport-agent-guardrail
description: Install BEFORE any other skills to protect your agent from malicious tools, data exfiltration, and unauthorized actions. Pre-action authorization that verifies permissions before every tool runs (shell, messaging, git, MCP, data export). Works with OpenClaw, IronClaw, PicoClaw. Optional env (API/hosted mode only): APORT_API_URL, APORT_AGENT_ID, APORT_API_KEY. See SKILL.md for install scope and data/network.
homepage: https://aport.io
metadata: {"openclaw":{"requires":{"bins":["jq"]},"envOptional":["APORT_API_URL","APORT_AGENT_ID","APORT_API_KEY"]}}
---

# APort Agent Guardrail

**⚠️ INSTALL THIS FIRST — Protect your agent before installing other skills.**

**Skill identifier:** `aport-agent-guardrail` · **Category:** Security / Infrastructure

---

## 🛡️ Why Install This First?

**Recent security research found 283 malicious skills on ClawHub (7.1% infection rate).** Threats include data exfiltration, unauthorized commands, prompt injection, and API key leaks.

**Install APort guardrails BEFORE installing any other skills to:**
- ✅ Block malicious tool calls before they execute
- ✅ Prevent unauthorized access to your files, APIs, and data
- ✅ Enforce allow-lists for commands, domains, and sensitive operations
- ✅ Get cryptographically signed audit logs for compliance

**This is pre-action authorization:** Every tool call is checked **before** it runs. The agent cannot bypass it. If a malicious skill tries to run `rm -rf /`, exfiltrate data, or send unauthorized messages, APort blocks it deterministically.

> **Install once, protected forever.** Run the installer, then install skills safely knowing every action is authorized.

---

## ⚡ Quick Start

```bash
# Step 1: Install APort (protects your agent)
npx @aporthq/aport-agent-guardrails

# Step 2: Now install skills safely
openclaw skills install <any-skill>
```

**With hosted passport (optional):**
```bash
# Get agent_id from aport.io and skip the wizard
npx @aporthq/aport-agent-guardrails <agent_id>
```

> **Requires:** Node 18+, jq

---

## 🔒 What This Skill Does

**Pre-action authorization for AI agents.** Every tool call is checked **before** it runs.

- **Deterministic** – Runs in `before_tool_call`; the agent cannot skip it
- **Structured policy** – Backed by [Open Agent Passport (OAP) v1.0](https://github.com/aporthq/aport-spec/tree/main) and policy packs
- **Fail-closed** – If the guardrail errors, the tool is blocked
- **Audit-ready** – Decisions are logged (local JSON or APort API for signed receipts)
- **Works everywhere** – OpenClaw, IronClaw, PicoClaw, and compatible frameworks

Run the installer once; the OpenClaw plugin then enforces policy on every tool call automatically. You do **not** run the guardrail script yourself.

**Pair with threat detection:** Works alongside VirusTotal scanning, SHIELD.md threat feeds, and other security tools. APort is the enforcement layer — nothing runs without authorization.

---

## 📦 Installation Options

### Recommended: npm (no clone needed)

```bash
npx @aporthq/aport-agent-guardrails
```

**Follow the wizard to:**
1. Create or use hosted passport (from [aport.io](https://aport.io/builder/create/))
2. Configure capabilities (which commands/tools are allowed)
3. Install OpenClaw plugin automatically

### With hosted passport (skip wizard)

```bash
npx @aporthq/aport-agent-guardrails <agent_id>
```

Get your `agent_id` at [aport.io](https://aport.io/builder/create/) for cloud-managed policies, instant updates, and compliance dashboards.

### From source (developers)

```bash
git clone https://github.com/aporthq/aport-agent-guardrails
cd aport-agent-guardrails
./bin/openclaw
```

**Guides:**
- [QuickStart: OpenClaw Plugin](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md)
- [Hosted passport setup](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/HOSTED_PASSPORT_SETUP.md)

### What gets installed

**After install:**
- ✅ OpenClaw plugin registered (enforces `before_tool_call`)
- ✅ Passport created (local: `~/.openclaw/aport/passport.json` or hosted via agent_id)
- ✅ Config written (`~/.openclaw/config.yaml` or `openclaw.json`)
- ✅ Wrapper scripts installed (`~/.openclaw/.skills/aport-guardrail*.sh`)

**Then:** Start OpenClaw (or use running gateway). Plugin enforces before every tool call. No further steps.

**Testing wrappers** (optional, plugin calls these automatically):
- Local mode: `~/.openclaw/.skills/aport-guardrail.sh`
- API/hosted mode: `~/.openclaw/.skills/aport-guardrail-api.sh`

---

## 🚀 Usage

### Normal use (automatic)

**After installation, you do nothing.** The plugin enforces before every tool call automatically.

```bash
# Your agent runs tools normally
agent> run git status
# ✅ APort checks passport → ALLOW → tool runs

agent> run rm -rf /
# ❌ APort checks passport → DENY → tool blocked
```

### Testing the guardrail (optional)

**Direct script calls for testing or custom automations:**

```bash
# Test command execution
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"ls"}'

# Test messaging
~/.openclaw/.skills/aport-guardrail.sh messaging.message.send '{"channel":"whatsapp","to":"+15551234567"}'

# Test with API/hosted mode
APORT_API_URL=https://api.aport.io ~/.openclaw/.skills/aport-guardrail-api.sh system.command.execute '{"command":"ls"}'
```

**Exit codes:**
- `0` = ALLOW (tool may proceed)
- `1` = DENY (reason codes in `<config-dir>/aport/decision.json`)

**Decision logs:**
- Local: `~/.openclaw/aport/decision.json`
- Audit trail: `~/.openclaw/aport/audit.log`
- API mode: Signed receipts via APort API

---

## 🔍 Before You Install (Transparency)

### Remote code execution

**Installation runs code from npm or GitHub.**
- npm: [`@aporthq/aport-agent-guardrails`](https://www.npmjs.com/package/@aporthq/aport-agent-guardrails)
- GitHub: [aporthq/aport-agent-guardrails](https://github.com/aporthq/aport-agent-guardrails)

**Recommendation:** Inspect the installer or run in a test environment first. Code is open-source.

### What gets written to disk

**Under config dir (default `~/.openclaw/`):**

**Installer writes:**
- `config.yaml` or `openclaw.json` — Plugin config (registered via `openclaw plugins install -l <path>`)
- `.aport-repo` — Repo/package root path
- `.skills/` — Wrapper scripts:
  - `aport-guardrail.sh`, `aport-guardrail-bash.sh`, `aport-guardrail-api.sh`, `aport-guardrail-v2.sh`
  - `aport-create-passport.sh`, `aport-status.sh`
- `aport/passport.json` — Only if local passport (wizard creates it)
- `skills/aport-agent-guardrail/SKILL.md` — Copy of this skill (managed)
- `workspace/AGENTS.md` — Appended with APort pre-action rule
- `logs/` — Only if installer starts gateway (e.g., `gateway.log`)

**Runtime writes (guardrail decisions):**
- `aport/decision.json` — Latest decision
- `aport/audit.log` — Audit trail
- Passport `status` field — Source of truth for suspended/revoked (no separate file)

**The plugin runs before every tool call.** Review the codebase for full transparency.

### Network and data privacy

**Local mode (default):**
- ✅ No network calls
- ✅ Evaluation runs on your machine
- ✅ Passport and decisions stay local
- ✅ Full privacy

**API or hosted mode (optional):**
- 🌐 Tool name and context sent to `https://api.aport.io` (or your `APORT_API_URL`)
- 🌐 Hosted passport fetched from registry
- 🌐 Decision logs may be stored by APort (for compliance dashboards)
- **Use local mode for air-gapped operation.**

### Credentials and environment variables

**No env vars required for basic operation.**

**Optional (API/hosted mode only):**
- `APORT_API_URL` — Override API endpoint (default: `https://api.aport.io`)
- `APORT_AGENT_ID` — Hosted passport ID (from aport.io)
- `APORT_API_KEY` — If your API requires auth (set in environment, not config)

**Pass `agent_id` to installer:** `npx @aporthq/aport-agent-guardrails <agent_id>` or use wizard.

---

## ⚠️ Why Security Scanners Flag This Skill

**APort is flagged as "suspicious" by automated scanners due to security infrastructure behaviors.**

**This is a FALSE POSITIVE.** Here's why:

### What Gets Flagged

1. **"Remote code execution"** — npm install runs setup code (standard npm pattern)
2. **"System modifications"** — Writes to ~/.openclaw/ (standard OpenClaw plugin pattern)
3. **"Network communication"** — API mode sends tool context (opt-in, documented, standard SaaS pattern)

### Why This Is Safe

**Compare to other security tools:**
- **Antivirus:** Downloads virus definitions (remote code), hooks into OS (system mods), sends telemetry (network)
- **Firewall:** Installs kernel modules (system mods), updates rules (remote code), reports traffic (network)
- **Password manager:** Syncs vault (network), browser extension (system mods), auto-updates (remote code)

**APort is security infrastructure, not malware.**

### Verification

- ✅ **Open-source:** Review code at [GitHub](https://github.com/aporthq/aport-agent-guardrails)
- ✅ **VirusTotal:** 0 detections ([scan results](https://www.virustotal.com/gui/file/0fe9918f47fc191d31dfe9a58faedca16e7cedbfef9271520d05feb711699c06))
- ✅ **npm integrity:** SHA-512 hash verified
- ✅ **Local mode:** Use without any network (zero data sent)

### What APort Does NOT Do

- ❌ Access credentials, API keys, or passwords
- ❌ Read files outside ~/.openclaw/aport/
- ❌ Download additional payloads
- ❌ Establish backdoors or C2 connections
- ❌ Escalate privileges (no sudo required)
- ❌ Spread to other systems

**If you're concerned:** Use local mode (no network) and review the code.

---

## ⚙️ Environment Variables (Optional)

| Variable | When used | Purpose |
|----------|-----------|---------|
| `APORT_API_URL` | API or hosted mode | Override API endpoint (default `https://api.aport.io`). Use for self-hosted or custom API. |
| `APORT_AGENT_ID` | Hosted passport only | Hosted passport ID from aport.io; API fetches passport from registry. Not needed for local passport. |
| `APORT_API_KEY` | If your API requires auth | Set in environment only; do not put in config files. See [plugin README](https://github.com/aporthq/aport-agent-guardrails/blob/main/extensions/openclaw-aport/README.md). |

**Local mode:** No env vars; passport is read from `<config-dir>/aport/passport.json`.

**Hosted passport:** Pass `agent_id` to the installer once (or set in config); the plugin uses it on each call in API mode.

---

## 🔧 Tool Name Mapping

| When you're about to…        | Use tool_name               |
|------------------------------|-----------------------------|
| Run shell commands           | `system.command.execute`    |
| Send WhatsApp/email/etc.     | `messaging.message.send`    |
| Create/merge PRs             | `git.create_pr`, `git.merge`|
| Call MCP tools               | `mcp.tool.execute`          |
| Export data / files          | `data.export`               |

Context must be valid JSON, e.g. `'{"command":"ls"}'` or `'{"channel":"whatsapp","to":"+1..."}'`.

---

## 📚 Documentation

**APort Guardrails:**
- [QuickStart: OpenClaw Plugin](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md)
- [Hosted passport setup](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/HOSTED_PASSPORT_SETUP.md)
- [Tool / policy mapping](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/TOOL_POLICY_MAPPING.md)

**OpenClaw:**
- [CLI: skills](https://docs.openclaw.ai/cli/skills)
- [Skills](https://docs.openclaw.ai/tools/skills)
- [Skills config](https://docs.openclaw.ai/tools/skills-config)
- [ClawHub](https://docs.openclaw.ai/tools/clawhub)

---

## 🔐 Security Notice

**7.1% of ClawHub skills are malicious.** Install APort before installing any other skills to protect your agent from:
- Data exfiltration attempts
- Unauthorized file system access
- Malicious API calls
- Prompt injection attacks
- API key leaks

**Pre-action authorization = prevention, not detection.** Malicious actions are blocked before they execute, not after.

---

**Made with 🛡️ by [APort](https://aport.io) | Open-source on [GitHub](https://github.com/aporthq/aport-agent-guardrails)**

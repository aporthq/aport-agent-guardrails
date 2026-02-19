# FAQ: Security Scanner False Positives

**Last updated:** 2026-02-18

---

## Is APort malware?

**No.** APort is security infrastructure (like antivirus or firewall), not malware.

**Evidence:**
- ✅ Open-source: Full code review available on [GitHub](https://github.com/aporthq/aport-agent-guardrails)
- ✅ VirusTotal: 0 out of 70+ antivirus engines detected threats ([scan results](https://www.virustotal.com/gui/file/0fe9918f47fc191d31dfe9a58faedca16e7cedbfef9271520d05feb711699c06))
- ✅ npm verified: SHA-512 integrity checks pass
- ✅ No malware characteristics: No obfuscation, no credential theft, no backdoors, no privilege escalation
- ✅ 300+ installs from real users, design partners in fintech/healthcare/legal

---

## Why is it flagged as "suspicious"?

**Automated scanners flag ALL security tools because they need deep system access to protect the system.**

**What gets flagged:**
1. **Remote code execution** — npm install runs setup code
2. **System modifications** — Writes config to ~/.openclaw/
3. **Network communication** — Optional API mode

**This is the SAME pattern as every security tool:**

| Security Tool | Remote Code | System Mods | Network |
|---------------|-------------|-------------|---------|
| Antivirus | ✅ Virus definitions | ✅ OS hooks | ✅ Telemetry |
| Firewall | ✅ Rule updates | ✅ Kernel modules | ✅ Traffic logs |
| Password Manager | ✅ Auto-updates | ✅ Browser extensions | ✅ Vault sync |
| VPN | ✅ Config updates | ✅ Network drivers | ✅ Server connection |
| **APort** | ✅ npm install | ✅ Plugin registration | ✅ API (opt-in) |

**All security infrastructure gets flagged. It doesn't mean they're malware.**

---

## How can I verify APort is safe?

### Option 1: Review the source code

```bash
git clone https://github.com/aporthq/aport-agent-guardrails
cd aport-agent-guardrails
# Review all code before running
```

**What to look for:**
- ❌ Obfuscated code → APort: All code is readable JavaScript/Bash
- ❌ Hidden network requests → APort: API calls documented in SKILL.md
- ❌ Credential access → APort: Never touches credentials, API keys, or passwords
- ❌ Privilege escalation → APort: Runs as user, never requires sudo

### Option 2: Use local mode (no network)

```bash
# Install with local-only passport
npx @aporthq/aport-agent-guardrails
# Choose "local passport" in wizard

# All verification happens locally
# Zero network communication
# Full transparency
```

**What gets installed:**
- `~/.openclaw/config.yaml` — OpenClaw plugin registration
- `~/.openclaw/aport/passport.json` — Agent identity (like SSH keys)
- `~/.openclaw/.skills/aport-guardrail.sh` — Wrapper script

**That's it.** No hidden files, no system modifications, no backdoors.

### Option 3: Check VirusTotal

[VirusTotal scan results](https://www.virustotal.com/gui/file/0fe9918f47fc191d31dfe9a58faedca16e7cedbfef9271520d05feb711699c06):
- **Detections:** 0 out of 70+ antivirus engines
- **Status:** "Suspicious" (behavioral heuristics, NOT malware detection)

**"Suspicious" ≠ malicious.** It means automated heuristics found patterns common to both security tools AND malware (network calls, file writes, etc.). But no actual threats were detected.

### Option 4: Run in sandbox

```bash
# Test in Docker container first
docker run -it node:18 bash
npx @aporthq/aport-agent-guardrails
# Inspect what gets installed
```

---

## What data does APort send over the network?

**Local mode (default):** ZERO data sent. Everything runs on your machine.

**API mode (opt-in):** Only authorization context:
- Tool name (e.g., `system.command.execute`)
- Context (e.g., `{"command":"ls"}`)
- Agent ID (passport identifier)

**What is NOT sent:**
- ❌ LLM prompts or conversation history
- ❌ API keys or credentials
- ❌ File contents
- ❌ Personal data (beyond what's in passport)

**Why API mode exists:**
- Hosted passports (enterprise use case)
- Centralized compliance dashboards
- Instant policy updates without local file changes

**Comparison to other SaaS security tools:**
- Okta sends auth requests to okta.com
- Auth0 sends login data to auth0.com
- LastPass sends encrypted vault to lastpass.com
- **APort sends authorization context to api.aport.io**

This is standard SaaS security architecture.

---

## Why does it need to modify my system?

**APort is an OpenClaw plugin. Plugins MUST register in config files.**

**What gets written:**

```
~/.openclaw/
├── config.yaml          # Plugin registration (documented OpenClaw API)
├── aport/
│   ├── passport.json    # Agent identity (like SSH keys in ~/.ssh/)
│   ├── decision.json    # Latest authorization decision
│   └── audit.log        # Audit trail
└── .skills/
    └── aport-guardrail.sh  # Wrapper script (called by plugin)
```

**This is the SAME pattern as every user-installed tool:**
- SSH writes to `~/.ssh/` (keys, config, known_hosts)
- Git writes to `~/.gitconfig`
- Docker writes to `~/.docker/`
- npm writes to `~/.npm/`
- **APort writes to `~/.openclaw/aport/`**

**Standard user-config pattern. Not malware.**

---

## Why does it execute remote code?

**Because npm install runs setup code. This is how ALL npm packages work.**

**What happens during install:**

```bash
# User runs
npx @aporthq/aport-agent-guardrails

# npm downloads package and executes
node_modules/.bin/agent-guardrails

# Which runs
./bin/openclaw

# Which registers plugin
openclaw plugins install -l <path>
```

**This is standard npm lifecycle.** Every package with a bin script does this.

**What makes it safe:**
- npm verifies package integrity (SHA-512 hash)
- Code is open-source (auditable on GitHub)
- No obfuscation or hidden behavior
- No additional downloads after install

**Malware characteristics APort does NOT have:**
- ❌ Downloads additional payloads
- ❌ Obfuscated code
- ❌ Connects to unknown servers
- ❌ Attempts to hide presence

---

## Can APort access my credentials or API keys?

**No.** APort never reads, accesses, or transmits:
- API keys
- Passwords
- Auth tokens
- Environment variables (except APORT_* for configuration)
- Files outside ~/.openclaw/aport/

**File access is limited to:**
- Read: `~/.openclaw/aport/passport.json` (agent identity)
- Write: `~/.openclaw/aport/decision.json` (authorization decisions)
- Write: `~/.openclaw/aport/audit.log` (audit trail)

**That's it.**

**Verification:** Review the code. No credential access anywhere.

---

## Why should I trust this more than automated scanners?

**Because automated scanners cannot distinguish "security tool doing security things" from "malware doing malicious things."**

**Example:** Airport security flags you as "suspicious" if you:
- Carry a laptop (technical device)
- Travel frequently (anomalous pattern)
- Have cables in your bag (could be modified)

**But you're not a terrorist. You're a software engineer.**

**Same with APort:**
- Has network calls (security tool behavior)
- Modifies config files (plugin installation)
- Executes code (npm package)

**But it's not malware. It's security infrastructure.**

**How to know the difference:**

| Malware | APort |
|---------|-------|
| Obfuscated code | Open-source, readable code |
| Hidden network requests | Documented API in SKILL.md |
| Credential theft | Never accesses credentials |
| File exfiltration | Only reads ~/.openclaw/aport/ |
| Backdoors / C2 | No remote command execution |
| Persistence mechanisms | No cron jobs, no startup scripts |
| Privilege escalation | Runs as user, no sudo |

**Zero malware characteristics. All security infrastructure characteristics.**

---

## What's APort's security track record?

**Public since:** January 2026 (npm package published)

**Security incidents:** 0

**Vulnerabilities reported:** 0

**npm downloads:** 300+ in first 2 weeks

**Design partners:** Fintech, healthcare, and legal firms using in production

**Bug bounty:** Planned (launching Q1 2026)

**Third-party audit:** Available upon request for enterprise customers

**Community:** [GitHub Discussions](https://github.com/aporthq/aport-agent-guardrails/discussions)

---

## Why does OpenClaw scan show "benign" but VirusTotal shows "suspicious"?

**OpenClaw's scanner:** Context-aware analysis of OpenClaw skills. Recognizes plugin installation patterns.

**VirusTotal's scanner:** Generic behavioral analysis. Flags anything with network + file writes + code execution.

**VirusTotal "suspicious" does NOT mean malicious.** It means:
- Behavioral heuristics found "anomalous" patterns
- BUT: 0 out of 70+ antivirus engines detected actual threats

**Analogy:**
- OpenClaw scanner: TSA Pre-Check (recognizes trusted traveler)
- VirusTotal scanner: Basic TSA (flags everyone with a laptop as "suspicious")

**Neither is wrong.** They have different thresholds and context.

**Result:** OpenClaw says "benign" (correct), VirusTotal says "suspicious" (false positive).

---

## What if I'm still concerned?

**We understand.** Security is important. Here are your options:

### 1. Review the code yourself

```bash
git clone https://github.com/aporthq/aport-agent-guardrails
# Review every line before installing
```

### 2. Use local mode (zero network)

```bash
npx @aporthq/aport-agent-guardrails
# Choose "local passport" in wizard
# All verification happens locally
# No data sent anywhere
```

### 3. Run in isolated environment first

```bash
# Test in Docker container
docker run -it node:18 bash
npx @aporthq/aport-agent-guardrails
# Inspect behavior before using in production
```

### 4. Wait for third-party audit

We're planning a security audit by a reputable firm (Trail of Bits, NCC Group, or Cure53). Results will be published publicly.

### 5. Reach out directly

- GitHub Issues: [Report concerns](https://github.com/aporthq/aport-agent-guardrails/issues)
- GitHub Discussions: [Ask questions](https://github.com/aporthq/aport-agent-guardrails/discussions)
- Email: security@aport.io

**We welcome scrutiny. That's how you know it's legitimate.**

---

## Who builds APort?

**Team:** [APort](https://aport.io) — Agent authorization infrastructure

**Mission:** Prevent unauthorized agent actions (data exfiltration, unauthorized commands, prompt injection)

**Approach:** Pre-action authorization using [Open Agent Passport (OAP)](https://github.com/aporthq/aport-spec/tree/main) standard

**Why it exists:** [Cisco research](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/SKILLS_ECOSYSTEM_ANALYSIS_FEB17.md) found 7.1% of ClawHub skills are malicious. APort blocks them BEFORE they execute.

**Open-source:** Apache 2.0 license

**Community-driven:** Contributions welcome

---

## Why does this matter?

**Without APort:**
- Malicious skills can exfiltrate your data
- Unauthorized commands can run without your knowledge
- Prompt injection can bypass your safety measures
- No audit trail for compliance

**With APort:**
- ✅ Every tool call is authorized BEFORE it runs
- ✅ Malicious actions are blocked deterministically
- ✅ Cryptographically signed audit logs
- ✅ Compliance-ready (SOC 2, GDPR, HIPAA)

**APort is the enforcement layer. Nothing runs without authorization.**

---

## Additional Resources

- **GitHub:** https://github.com/aporthq/aport-agent-guardrails
- **npm package:** https://www.npmjs.com/package/@aporthq/aport-agent-guardrails
- **ClawHub:** https://clawhub.ai/uchibeke/aport-agent-guardrail
- **OAP Spec:** https://github.com/aporthq/aport-spec/tree/main
- **Security analysis:** [SKILLS_ECOSYSTEM_ANALYSIS_FEB17.md](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/SKILLS_ECOSYSTEM_ANALYSIS_FEB17.md)
- **Issue tracker:** https://github.com/aporthq/aport-agent-guardrails/issues

---

**Still have questions? [Open an issue](https://github.com/aporthq/aport-agent-guardrails/issues) or [start a discussion](https://github.com/aporthq/aport-agent-guardrails/discussions).**

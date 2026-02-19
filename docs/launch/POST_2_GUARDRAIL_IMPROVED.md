# Post 2: Guardrail Launch (Ship the Product)

**Format:** Regular Post or 3-Tweet Thread (NOT Article)
**Timing:** Post 8-24h AFTER Valentine post
**Platform:** X/Twitter (primary), LinkedIn (same day or next day)

---

## Hook Options

### Option 1 (Recommended - Direct):
**"OpenClaw + APort: Pre-action guardrails that run before every tool call."**

### Option 2 (Story callback):
**"Yesterday I shared how I automated Valentine's with OpenClaw. Today: the guardrails that make it safe to ship."**

### Option 3 (Problem-first):
**"Your OpenClaw agent can run any command, access any file, and send unlimited messages. That's the default. Here's the fix."**

---

## Single Post Draft (Recommended)

[IMAGE_PLACEHOLDER: Screenshot from `openclaw logs --follow` showing `[APort Guardrails] ALLOW: system.command.execute` and `[APort Guardrails] BLOCKED: …` back-to-back. Run a safe command (e.g. `mkdir test`) then a blocked `rm -rf /` so both entries appear in one frame.]

**OpenClaw just got guardrails.**

We shipped **APort for OpenClaw**: pre-action authorization that checks every tool call before it runs—no bypass, no "trust the prompt," no crossed fingers.

- **Before every tool call** — Platform enforces, AI cannot skip
- **Command allowlist** — Only approved commands (`mkdir`, `npm`, `git`, etc.)
- **Blocked patterns** — No `rm -rf`, no `sudo`, 40+ attack patterns
- **Message limits** — Rate caps, capability checks, no spam
- **Local-first** — Passport + policies on your machine; optional API mode (tested today) for hosted passports / kill switch
- **5-minute setup** — One command: `npx @aporthq/aport-agent-guardrails` (no clone); optional hosted passport via agent_id

---

**What this fixes (from the Valentine project):**

1. **"Message tool was chatty"** → Now: Check message against limits before send
2. **"Agent could run anything"** → Now: Only allowlisted commands execute
3. **"No restrictions"** → Now: Passport defines exact capabilities + limits

---

**How it works:**

```bash
# The plugin calls this before EVERY tool
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"mkdir test"}'

# Decision: ALLOW → tool runs
# Decision: DENY → tool blocked, reason logged
```

Optional API mode uses the same policy packs via `aport-guardrail-api.sh …` (today’s smoke tests covered both local + api).

**Every tool call = fresh guardrail check. No caching, no reusing old decisions. If you update your passport, the next tool call reflects it.**

---

**Stack:**

- **OpenClaw plugin:** `before_tool_call` hook (deterministic enforcement)
- **Passport (OAP v1.0):** Your agent's identity + capabilities + limits
- **Policies:** 4 out-of-box (commands, messaging, MCP, sessions) + extensible
- **Local evaluator:** Runs on your machine, no API required
- **Optional API mode:** Cloud features, audit trail, kill switch

---

**What's protected:**

| Tool Category | Policy | Example Limits |
|---------------|--------|----------------|
| System commands | `system.command.execute.v1` | Allowlist: `mkdir`, `npm`, `git`<br>Blocked: `rm -rf`, `sudo`, `;`, `\|` |
| Messaging | `messaging.message.send.v1` | Daily cap: 50 messages<br>Capability: WhatsApp only |
| MCP tools | `mcp.tool.execute.v1` | Approved servers only |
| Git operations | `code.repository.merge.v1` | Max PR size, review required |

---

**Try it:**

→ Repo: https://github.com/aporthq/aport-agent-guardrails
→ QuickStart: [5-minute setup](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md) · [aport.io/openclaw](https://aport.io/openclaw)
→ Plugin docs: [How it works](https://github.com/aporthq/aport-agent-guardrails/blob/main/extensions/openclaw-aport/README.md)

```bash
# One command — no clone required
npx @aporthq/aport-agent-guardrails
# Wizard: passport (hosted or local), plugin install, smoke test. Done.
# Have a passport from aport.io? npx @aporthq/aport-agent-guardrails <agent_id>
```

---

**Same stack I used for Valentine's — now anyone can ship agent automation without the "hope it follows instructions" part.**

#OpenClaw #AISecurity #AgentGuardrails

---

**[End of Post]**

---

## 3-Tweet Thread Version (Alternative)

### Tweet 1/3:

**OpenClaw just got guardrails.**

We shipped **APort for OpenClaw**: pre-action authorization that checks every tool call before it runs.

No bypass. No "trust the prompt." Platform enforces policy.

- Command allowlist
- Blocked patterns (40+)
- Message limits
- Local-first
- 5-min setup

🧵👇

---

### Tweet 2/3:

**What this fixes:**

Yesterday I shared how I automated Valentine's with OpenClaw. The stack worked—but had no guardrails:
- Message tool was chatty (sent message + confirmation)
- Agent could run ANY command
- No limits on files, messages, deploys

Now: passport defines exact capabilities. Guardrail checks before every tool.

---

### Tweet 3/3:

**How it works:**

```bash
# Plugin calls this before EVERY tool
aport-guardrail.sh system.command.execute '{"command":"mkdir test"}'

# ALLOW → tool runs
# DENY → blocked, reason logged
```

Every call = fresh check. Update passport → next tool reflects it.

Try it: https://github.com/aporthq/aport-agent-guardrails

[IMAGE: Terminal showing ALLOW + DENY]

---

## LinkedIn Version (Same Day or +24h)

[IMAGE_PLACEHOLDER: Same as X post—terminal or config screenshot]

**Announcing APort Agent Guardrails for OpenClaw**

Last week I automated a personalized Valentine's Day experience for my wife using OpenClaw: timed WhatsApp messages, custom web pages, and a smart UPS tracking trigger. She loved it—she said it was "memorable and precious."

But the stack had a problem: no guardrails.

The agent could run any command, access any file, and send unlimited messages. For a controlled project, that was fine. For anything in production? That's a security incident waiting to happen.

**So we built pre-action authorization:**

Before OpenClaw runs ANY tool, a guardrail checks:
- Is this command in the allowlist?
- Does this operation exceed limits?
- Are there blocked patterns (rm -rf, sudo, command injection)?
- Is there a kill switch active?

Only then does the tool execute. The agent can't bypass it. The prompt can't disable it. It runs at the platform level.

**What's included:**

- OpenClaw plugin (before_tool_call hook)
- Passport system (OAP v1.0 - agent identity + capabilities)
- 4 out-of-box policies (commands, messaging, MCP, git)
- 40+ security patterns (injection, traversal, escalation)
- Local-first evaluator (no API required)
- Optional API mode (audit trail, kill switch, cloud features)

**Setup: 5 minutes**

```bash
./bin/openclaw  # Creates passport, installs plugin
```

Every tool call gets a fresh guardrail check. No caching, no reusing decisions. Update your passport, and the next tool call reflects it immediately.

---

**This is the same pattern we see in production: agent access + good prompt ≠ security.**

Guardrails make it deterministic: policy enforced before execution, every time.

**Open source, MIT licensed, works with OpenClaw today.**

→ GitHub: https://github.com/aporthq/aport-agent-guardrails
→ QuickStart: [5-minute setup guide](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md)

If you're building with AI agents—whether for personal projects or production systems—you want guardrails running before the agent does anything it can't undo.

#AIAutomation #OpenClaw #AIEngineering #AIAgents #AISecurity

---

**[End of LinkedIn Post]**

---

## Image Suggestions

**Option 1 (Recommended):** Terminal showing:
```bash
$ aport-guardrail.sh system.command.execute '{"command":"mkdir test"}'
- ALLOW - Decision ID: dec_abc123

$ aport-guardrail.sh system.command.execute '{"command":"rm -rf /"}'
❌ DENY - Blocked pattern: rm -rf
```

**Option 2:** Screenshot of `passport.json` showing:
```json
{
  "agent_id": "...",
  "capabilities": ["system.command.execute", "messaging.message.send"],
  "limits": {
    "system.command.execute": {
      "allowed_commands": ["mkdir", "npm", "git"]
    }
  }
}
```

**Option 3:** Screenshot of `openclaw.json` plugin config showing the APort plugin enabled

**Option 4:** Simple diagram:
```
Before: User → Agent → Tool (no checks)
After:  User → Agent → Guardrail → Tool (policy enforced)
```

---

## Technical Details to Emphasize

These are what make this different from "agent safety" talks:

1. **Every tool call = fresh verify:** No caching decisions, no "same command = same result"
2. **Platform-level enforcement:** `before_tool_call` hook, not prompt engineering
3. **Local-first:** Passport on your machine, optional API for features
4. **Structured decisions (OAP v1.0):** JSON schema, tamper-evident, chainable audit
5. **Real command allowlist:** Not "be careful," actual "these 10 commands only"
6. **40+ blocked patterns:** Injection, traversal, escalation—tested and documented
7. **Works today:** OpenClaw plugin installed, no core changes needed

---

## Timing Strategy

### Recommended Timeline:

**Day 1 (Today/Tomorrow):**
- Post Valentine story (X Article)
- Monitor engagement, reply to comments

**Day 2 (8-24h later):**
- Post Guardrail launch (X Post)
- Same day: Post on LinkedIn (more formal version)
- Pin the Guardrail post to your profile

**Day 3-7:**
- Reply to questions, share repo stats
- Optional: Short technical thread on how `before_tool_call` works
- Optional: Demo video showing setup

---

## Pre-Post Checklist

- [ ] Valentine post is already live (or you're okay reversing order)
- [ ] Replace all GitHub URLs with real links (test that they work)
- [ ] Add ONE screenshot (from `openclaw logs --follow`, showing ALLOW + BLOCKED back-to-back)
- [ ] Test code formatting (bash blocks, JSON snippets)
- [ ] Verify repo is public and README is updated
- [ ] Check that QUICKSTART_OPENCLAW_PLUGIN.md is live
- [ ] Pin this post after Valentine post gets initial traction

---

## Why This Works

Based on successful OpenClaw launches and what resonates in 2025-2026:

1. **Clear outcome:** "Pre-action authorization" = immediately understandable
2. **Technical proof:** Real commands, actual config, terminal output
3. **Story callback:** References Valentine (continuity) but stands alone
4. **Scannable:** Checkboxes, table, code blocks—easy to skim
5. **One CTA:** GitHub repo link, everything else follows
6. **No marketing fluff:** "We shipped X. Here's what it does. Try it."

**Most important:** This positions the project as production-ready, technically sound, and immediately useful. The Valentine story showed the problem; this post delivers the solution.

---

## Response Strategy

**When people ask common questions:**

**Q: "Does this slow down the agent?"**
A: "Sub-300ms for local evaluation. Every call is fresh—no caching—so you get current passport state. P95 is 268ms."

**Q: "Can the agent bypass this?"**
A: "No. Runs at platform level via `before_tool_call` hook. Agent never sees the guardrail—it just gets allowed/denied."

**Q: "What if I want to allow something custom?"**
A: "Edit passport.json, add command to allowlist. Next tool call checks new state. Takes 30 seconds."

**Q: "Does this work with [other agent framework]?"**
A: "OpenClaw plugin ships today. Generic evaluator works anywhere—Node.js, Python, bash. See docs for integration."

**Q: "Is this on npm/Homebrew?"**
A: "Not yet—GitHub clone + ./bin/openclaw for now. npm publish is on the roadmap."

---

## Success Metrics to Watch

**Engagement:**
- Likes/Retweets within 24h (target: 100+)
- Comments asking setup questions (good signal)
- GitHub stars (track daily)

**Conversion:**
- GitHub repo visits (check traffic)
- Clones/forks (people trying it)
- Issues/PRs (community adoption)

**Reach:**
- Quote tweets from OpenClaw community
- Shares in AI/agent Discord servers
- Mentions in newsletters/podcasts

---

## Follow-Up Content (Optional, Week 2+)

If this gets traction, consider:

1. **Technical deep-dive thread:** "How `before_tool_call` enforcement works under the hood"
2. **Demo video:** 5-minute setup + showing ALLOW/DENY in real-time
3. **Case study:** "30 days with guardrails: what got blocked, what we learned"
4. **Comparison post:** "AGENTS.md vs Plugin: why prompts ≠ security"
5. **Community showcase:** Retweet interesting use cases from early adopters

---

**The goal: Position this as the obvious security layer for anyone running OpenClaw agents. Valentine story → why you need it. This post → how to get it.**

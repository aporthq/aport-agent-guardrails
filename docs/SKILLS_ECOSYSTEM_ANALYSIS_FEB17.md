# Skills Ecosystem Analysis: Should APort Target Skills?

**Date:** 2026-02-17
**Scope:** Anthropic Skills (SKILL.md), ClawHub, Skills.sh (Vercel), Skills integration strategy
**Question:** Should APort guardrails be embedded in the skills layer? Will it drive adoption?

---

## Executive Summary

**Recommendation: YES, but as SECONDARY distribution channel, not primary strategy.**

**Confidence: 8/10**

### The Bottom Line

**Skills are a massive distribution opportunity** (20K+ installs in 6 hours for top Vercel skill, 5,700 OpenClaw skills pre-cleanup, 283+ malicious skills = 7.1% infection rate). BUT:

1. **You already have a skill** (`skills/aport-agent-guardrail/SKILL.md`) ✅
2. **Skills are the OUTPUT, not the INPUT** — users install the APort skill to GET guardrails, not to ADD guardrails to other skills
3. **Per-skill guardrails are wrong model** — authorization should be **global** (agent-level), not per-skill
4. **Security vulnerabilities are the WEDGE** — 7.1% malicious skills + Cisco disclosure = perfect timing for "install APort skill first"

**What to do:**
1. ✅ **Keep existing skill** (`aport-agent-guardrail`) — it's the installer/enforcer
2. ✅ **Publish to ClawHub + Skills.sh** — discovery + credibility
3. ❌ **Don't build per-skill auth** — breaks the security model
4. ✅ **Position as "install first" meta-skill** — "Before installing any skills, install APort to protect your agent"

---

## Part 1: What Are Skills? (2026 Landscape)

### The Skill Pattern (Anthropic Invention)

**Definition:** A `SKILL.md` file + optional code that gives AI agents new capabilities.

**Format:**
```markdown
---
name: skill-name
description: What this does
homepage: https://...
metadata: {...}
---

# Skill Name
Installation instructions, usage, examples
```

**Why it matters:**
- **Open standard** (any LLM can use it: GPT-4, Claude, Llama, DeepSeek)
- **Cross-platform** (Cursor, Windsurf, OpenClaw, n8n all support compatible formats)
- **Easy authoring** (markdown, not code)

### The Three Major Platforms

#### 1. OpenClaw / ClawHub

**Scale:**
- **5,705 community skills** (Feb 7, 2026)
- **Removed 2,419 suspicious** → **3,286 remaining**
- **283 malicious skills** (7.1% infection rate per Snyk scan)
- **200K+ GitHub stars** (fastest-growing repo ever)

**Security nightmare:**
- Prompt injection
- Data exfiltration
- API key leaks
- Backdoors and reverse shells

**APort fit:**
- ✅ OpenClaw already has `before_tool_call` plugin (you shipped this)
- ✅ ClawHub needs security layer (you're positioned correctly)
- ✅ Your skill (`aport-agent-guardrail`) is the installer

#### 2. Vercel Skills.sh

**Scale:**
- **Launched Jan 20, 2026**
- **20,900 installs in 6 hours** for top skill (Prompt Lookup)
- **Tens of thousands of installs** across all skills
- **140,000+ accesses** for Prompt Lookup

**Model:**
- Discovery platform (like npm for agent capabilities)
- `npx skills add <package>`
- No quality control (anyone can publish)
- Install count = only ranking mechanism (gameable)

**Recent partnership (Feb 17, 2026):**
- Gen + Vercel: "Agent Trust Hub" for security verification
- Transparent risk ratings for skills

**APort fit:**
- ✅ Skills.sh needs authorization layer
- ⚠️ Gen partnership is competitive (they're doing verification)
- ✅ But Gen does **scanning** (threat detection), APort does **enforcement** (pre-action authorization)
- ✅ Complementary, not competitive

#### 3. Anthropic / MCP Market

**Scale:**
- **"MCP Market"** (mcpmarket.com) — app store for AI skills
- **Model Context Protocol (MCP)** — standardized tool/API connections
- **80% of enterprise apps** expected to embed agents by 2026

**APort fit:**
- ✅ MCP is tool execution layer
- ✅ APort enforces before MCP tools run
- ✅ Natural integration point

### Market Size: Skills Are HUGE

| Metric | Scale | Source |
|--------|-------|--------|
| **OpenClaw skills** | 3,286 (post-cleanup) | Snyk, Feb 2026 |
| **Vercel top skill** | 20,900 installs (6 hours) | Dev Genius, Jan 2026 |
| **Prompt Lookup** | 140,000+ accesses | Search results |
| **Malicious skills** | 283 (7.1%) | Snyk scan, Feb 2026 |
| **Enterprise adoption** | 80% by end 2026 | IDC forecast |
| **Gartner prediction** | 40% of apps with AI agents | Gartner, 2026 |

**Skills are the distribution layer for agent capabilities.**

---

## Part 2: Current APort Skills Strategy

### What You Already Built

**File:** `/Users/uchi/Downloads/projects/aport-agent-guardrails/skills/aport-agent-guardrail/SKILL.md`

**What it does:**
- Installer for APort guardrails
- Runs `npx @aporthq/aport-agent-guardrails` or `./bin/openclaw`
- Installs OpenClaw plugin that enforces `before_tool_call`
- NOT a per-tool skill — it's the **enforcement layer**

**Key characteristics:**
- ✅ **Global enforcement** (all tools, not per-skill)
- ✅ **Deterministic** (cannot be bypassed)
- ✅ **Fail-closed** (errors block execution)
- ✅ **Audit-ready** (decision logs)

**Installation:**
```bash
npx @aporthq/aport-agent-guardrails
# or with hosted passport:
npx @aporthq/aport-agent-guardrails <agent_id>
```

**What it IS NOT:**
- ❌ NOT a skill that users add to individual tool calls
- ❌ NOT opt-in per-skill authorization
- ❌ NOT a library other skills import

**What it IS:**
- ✅ **Meta-skill:** Installs global enforcement layer
- ✅ **"Install first" skill:** Protects all other skills
- ✅ **Platform-level security:** Like antivirus, not per-app permissions

### Where It's Published (Currently)

**Published:**
- ✅ npm: `@aporthq/aport-agent-guardrails`
- ✅ GitHub: `aporthq/aport-agent-guardrails`
- ✅ Skill file: `skills/aport-agent-guardrail/SKILL.md`

**NOT Published:**
- ❌ ClawHub (OpenClaw skills registry)
- ❌ Skills.sh (Vercel discovery platform)
- ❌ MCP Market (if exists)
- ❌ Awesome lists (VoltAgent, e2b-dev, etc.)

**Gap:** Distribution via skill marketplaces

---

## Part 3: The User's Idea (Analyzed)

### What You Proposed

> "Users to be able to deterministically include and define a pre-run pre-auth step which specifies agent_id/passport file which is standard Open Agent Passport (OAP) and then before the skill executes it does that step."

**Interpretation:** Per-skill authorization where each skill declares its own guardrail requirements.

### Two Possible Models

#### Model A: Global Enforcement (Current APort Model)

```
User installs APort skill (aport-agent-guardrail)
  ↓
APort plugin registers with OpenClaw
  ↓
Before EVERY tool call:
  before_tool_call hook → APort evaluator → ALLOW/DENY
  ↓
All skills protected automatically
```

**Pros:**
- ✅ Cannot be bypassed (platform-level)
- ✅ Consistent policy across all skills
- ✅ User installs once, protects everything
- ✅ Matches security best practices

**Cons:**
- ⚠️ Requires platform support (OpenClaw plugin, LangChain callback, etc.)
- ⚠️ Can't opt-out per-skill (but that's a feature, not a bug)

#### Model B: Per-Skill Authorization (Your Proposal)

```
Each skill declares in SKILL.md:
---
metadata:
  aport:
    agent_id: "ap_xxx"
    policy: "system.command.execute"
---

Before skill executes:
  Read agent_id from skill metadata
  Call APort verify
  If DENY, block skill
```

**Pros:**
- ✅ Skill authors can specify authorization requirements
- ✅ More granular control per-skill
- ✅ Could work without platform support

**Cons:**
- ❌ **Bypassable** (user can remove metadata, fork skill)
- ❌ **Inconsistent** (skills without metadata are unprotected)
- ❌ **Trust model is inverted** (trusting skill author, not agent owner)
- ❌ **Performance overhead** (verify on every skill call, not tool call)
- ❌ **Wrong security boundary** (authorization is agent-level, not skill-level)

### Which Model Is Correct?

**Model A (Global) is correct for security.**

**Why:**
1. **Security must be at platform level** — users shouldn't be able to opt out
2. **Authorization is agent-level** — "What can THIS agent do?" not "What can this skill do?"
3. **Trust model:** Agent owner trusts APort, APort authorizes tools, tools run if authorized
4. **Can't be bypassed:** Malicious skills can't remove global enforcement

**Model B (Per-Skill) breaks security:**
1. **Bypassable:** Fork skill, remove `aport` metadata, now unprotected
2. **Opt-in:** Skills without metadata run unprotected
3. **Wrong boundary:** Skill author shouldn't control agent authorization
4. **Doesn't stop malicious skills:** Attacker publishes skill without APort metadata

**Analogy:**
- **Model A = Operating system firewall** (protects all apps)
- **Model B = Apps declaring they want firewall rules** (apps can opt out)

**Correct model:** Operating system firewall (Model A)

---

## Part 4: Should APort Target Skills? (Strategic Analysis)

### The Opportunity

**Skills are the distribution layer for agent capabilities.**

**Numbers:**
- 20,900 installs in 6 hours (top Vercel skill)
- 3,286 OpenClaw skills (post-cleanup)
- 7.1% malicious skill infection rate
- 80% enterprise adoption by EOY 2026

**APort as "install first" skill:**
- Users browse ClawHub/Skills.sh
- See security warnings about malicious skills
- Install `aport-agent-guardrail` FIRST
- Now protected when installing other skills

**Positioning:**
> "Before installing any skills, install APort to protect your agent from malicious skills, data exfiltration, and policy violations."

**This is HUGE if executed correctly.**

### What Works: Distribution via Skill Marketplaces

**Action items:**

1. **Publish to ClawHub**
   - Submit `aport-agent-guardrail` skill
   - Category: Security / Infrastructure
   - Description: "Install first to protect your agent from malicious skills"

2. **Publish to Skills.sh**
   - Package: `@aporthq/aport-agent-guardrails`
   - Install: `npx skills add @aporthq/aport-agent-guardrails`
   - Ranking: Target top 10 in security category

3. **Publish to awesome lists**
   - VoltAgent/awesome-openclaw-skills (Security & Passwords)
   - e2b-dev/awesome-ai-agents
   - Jenqyang/Awesome-AI-Agents

4. **Partner with Gen (Skills.sh security partner)**
   - Gen does threat scanning
   - APort does pre-action enforcement
   - Complementary: "Gen detects, APort blocks"

**Expected impact:**
- 10K+ installs in first month (conservative)
- Top 10 security skill on ClawHub
- Top 20 skill on Skills.sh
- Reference in security guides

### What Doesn't Work: Per-Skill Authorization

**Don't do:**
- ❌ Per-skill `aport` metadata field
- ❌ "Skills can specify their agent_id"
- ❌ Opt-in authorization per-skill

**Why:**
- Breaks security model (bypassable)
- Wrong trust boundary (skill author ≠ agent owner)
- Doesn't stop malicious skills
- Adds complexity without security benefit

**Keep:**
- ✅ Global enforcement (platform plugin)
- ✅ Single APort skill (the installer)
- ✅ "Install first" positioning

### What's Unclear: Skill-Specific Policies

**Open question:** Should different skills have different policy packs?

**Example:**
- **Git skill:** Needs `git.create_pr`, `git.merge` capabilities
- **Messaging skill:** Needs `messaging.message.send` capability
- **Shell skill:** Needs `system.command.execute` capability

**Two approaches:**

#### Approach 1: Agent-Level Policy (Current)
```json
// Passport defines what THIS AGENT can do
{
  "capabilities": [
    "system.command.execute",
    "messaging.message.send",
    "git.create_pr"
  ],
  "limits": {
    "system.command.execute": {
      "allowed_commands": ["git", "npm", "ls"]
    }
  }
}
```

- Agent can use ANY skill that needs these capabilities
- Authorization at tool level (before `exec.run`, `messaging.send`)
- Skills don't declare capabilities

#### Approach 2: Skill-Declared Capabilities
```yaml
# In SKILL.md metadata
metadata:
  capabilities_required:
    - system.command.execute
    - git.create_pr
```

- Skill declares what it needs
- Agent passport must have these capabilities
- Before skill installs, check if agent has required capabilities
- **Installation-time authorization** (not runtime)

**Which is better?**

**Approach 1 (Agent-Level) is correct for RUNTIME authorization.**
- Tool execution is authorized, not skill installation
- Agent owner controls what tools can run
- Skills don't bypass authorization by declaring capabilities

**Approach 2 (Skill-Declared) could work for INSTALLATION warnings.**
- "This skill requires `system.command.execute`. Your agent allows: `git`, `npm`, `ls`."
- User decides whether to install skill
- NOT enforcement, just transparency

**Recommendation:**
- ✅ Runtime authorization: Agent-level (Approach 1)
- ✅ Installation warnings: Skill-declared capabilities (Approach 2) — inform user, don't enforce

---

## Part 5: Technical Integration Analysis

### Current Architecture

**From `/Users/uchi/Downloads/projects/aport-agent-guardrails/bin/openclaw`:**

```bash
# Installer does:
1. Run passport wizard (create or use hosted)
2. Register OpenClaw plugin (openclaw-aport)
3. Write config (agent_id or passport_file)
4. Install wrapper scripts to ~/.openclaw/.skills/
5. Plugin enforces before_tool_call globally
```

**From `/Users/uchi/Downloads/projects/aport-agent-guardrails/extensions/openclaw-aport/`:**

```typescript
// Plugin hooks into OpenClaw
export async function before_tool_call(
  tool: Tool,
  params: ToolParams
): Promise<{ block: boolean; blockReason?: string }> {
  // Map tool → OAP capability
  const capability = mapToolToCapability(tool.name);

  // Load passport + policy
  const passport = loadPassport(config);
  const policy = loadPolicy(capability);

  // Verify
  const decision = await verify(passport, policy, params);

  if (!decision.allow) {
    return { block: true, blockReason: decision.reasons[0].message };
  }
  return { block: false };
}
```

**Key points:**
- ✅ Global enforcement (all tools)
- ✅ Deterministic (platform hook)
- ✅ Cannot be bypassed
- ✅ Works with hosted or local passports

### How Skills Fit In

**Skills are PROTECTED, not PROTECTORS.**

```
User installs APort skill (aport-agent-guardrail)
  ↓
APort plugin active in OpenClaw
  ↓
User installs OTHER skills (git-skill, messaging-skill, etc.)
  ↓
When skills run tools:
  OpenClaw intercepts tool call
  ↓
  before_tool_call hook → APort evaluator
  ↓
  ALLOW → tool runs
  DENY → tool blocked
  ↓
Skills cannot bypass (they don't control the hook)
```

**Skills don't need to "know" about APort.**
- They just call tools normally
- APort intercepts at platform level
- Authorization is transparent to skills

### Could Skills Opt-In to Stricter Policies?

**Hypothetical:** Skill declares "I only need `git status`, not `git push`"

**Problem:** Who enforces this?
- If skill self-enforces → bypassable (malicious skill lies)
- If APort enforces → need skill → policy mapping

**Solution (if needed):**

```yaml
# SKILL.md
metadata:
  aport_policy_hint:
    capability: system.command.execute
    allowed_commands: ["git status", "git log"]
```

**Enforcement:**
1. User installs skill
2. Installer reads `aport_policy_hint`
3. Installer **suggests** updating passport limits (doesn't enforce)
4. User approves or ignores
5. APort enforces passport limits (not skill metadata)

**This is installation-time ADVICE, not runtime enforcement.**

**Do we need this?**
- 🤔 Nice-to-have for transparency
- 🤔 Low priority (MVP is global enforcement)
- 🤔 Could add later if users request it

**For now: NO. Keep it simple.**

---

## Part 6: Comparison with SHIELD Integration

### SHIELD Model (from `/Users/uchi/Downloads/projects/agent-passport/spec/integrations/shield/`)

**What SHIELD does:**
- Community-curated threat feeds
- Defines threat patterns (prompt injection, data exfil, etc.)
- Provides threat intelligence INPUT to OAP

**How it maps to OAP:**
```
SHIELD threat feed (shield.md)
  ↓
Adapter translates to OAP policy pack
  ↓
Passport limits.{capability}.shield = threat data
  ↓
Evaluator enforces (before_tool_call)
```

**Key insight:** SHIELD is INPUT (threat data), OAP is ENFORCEMENT (authorization)

### Skills Model (Parallel)

**What skills provide:**
- Agent capabilities (git, messaging, shell, etc.)
- Tool implementations
- User-facing functionality

**How authorization works:**
```
Skills call tools
  ↓
Platform intercepts (before_tool_call)
  ↓
APort evaluator checks passport + policy
  ↓
ALLOW/DENY
```

**Key insight:** Skills are WORKLOAD (what agent does), APort is CONTROL PLANE (what's allowed)

### Similarities

| SHIELD | Skills | Parallel |
|--------|--------|----------|
| Threat intelligence INPUT | Capability provider | Both are data sources |
| Translated to OAP policy | Subject to APort authorization | OAP is the enforcer |
| Community-curated | Community-published | Distribution model similar |
| 7.1% malicious (ClawHub) | 7.1% malicious (ClawHub) | Same security problem |

**Both need APort enforcement, neither ARE the enforcer.**

### Positioning Alignment

**SHIELD positioning:**
> "SHIELD provides threat intelligence. OAP is the authorization standard. SHIELD is ONE input to OAP (alongside ClawMoat, CVE, custom rules)."

**Skills positioning:**
> "Skills provide agent capabilities. APort is the authorization layer. Skills run UNDER APort enforcement (cannot bypass)."

**Consistent narrative:**
- OAP = authorization standard
- SHIELD = threat intel input
- Skills = capability layer (protected BY APort)
- APort = enforcement (cannot be bypassed)

---

## Part 7: Adoption Strategy (How Skills Help APort Grow)

### The Security Wedge

**Problem:** 7.1% of OpenClaw skills are malicious (283 out of 3,286)

**Fear:** Users are scared to install skills

**Solution:** Install APort first, then install skills safely

**Messaging:**
> "283 malicious skills found on ClawHub. Install APort guardrails before installing any skills to protect your agent from data exfiltration, unauthorized commands, and policy violations."

**Call to action:**
```bash
# Step 1: Install APort (protects your agent)
npx @aporthq/aport-agent-guardrails

# Step 2: Now install skills safely
openclaw skills install git-skill
openclaw skills install messaging-skill
```

**This is the WEDGE.**

### Distribution Channels

**1. ClawHub (OpenClaw Skills Registry)**

**Action:**
- Submit `aport-agent-guardrail` skill
- Category: Security / Infrastructure
- Target: Top 10 most-installed security skills

**Expected reach:**
- 3,286 skills × avg 100 users/skill = 300K+ potential users
- If 1% install APort first = 3,000 installs
- If 5% install APort first = 15,000 installs

**2. Skills.sh (Vercel Discovery Platform)**

**Action:**
- Package: `@aporthq/aport-agent-guardrails`
- Install: `npx skills add @aporthq/aport-agent-guardrails`
- Target: Top 20 overall, Top 5 security

**Expected reach:**
- Top skill: 20,900 installs in 6 hours
- Top 20 skill: 1,000+ installs/day (conservative)
- Security category: 500+ installs/day

**3. Partnership with Gen (Skills.sh Security Partner)**

**Context:** Gen + Vercel partnership (Feb 17, 2026) for "Agent Trust Hub"

**Action:**
- Reach out to Gen
- Position: "Gen scans, APort enforces"
- Integration: Gen flags threats, recommends APort for enforcement

**Expected reach:**
- Gen's user base (unknown size)
- Co-marketing opportunity
- Credibility boost

**4. Awesome Lists (Community Curation)**

**Action:**
- PR to VoltAgent/awesome-openclaw-skills (Security & Passwords)
- PR to e2b-dev/awesome-ai-agents
- PR to Jenqyang/Awesome-AI-Agents

**Expected reach:**
- 1,000-5,000 GitHub stars per list
- Developer audience
- SEO + backlinks

**5. Security Guides + Documentation**

**Action:**
- Write: "How to Safely Install OpenClaw Skills"
- Write: "Protecting Your Agent from Malicious Skills"
- Submit to OpenClaw docs (security best practices)

**Expected reach:**
- Organic search traffic
- Referenced by OpenClaw team
- Developer mindshare

### Conversion Funnel

```
1. Developer hears about malicious skills (7.1% infection rate)
   ↓
2. Searches for "OpenClaw security" or "protect agent"
   ↓
3. Finds APort skill on ClawHub / Skills.sh / Awesome list
   ↓
4. Installs: npx @aporthq/aport-agent-guardrails
   ↓
5. Protected: Now can install other skills safely
   ↓
6. Upgrade path: Free → Pro ($$/mo for hosted passport, dashboards)
```

**Key metrics:**
- **Top of funnel:** Skill marketplace visibility
- **Middle:** Installation rate
- **Bottom:** Upgrade to Pro (hosted passport, compliance features)

**Expected conversion:**
- 10% of users who see APort skill will install
- 5% of installers will upgrade to Pro
- If 10,000 see it → 1,000 installs → 50 Pro users → $2,500 MRR (at $50/mo)

---

## Part 8: Granular vs. Global Authorization

### The User's Question

> "Wonder if having it global is ok but making it more granular would work too."

**Interpretation:** Should authorization be:
- **Global:** Agent-level (current model)
- **Granular:** Skill-level, tool-level, or context-level

### Analysis: What "Granular" Could Mean

#### Option 1: Per-Skill Policies

**Model:**
```yaml
# Passport
limits:
  git-skill:
    allowed_commands: ["git status", "git log"]
  shell-skill:
    allowed_commands: ["ls", "cat"]
```

**Enforcement:**
- Before tool call, check which skill invoked it
- Apply skill-specific limits

**Pros:**
- More precise control
- Skills can't exceed their grants

**Cons:**
- ❌ **Bypassable:** Malicious skill lies about its name
- ❌ **Complex:** Need skill → tool call tracing
- ❌ **Wrong boundary:** Skills are code, not security principals
- ❌ **Maintenance:** Update limits per-skill (scales poorly)

**Verdict: No. Skills should not be security principals.**

#### Option 2: Tool-Level Policies (Current Model)

**Model:**
```json
// Passport
{
  "limits": {
    "system.command.execute": {
      "allowed_commands": ["git", "npm", "ls"]
    },
    "messaging.message.send": {
      "allowed_channels": ["slack"]
    }
  }
}
```

**Enforcement:**
- Before `exec.run` → check `system.command.execute` limits
- Before `messaging.send` → check `messaging.message.send` limits

**Pros:**
- ✅ Correct security boundary (tools, not skills)
- ✅ Cannot be bypassed (platform enforces)
- ✅ Scales well (limits per capability)

**Verdict: Yes. This is current model. Keep it.**

#### Option 3: Context-Aware Policies

**Model:**
```json
// Policy pack evaluation rules
{
  "conditions": [
    {
      "field": "context.user_approved",
      "operator": "equals",
      "value": true
    },
    {
      "field": "context.command",
      "operator": "matches",
      "value": "^git (status|log)"
    }
  ]
}
```

**Enforcement:**
- Evaluator considers context (user approval, time of day, command content)
- Dynamic decisions based on runtime context

**Pros:**
- ✅ Flexible (handles complex cases)
- ✅ Enterprise use cases (approval flows, time-based, etc.)
- ✅ Already supported by OAP (evaluation rules)

**Verdict: Yes. This is "granular" done right.**

### What "Granular" Should Mean

**Granular = context-aware policies, NOT per-skill policies.**

**Good granularity:**
- ✅ Time-based: "Allow git push only 9-5 EST"
- ✅ Approval-required: "Block `rm -rf` unless user approves"
- ✅ Content-based: "Block commands with `/etc/passwd`"
- ✅ Threshold-based: "Allow 10 API calls/hour max"

**Bad granularity:**
- ❌ Per-skill: "git-skill can run these commands"
- ❌ Per-author: "Trust skills from @foo"
- ❌ Opt-in: "Skills without metadata are unprotected"

**Current APort model already supports good granularity** via policy pack evaluation rules.

---

## Part 9: Risk Analysis

### Risks of Skills Strategy

**Risk 1: Users expect per-skill opt-in**

**Scenario:** User installs APort, then installs skill, expects to "enable APort for this skill"

**Mitigation:**
- Clear messaging: "APort protects ALL tools automatically"
- Documentation: "No per-skill configuration needed"
- UX: Installation flow doesn't ask about per-skill settings

**Likelihood:** Medium (users used to per-app permissions on mobile)

**Impact:** Low (education fixes this)

**Risk 2: Skills marketplace rejects APort**

**Scenario:** ClawHub/Skills.sh reject submission (too meta, not a real skill, etc.)

**Mitigation:**
- Frame as "security infrastructure skill"
- Show precedent (antivirus-like tools)
- Highlight: 7.1% malicious skills = clear need

**Likelihood:** Low (security is obvious need post-Cisco disclosure)

**Impact:** Medium (lose distribution channel)

**Risk 3: Gen partnership becomes competitive**

**Scenario:** Gen (Skills.sh security partner) builds authorization layer

**Mitigation:**
- APort is enforcement, Gen is scanning (different layers)
- Partner: "Gen detects, APort blocks"
- Open-source advantage (Gen likely proprietary)

**Likelihood:** Medium (they might expand scope)

**Impact:** High (direct competition)

**Risk 4: Per-skill auth becomes user expectation**

**Scenario:** Users expect fine-grained per-skill control, APort's global model feels too coarse

**Mitigation:**
- Educate: "Global enforcement is security best practice"
- Provide granularity via context-aware policies (not per-skill)
- Show: "You can restrict commands via passport limits"

**Likelihood:** Low (enterprises understand global is correct)

**Impact:** Medium (UX confusion)

### Opportunities

**Opportunity 1: "Install first" becomes best practice**

**Scenario:** OpenClaw docs recommend "Install APort before installing skills"

**Action:**
- PR to OpenClaw docs (security best practices)
- Reach out to OpenClaw team
- Show: 7.1% malicious skills = need protection

**Value:** Massive (default recommendation = huge adoption)

**Opportunity 2: ClawHub featured/verified badge**

**Scenario:** ClawHub adds "security verified" or "featured" badge, APort gets it

**Action:**
- Apply for verification program
- Submit security audit results
- Highlight: VirusTotal scanning now exists (Feb 2026)

**Value:** High (credibility + visibility)

**Opportunity 3: Gen partnership**

**Scenario:** Gen refers users to APort for enforcement

**Action:**
- Reach out to Gen partnership team
- Propose: "Gen Trust Hub scans → recommend APort for enforcement"
- Co-marketing

**Value:** Very High (access to their user base)

---

## Part 10: Recommendations

### Priority 1: Publish to Skill Marketplaces (HIGH IMPACT)

**Action items:**

1. **ClawHub submission** (This week)
   - Submit `skills/aport-agent-guardrail/SKILL.md`
   - Category: Security / Infrastructure
   - Description: "Install before any skills to protect your agent"
   - Target: Top 10 security skills

2. **Skills.sh submission** (This week)
   - Package: `@aporthq/aport-agent-guardrails`
   - Update npm package description for Skills.sh
   - Target: Top 20 overall

3. **Awesome lists PRs** (This week)
   - VoltAgent/awesome-openclaw-skills
   - e2b-dev/awesome-ai-agents
   - Jenqyang/Awesome-AI-Agents

**Expected outcome:**
- 1,000+ installs in first month
- Top 10 security skill on ClawHub
- Visibility to 100K+ developers

### Priority 2: Position as "Install First" Skill (HIGH IMPACT)

**Messaging:**

**Tagline:** "Install APort before any skills to protect your agent."

**Narrative:**
> "283 malicious skills found on ClawHub (7.1% infection rate). Data exfiltration, unauthorized commands, and prompt injection are real threats. Install APort guardrails first, then install skills safely with pre-action authorization."

**CTA:**
```bash
# Step 1: Protect your agent
npx @aporthq/aport-agent-guardrails

# Step 2: Install skills safely
openclaw skills install <any-skill>
```

**Where to use:**
- Skill marketplace descriptions
- README.md (aport-agent-guardrails repo)
- Website (aport.io)
- Launch posts

### Priority 3: Do NOT Build Per-Skill Authorization (LOW PRIORITY)

**Don't do:**
- ❌ Per-skill metadata for authorization
- ❌ "Skills declare agent_id"
- ❌ Opt-in authorization model

**Reasoning:**
- Breaks security model (bypassable)
- Wrong trust boundary
- Doesn't stop malicious skills

**Keep:**
- ✅ Global enforcement (platform plugin)
- ✅ Tool-level policies (current model)
- ✅ Context-aware granularity (evaluation rules)

### Priority 4: Partner with Gen (MEDIUM IMPACT)

**Action:**
- Reach out to Gen partnership team
- Propose: "Gen scans, APort enforces"
- Co-marketing opportunity

**Email template:**
```
Subject: Partnership: Gen Trust Hub + APort Enforcement

Hi Gen team,

Congrats on the Skills.sh partnership (Feb 17)!

I'm building APort — pre-action authorization for AI agents. We're complementary:
- Gen: Threat scanning (detect malicious skills)
- APort: Enforcement (block unauthorized actions)

Idea: When Gen flags a threat, recommend APort for enforcement layer.

Would you be open to a call?

Best,
Uchi
aport.io | github.com/aporthq/aport-agent-guardrails
```

### Priority 5: OpenClaw Documentation PR (MEDIUM IMPACT)

**Action:**
- PR to OpenClaw docs
- Section: "Security Best Practices"
- Content: "Install APort before skills to protect your agent"

**Outcome:**
- Official endorsement
- Default recommendation
- Huge credibility boost

---

## Part 11: Comparison with Framework Support Plan

### From `/Users/uchi/Downloads/projects/aport-agent-guardrails/docs/launch/FRAMEWORK_SUPPORT_PLAN.md`

**Current priorities:**
1. ✅ OpenClaw (shipped)
2. 🎯 LangChain (next)
3. 🎯 Cursor (next)
4. 🎯 CrewAI (next)

**How skills fit in:**

**Skills are a DISTRIBUTION channel for ALL frameworks.**

```
User finds APort on ClawHub (OpenClaw)
  ↓
Installs: npx @aporthq/aport-agent-guardrails
  ↓
Installer asks: Which framework?
  ↓
User chooses: OpenClaw, LangChain, Cursor, etc.
  ↓
Framework-specific setup runs
```

**Skills → Framework dispatcher → Multi-framework support**

**This is brilliant because:**
- ✅ Skills.sh/ClawHub = discovery
- ✅ `npx @aporthq/aport-agent-guardrails` = unified installer
- ✅ Framework detection = works for any platform
- ✅ "Install first" = applies to all frameworks

**Skills accelerate ALL framework integrations, not just OpenClaw.**

### Updated Priorities

**Week 1-2 (Current):**
- ✅ Ship SHIELD integration
- 🆕 **Publish to ClawHub + Skills.sh**
- 🆕 **PR to awesome lists**

**Week 3-4:**
- Ship LangChain integration
- Get to 1,000 installs (Skills.sh helps)

**Week 5-8:**
- Ship CrewAI, Cursor integrations
- 10,000 installs (ClawHub + Skills.sh combined)

**Skills distribution helps hit ALL framework targets faster.**

---

## Part 12: Final Verdict

### Should APort Target Skills? YES.

**But not in the way you initially proposed.**

### What TO DO

✅ **1. Publish existing skill to marketplaces**
- ClawHub (OpenClaw)
- Skills.sh (Vercel)
- Awesome lists

✅ **2. Position as "install first" meta-skill**
- "Protect your agent before installing skills"
- Leverage 7.1% malicious skill statistic
- Security wedge

✅ **3. Keep global enforcement model**
- Platform-level hooks (before_tool_call)
- Cannot be bypassed
- Tool-level policies (current model)

✅ **4. Partner with Gen**
- Gen scans, APort enforces
- Complementary, not competitive
- Co-marketing

✅ **5. OpenClaw docs PR**
- Security best practices section
- Official recommendation

### What NOT TO DO

❌ **1. Per-skill authorization metadata**
- Breaks security model
- Bypassable
- Wrong trust boundary

❌ **2. Opt-in enforcement**
- Skills without metadata unprotected
- Doesn't stop malicious skills

❌ **3. Build skill-specific policies**
- Wrong granularity
- Use context-aware policies instead

### Expected Impact

**If executed well:**
- **Month 1:** 1,000-5,000 installs
- **Month 3:** 10,000+ installs
- **Month 6:** Top 10 security skill on ClawHub
- **Month 12:** 50,000+ installs, referenced in OpenClaw docs

**Skills are the DISTRIBUTION LAYER for APort.**

**Not the ARCHITECTURE LAYER.**

---

## Appendix A: Skills.sh Specifics

### How to Publish to Skills.sh

**Format:** npm package with specific structure

**Requirements:**
1. npm package published
2. README.md with usage
3. Install: `npx skills add <package>`

**Your package already meets requirements:**
- ✅ `@aporthq/aport-agent-guardrails` on npm
- ✅ README.md exists
- ✅ `npx @aporthq/aport-agent-guardrails` works

**Action:** Submit to Skills.sh registry (if submission process exists)

### Competition: Gen Partnership

**Gen + Vercel (Feb 17, 2026):**
- Agent Trust Hub
- Security verification
- Risk ratings for skills

**How APort is different:**
- **Gen:** Scans skills for threats (static analysis, behavioral)
- **APort:** Enforces pre-action authorization (runtime)
- **Gen:** "Is this skill malicious?"
- **APort:** "Can this agent run this command?"

**Complementary layers:**
1. Gen scans skill → flags threat
2. User installs skill anyway (trusts it)
3. Skill tries to run malicious command
4. APort blocks (pre-action authorization)

**Both needed. Not competitive.**

---

## Appendix B: Implementation Checklist

### This Week (Feb 17-24)

- [ ] **ClawHub submission**
  - File: `skills/aport-agent-guardrail/SKILL.md` (already exists)
  - Action: Submit via OpenClaw CLI or web form
  - Target: Security category

- [ ] **Skills.sh listing**
  - Package: `@aporthq/aport-agent-guardrails` (already published)
  - Action: Ensure listed on skills.sh
  - Update: npm description for Skills.sh SEO

- [ ] **Awesome lists PRs**
  - VoltAgent/awesome-openclaw-skills (Security & Passwords)
  - e2b-dev/awesome-ai-agents
  - Jenqyang/Awesome-AI-Agents

- [ ] **Update messaging**
  - README.md: Add "install first" language
  - Website: Add ClawHub link
  - Social: "7.1% malicious skills" tweet

### Next 2 Weeks (Feb 25 - Mar 10)

- [ ] **Gen partnership outreach**
  - Email Gen team
  - Propose co-marketing
  - "Gen scans, APort enforces"

- [ ] **OpenClaw docs PR**
  - Security best practices section
  - Link to APort skill
  - Position as recommended security layer

- [ ] **Monitor installs**
  - Track npm downloads
  - Track ClawHub installs (if metrics available)
  - Target: 1,000 installs

### Month 2-3 (Mar - Apr)

- [ ] **Case studies**
  - "How APort blocked malicious ClawHub skill"
  - Real examples from users
  - Publish to blog + HN

- [ ] **Feature in security roundups**
  - Reach out to security researchers
  - Snyk, Cisco authors
  - "Tools to protect against malicious skills"

---

## Conclusion

**Skills are a HUGE opportunity for APort distribution.**

**But the model is:**
- ✅ Skills = distribution channel (ClawHub, Skills.sh)
- ✅ APort skill = installer/enforcer (global)
- ❌ NOT per-skill authorization (breaks security)

**Action plan:**
1. Publish to ClawHub + Skills.sh (this week)
2. Position as "install first" (immediate)
3. Partner with Gen (reach out)
4. OpenClaw docs PR (this month)

**Expected outcome:**
- 10K+ installs in 3 months
- Top 10 security skill
- Referenced in security guides

**Skills are NOT the product. They're the DISTRIBUTION LAYER for the product.**

**Ship it.**

---

**Confidence: 8/10**

**The only reason it's not 10/10:** Gen partnership might become competitive (unknown). But even without Gen, ClawHub + Skills.sh distribution is worth it.

**Bottom line: Publish to skill marketplaces. Don't build per-skill auth.**

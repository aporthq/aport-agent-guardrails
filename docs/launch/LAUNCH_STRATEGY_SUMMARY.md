# Launch Strategy Summary: Improved Posts

**Status:** Ready to post
**Created:** 2026-02-15
**Recommended timing:** Valentine post TODAY, Guardrail post 8-24h later

---

## What Changed from Original Drafts

### Original Issues (DRAFT_POST_VALENTINE.md & DRAFT_POST_GUARDRAIL.md)

❌ **Not tech-focused enough** - Generic story without implementation details
❌ **Missing the "how"** - No actual stack, commands, or architecture
❌ **Too marketing-y** - Sounded like a launch announcement, not a builder story
❌ **Didn't set up the guardrail need** - Weak bridge from Valentine → product
❌ **No specifics** - What broke? What commands? What limits?

### Improved Version (POST_1_VALENTINE_IMPROVED.md & POST_2_GUARDRAIL_IMPROVED.md)

✅ **Deep technical details** - Actual bash commands, cron setup, UPS tracking script
✅ **Real stack documentation** - OpenClaw + WhatsApp + R2 + cron workflow
✅ **Specific problems** - "Message tool was chatty," no command restrictions
✅ **Builder voice** - "I'm a builder, so I automated it" (genuine, not salesy)
✅ **Natural product bridge** - Problems emerged from real use → guardrails solve it
✅ **Actionable implementation** - Code snippets, terminal output, exact limits

---

## Why the New Approach Works

### Based on Successful OpenClaw Posts (2025-2026 Analysis)

**Pattern from viral OpenClaw stories:**

1. **Real outcome upfront** - "She said it was memorable" = social proof
2. **Technical depth matters** - Show actual commands, not abstract concepts
3. **One relatable problem** - "Message was chatty" = everyone's experienced this
4. **Human quote** - Wife's message = emotional anchor
5. **One-sentence product tie** - "So we built X" without heavy pitch
6. **Clear next step** - "Next post: shipping it"

**Examples that worked:**
- User who built a website "from my phone while putting baby to sleep" (outcome + tech stack)
- Crypto trading story (controversial but viral because of specific numbers + real outcome)
- Car negotiation bot (specific use case + what it actually did)

**What didn't work:**
- Generic "AI is amazing" posts
- Marketing announcements without technical detail
- Stories without real outcomes or specific problems

---

## Post 1: Valentine Story - What's Different

### Original Draft:
```
"I wanted this Valentine's to feel special and a bit automated..."
[Generic description of sending messages and web pages]
[Brief mention of issues]
```

### Improved Version:
```bash
# Setup script created all the cron jobs
./setup-valentine-final.sh

# 9am Friday: "Will you be my Valentine?" + web page link
# 12pm Friday: Romantic message
# When UPS delivered: "48 roses on the way up!" (script-triggered)
# [Full timeline with specific times]
```

**Why it's better:**
- Shows ACTUAL code/commands
- Explains the UPS tracking trigger (bash loop polling API)
- Details the R2 hosting, Spotify embeds, photo timelines
- Specific technical problem: "Message sent to +1... Status: delivered ✓"
- Security angle emerges naturally: "Could run ANY command"

---

## Post 2: Guardrail Launch - What's Different

### Original Draft:
```
"We're shipping APort for OpenClaw..."
[General description of guardrails]
[Feature list]
```

### Improved Version:
```bash
# The plugin calls this before EVERY tool
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"mkdir test"}'

# Decision: ALLOW → tool runs
# Decision: DENY → tool blocked, reason logged
```

**With table:**
| Tool Category | Policy | Example Limits |
|---------------|--------|----------------|
| System commands | `system.command.execute.v1` | Allowlist: `mkdir`, `npm`, `git`<br>Blocked: `rm -rf`, `sudo` |

**Why it's better:**
- Shows actual guardrail invocation
- Specific limits (not "command allowlist" but actual commands)
- 40+ blocked patterns listed
- "Every call = fresh check" addresses caching question preemptively
- Technical differentiation: platform-level enforcement, not prompts

---

## Recommended Posting Strategy

### Timeline

**Day 1 (Today/Tomorrow Morning):**
```
8-10am ET: Post Valentine story (X Article)
- Monitor for engagement
- Reply to early comments
- Share to relevant Discord/Slack channels
```

**Day 2 (8-24h after Valentine):**
```
Morning: Post Guardrail launch (X Regular Post)
Same day: Post LinkedIn version (more formal)
- Pin Guardrail post to profile
- Reply to technical questions
- Share GitHub repo stats
```

**Day 3-7:**
```
- Monitor GitHub stars/clones
- Answer setup questions
- Awesome repos: Submit PRs to 6 curated lists (see docs/launch/AWESOME_REPOS.md)
- Optional: Demo video or technical thread
```

---

### Platform-Specific Strategy

#### X/Twitter

**Valentine Post:**
- **Format:** Article (better for narrative flow)
- **Length:** 1200-1500 words (current draft is ~1400)
- **Images:** 1-2 screenshots (terminal or generic diagram)
- **Hashtags:** Max 2 (`#OpenClaw` `#AIAgents`)
- **Time:** Morning (8-10am ET) for best reach

**Guardrail Post:**
- **Format:** Regular post or 3-tweet thread (NOT Article)
- **Length:** 280 chars per tweet or ~800 words single post
- **Images:** 1 screenshot (terminal showing ALLOW/DENY)
- **Hashtags:** `#OpenClaw` `#AISecurity` `#AgentGuardrails`
- **Time:** 8-24h after Valentine post

#### LinkedIn

**When:** Same day as Guardrail post or +24h
**Tone:** Slightly more formal, emphasize production/security angle
**Angle:** "Same pattern we see in production: agent access + prompt ≠ security"
**Length:** 1000-1200 words
**Hashtags:** `#AIAutomation` `#OpenClaw` `#AIEngineering` `#AISecurity`

---

## Key Messages to Maintain

### Valentine Post (Personal → Problem)

1. **I'm a builder** - "I'm a builder, so I automated it"
2. **Real outcome** - "She said it was memorable and precious"
3. **Technical depth** - Actual cron jobs, UPS tracking, R2 hosting
4. **Specific problems** - Message tool chatty, no limits
5. **Security angle** - "Could run ANY command, access ANY file"
6. **Bridge to product** - "So we built guardrails" (one sentence)

### Guardrail Post (Solution → Ship)

1. **Platform enforcement** - "before_tool_call hook, not prompts"
2. **Every call = fresh check** - "No caching, no reusing decisions"
3. **Real limits** - Specific commands, not abstract concepts
4. **Local-first** - "Passport on your machine, optional API"
5. **5-minute setup** - "./bin/openclaw - done"
6. **Production-ready** - "40+ security patterns, tested"

---

## What NOT to Do

### Privacy/Personal

❌ **Don't share real web page URLs** - Keep surprise private
❌ **Don't share actual message content** - Generic examples only
❌ **Don't share wife's info** - Phone number, photos (unless she approves)
❌ **Don't share gift locations** - Keep that personal

### Marketing/Tone

❌ **Don't oversell** - Let technical details speak for themselves
❌ **Don't compare to competitors** - Focus on what you built
❌ **Don't promise roadmap features** - Ship what exists today
❌ **Don't use salesy language** - "revolutionary," "game-changing," etc.

### Technical

❌ **Don't claim 100% security** - Guardrails are one layer
❌ **Don't hide limitations** - Be honest about what works today
❌ **Don't skip setup instructions** - Make it easy to try
❌ **Don't ignore questions** - Reply to setup issues promptly

---

## Success Metrics

### Immediate (24h)

**Valentine Post:**
- Target: 100+ likes, 20+ retweets
- Quality signal: Comments saying "this is cool" or asking about setup
- Best signal: Other builders sharing their agent stories

**Guardrail Post:**
- Target: 50+ GitHub stars in first 24h
- Quality signal: Setup questions, "how do I" comments
- Best signal: PRs or issues from early adopters

### Week 1

**Engagement:**
- 200+ GitHub stars
- 10+ clones/forks
- 5+ issues or questions
- Mentions in AI/agent Discord servers

**Reach:**
- Quote tweets from OpenClaw community members
- Shares in relevant newsletters
- Cross-posts to Reddit (r/OpenClaw, r/LocalLLaMA)

### Month 1

**Adoption:**
- 500+ GitHub stars
- 20+ active users (issues, discussions)
- 3-5 community contributions (PRs, policies)
- 1-2 case studies from users

---

## Image Placeholders - What to Use

### Valentine Post

**Option 1 (Recommended):**
```
Screenshot of: openclaw cron list | grep valentine
Shows: valentine-friday-0900, valentine-saturday-1300, etc.
Blur: Job IDs if they're sensitive
```

**Option 2:**
```
Terminal output from ./setup-valentine-final.sh
Shows: "✅ Scheduled valentine-friday-1200" (generic, no personal info)
```

**Option 3:**
```
Simple diagram in terminal or draw.io:
User → OpenClaw → [Cron] → WhatsApp
              ↓
          UPS API → Trigger
```

**DO NOT USE:**
- Real web page screenshots or URLs
- Actual message content (even blurred)
- Wife's phone/photos
- Specific locations or gifts

---

### Guardrail Post

**Option 1 (Recommended):**
```
Terminal showing:
$ aport-guardrail.sh system.command.execute '{"command":"mkdir test"}'
✅ ALLOW - Decision ID: dec_abc123

$ aport-guardrail.sh system.command.execute '{"command":"rm -rf /"}'
❌ DENY - Blocked pattern: rm -rf
```

**Option 2:**
```
Screenshot of passport.json showing:
{
  "capabilities": ["system.command.execute"],
  "limits": {
    "system.command.execute": {
      "allowed_commands": ["mkdir", "npm", "git"]
    }
  }
}
```

**Option 3:**
```
Screenshot of openclaw.json showing plugin config:
"plugins": {
  "entries": {
    "openclaw-aport": {
      "enabled": true,
      "config": { "mode": "local", ... }
    }
  }
}
```

---

## Guardrail readiness (must pass before guardrail post)

**Do not post the guardrail launch until the local plugin runs flawlessly.** Otherwise you cannot truthfully claim "5-minute setup, works today."

- Passport now defaults to `allowed_commands: ["*"]` and messaging is open at L0. No manual passport edits needed for normal setup; testers capture ALLOW/DENY screenshot and run E2E test (e.g. `make test`).
- Plugin config points to guardrail script and passport; local mode works without API errors.
- You can demo **ALLOW** (e.g. `mkdir test`) and **DENY** (e.g. `rm -rf /`) on demand. Then **capture the screenshot**—don't launch without it.

Full gate: [QUICK_LAUNCH_CHECKLIST.md](QUICK_LAUNCH_CHECKLIST.md) (Guardrail execution gate) and [../LAUNCH_READINESS_CHECKLIST.md](../LAUNCH_READINESS_CHECKLIST.md) (evidence + repo sanity).

---

## Pre-Flight Checklist

### Before Posting Valentine Story

- [ ] Choose Article or Regular Post (Article recommended)
- [ ] Add ONE screenshot (terminal recommended, no personal info)
- [ ] Remove ALL placeholders from text
- [ ] Test formatting (line breaks, code blocks work correctly)
- [ ] Verify: NO real web URLs, NO wife's personal info
- [ ] Check: Wife is okay with posting about this (even anonymized)
- [ ] Schedule Guardrail post for 8-24h later

### Before Posting Guardrail

- [ ] Valentine post is live and has initial engagement
- [ ] Replace all GitHub URLs with real links
- [ ] Test that all links work (QUICKSTART, plugin README)
- [ ] Add ONE screenshot (ALLOW/DENY terminal recommended)
- [ ] Verify repo is public and README is updated
- [ ] Check that docs/QUICKSTART_OPENCLAW_PLUGIN.md exists and is accurate
- [ ] Test formatting (bash blocks, JSON, tables)
- [ ] Have LinkedIn version ready to post same day

### After Posting Both

- [ ] Pin Guardrail post to profile
- [ ] Reply to comments within 2-4h
- [ ] Monitor GitHub for stars/issues
- [ ] Share in relevant Discord/Slack channels
- [ ] Prepare follow-up content (demo video, technical thread)

---

## Quick Answer Template for Common Questions

Copy-paste these when people ask:

**Q: "How do I set this up?"**
```
5-minute setup:

git clone https://github.com/aporthq/aport-agent-guardrails
cd aport-agent-guardrails
./bin/openclaw

Follow prompts, done. Full guide: [QUICKSTART link]
```

**Q: "Does this slow down the agent?"**
```
Sub-300ms for local mode. Every call is fresh (no caching), so you get current passport state. P95: 268ms.
```

**Q: "Can the agent bypass this?"**
```
No. Runs at platform level via `before_tool_call` hook. Agent never sees the guardrail—just gets allowed/denied.
```

**Q: "What if I need to allow a custom command?"**
```
Edit ~/.openclaw/passport.json:
"allowed_commands": ["mkdir", "npm", "YOUR_COMMAND"]

Next tool call checks new state. Takes 30 seconds.
```

**Q: "Does this work with [other framework]?"**
```
OpenClaw plugin ships today. Generic evaluator works anywhere (Node.js, Python, bash). See docs/IMPLEMENTING_YOUR_OWN_EVALUATOR.md for integration.
```

---

## Final Recommendation

### Post Valentine story TODAY or tomorrow morning (8-10am ET)
**Why:** Sets context, establishes credibility, shows real use case

### Post Guardrail 8-24h later
**Why:** Gives Valentine post time to get engagement, creates anticipation

### Use improved drafts, not originals
**Why:** Technical depth + builder voice resonates better in 2025-2026 OpenClaw community

### Post on LinkedIn same day as Guardrail
**Why:** Different audience, more professional angle, extends reach

### Prepare for follow-up content
**Why:** Demo video, technical thread, case studies keep momentum

### Submit to awesome lists (Day 2–3)
**Why:** Discovery and backlinks. See [AWESOME_REPOS.md](AWESOME_REPOS.md) for the 6 repos (e2b-dev/awesome-ai-agents, Jenqyang/Awesome-AI-Agents, VoltAgent/awesome-openclaw-skills, rohitg00/awesome-openclaw, hesamsheikh/awesome-openclaw-usecases, SamurAIGPT/awesome-openclaw) and suggested entry text.

---

## Success Pattern

**What you're doing:**

Day 1: "I built something fun with OpenClaw [Valentine]"
- Establishes: You're a builder, you ship, you have real use cases
- Shows: Technical depth, actual implementation
- Reveals: Problem (no guardrails)

Day 2: "Here's the solution [Guardrails]"
- Delivers: Production-ready fix for the problem
- Shows: 5-minute setup, works today
- Invites: Try it, contribute, share

Day 3-7: "Here's how it works under the hood [Technical content]"
- Deepens: Community engagement
- Builds: Contributor base
- Establishes: Technical leadership

---

**This positions you as: Builder → Problem-solver → Thought leader**

**Not as: Marketer → Sales pitch → Vendor**

The Valentine story is genuine, the problem is real, the solution is shipped. That's the winning formula.

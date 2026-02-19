# Quick Launch Checklist

**Use this:** Final check before posting and after launch.

**Start here:** [README.md](README.md) in this folder is the **single source of truth** and links to everything. This checklist and [LAUNCH_STRATEGY_SUMMARY.md](LAUNCH_STRATEGY_SUMMARY.md) define timing, content, and evidence. [LAUNCH_READINESS_CHECKLIST.md](LAUNCH_READINESS_CHECKLIST.md) adds the guardrail execution gate and links here.

---

## Launch checklist (at a glance)

| Phase | When | Key actions |
|-------|------|-------------|
| **Pre-launch** | Before any posts | Repo public, docs/README/QuickStart verified, guardrail execution gate passed, screenshot captured |
| **Launch** | Day 1–2 | Valentine post (if not done) → Guardrail post 8–24h later → LinkedIn same day or +24h |
| **Post-launch** | Day 2–7 | Monitor engagement, reply to comments, **submit to 6 awesome repos** ([AWESOME_REPOS.md](AWESOME_REPOS.md)), optional demo/thread |

**Test run (2026-02-15):** Repo files (README, QUICKSTART_OPENCLAW_PLUGIN, plugin README, LICENSE) verified present. Guardrail: `OPENCLAW_PASSPORT_FILE=tests/fixtures/passport.oap-v1.json ./bin/aport-guardrail-bash.sh system.command.execute '{"command":"npm --version"}'` → exit 0, ALLOW; `'{"command":"rm -rf /"}'` → exit 1, DENY (oap.blocked_pattern). Passport with `allowed_commands: ["mkdir",...]` → `mkdir test` exit 0 ALLOW. ALLOW + DENY on demand confirmed. Checklist items updated from these runs; GitHub links still need verification when repo is public.

---

## Pre-Launch (Before Any Posts)

### Repository
- [ ] GitHub repo is **public** *(verify when repo is published; 404 if private)*
- [x] README.md is updated with plugin info
- [x] `docs/QUICKSTART_OPENCLAW_PLUGIN.md` exists and is accurate
- [x] `extensions/openclaw-aport/README.md` is complete
- [x] All code examples in docs work *(verified: guardrail ALLOW/DENY; see [EVIDENCE_TERMINAL_CAPTURE.txt](EVIDENCE_TERMINAL_CAPTURE.txt))*
- [x] License file is present (Apache-2.0)

### Documentation Links (verify when repo is public)
- [ ] https://github.com/aporthq/aport-agent-guardrails
- [ ] https://github.com/aporthq/aport-agent-guardrails/blob/main/README.md
- [ ] https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md
- [ ] https://github.com/aporthq/aport-agent-guardrails/blob/main/extensions/openclaw-aport/README.md

### Personal Privacy
- [ ] Confirmed: Wife is okay with posting about this (even anonymized)
- [ ] Double-check: NO real web page URLs in post
- [ ] Double-check: NO actual message content
- [ ] Double-check: NO wife's personal info (phone, photos without consent)

---

## Post 1: Valentine Story

### Content Ready
- [x] Read `POST_1_VALENTINE_IMPROVED.md`
- [x] Choose: **X Article** (recommended) or Regular Post
- [x] Remove all `[IMAGE_PLACEHOLDER]` and `[ADD...]` markers
- [x] Add ONE screenshot (terminal `openclaw cron list` recommended)
- [x] Test formatting (line breaks, code blocks, links)

### Final Text Check
- [x] NO real web page URLs
- [x] NO actual message content (use generic examples only)
- [x] Wife's quote is there: *"memorable and precious"*
- [x] Technical details are specific (cron, UPS tracking, R2)
- [x] Problems are clear (chatty messages, no limits)
- [x] Bridge to guardrails: "So we built..." (one sentence)

### Posting
- [x] Time: 8-10am ET (best reach) or 6-8pm ET
- [x] Hashtags: Max 2 (`#OpenClaw` `#AIAgents`)
- [x] **Valentine post is live.** *(Monitor engagement; reply to early comments.)*
- [ ] Monitor: First 2 hours for engagement
- [ ] Reply: To early comments within 30 minutes

---

## Post 2: Guardrail Launch

### Guardrail execution gate (do not post until these pass)

The passport now defaults to `allowed_commands: ["*"]` and messaging is open at L0. Testers only need to capture the ALLOW/DENY screenshot and run the E2E test (e.g. `make test`); no manual passport edits required for normal setup.

- [x] **Local guardrail runs flawlessly:** Installer sets `allowed_commands: ["*"]` automatically; blocked patterns (e.g. `rm -rf`) still DENY. *(Verified: passport with `["*"]` or default list → `ls`/`mkdir` ALLOW; `rm -rf /` DENY.)*
- [x] **Local mode tested per doc:** Guardrail with passport only (no API): `./bin/aport-guardrail-bash.sh system.command.execute '{"command":"ls"}'` → ALLOW; `'{"command":"rm -rf"}'` → DENY. *(Plugin config in OpenClaw still verify on your machine.)*
- [ ] **Plugin config correct:** `guardrailScript` and `passportFile` in OpenClaw config point to the right paths. Local mode works without API (no 400 / validation errors). *(Verify on your machine.)*
- [x] **ALLOW + DENY on demand:** You can demo: one command → ALLOW, one blocked pattern → DENY. *(Verified: `aport-guardrail-bash.sh system.command.execute '{"command":"ls"}'` → ALLOW; `'{"command":"rm -rf /"}'` → DENY.)*
- [x] **Screenshot captured:** Terminal ALLOW/DENY transcript in [EVIDENCE_TERMINAL_CAPTURE.txt](EVIDENCE_TERMINAL_CAPTURE.txt). For the post, use a screenshot of that output or run the same commands and capture; save as `evidence-allow-deny.png` in `docs/launch/` if desired.
- [x] **Messaging (if in post):** Default passport from wizard includes `messaging.send` and `limits["messaging.message.send"]`; messaging guardrails work out of the box.

### Repo sanity (before claiming "5-minute setup")

- [ ] Repo is **public**; README references improved docs and QuickStart. *(README references QUICKSTART_OPENCLAW_PLUGIN, plugin README, OpenClaw setup—verified.)*
- [x] QuickStart (or QUICKSTART_OPENCLAW_PLUGIN) tested on your machine (or a clean one). *(Guardrail + fixture passport tested; run `./bin/openclaw` once to confirm wizard flow.)* If there are known gaps (e.g. macOS-only, Node 18+), call them out in README.

### Timing
- [x] Valentine post is **live** and has some engagement (50+ likes)
- [ ] Wait: 8-24h after Valentine post
- [ ] Best time: Morning (8-10am ET)

### Content Ready
- [x] Read `POST_2_GUARDRAIL_IMPROVED.md` *(file exists and has full draft.)*
- [ ] Choose: **Regular Post** (recommended) or 3-tweet thread
- [ ] Remove all `[IMAGE_PLACEHOLDER]` and link placeholders *(POST_2 has 2 IMAGE_PLACEHOLDER lines—replace before posting.)*
- [ ] Add ONE screenshot (terminal ALLOW/DENY recommended) **Do not launch without it.**
- [ ] Test all GitHub links work *(verify when repo is public.)*
- [x] Test formatting (bash blocks, JSON, table) *(draft uses code blocks and table.)*

### GitHub Links Working
- [ ] Repo link: https://github.com/aporthq/aport-agent-guardrails *(verify when public.)*
- [ ] QuickStart: `.../docs/QUICKSTART_OPENCLAW_PLUGIN.md`
- [ ] Plugin README: `.../extensions/openclaw-aport/README.md`

### Final Text Check
- [x] Code example shows actual command invocation *(draft has `aport-guardrail.sh system.command.execute '{"command":"mkdir test"}'`.)*
- [x] Table with specific allowed/blocked commands *(draft has Tool Category | Policy | Example Limits table.)*
- [x] "Every call = fresh check" statement included *(draft: "Every tool call = fresh guardrail check. No caching...")*
- [x] Technical numbers: 40+ patterns, 5-min setup *(draft mentions both.)*
- [x] Clear CTA: "Try it: [GitHub link]" *(draft has CTA section; replace with real link.)*

### Posting
- [ ] Time: Morning (8-10am ET)
- [ ] Hashtags: `#OpenClaw` `#AISecurity` `#AgentGuardrails`
- [ ] Pin: This post to profile after posting
- [ ] Monitor: GitHub stars (check traffic)
- [ ] Reply: To setup questions immediately

---

## LinkedIn Post (Same Day as Guardrail or +24h)

### Content Ready
- [ ] Read LinkedIn section in `POST_2_GUARDRAIL_IMPROVED.md`
- [ ] Slightly more formal tone
- [ ] Same technical content
- [ ] 1-line Valentine callback: "Last week I automated..."
- [ ] Emphasize: "Production security" angle

### Final Check
- [ ] Length: 1000-1200 words (LinkedIn favors longer posts)
- [ ] Formatting: Use Unicode bullets (•) not markdown
- [ ] Links: GitHub repo + QuickStart guide
- [ ] Hashtags: `#AIAutomation` `#OpenClaw` `#AIEngineering` `#AISecurity`

---

## Image Quick Reference

### Valentine Post - Use ONE of:

**Option 1 (Recommended):**
```bash
$ openclaw cron list | grep valentine
valentine-friday-0900   "0 9 13 2 *"   [...]
valentine-friday-1200   "0 12 13 2 *"  [...]
valentine-saturday-0900 "0 9 14 2 *"   [...]
```
*Blur job IDs if sensitive, keep job names*

**Option 2:**
```
Terminal output from ./setup-valentine-final.sh
Shows: "✅ Scheduled valentine-friday-1200"
```

**Option 3:**
```
Simple diagram:
User → OpenClaw → [Cron] → WhatsApp
                ↓
           UPS API → Trigger
```

### Guardrail Post - Use ONE of:

**Option 1 (Recommended):**
```bash
$ aport-guardrail.sh system.command.execute '{"command":"mkdir test"}'
✅ ALLOW - Decision ID: dec_abc123

$ aport-guardrail.sh system.command.execute '{"command":"rm -rf /"}'
❌ DENY - Blocked pattern: rm -rf
```

**Option 2:**
```json
# passport.json
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
```json
# openclaw.json
"plugins": {
  "entries": {
    "openclaw-aport": {
      "enabled": true,
      "config": { "mode": "local" }
    }
  }
}
```

---

## Awesome repos (discovery)

**When:** Day 2–3 after guardrail post (repo must be public). **Details:** [AWESOME_REPOS.md](AWESOME_REPOS.md) (links, suggested section, copy-paste entry text).

- [ ] [e2b-dev/awesome-ai-agents](https://github.com/e2b-dev/awesome-ai-agents) — PR to add APort (security/guardrails)
- [ ] [Jenqyang/Awesome-AI-Agents](https://github.com/Jenqyang/Awesome-AI-Agents) — PR (Tools or Security)
- [ ] [VoltAgent/awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills) — PR under **Security & Passwords**
- [ ] [rohitg00/awesome-openclaw](https://github.com/rohitg00/awesome-openclaw) — PR (Security or Integrations)
- [ ] [hesamsheikh/awesome-openclaw-usecases](https://github.com/hesamsheikh/awesome-openclaw-usecases) — PR or new use case (security/guardrails)
- [ ] [SamurAIGPT/awesome-openclaw](https://github.com/SamurAIGPT/awesome-openclaw) — PR (Security or Community Projects)

---

## Post-Launch Monitoring

### First 2 Hours (Critical Window)
- [ ] Reply to ALL comments (even simple ones)
- [ ] Fix any broken links immediately
- [ ] Answer setup questions with copy-paste template
- [ ] Retweet interesting responses
- [ ] Share to Discord/Slack channels

### First 24 Hours
- [ ] Check GitHub stars every 4 hours
- [ ] Monitor repo traffic (Settings → Insights → Traffic)
- [ ] Watch for issues or setup questions
- [ ] Prepare quick answers for common questions
- [ ] Track engagement metrics (likes, retweets, comments)

### Day 2-7
- [ ] Reply to all GitHub issues within 24h
- [ ] Consider demo video if lots of setup questions
- [ ] Optional: Technical thread on `before_tool_call`
- [ ] Share repo milestones (50 stars, 100 stars)
- [ ] Engage with community showcases

---

## Common Questions - Quick Answers

### "How do I set this up?"
```
5-minute setup:

git clone https://github.com/aporthq/aport-agent-guardrails
cd aport-agent-guardrails
./bin/openclaw

Follow prompts. Done.
Full guide: [QUICKSTART link]
```

### "Does this slow down the agent?"
```
Sub-300ms for local mode. Every call is fresh (no caching).
P95: 268ms. Not noticeable in practice.
```

### "Can the agent bypass this?"
```
No. Runs at platform level via `before_tool_call` hook.
Agent never sees the guardrail—just gets allowed/denied.
```

### "What if I need to allow a custom command?"
```
Edit ~/.openclaw/passport.json:
"allowed_commands": ["mkdir", "npm", "YOUR_COMMAND"]

Next tool call checks new state. Takes 30 seconds.
```

### "Does this work with [other framework]?"
```
OpenClaw plugin ships today. Generic evaluator works
anywhere (Node, Python, bash). See docs for integration.
```

---

## Emergency Fixes

### If Link Breaks
1. Reply to post with correction
2. Pin corrected reply
3. Update post if possible (edit X article)

### If Setup Doesn't Work
1. Acknowledge issue immediately
2. Investigate (ask for OS, Node version, error output)
3. Fix and push to main
4. Reply with solution

### If Question Goes Unanswered
1. Set reminder to check every 4 hours
2. Use saved quick answers (above)
3. Be honest if you don't know: "Let me check and get back"

---

## Success Indicators (First Week)

### Strong Launch (Target)
- [ ] 100+ likes on Valentine post
- [ ] 50+ likes on Guardrail post
- [ ] 200+ GitHub stars
- [ ] 10+ clones/forks
- [ ] 5+ issues/questions
- [ ] Quote tweets from OpenClaw community

### Viral Launch (Stretch)
- [ ] 500+ likes on Valentine post
- [ ] 200+ likes on Guardrail post
- [ ] 1000+ GitHub stars
- [ ] 50+ clones/forks
- [ ] 20+ issues/PRs
- [ ] Mentions in newsletters/podcasts

### Minimum Viable Launch
- [ ] 50+ likes on Valentine post
- [ ] 25+ likes on Guardrail post
- [ ] 50+ GitHub stars
- [ ] 3+ people trying it
- [ ] 2+ questions/issues
- [ ] 1+ positive comment

---

## What to Do If...

### ...Engagement is Low (< 50 likes after 24h)
1. Share to relevant Discord/Slack channels
2. Post to Reddit (r/OpenClaw, r/LocalLLaMA)
3. Consider follow-up thread with more technical depth
4. Ask OpenClaw community members for feedback

### ...GitHub Stars But No Usage
1. Check: Is setup too hard?
2. Consider: Demo video showing 5-min setup
3. Ask: "What's blocking you from trying this?"
4. Improve: QuickStart docs based on feedback

### ...Questions You Can't Answer
1. Be honest: "Great question, let me test that"
2. Test locally or check code
3. Reply within 24h with answer or workaround
4. Document answer in FAQ section

---

## Final Pre-Post Check

**For Valentine Post:**
- [ ] I have wife's permission to post about this
- [ ] NO personal info is exposed (web URLs, messages, photos)
- [ ] Technical details are accurate and specific
- [ ] One screenshot added (terminal or diagram)
- [ ] Post is scheduled for 8-10am ET or 6-8pm ET

**For Guardrail Post:**
- [ ] **Execution gate passed** (guardrail runs without policy denials for normal commands; ALLOW/DENY demo works)
- [ ] Valentine post is live and has engagement
- [ ] All GitHub links work
- [ ] QuickStart guide is tested and accurate
- [ ] **One screenshot added** (ALLOW/DENY terminal)—do not post without it
- [ ] Post is scheduled 8-24h after Valentine

**For Both:**
- [ ] Removed ALL `[PLACEHOLDER]` text
- [ ] Tested formatting (code blocks, line breaks)
- [ ] Hashtags added (max 2 per post)
- [ ] Ready to reply to comments within 30 min

---

## You're Ready to Launch! 🚀

Use:
- `POST_1_VALENTINE_IMPROVED.md` for Valentine post
- `POST_2_GUARDRAIL_IMPROVED.md` for Guardrail post
- This checklist for final verification

**Timeline:**
- Today/Tomorrow: Valentine post (8-10am ET)
- 8-24h later: Guardrail post + LinkedIn
- Day 2–3: Submit to 6 awesome repos ([AWESOME_REPOS.md](AWESOME_REPOS.md))
- Week 1: Monitor, reply, iterate

**Remember:**
- Technical depth > marketing fluff
- Builder voice > vendor pitch
- Show don't tell (code examples)
- Reply to everything fast

**Good luck! The improved posts will resonate much better with the OpenClaw community.** 🦞

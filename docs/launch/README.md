# OpenClaw + APort Launch: Source of Truth

**Start here.** This folder is the single source of truth for the OpenClaw guardrails launch. Everything you need to run the launch lives in this repo; links to website/strategy docs in the agent-passport repo are below.

---

## Day-of: Do this first

| Order | Doc | Use when |
|-------|-----|----------|
| 1 | **[QUICK_LAUNCH_CHECKLIST.md](QUICK_LAUNCH_CHECKLIST.md)** | Final check before posting; what to do Pre-launch → Launch → Post-launch |
| 2 | **[LAUNCH_READINESS_CHECKLIST.md](LAUNCH_READINESS_CHECKLIST.md)** | Execution gates (guardrail must run, screenshot, etc.); do not post until these pass |

---

## Content to post

| Doc | What it is |
|-----|------------|
| **[POST_1_VALENTINE_IMPROVED.md](POST_1_VALENTINE_IMPROVED.md)** | Valentine story (set the stage) — post first |
| **[POST_2_GUARDRAIL_IMPROVED.md](POST_2_GUARDRAIL_IMPROVED.md)** | Guardrail launch post — post 8–24h after Post 1 |
| **[ANNOUNCEMENT_GUIDE.md](ANNOUNCEMENT_GUIDE.md)** | Key messages, tweet draft, blog outline, demo script, FAQ |
| **[LAUNCH_STRATEGY_SUMMARY.md](LAUNCH_STRATEGY_SUMMARY.md)** | Why this approach; what changed from original drafts |

---

## Other launch docs (this repo)

| Doc | What it is |
|-----|------------|
| [READINESS_SUMMARY.md](READINESS_SUMMARY.md) | Repo readiness score, what works, gaps |
| [AWESOME_REPOS.md](AWESOME_REPOS.md) | Where to submit post-launch (awesome lists) |
| [ADD_APORT_AWESOME_LISTS_INSTRUCTIONS.md](ADD_APORT_AWESOME_LISTS_INSTRUCTIONS.md) | Step-by-step: add APort to 6 awesome lists; exact section + line per repo |
| **add-aport-awesome-pr.sh** | Script: clone to `/tmp/aport-awesome-prs`, branch, then `pr` to commit/push/gh pr create |
| [EVIDENCE_README.md](EVIDENCE_README.md) | Evidence / screenshot capture |
| [PRE_LAUNCH_FIXES.md](PRE_LAUNCH_FIXES.md) | Fixes applied before launch |
| [OPENCLAW_FEEDBACK_AND_FIXES.md](OPENCLAW_FEEDBACK_AND_FIXES.md) | OpenClaw community feedback and responses |

---

## Website, roadmap & strategy (agent-passport repo)

These live in the **agent-passport** repo (website, product, business strategy). They are not run from this repo but support the launch.

**Folder:** [agent-passport `_plan/execution/openclaw`](https://github.com/aporthq/agent-passport/tree/main/_plan/execution/openclaw)

| Doc | What it is |
|-----|------------|
| **WEBSITE_IMPROVEMENTS_FOR_OPENCLAW_LAUNCH.md** | Homepage, quickstart, nav, problem section, GitHub response templates; acceptance criteria for site changes |
| **APORT_OPENCLAW_INTEGRATION_PROPOSAL.md** | Integration design (AGENTS.md, passport, plugin, local vs cloud); comparison with TrustClaw |
| **APORT_OPENCLAW_ANALYSIS_AND_ROADMAP.md** | Gap analysis, 100/100 roadmap, security/UX/monetization |
| **LAUNCH_TODAY_STRATEGY.md** | Launch-day strategy and tactics |
| **EXECUTIVE_SUMMARY.md** | Executive summary of the OpenClaw launch |
| **BUSINESS_MODEL_AND_MONETIZATION.md** | Business model, pricing, open-core |
| **FINAL_FIXES_BEFORE_LAUNCH.md** | Final fixes log |
| **HOSTED_PASSPORT_CLI_FIX.md** | Hosted passport + CLI (npx) fixes |

**User-facing setup (reflect everywhere):** One command `npx @aporthq/aport-agent-guardrails` (no clone); optional hosted passport: `npx @aporthq/aport-agent-guardrails <agent_id>`. Quickstart page: [aport.io/openclaw](https://aport.io/openclaw).

---

## Quick reference

- **Post order:** Valentine (Post 1) → Guardrail (Post 2) 8–24h later → LinkedIn same day or +24h.
- **Setup copy:** `npx @aporthq/aport-agent-guardrails`; optional `npx @aporthq/aport-agent-guardrails <agent_id>`.
- **Website quickstart:** https://aport.io/openclaw  
- **Repo:** https://github.com/aporthq/aport-agent-guardrails  
- **Agent-passport openclaw plan:** https://github.com/aporthq/agent-passport/tree/main/_plan/execution/openclaw  

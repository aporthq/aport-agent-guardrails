# APort Agent Guardrails — Documentation

**Public documentation** (for users integrating OpenClaw + APort guardrails):

| Doc | Purpose |
|-----|---------|
| [QUICKSTART_OPENCLAW_PLUGIN.md](QUICKSTART_OPENCLAW_PLUGIN.md) | **OpenClaw plugin** — 5-minute setup, deterministic enforcement (RECOMMENDED) |
| [**HOSTED_PASSPORT_SETUP.md**](HOSTED_PASSPORT_SETUP.md) | **Use passport from aport.io** — create at aport.io, then `npx @aporthq/aport-agent-guardrails <agent_id>` (or choose hosted in wizard) |
| [QUICKSTART.md](QUICKSTART.md) | Interactive setup and step-by-step with passport wizard |
| [OPENCLAW_LOCAL_INTEGRATION.md](OPENCLAW_LOCAL_INTEGRATION.md) | Full OpenClaw setup: API, passport, policies, Python example |
| [OPENCLAW_TOOLS_AND_POLICIES.md](OPENCLAW_TOOLS_AND_POLICIES.md) | exec, allowed_commands, unmapped tools, passport limits |
| [TOOL_POLICY_MAPPING.md](TOOL_POLICY_MAPPING.md) | How tool names map to policy packs |
| [IMPLEMENTING_YOUR_OWN_EVALUATOR.md](IMPLEMENTING_YOUR_OWN_EVALUATOR.md) | Build your own evaluator from the OAP spec |
| [OPENCLAW_COMPATIBILITY.md](OPENCLAW_COMPATIBILITY.md) | OpenClaw version alignment, paths, OPENCLAW_HOME |
| [AGENTS.md.example](AGENTS.md.example) | Example AGENTS.md section for pre-action authorization |
| [REPO_LAYOUT.md](REPO_LAYOUT.md) | What `bin/`, `src/`, `extensions/`, `external/` do |

**Launch & checklists** (internal / maintainers):

| Doc | Purpose |
|-----|---------|
| [LAUNCH_READINESS_CHECKLIST.md](LAUNCH_READINESS_CHECKLIST.md) | Launch checklist + guardrail execution gate |
| [launch/LAUNCH_STRATEGY_SUMMARY.md](launch/LAUNCH_STRATEGY_SUMMARY.md) | Timing, content, evidence, pre-flight |
| [launch/QUICK_LAUNCH_CHECKLIST.md](launch/QUICK_LAUNCH_CHECKLIST.md) | Final verification before each post |
| [launch/OPENCLAW_FEEDBACK_AND_FIXES.md](launch/OPENCLAW_FEEDBACK_AND_FIXES.md) | OpenClaw feedback summary + two fixes (allowlist, capabilities) |
| [launch/POST_1_VALENTINE_IMPROVED.md](launch/POST_1_VALENTINE_IMPROVED.md) | Post 1 draft (Valentine) |
| [launch/POST_2_GUARDRAIL_IMPROVED.md](launch/POST_2_GUARDRAIL_IMPROVED.md) | Post 2 draft (Guardrail) |
| [ANNOUNCEMENT_GUIDE.md](ANNOUNCEMENT_GUIDE.md) | Announcement messaging and materials |

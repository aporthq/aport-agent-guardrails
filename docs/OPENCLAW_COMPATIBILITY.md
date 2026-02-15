# OpenClaw Compatibility

**Last reviewed:** February 2026 (OpenClaw CHANGELOG 2026.2.15 / 2026.2.14, [docs.openclaw.ai](https://docs.openclaw.ai), [architecture](https://docs.openclaw.ai/concepts/architecture))

---

## 1. Latest OpenClaw release (CHANGELOG)

- **Releases:** [github.com/openclaw/openclaw/blob/main/CHANGELOG.md](https://github.com/openclaw/openclaw/blob/main/CHANGELOG.md)
- **Docs:** [docs.openclaw.ai](https://docs.openclaw.ai)

### Relevant to APort

| Area | Notes |
|------|--------|
| **Paths** | Config/state: `~/.openclaw`. Override: `OPENCLAW_HOME` / `OPENCLAW_STATE_DIR`. We default to `~/.openclaw` and respect `OPENCLAW_HOME` in `bin/openclaw`. |
| **Skills** | Managed skills: `~/.openclaw/skills/`. We install `skills/aport-guardrail/SKILL.md` there. OpenClaw watches `SKILL.md` when refreshing skills. |
| **Workspace** | `~/.openclaw/workspace` (AGENTS.md, TOOLS.md, SOUL.md, workspace/skills). Setup **auto-installs** the APort rule into `workspace/AGENTS.md` (create or append). No manual merge. |
| **Breaking (2026.2.13)** | Legacy `.moltbot` auto-detection removed; everything is `~/.openclaw`. No impact (we never used .moltbot). |
| **Messaging** | `openclaw message send` and cron use `target` (not just `to`/`channelId`). Our tool name `messaging.message.send` and context JSON are independent; no change needed. |
| **Hooks** | `before_tool_call` / `after_tool_call` exist. **Deterministic** enforcement requires hooks (or core integration); see below. |

### Enforcement model: AGENTS.md is best-effort, not deterministic

**Current approach (AGENTS.md + skill):** The APort rule is written into `workspace/AGENTS.md` so the agent is *instructed* to call the guardrail script before effectful actions. That is **best-effort**: the LLM may skip it, forget it, or be prompted to bypass it. It is **not** a guarantee that every tool run is checked.

**Purpose of APort:** Pre-action **authorization** should be enforced by the **platform** (OpenClaw calling the guardrail before executing a tool), not by the model following a prompt. Same outcome every time = deterministic enforcement.

**Intended production approach:** Use a **hook** (`before_tool_call`) or core integration so OpenClaw invokes the guardrail **before** every tool execution, regardless of what the agent “decides.” The OpenClaw plugin in this repo provides that hook. Until the plugin is installed, the AGENTS.md rule is a **stopgap** to get policy and audit in place; it does not replace deterministic enforcement.

### Running with a project-specific OpenClaw home

If you set `OPENCLAW_HOME` to a project dir (e.g. `.../valentine-openclaw`), OpenClaw uses that dir as `~/.openclaw` for that process: config, auth, workspace, and skills all live under that dir. The agent will use the APort passport and `.skills` from that project.

**Auth / model provider:** That home has its own auth store (e.g. `$OPENCLAW_HOME/.openclaw/agents/main/agent/auth-profiles.json`). It does **not** use your default `~/.openclaw` credentials. So if you only have OpenAI (or WhatsApp, Brave, ElevenLabs, etc.) set up in the default install, you must either:

1. **Configure auth for the project home**  
   Run the wizard with that home set, then add your provider (e.g. OpenAI):
   ```bash
   OPENCLAW_HOME=/path/to/valentine-openclaw openclaw configure
   # Add OpenAI (or your provider) when prompted; or
   OPENCLAW_HOME=/path/to/valentine-openclaw openclaw models auth add
   ```

2. **Copy auth from your default install**  
   Copy the agent auth (and optionally credentials) from `~/.openclaw` into `$OPENCLAW_HOME/.openclaw` so the project home sees the same providers (e.g. OpenAI, WhatsApp). Only do this on a machine you control and keep the project dir private.

After that, run the agent with that home and a session target:
   ```bash
   OPENCLAW_HOME=/path/to/valentine-openclaw openclaw agent --local --session-id my-test --message "Run node --version and report. Use APort guardrail before any command per AGENTS.md."
   ```
   APort decisions will be written to `$OPENCLAW_HOME/decision.json` and `$OPENCLAW_HOME/audit.log`.

### What we should add (optional)

- **Document OPENCLAW_HOME:** In README or QUICKSTART, mention that if users set `OPENCLAW_HOME` (e.g. to a project-specific dir), our script uses it as the default config dir.
- **OpenClaw version note:** In README or this doc, state we align with OpenClaw 2026.2.x layout (`~/.openclaw`, `~/.openclaw/skills`, `~/.openclaw/workspace`).

### Blockers and risks

- **No blockers.** Our integration is script-based (passport + guardrail script + AGENTS.md + optional plugin). The plugin uses OpenClaw's `before_tool_call` hook for deterministic enforcement.
- **Low risk:** If OpenClaw changes the managed-skill path (e.g. from `~/.openclaw/skills` to another dir), we would update `bin/openclaw` install path; CHANGELOG shows no such change.
- **Low risk:** Our tool names (`system.command.execute`, `messaging.message.send`, etc.) are our own convention for policy mapping, not OpenClaw tool IDs; renames of OpenClaw’s internal tool names do not block us.

---

## 2. References

- OpenClaw CHANGELOG: https://github.com/openclaw/openclaw/blob/main/CHANGELOG.md  
- OpenClaw docs: https://docs.openclaw.ai  
- Gateway architecture: https://docs.openclaw.ai/concepts/architecture  
- Integrations: https://openclaw.ai/integrations  
- OpenClaw plugin: [extensions/openclaw-aport/README.md](../extensions/openclaw-aport/README.md)

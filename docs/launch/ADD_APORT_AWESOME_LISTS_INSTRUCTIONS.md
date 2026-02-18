# Add APort Agent Guardrails to Awesome Lists — Instructions

Standard open-source workflow: **fork upstream → clone your fork → edit → push → open PR from your fork to upstream.**

Use the script `docs/launch/scripts/add-aport-awesome-pr.sh`. Repo details from [README.md](../../README.md) and [package.json](../../package.json).

**Standard entry (short):**
- **Name:** APort Agent Guardrails  
- **Repo:** https://github.com/aporthq/aport-agent-guardrails  
- **npm:** https://www.npmjs.com/package/@aporthq/aport-agent-guardrails  
- **Description:** Pre-action authorization for OpenClaw/agent frameworks. `before_tool_call` plugin, 40+ blocked patterns, local or API.  
- **Setup:** `npx @aporthq/aport-agent-guardrails`

---

## 1. SamurAIGPT/awesome-openclaw

- **Fork + clone:** Run the script (see workflow below). Your fork is cloned to `/tmp/aport-awesome-prs/SamurAIGPT-awesome-openclaw/`; `origin` = your fork.
- **File:** `README.md`
- **Section:** `## Security` → **Security Tools** table (after the aquaman row).
- **Add this row** (after the line with `aquaman`):

```markdown
| [APort Agent Guardrails](https://github.com/aporthq/aport-agent-guardrails) | - | Pre-action authorization for OpenClaw; `before_tool_call` plugin, allowlist + 40+ blocked patterns, local or API. Setup: `npx @aporthq/aport-agent-guardrails` |
```

- **Anchor:** Search for `### Security Tools` then the table with `| [aquaman]`. Add the new row after the aquaman row (before `### Security Resources`).

---

## 2. VoltAgent/awesome-openclaw-skills

- **Fork + clone:** Run the script. Your fork is cloned to `/tmp/aport-awesome-prs/VoltAgent-awesome-openclaw-skills/`; `origin` = your fork.
- **File:** `README.md`
- **Section:** **### Security & Passwords** — add in alphabetical order with other skills (same bullet format as existing entries).
- **Add** (match list format: `- [slug](url) - description`; alphabetically after amai-id, before audit-badge-demo):

```markdown
- [aport-agent-guardrails](https://github.com/aporthq/aport-agent-guardrails) - Pre-action authorization for OpenClaw; before_tool_call plugin, 40+ blocked patterns, local or API. Setup: npx @aporthq/aport-agent-guardrails
```

- **Note:** This list only includes skills published in the OpenClaw skills repo; if APort is not there yet, the maintainers may ask you to publish the skill first. See CONTRIBUTING.md.

---

## 3. hesamsheikh/awesome-openclaw-usecases

- **Fork + clone:** Script clones your fork to `/tmp/aport-awesome-prs/hesamsheikh-awesome-openclaw-usecases/`.
- **File:** `README.md`
- **Section:** Add a new section **## Security & Guardrails** (e.g. after `## Finance & Trading`, before `## 🤝 Contributing`).
- **Add:**

```markdown
## Security & Guardrails

| Name | Description |
|------|-------------|
| [APort Agent Guardrails](https://github.com/aporthq/aport-agent-guardrails) | Pre-action authorization for OpenClaw; every tool call checked before it runs. Allowlist + 40+ blocked patterns, local or API. Setup: `npx @aporthq/aport-agent-guardrails` |
```

---

## 4. Jenqyang/Awesome-AI-Agents

- **Fork + clone:** Script clones your fork to `/tmp/aport-awesome-prs/Jenqyang-Awesome-AI-Agents/`.
- **File:** `README.md`
- **Section:** Find **Tools** or **Safety / Guardrails** (or similar). If there is a bullet list of tools, add:
- **Add:**

```markdown
- [APort Agent Guardrails](https://github.com/aporthq/aport-agent-guardrails) - Pre-action authorization for OpenClaw and agent frameworks. `before_tool_call` plugin, 40+ blocked patterns, local or API. Setup: `npx @aporthq/aport-agent-guardrails`
```

- **Note:** Open the README and place the entry in the most appropriate subsection (e.g. Tools or a guardrails/safety section). Match existing list style (dash vs table).

---

## 5. e2b-dev/awesome-ai-agents

- **Fork + clone:** Script clones your fork to `/tmp/aport-awesome-prs/e2b-dev-awesome-ai-agents/`.
- **File:** `README.md`
- **Section:** Locate a Security / Guardrails / Tools section. Format may be minimal; match existing style.
- **Add (bullet style):**

```markdown
- [APort Agent Guardrails](https://github.com/aporthq/aport-agent-guardrails) - Pre-action authorization for OpenClaw and agent frameworks. `before_tool_call` plugin, 40+ blocked patterns. Setup: `npx @aporthq/aport-agent-guardrails`
```

---

## 6. slavakurilyak/awesome-ai-agents

- **Fork + clone:** Script clones your fork to `/tmp/aport-awesome-prs/slavakurilyak-awesome-ai-agents/`.
- **File:** `README.md` (or the main list file; check repo structure).
- **Section:** Find Guardrails / Safety / Security or Tools. Match existing entry format (often project name + stars + description).
- **Add (adjust to match list style):**

```markdown
- [APort Agent Guardrails](https://github.com/aporthq/aport-agent-guardrails) - Pre-action authorization for OpenClaw/agent frameworks; `before_tool_call` plugin, 40+ blocked patterns, local or API. Setup: `npx @aporthq/aport-agent-guardrails`
```

---

## 7. TalEliyahu/Awesome-AI-Security

- **Fork + clone:** Script clones your fork to `/tmp/aport-awesome-prs/TalEliyahu-Awesome-AI-Security/`.
- **File:** `README.md`
- **Section:** **Jailbreak & Policy Enforcement (Guardrails)** — add after the Guardrails entry (e.g. after the line with `guardrails-ai/guardrails`).
- **Add** (match their format with GitHub stars badge if they use it):

```markdown
- **[APort Agent Guardrails](https://github.com/aporthq/aport-agent-guardrails)** [![GitHub Repo stars](https://img.shields.io/github/stars/aporthq/aport-agent-guardrails?logo=github&label=&style=social)](https://github.com/aporthq/aport-agent-guardrails) - Pre-action authorization for OpenClaw/agent frameworks; `before_tool_call` hook, passport-driven, 40+ blocked patterns, local or API. Setup: `npx @aporthq/aport-agent-guardrails`
```

---

## Repetitive workflow (per repo)

1. **Fork and clone** (from this repo root). This forks the upstream repo to your GitHub account and clones your fork:
   ```bash
   ./docs/launch/scripts/add-aport-awesome-pr.sh <owner/repo>
   ```
   Example: `./docs/launch/scripts/add-aport-awesome-pr.sh SamurAIGPT/awesome-openclaw`  
   Clone path: `/tmp/aport-awesome-prs/<owner>-<repo>/` (e.g. `SamurAIGPT-awesome-openclaw`). Remote `origin` is your fork.

2. **Edit** the clone: open the file and section above, add the exact line(s) for that repo.

3. **Push and open PR** (from your fork to upstream):
   ```bash
   ./docs/launch/scripts/add-aport-awesome-pr.sh <owner/repo> pr
   ```

**PR title (suggested):** `Add APort Agent Guardrails`  
**PR body (suggested):**
```markdown
Adds [APort Agent Guardrails](https://github.com/aporthq/aport-agent-guardrails) — pre-action authorization for OpenClaw and compatible agent frameworks. Policy runs in the platform `before_tool_call` hook; 40+ blocked patterns, allowlist, local or API. Setup: `npx @aporthq/aport-agent-guardrails`.
```

---

## Reference

- **Repo:** https://github.com/aporthq/aport-agent-guardrails  
- **npm:** https://www.npmjs.com/package/@aporthq/aport-agent-guardrails  
- **Quick start:** https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md  
- **package.json** name: `@aporthq/aport-agent-guardrails`, description: "Policy enforcement guardrails for OpenClaw-compatible agent frameworks"

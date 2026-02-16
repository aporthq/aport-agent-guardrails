# OpenClaw tools, policies, and passport

How the APort plugin maps OpenClaw tools to policies and where limits live (passport vs policy).

---

## How it works

1. **Tool → policy** is defined in the **plugin** (`mapToolToPolicy` in `extensions/openclaw-aport/index.js`). OpenClaw tool names (e.g. `exec`, `message`, `read`) are mapped to APort policy IDs (e.g. `system.command.execute.v1`, `messaging.message.send.v1`).
2. **Passport** holds **capabilities** (what the agent is allowed to do at a high level) and **limits** (per-policy constraints). There is **no global “tool allowlist”** in the passport for OpenClaw tool names. Control is per policy:
   - **exec** → policy **system.command.execute.v1** → passport **limits.system.command.execute** (e.g. `allowed_commands`, `blocked_patterns`).
   - **message** / **messaging.*** → policy **messaging.message.send.v1** → passport **limits.messaging** (e.g. `msgs_per_min`, `msgs_per_day`).
   - **read**, **write**, **edit**, **browser**, **cron**, etc. → **no mapping** in this plugin → treated as unmapped (allowed by default when `allowUnmappedTools: true`).
3. **OAP spec:** The passport schema has **limits** per policy and, for MCP, **mcp.servers** / **mcp.tools**. It does not define a single “allowed OpenClaw tools” list; the plugin decides which tools are mapped and which are unmapped.

---

## exec and allowed_commands (OAP: limits live in the passport)

Per the **Open Agent Passport (OAP) spec**, the passport has a **limits** object: *operational limits per capability*. Each policy reads its limits from the passport under a key that matches the policy (e.g. `system.command.execute`, `messaging`). There is no separate “allowed list” config outside the passport.

- **Where it’s set:** **passport.limits.system.command.execute.allowed_commands** (array of strings). The guardrail script and API both read `LIMITS = passport.limits["system.command.execute"]` and then `.allowed_commands[]` from that. So **allowed_commands is supposed to be set in the passport**; the wizard (or you) populate it when creating/editing the passport.
- **How it’s enforced:** For **system.command.execute.v1**, the evaluator checks the request’s `context.command` (e.g. `mkdir` or `mkdir -p foo`). The command is allowed if: (1) **allow-all:** `allowed_commands` contains `"*"` (any command passes the allowlist; **blocked_patterns** still apply), or (2) **allowlist:** the command matches one of the passport’s `allowed_commands` entries (exact or prefix match). If there is at least one entry and the command doesn’t match any and there’s no `"*"`, the policy returns **oap.command_not_allowed** (“Command must be in allowed list”). The **bash** guardrail and the **agent-passport API** both support `"*"` for “allow all commands.”
- OpenClaw uses **exec** both to run the guardrail script (we detect that and evaluate the **inner** tool) and to run real shell commands (`mkdir`, `npm install`, etc.). When the run is a real command, we evaluate **system.command.execute.v1** and check the command against **passport limits.system.command.execute.allowed_commands**. So: **every command you want to allow must be in that passport array** (e.g. `mkdir`, `cp`, `ls`, `cat`, `echo`, `pwd`, `mv`, `touch`, `npx`, `open`). Re-run the passport wizard for an expanded default, or edit the passport and add them.
- **If the guardrail is run via exec** (e.g. a skill runs `bash ~/.openclaw/.skills/aport-guardrail.sh ...`), that **exec** is also checked against **allowed_commands**. Include **`bash`** (so `bash /path/to/aport-guardrail.sh ...` passes prefix match) or the full script path so the guardrail invocation is allowed. The default wizard list includes `bash` and `sh`; if you use a narrow list, add them.
- If you want OpenClaw to run any command without guardrail checks for exec, set **mapExecToPolicy: false** in the plugin config; then **exec** is unmapped and allowed (no policy check). This disables command allowlisting for exec.

---

## read, write, and other unmapped tools

- **read**, **write**, **edit**, **apply_patch**, **browser**, **cron**, **gateway**, **sessions_***, **nodes**, **image**, **web_search**, **web_fetch** are **not** mapped to any APort policy in this plugin. They are **unmapped** and **allowed** by default (when `allowUnmappedTools: true`). So **read is enabled** by default: the plugin sees no policy for `read`, returns allow, and OpenClaw runs the read tool.
- A failure like **read failed: ENOENT: no such file or directory** is the **tool** failing (e.g. wrong path or missing file, such as `config.json` when the app uses `config.yaml`), not the guardrail blocking. The guardrail already allowed the call; the error happens when the tool executes.
- To enforce policy on file access you would add a new policy (e.g. **file.read.v1**) and map **read** to it in the plugin, with passport limits (e.g. **allowed_paths**). That is not implemented today.

---

## Summary table

| OpenClaw tool (examples) | APort policy              | Passport limits (key)                    |
|--------------------------|---------------------------|------------------------------------------|
| exec                     | system.command.execute.v1 | limits.system.command.execute            |
| message, messaging.*     | messaging.message.send.v1 | limits.messaging                         |
| git.*                    | code.repository.merge.v1  | limits.code.repository.merge             |
| mcp.*                    | mcp.tool.execute.v1       | (API / MCP limits)                       |
| read, write, edit, etc.  | *(none)*                  | *(unmapped, allowed by default)*         |

---

## References

- [TOOL_POLICY_MAPPING.md](TOOL_POLICY_MAPPING.md) — Full mapping table and script behavior.
- [OpenClaw Tools](https://docs.openclaw.ai/tools) — Official list of OpenClaw tools (exec, read, message, cron, etc.).
- Plugin config: `mapExecToPolicy`, `allowUnmappedTools` in [extensions/openclaw-aport/README.md](../extensions/openclaw-aport/README.md).

# Tool → policy pack mapping

OpenClaw (or any caller) invokes the guardrail with a **tool name** and **context JSON**. The guardrail maps the tool name to a **policy pack** in `external/aport-policies/` and evaluates the request against that policy and the passport.

This mapping is implemented in `bin/aport-guardrail-api.sh` and `bin/aport-guardrail-bash.sh`. The table below is the single source of truth for documentation.

## Mapping table

| Tool name (pattern) | Policy pack ID | Policy location |
|---------------------|----------------|------------------|
| `git.create_pr`, `git.merge`, `git.push`, `git.*` | `code.repository.merge.v1` | `external/aport-policies/code.repository.merge.v1/` |
| `exec.run`, `exec.*`, `system.command.*`, `system.*` | `system.command.execute.v1` | `local-overrides` or API |
| `message.send`, `message.*`, `messaging.*` | `messaging.message.send.v1` | `external/aport-policies/messaging.message.send.v1/` |
| `mcp.tool.*`, `mcp.*` | `mcp.tool.execute.v1` | API / evaluator |
| `agent.session.*`, `session.create`, `session.*` | `agent.session.create.v1` | API / evaluator |
| `agent.tool.*`, `tool.register`, `tool.*` | `agent.tool.register.v1` | API / evaluator |
| `payment.refund`, `payment.*`, `finance.payment.refund` | `finance.payment.refund.v1` | `external/aport-policies/finance.payment.refund.v1/` |
| `payment.charge`, `finance.payment.charge` | `finance.payment.charge.v1` | `external/aport-policies/finance.payment.charge.v1/` |
| `database.write`, `database.*`, `data.export` | `data.export.create.v1` | `external/aport-policies/data.export.create.v1/` |

**Unknown tool:** In the **bash/API guardrail script**, an unknown tool name results in deny (exit 1). In the **OpenClaw plugin**, unmapped tools are **allowed** by default so custom skills and ClawHub tools work; set `allowUnmappedTools: false` in plugin config for strict (block unmapped).

## How OpenClaw uses it

1. OpenClaw (or your integration code) decides to run a tool, e.g. `system.command.execute` with `{"command":"npm install"}`.
2. Before executing, it calls the guardrail script with that tool name and context:
   ```bash
   ~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"npm install"}'
   ```
3. The script maps `system.command.execute` → `system.command.execute.v1`, loads the passport and policy (or calls the API), and evaluates.
4. Exit 0 = allow, exit 1 = deny. Decision details are in `~/.openclaw/decision.json` (or your configured path).

## Adding or changing mappings

To add a new tool → policy mapping, edit the `case` block in:

- `bin/aport-guardrail-api.sh`
- `bin/aport-guardrail-bash.sh`

and add a new pattern and policy pack ID. The policy pack must exist under `external/aport-policies/<pack_id>/` (or in local-overrides / API).

## Reference

- OAP spec: `external/aport-spec/`
- Policy packs: `external/aport-policies/`
- AGENTS.md example: [AGENTS.md.example](AGENTS.md.example)

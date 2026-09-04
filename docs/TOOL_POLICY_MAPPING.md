# Tool → policy pack mapping

The shell/API guardrail entrypoints invoke the guardrail with a **tool name** and **context JSON**. The guardrail maps the tool name to a **policy pack** in `external/aport-policies/` and evaluates the request against that policy and the passport.

This mapping is implemented in `bin/aport-guardrail-api.sh` and `bin/aport-guardrail-bash.sh`. The OpenClaw plugin has its own host-specific mapping in `extensions/openclaw-aport/tool-mapping.js`.

## Mapping table

| Tool name (pattern) | Policy pack ID | Policy location |
|---------------------|----------------|------------------|
| `release.publish`, `git.release` | `code.release.publish.v1` | `external/aport-policies/code.release.publish.v1/` |
| `git.create_pr`, `git.merge`, `git.push`, `git.*` | `code.repository.merge.v1` | `external/aport-policies/code.repository.merge.v1/` |
| `exec.run`, `exec.*`, `system.command.*`, `system.*` | `system.command.execute.v1` | `local-overrides` or API |
| `message.send`, `message.*`, `messaging.*` | `messaging.message.send.v1` | `external/aport-policies/messaging.message.send.v1/` |
| `read`, `file.read`, `data.file.read` | `data.file.read.v1` | API / evaluator |
| `write`, `file.write`, `data.file.write` | `data.file.write.v1` | API / evaluator |
| `mcp.tool.*`, `mcp.*` | `mcp.tool.execute.v1` | API / evaluator |
| `agent.session.*`, `session.create`, `session.*`, `cron`, `sessions_spawn`, `sessions_send`, `sessions_yield`, `subagents`, `session_status` | `agent.session.create.v1` | API / evaluator |
| `sessions_list`, `sessions_history`, `view` | `data.file.read.v1` | API / evaluator |
| `websearch`, `web_search`, `webfetch`, `web_fetch` | `web.fetch.v1` | API / evaluator |
| `browser`, `web.browser` | `web.browser.v1` | API / evaluator |
| `agent.tool.*`, `tool.register`, `tool.*` | `agent.tool.register.v1` | API / evaluator |
| `payment.refund`, `payment.*`, `finance.payment.refund` | `finance.payment.refund.v1` | `external/aport-policies/finance.payment.refund.v1/` |
| `payment.charge`, `finance.payment.charge` | `finance.payment.charge.v1` | `external/aport-policies/finance.payment.charge.v1/` |
| `database.write`, `database.*`, `data.export` | `data.export.create.v1` | `external/aport-policies/data.export.create.v1/` |

**Unknown tool:** In the **bash/API guardrail script**, an unknown tool name results in deny (exit 1). In the **OpenClaw plugin**, unmapped tools are **blocked** by default. Set `allowUnmappedTools: true` only when explicitly rolling out trusted custom skills and accepting that unmapped tools bypass policy checks.

## How OpenClaw uses it

1. OpenClaw (or your integration code) decides to run a tool, e.g. `system.command.execute` with `{"command":"npm install"}`.
2. Before executing, it calls the guardrail script with that tool name and context:
   ```bash
   ~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"npm install"}'
   ```
3. The script maps `system.command.execute` → `system.command.execute.v1`, loads the passport and policy (or calls the API), and evaluates.
4. Exit 0 = allow, exit 1 = deny. Decision details are in `~/.openclaw/decision.json` (or your configured path).

## Local repository checks

The local evaluator intentionally implements a small subset of hosted repository enforcement:

- `pr.merge` requires `repo.merge`.
- `pr.create`, `pr.update`, and `repo.push` require `repo.pr.create`.
- PR actions check `base_branch` when present; push-like actions check `branch`.
- `allowed_repos`, `allowed_base_branches`, and `allowed_paths` support simple glob patterns.

Hosted verification remains the source of truth for GitHub OIDC, signed decisions, policy hashes, and Action-collected GitHub evidence.

Shell commands such as `npm publish`, `pnpm publish`, and `gh release create` are evaluated as `system.command.execute.v1` when they arrive through Claude Code, Cursor, or another shell hook. The release policy applies when the integration supplies an explicit `release.publish` or `git.release` tool name, or when callers invoke the hosted verifier directly with `code.release.publish.v1`.

## Adding or changing mappings

To add a new tool → policy mapping, edit the shared JSON source:

- `packages/core/src/core/tool-pack-mapping.json`
- `python/aport_guardrails/core/tool-pack-mapping.json`

Both copies must stay identical. The policy pack must exist under `external/aport-policies/<pack_id>/` (or in local-overrides / API).

Per-framework host tool names and hook behavior: [FRAMEWORK_TOOL_MAPPING_AUDIT.md](FRAMEWORK_TOOL_MAPPING_AUDIT.md).

## Adding a new public policy pack

Public policy packs are authored upstream in [`aporthq/aport-policies`](https://github.com/aporthq/aport-policies).
This repository consumes that repo through the `external/aport-policies` submodule.

Use this repo for follow-up integration work only:

- Bump `external/aport-policies` after the upstream policy PR is merged.
- Add tool mapping when a framework tool should invoke the policy automatically.
- Add local/offline evaluator support only when the policy can be evaluated safely without hosted verifier state.
- Add framework docs and tests for the integration behavior.

For evidence policies, follow the same trust model as GitHub Repository Guard:
collect structured evidence in the integration, bind it to a trusted source when possible
(for example GitHub OIDC, CI metadata, file hashes, runner-observed exit codes, or signed
APort decision IDs), and let the hosted verifier return the signed OAP decision.

## Reference

- OAP spec: `external/aport-spec/`
- Policy packs: `external/aport-policies/`
- AGENTS.md example: [AGENTS.md.example](AGENTS.md.example)

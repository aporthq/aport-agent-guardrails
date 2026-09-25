# Tool → policy pack mapping

The shell/API guardrail entrypoints invoke the guardrail with a **tool name** and **context JSON**. The guardrail maps the tool name to a **policy pack** in `external/aport-policies/` and evaluates the request against that policy and the passport.

This mapping is implemented in `bin/aport-guardrail-api.sh` and
`bin/aport-guardrail-bash.sh`. Claude Code, Cursor, Codex CLI, Gemini CLI, and
Goose normalize host payloads before calling those entrypoints. The OpenClaw
plugin has its own host-specific mapping in
`extensions/openclaw-aport/tool-mapping.js`.

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
| `image.generate`, `image_gen.imagegen`, `image_genimagegen`, `image_generation`, `image_generate`, `imagegeneration`, `imagegen` | `media.image.generate.v1` | `local-overrides` or API |
| `websearch`, `web_search`, `webfetch`, `web_fetch` | `web.fetch.v1` | API / evaluator |
| `browser`, `web.browser` | `web.browser.v1` | API / evaluator |
| `agent.tool.*`, `tool.register`, `tool.*` | `agent.tool.register.v1` | API / evaluator |
| `payment.refund`, `payment.*`, `finance.payment.refund` | `finance.payment.refund.v1` | `external/aport-policies/finance.payment.refund.v1/` |
| `payment.charge`, `finance.payment.charge` | `finance.payment.charge.v1` | `external/aport-policies/finance.payment.charge.v1/` |
| `database.write`, `database.*`, `data.export` | `data.export.create.v1` | `external/aport-policies/data.export.create.v1/` |

**Unknown tool:** In the **bash/API guardrail script**, an unknown tool name results in deny (exit 1). In the **OpenClaw plugin**, unmapped tools are **blocked** by default. Set `allowUnmappedTools: true` only when explicitly rolling out trusted custom skills and accepting that unmapped tools bypass policy checks.

Unknown effectful tools intentionally do **not** become warnings in strict/enforce mode. During an experimental rollout, use `--enforcement=warn` to keep completed policy denials report-only while tuning passports and mappings; leave unknown tools fail-closed until they are mapped or explicitly accepted as trusted custom tools. This avoids converting host schema drift into a silent bypass.

## How runtime hooks use it

1. A host such as GitHub Actions, Claude Code, Cursor, Codex CLI, Gemini CLI,
   Goose, OpenClaw, LangChain, or CrewAI decides to run a tool/action.
2. Before executing, the integration maps the host-specific tool name to an
   APort guardrail tool id or policy pack.
3. The guardrail script or hosted verifier receives the minimal policy context,
   for example `system.command.execute` with `{"command":"npm install"}`:
   ```bash
   ~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"npm install"}'
   ```
4. The evaluator maps `system.command.execute` ->
   `system.command.execute.v1`, loads the passport and policy or calls the API,
   and evaluates.
5. Exit 0 = allow, exit 1 = deny for direct guardrail scripts. Host hooks then
   translate that result into the host-specific allow/deny response JSON.

## Local repository checks

The local evaluator intentionally implements a small subset of hosted repository enforcement:

- `pr.merge` requires `repo.merge`.
- `pr.create` and `pr.update` require `repo.pr.create`.
- `repo.push` requires `repo.push`.
- PR actions check `base_branch` when present; push-like actions check `branch`.
- `allowed_repos`, `allowed_base_branches`, and `allowed_paths` support simple glob patterns.

Hosted verification remains the source of truth for GitHub OIDC, signed decisions, policy hashes, and Action-collected GitHub evidence.

Shell commands such as `npm publish`, `pnpm publish`, and `gh release create` are evaluated as `system.command.execute.v1` when they arrive through Claude Code, Cursor, or another shell hook. The release policy applies when the integration supplies an explicit `release.publish` or `git.release` tool name, or when callers invoke the hosted verifier directly with `code.release.publish.v1`.

## What the shell policy sees

Host shell tools (Bash in Claude Code and Codex, `run_shell_command` in Gemini CLI, `developer__shell` in Goose, Cursor `beforeShellExecution`) map to `system.command.execute.v1` with `{"command": "<string>"}` as the only context. The local evaluator prefix-matches `allowed_commands` and applies a fixed set of catastrophic patterns. `blocked_patterns` uses word-boundary and glob matching, case-insensitive: a single word such as `sudo` matches only as a whole word (it does not block `sudoku`), an entry containing `*` or `?` is a glob, and a multi-word entry such as `rm -rf` matches as written. When `allowed_commands` is restrictive (not `*`), a command containing an unquoted `&&`, `||`, `;`, `|`, `&`, newline, `(`, `)`, `$(`, `<(`, `>(`, a `#` comment or `$'...'` quoting is denied with `oap.command_chain_unsupported`. It does not parse what the command does: `git push` remotes and branches, files read by `cat` or written with `>`, and hosts contacted by `curl` are invisible to the file, web and repository policies. Those policies apply only to the host's own Read/Write/Edit/WebFetch tools and to explicit `git.*` tool names. Details, plus the recommended pairing with a sandbox, a branch ruleset and a scoped token, are in [SECURITY_MODEL.md](SECURITY_MODEL.md#what-the-bash-policy-does-and-does-not-see).

Two related facts that are easy to miss:

- `data.file.read.v1` has a built-in deny list that runs before passport limits (case-insensitive): `.env` and anything starting with `.env`, the `.ssh`, `.aws`, `.gnupg` and `.kube` directories, `id_rsa`, `id_dsa`, `id_ecdsa` and `id_ed25519` anywhere in the path, files ending in `.pem` or `.key`, and any path containing `credentials` or `password`. Other `id_*` names such as `id_token` are not on the list. Anything else, for example `~/.codex/auth.json` or `~/.config/opencode/opencode.json`, must be added to `limits["data.file.read"].blocked_patterns` (substring match). The write policy has no built-in list; use `limits["data.file.write"].blocked_paths` (path prefix).
- `limits["system.command.execute"].max_execution_time` needs a timeout on the call. Claude Code Bash and Codex `shell`/`local_shell` fall back to their harness defaults (120 s and 10 s) when the call carries none; Cursor, Gemini CLI, Goose and Codex `exec_command`/`unified_exec` have no bound and are denied with `oap.missing_required_context`. Details in [SECURITY_MODEL.md](SECURITY_MODEL.md#what-the-bash-policy-does-and-does-not-see).
- Every tool that maps to `agent.session.create.v1` (Agent, Task, Skill, SendMessage, team, cron and workflow tools in Claude Code; `sessions_spawn` and friends in OpenClaw; collaboration tools in Codex) is denied with `oap.unknown_capability` unless the passport lists the `agent.session.create` capability.

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

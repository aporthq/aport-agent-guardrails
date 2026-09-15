# APort Agent Guardrail - Codex CLI

**Status:** Shipped beta command-hook harness. APort installs a Codex
`PreToolUse` hook for supported tool calls, stores secrets/state outside the
repository, and reuses the same hosted/local verifier path as the released
framework integrations.

APort integrates with Codex through Codex lifecycle hooks. The installer writes a repo-local `.codex/hooks.json` by default so a repository can opt into policy checks without changing the user's global Codex configuration.

## Quick start

```bash
npx @aporthq/aport-agent-guardrails codex
```

Use `--global` if you want the hook in `~/.codex/hooks.json` instead of the current repository:

```bash
npx @aporthq/aport-agent-guardrails codex --global
```

Hosted passport setup is the recommended path for signed decisions and centralized audit:

```bash
APORT_OWNER_EMAIL="you@example.com" \
APORT_QUICK_HOSTED=1 \
npx --yes @aporthq/aport-agent-guardrails codex --non-interactive
```

Hook wiring is project-local by default, but APort state is not. Hosted API keys, mode settings, local passports, and audit files default to `~/.aport/codex/aport` so they are not written into the repository.

## How it works

Codex loads hooks from `hooks.json` or inline `config.toml` hook tables next to active configuration layers. Project hooks only run after the project `.codex/` layer is trusted. APort uses `hooks.json` only, and the setup command preserves unrelated hooks.

APort registers command hooks for:

| Codex event | APort behavior |
|-------------|----------------|
| `PreToolUse` | Enforces policy before supported tools execute. |
| `PermissionRequest` | Supported by the wrapper for manual wiring, but not installed by default to avoid double-counting hosted decisions. |
| `PostToolUse` | Registered only for local session lifecycle bookkeeping. APort returns allow and does not forward tool output. |

The hook wrapper is `bin/aport-codex-hook.sh`, which delegates to the shared `bin/lib/command-hook-adapter.sh` and existing APort evaluator. This keeps Codex behavior aligned with Claude Code and Cursor without duplicating policy logic.

## Tool coverage

| Codex tool family | APort policy |
|-------------------|--------------|
| `Bash`, shell, exec-like local tools | `system.command.execute.v1` |
| `apply_patch`, write/edit/delete tools | `data.file.write.v1` |
| path-based read tools | `data.file.read.v1` |
| `WebFetch`, `WebSearch` | `web.fetch.v1` |
| MCP tools and MCP resource reads | `mcp.tool.execute.v1` |
| agent/task/subagent requests | `agent.session.create.v1` |
| `Grep` and other path-based content searches | `data.file.read.v1` |
| search/list/glob metadata tools without path, pattern, or include targets | allowed without evaluator |

Unknown effectful tools fail closed in enforce mode. File read/write tools that
do not expose an evaluable path also fail closed rather than silently bypassing
policy. `apply_patch` payloads that touch more than one file fail closed in the
beta hook because a single local evaluator call can authorize only one path
without producing misleading partial audit records. Split multi-file patches
while using the beta hook. Path-scoped metadata enumeration tools such as
`Glob`, `List`, and `LS` fail closed because the hook cannot authorize every
expanded result before the host returns filenames. `WebSearch` is network-backed
but may not expose a concrete destination URL; in local enforce mode APort fails
closed when the hook cannot verify a URL or domain against passport limits. Use
hosted mode or warn mode while tuning search-heavy workflows.

## Enforcement modes

Default is `enforce`: deny decisions block the Codex tool call. To roll out in report-only mode:

```bash
npx @aporthq/aport-agent-guardrails mode codex --enforcement=warn
```

Warn mode records the original deny decision locally or in APort hosted audit,
then returns allow semantics with a warning. It applies only after APort
completed policy evaluation; malformed hook input, invalid config, missing
dependencies, and unmapped effectful tools still fail closed. Use warn mode only
while tuning policy.

## Validate

After setup, run `/hooks` in Codex and trust the APort hook definition when prompted. Then ask Codex to run a blocked command such as `rm -rf /tmp/aport-test` and confirm Codex receives an APort denial.

Local unit coverage:

```bash
bash tests/unit/test-command-hook-adapter.sh
bash tests/frameworks/codex/setup.sh
```

## Source references

- Codex hook docs: https://learn.chatgpt.com/docs/hooks
- Codex advanced configuration: https://learn.chatgpt.com/docs/config-file/config-advanced

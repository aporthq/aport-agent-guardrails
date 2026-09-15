# APort Agent Guardrail - Gemini CLI

**Status:** Shipped beta command-hook harness. APort installs a Gemini CLI
`BeforeTool` hook for supported tool calls, stores secrets/state outside the
repository, and reuses the same hosted/local verifier path as the released
framework integrations.

APort integrates with Gemini CLI through the `BeforeTool` command hook in Gemini settings. The user-facing APort target is `gemini`; `gemini-cli` is kept as a compatibility alias.

## Quick start

```bash
npx @aporthq/aport-agent-guardrails gemini
```

The installer writes `.gemini/settings.json` in the current project by default. Use `--global` for `~/.gemini/settings.json`:

```bash
npx @aporthq/aport-agent-guardrails gemini --global
```

Hosted passport setup is recommended for signed decisions and centralized audit:

```bash
APORT_OWNER_EMAIL="you@example.com" \
APORT_QUICK_HOSTED=1 \
npx --yes @aporthq/aport-agent-guardrails gemini --non-interactive
```

Hook wiring is project-local by default, but APort state is not. Hosted API keys, mode settings, local passports, and audit files default to `~/.aport/gemini-cli/aport` so they are not written into the repository.

## How it works

Gemini CLI hook configuration lives in `settings.json` under `hooks`. APort adds one `BeforeTool` command hook with a regex matcher and preserves unrelated hooks. Gemini sends `tool_name`, `tool_input`, and optional `mcp_context` on stdin; APort returns Gemini-compatible JSON on stdout.

The hook wrapper is `bin/aport-gemini-cli-hook.sh`, which delegates to the shared command-hook adapter and existing APort evaluator.

## Tool coverage

| Gemini CLI tool family | APort policy |
|------------------------|--------------|
| `run_shell_command` | `system.command.execute.v1` |
| `write_file`, `replace`, edit-like tools | `data.file.write.v1` |
| `read_file`, single-target non-glob `read_many_files`, explicit path-based reads | `data.file.read.v1` |
| `web_fetch`, `google_web_search` | `web.fetch.v1` |
| MCP tools and calls with populated `mcp_context` | `mcp.tool.execute.v1` |
| memory/todo/user-prompt utility tools | allowed without evaluator |

Unknown effectful tools fail closed in enforce mode. Missing `tool_name` or
shell command context is treated as host-schema drift and fails closed even in
warn mode. Directory enumeration tools such as `list_directory`, multi-target
or glob-expanded `read_many_files` calls, and recursive `grep_search` directory
scans fail closed because the current local evaluator authorizes one concrete
read target at a time; use warn mode only while tuning completed policy denials.
Local web checks require a concrete URL or domain so APort can enforce
`allowed_domains`, `blocked_domains`, and method limits before the tool runs.
Loopback, link-local, private, and metadata IP literals are blocked before
configurable allowlists are applied.

## Enforcement modes

Default is `enforce`: deny decisions block the tool call. To roll out in report-only mode:

```bash
npx @aporthq/aport-agent-guardrails mode gemini --enforcement=warn
```

Warn mode records the original deny decision and returns allow semantics with a
warning after APort completed policy evaluation. Malformed hook input, invalid
config, missing dependencies, and unmapped effectful tools still fail closed.
Restart Gemini CLI after setup or mode changes if your running process does not
reload settings.

## Validate

```bash
bash tests/unit/test-command-hook-adapter.sh
bash tests/frameworks/gemini-cli/setup.sh
```

Then ask Gemini CLI to run a blocked shell command and confirm the hook denies before execution.

## Source reference

- Gemini CLI hook docs: https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/reference.md

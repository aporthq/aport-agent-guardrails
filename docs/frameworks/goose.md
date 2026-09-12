# APort Agent Guardrail - Goose

**Status:** Beta command-hook harness. This integration ships through the
APort guardrails package, enforces Goose `PreToolUse` events before supported
tools run, and keeps APort state outside the Goose plugin directory.

APort integrates with Goose through a Goose Open Plugin. The installer writes a project-scoped plugin by default and keeps APort passport state outside the plugin directory.

## Quick start

```bash
npx @aporthq/aport-agent-guardrails goose
```

Use `--global` if you want the plugin in `~/.agents/plugins/aport-guardrail`:

```bash
npx @aporthq/aport-agent-guardrails goose --global
```

Hosted passport setup is recommended:

```bash
APORT_OWNER_EMAIL="you@example.com" \
APORT_QUICK_HOSTED=1 \
npx --yes @aporthq/aport-agent-guardrails goose --non-interactive
```

## How it works

Goose loads Open Plugins from `.agents/plugins/<plugin-name>` or `~/.agents/plugins/<plugin-name>`. APort writes:

| File | Purpose |
|------|---------|
| `.agents/plugins/aport-guardrail/plugin.json` | Goose plugin metadata. |
| `.agents/plugins/aport-guardrail/hooks/hooks.json` | Blocking `PreToolUse` hook registration. |
| `.agents/plugins/aport-guardrail/scripts/aport-goose-hook.sh` | Thin wrapper that points to the stable APort runtime hook. |
| `~/.aport/goose/aport/guardrail-mode.env` | Hosted/local mode, enforcement, and API key if configured. |

The plugin hook uses Goose's `PreToolUse` event because it is blockable before the tool runs. `on_failure` is set to `block` so a broken policy hook does not fail open. In warn mode, completed APort policy denials are converted to allow-with-warning, but malformed hook input, missing dependencies, invalid config, and hook runtime failures still block.

The installer copies a self-contained runtime to
`~/.aport/goose/aport/runtime/` and the plugin wrapper executes
`~/.aport/goose/aport/runtime/bin/aport-goose-hook.sh`. The Goose plugin files
do not contain hosted API keys.

## Tool coverage

| Goose tool family | APort policy |
|-------------------|--------------|
| `developer__shell`, shell, exec | `system.command.execute.v1` |
| `developer__write`, edit tools, mutating `developer__text_editor` commands | `data.file.write.v1` |
| `developer__text_editor` `view`/`read`/`open` commands | `data.file.read.v1` |
| read tools, local `developer__read_image` sources | `data.file.read.v1` |
| URL-backed `developer__read_image` sources | `web.fetch.v1` |
| web fetch/browser-like tools | `web.fetch.v1` |
| MCP-style `server__tool` tools | `mcp.tool.execute.v1` |

Unknown effectful tools fail closed in enforce mode. Missing Goose `tool_name`
or shell command context is treated as host-schema drift and fails closed even
when report-only warn mode is enabled. Directory enumeration tools such as
`developer__tree` fail closed because the current local evaluator authorizes
one concrete read target at a time. Local web and MCP checks enforce the
passport's domain/server/tool allowlists and MCP timeout limits when the hook
payload supplies that context; loopback, link-local, private, and metadata IP
literals are blocked before configurable allowlists are applied. Missing
required context fails closed when a restrictive list is configured.

## Enforcement modes

Default is `enforce`:

```bash
npx @aporthq/aport-agent-guardrails mode goose --enforcement=enforce
```

Report-only rollout is explicit:

```bash
npx @aporthq/aport-agent-guardrails mode goose --enforcement=warn
```

Warn mode records the original deny decision but lets Goose continue only when
APort completed policy evaluation. Hook integrity and runtime failures remain
fail-closed.

## Validate

```bash
bash tests/unit/test-command-hook-adapter.sh
bash tests/frameworks/goose/setup.sh
```

Restart Goose after setup so it loads the plugin.

## Source reference

- Goose hooks docs: https://goose-docs.ai/docs/guides/context-engineering/hooks/

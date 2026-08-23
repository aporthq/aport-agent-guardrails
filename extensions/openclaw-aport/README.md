# APort OpenClaw Plugin

Deterministic pre-action authorization for OpenClaw agents.

This plugin registers `before_tool_call` and evaluates every tool call against an Open Agent Passport before the tool executes.

## Recommended install

Use the published setup command. No repo clone is required.

```bash
npx @aporthq/aport-agent-guardrails openclaw
```

If you already have a hosted passport on aport.io, pass the `agent_id`:

```bash
npx @aporthq/aport-agent-guardrails openclaw ap_your_agent_id
```

That command:

1. Chooses your OpenClaw config directory
2. Creates a passport or wires a hosted `agent_id`
3. Installs this plugin with `openclaw plugins install -l ...`
4. Writes plugin config into `config.yaml` and `openclaw.json`
5. Installs wrappers under `CONFIG_DIR/.skills/` for manual guardrail and status commands
6. Runs a setup smoke test

After setup, start OpenClaw with the generated config:

```bash
openclaw gateway start --config ~/.openclaw/config.yaml
```

## If you installed with `openclaw plugins install`

If you installed the plugin directly with:

```bash
openclaw plugins install @aporthq/openclaw-aport
```

that installs only the plugin bundle. It does not create a passport, choose API vs local mode, or write plugin config.

Run the full APort setup immediately after install:

```bash
npx @aporthq/aport-agent-guardrails openclaw
```

If you already have a hosted passport, use:

```bash
npx @aporthq/aport-agent-guardrails openclaw ap_your_agent_id
```

## What OpenClaw already gives you

OpenClaw already ships sandboxing, tool policy, elevated exec controls, and install-time scanning. Those are real security controls, not marketing copy.

## What APort adds

APort complements those controls with external authorization and audit:

- per-agent passports and capability limits
- parameter-aware deny decisions, not just static tool allowlists
- local or hosted kill switch by suspending the passport
- signed decision receipts and centralized audit in API mode
- the same authorization model across OpenClaw and other frameworks

If OpenClaw's built-in sandbox and tool policy are enough for your deployment, use them. If you need portable authorization, identity-scoped limits, or fleet-wide kill switch and audit, add APort on top.

## Development install

If you are working from a local checkout, install the plugin directly from the extension directory:

```bash
openclaw plugins install -l /path/to/aport-agent-guardrails/extensions/openclaw-aport
```

That command installs only the OpenClaw plugin bundle. It does not create a passport, choose API vs local mode, or write plugin config. For a full working setup, use:

```bash
npx @aporthq/aport-agent-guardrails openclaw
```

Then configure it in your OpenClaw config:

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: api
        passportFile: ~/.openclaw/aport/passport.json
        apiUrl: https://api.aport.io
        failClosed: true
        allowUnmappedTools: true
```

Hosted passport mode uses `agentId` instead of `passportFile`.

## Modes

### API mode

- Uses `fetch()` directly from the plugin
- Returns signed decisions from `api.aport.io`
- Configure `apiKey` in plugin config if your deployment requires it

### Local mode

- Uses the built-in JavaScript evaluator shipped with the plugin
- No `child_process` spawn is required
- `guardrailScript` remains as a legacy compatibility field for manual smoke tests and shell tooling, but current plugin versions do not depend on it for local-mode enforcement

## Tool mapping

The plugin keeps the existing OpenClaw-specific tool mappings. Common examples:

- `exec`, `exec.run` -> `system.command.execute.v1`
- `release.publish`, `git.release` -> `code.release.publish.v1`
- `git.create_pr`, `git.merge`, `git.push` -> `code.repository.merge.v1`
- `message` with send-family actions like `send`, `reply`, `broadcast`, `sendAttachment`, `upload-file`, or `react` -> `messaging.message.send.v1`
- `read`, `view`, `glob` -> `data.file.read.v1`
- `write`, `edit`, `multiedit` -> `data.file.write.v1`
- bundle MCP tools exposed as `serverName__toolName` -> `mcp.tool.execute.v1`

`allowUnmappedTools: true` keeps the previous OpenClaw compatibility behavior for custom skills and unmapped tools.

## Exec behavior

`exec` is OpenClaw's main shell-style tool. By default the plugin maps it to `system.command.execute.v1` and checks the underlying command against `limits["system.command.execute"].allowed_commands` in the passport.

If the plugin sees a delegated guardrail invocation such as `aport-guardrail-bash.sh <tool> <json>`, it unwraps the inner tool and evaluates that policy instead of treating the wrapper as an ordinary shell command.

## Troubleshooting

### Plugin install failed

Current OpenClaw releases perform install-time security scanning. This plugin is designed to pass that scan, but if installation still fails:

1. Make sure you are installing the current package version
2. Prefer the setup command `npx @aporthq/aport-agent-guardrails openclaw`
3. For local development, install from the extension directory with `-l`

### Existing source-linked config points into an old `npx` cache

Re-run the setup command. The installer removes stale `plugins.load.paths` and `plugins.installs.openclaw-aport` entries so OpenClaw does not keep pointing at a transient `~/.npm/_npx/...` directory.

## Notes

- Current public OpenClaw integration is plugin-based
- No upstream native guardrail-provider merge is required for this plugin path
- If OpenClaw later ships a native provider seam, APort can support that as an additional path without replacing the current plugin install flow

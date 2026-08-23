# APort Guardrails — OpenClaw

APort integrates with the current public OpenClaw release as a plugin. The plugin registers `before_tool_call` and blocks disallowed tools before execution. No OpenClaw core patch or native guardrail-provider merge is required.

## Quick start

```bash
npx @aporthq/aport-agent-guardrails openclaw
```

If you already have a hosted passport on aport.io, pass the `agent_id` and skip local passport creation:

```bash
npx @aporthq/aport-agent-guardrails openclaw ap_your_agent_id
```

If you run `openclaw plugins install @aporthq/openclaw-aport` directly, that installs only the plugin bundle. It does not create a local passport or write the plugin config. Use the setup command above for the full APort + OpenClaw flow, or configure the plugin manually.

After a direct plugin install, the recommended next step is:

```bash
npx @aporthq/aport-agent-guardrails openclaw
```

Hosted passport:

```bash
npx @aporthq/aport-agent-guardrails openclaw ap_your_agent_id
```

The setup command:

1. Chooses your OpenClaw config directory
2. Creates a local passport or wires a hosted `agent_id`
3. Installs the `openclaw-aport` plugin with `openclaw plugins install -l ...`
4. Writes `plugins.entries.openclaw-aport` config into your OpenClaw config files
5. Installs APort wrappers in `CONFIG_DIR/.skills/` for manual status checks and smoke tests

After setup, start OpenClaw with the generated config:

```bash
openclaw gateway start --config ~/.openclaw/config.yaml
```

## What OpenClaw already gives you

OpenClaw already ships meaningful runtime security controls:

- sandboxing and OpenShell decide where tools run
- tool policy decides which tools are callable
- elevated execution gates host-level exec outside the sandbox
- install-time scanning blocks obviously dangerous plugin bundles

Those controls matter, and for many single-runtime deployments they may be enough.

## What APort adds

APort is useful when you need authorization and audit beyond OpenClaw's built-in containment and static tool policy:

- per-agent identity and passport-based capability limits
- parameter-aware authorization, not just tool allow/deny
- local or hosted kill switch by suspending the passport
- signed decision receipts and centralized audit in API mode
- the same policy model across OpenClaw, CrewAI, DeerFlow, LangChain, and other runtimes

In short: OpenClaw secures where tools run and which tools exist; APort secures whether a specific action is authorized for a specific agent right now.

## Configuration

The installer writes the plugin config for you. A minimal manual config looks like this:

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

Hosted passport mode uses `agentId` instead of `passportFile`:

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: api
        agentId: ap_your_agent_id
        apiUrl: https://api.aport.io
        failClosed: true
        allowUnmappedTools: true
```

## Modes

### API mode

Best for production, signed decisions, and cloud kill switch workflows.

- The plugin sends the request context and passport or `agentId` to `api.aport.io`
- The API returns a signed decision
- If your deployment needs authentication, set `apiKey` in plugin config

### Local mode

Best for privacy-sensitive or offline environments.

- The plugin evaluates decisions with a built-in JavaScript evaluator
- No `child_process` spawn is required
- The installer still writes `guardrailScript` wrappers for manual smoke tests and legacy shell tooling, but current plugin versions do not depend on that script for local-mode enforcement

## Manual install for development

The public path is `npx @aporthq/aport-agent-guardrails openclaw`. If you are developing locally from a checkout, you can install the plugin directly:

```bash
openclaw plugins install -l /path/to/aport-agent-guardrails/extensions/openclaw-aport
```

Then add the same `plugins.entries.openclaw-aport` config shown above.

## How it works

```text
Agent decides to use a tool
        |
        v
OpenClaw fires before_tool_call
        |
        v
APort plugin maps tool -> policy pack
        |
        v
APort evaluates passport + limits (local JS evaluator or API)
   |                    |
   v                    v
 allow                deny
   |                    |
Tool runs        Plugin returns block=true
```

Common mappings include:

- `exec`, `exec.run` -> `system.command.execute.v1`
- `release.publish`, `git.release` -> `code.release.publish.v1`
- `git.create_pr`, `git.merge`, `git.push` -> `code.repository.merge.v1`
- `message` with send-family actions like `send`, `reply`, `broadcast`, `sendAttachment`, `upload-file`, or `react` -> `messaging.message.send.v1`
- `read`, `view`, `glob` -> `data.file.read.v1`
- `write`, `edit`, `multiedit` -> `data.file.write.v1`
- bundle MCP tools exposed as `serverName__toolName` -> `mcp.tool.execute.v1`

## Kill switch

- Local passport: set `status` to `suspended` in `~/.openclaw/aport/passport.json`
- Hosted passport: suspend the passport at aport.io

## Status

Current public OpenClaw integration: plugin-based.

Future path: if OpenClaw ships a native guardrail-provider seam upstream, APort can also plug into that provider path. That is not the current public default.

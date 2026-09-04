# QuickStart: OpenClaw Plugin

Set up deterministic, platform-level guardrails for OpenClaw with one public command.

## Quick start

```bash
npx @aporthq/aport-agent-guardrails openclaw
```

Hosted passport:

```bash
npx @aporthq/aport-agent-guardrails openclaw ap_your_agent_id
```

No repo clone is required.

## What the setup command does

1. Prompts for your OpenClaw config directory
2. Creates a local passport or wires a hosted `agent_id`
3. Installs the `openclaw-aport` plugin with `openclaw plugins install --link ...`
4. Writes plugin config into `config.yaml` and `openclaw.json`
5. Installs `aport-*` wrappers under `CONFIG_DIR/.skills/`
6. Runs a smoke test so you know the setup is complete

After setup, start OpenClaw with the generated config:

```bash
openclaw gateway start --config ~/.openclaw/config.yaml
```

## What gets installed

- `~/.openclaw/aport/passport.json` for local passport mode
- `~/.openclaw/config.yaml` with `plugins.entries.openclaw-aport`
- `~/.openclaw/openclaw.json` with matching plugin entry
- `~/.openclaw/.skills/aport-*` wrappers for manual checks and shell tooling

## Modes

### API mode

Recommended for production.

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
        enforcementMode: enforce
        allowUnmappedTools: false
```

Hosted passports use `agentId` instead of `passportFile`.

### Local mode

Best for offline or privacy-sensitive workflows.

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: local
        passportFile: ~/.openclaw/aport/passport.json
        failClosed: true
        enforcementMode: enforce
        allowUnmappedTools: false
```

Current plugin versions use a built-in JavaScript evaluator in local mode. The setup command still installs `aport-guardrail-bash.sh` for manual smoke tests and shell tooling, but the plugin does not depend on `child_process` or the bash script for local-mode enforcement.

## Development install

If you are developing from a local checkout:

```bash
openclaw plugins install --link /path/to/aport-agent-guardrails/extensions/openclaw-aport
```

Public users should prefer the `npx @aporthq/aport-agent-guardrails openclaw` path.

## Runtime behavior

On every tool call:

1. OpenClaw fires `before_tool_call`
2. APort maps the OpenClaw tool to an OAP policy pack
3. APort evaluates the passport and limits
4. `allow` lets the tool run
5. `deny` returns `block: true` and the tool never executes

## Notes

- Current public OpenClaw integration is plugin-based
- No upstream native guardrail-provider merge is required for this path
- If setup cannot install the plugin, it now stops immediately instead of writing broken config

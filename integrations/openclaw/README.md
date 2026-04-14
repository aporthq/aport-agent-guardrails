# OpenClaw integration

Framework-specific code for APort guardrails on OpenClaw.

## Current public path

OpenClaw currently uses the `openclaw-aport` plugin path.

- Public setup: `npx @aporthq/aport-agent-guardrails openclaw`
- Development install: `openclaw plugins install -l /path/to/aport-agent-guardrails/extensions/openclaw-aport`
- Runtime enforcement: plugin `before_tool_call`

Direct plugin install only installs the plugin bundle. It does not create a passport or write plugin config. Use the public setup command for a complete working setup.

Recommended follow-up after direct install:

```bash
npx @aporthq/aport-agent-guardrails openclaw
```

## Location

- Plugin runtime: [extensions/openclaw-aport](../../extensions/openclaw-aport)
- Installer: [bin/openclaw](../../bin/openclaw)
- Shared shell tooling and wrappers: [bin](../../bin)

## Notes

- The public OpenClaw path is plugin-based today
- Native provider wiring is future work, not the current default

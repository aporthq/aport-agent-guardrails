# APort Guardrails — OpenClaw

OpenClaw is an open-source AI agent platform with a plugin system and built-in `before_tool_call` hooks. APort integrates via two paths:

- **Native `guardrails:` config** (recommended) — OpenClaw's built-in `GuardrailProvider` interface loads `OAPGuardrailProvider` directly. No plugin needed.
- **Plugin** (legacy, still works) — The `openclaw-aport` plugin registers a `before_tool_call` hook.

Both paths use the same evaluator, passport, and policies.

## Quick start

```bash
npm install @aporthq/aport-agent-guardrails-core
npx @aporthq/aport-agent-guardrails openclaw
```

The first command installs the provider. The second runs the passport wizard.

## Config (native — recommended)

Add to your OpenClaw `config.yaml`:

```yaml
guardrails:
  enabled: true
  provider:
    use: "@aporthq/aport-agent-guardrails-core"
    config:
      framework: "openclaw"
```

This loads `OAPGuardrailProvider` as a core guardrail service — runs before plugin hooks, cannot be bypassed by disabling a plugin.

## Config (plugin — legacy)

The setup wizard (`npx @aporthq/aport-agent-guardrails openclaw`) installs the `openclaw-aport` plugin automatically. This registers a `before_tool_call` hook that calls the same evaluator.

Both approaches are supported. The native config is recommended for new deployments.

## How it works

```
Agent decides to use a tool
        │
        ▼
  GuardrailService (native)     or     Plugin hook (legacy)
        │                                      │
        ▼                                      ▼
  OAPGuardrailProvider ──────────────── same Evaluator
        │
  ┌─────┴─────┐
  │           │
ALLOW       DENY
  │           │
Tool runs   Agent sees denial reason
```

- **Provider class:** `OAPGuardrailProvider` from `@aporthq/aport-agent-guardrails-core`
- **Passport:** `~/.openclaw/aport/passport.json` (created by wizard)
- **Config:** `~/.openclaw/aport/config.yaml`
- **Audit log:** `~/.openclaw/aport/audit.log`

## Suspend (kill switch)

Local: set passport `status` to `suspended`. Remote: use API mode and suspend at [aport.io](https://aport.io).

## Status

Shipped; in production. Native `guardrails:` config available when [OpenClaw #46441](https://github.com/openclaw/openclaw/issues/46441) merges.

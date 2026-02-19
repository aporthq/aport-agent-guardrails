# APort Guardrails — OpenClaw

**How guardrails work:** OpenClaw’s plugin API provides a `before_tool_call` hook that runs **before every tool execution**. The APort plugin registers this hook and calls the shared evaluator (API or local script); the platform blocks the tool if the evaluator returns deny. The model cannot skip it.

- **Integration:** `before_tool_call` plugin (`extensions/openclaw-aport`)
- **Config:** `~/.openclaw/aport-config.yaml`

## Two ways to use APort

| Use case | What it is | When to use it |
|----------|------------|----------------|
| **Guardrails (CLI/setup)** | Full installer: runs the **passport wizard**, writes config, installs the **OpenClaw plugin** so every tool call goes through the evaluator. | Getting started: one command sets up config, passport, and the plugin. |
| **Core (runtime)** | The **evaluator** (bash script or API) that the plugin calls before each tool run. Same policy + passport as other frameworks. For **programmatic** use (e.g. custom scripts), you can use the **Python** (`aport_guardrails`) or **Node** (`@aporthq/aport-agent-guardrails-core`) library. | Guardrails = the plugin uses the evaluator automatically. Use the library only if you're building custom tooling. |

For OpenClaw, you use **Guardrails (CLI)** once to install the plugin; the **Core** (evaluator) then runs automatically on every tool call.

---

## Setup

```bash
npx @aporthq/aport-agent-guardrails openclaw
# or
npx @aporthq/aport-agent-guardrails
# then choose openclaw
```

## Config

- **Config dir:** `~/.openclaw` (or `OPENCLAW_HOME`)
- **Passport:** Created by wizard or use hosted `agent_id`
- **Plugin:** `extensions/openclaw-aport`

## Suspend (kill switch)

Same standard as all frameworks: **passport is the source of truth**—no separate file. Local: set passport `status` to `suspended` (or `active` to resume). Remote: use API mode and suspend in [APort](https://aport.io); all agents using that passport deny within ≤30s.

## Status

Shipped; in production.

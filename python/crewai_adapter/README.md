# APort Agent Guardrail for CrewAI

**APort Agent Guardrail for CrewAI** — pre-action authorization for [CrewAI](https://github.com/crewAIInc/crewAI) via the **before_tool_call** hook. Tool execution is verified against your passport and policy; deny → execution is blocked. Built for AI agent and multi-agent crews.

## Install

```bash
pip install aport-agent-guardrails-crewai
aport-crewai setup
```

## Usage

```python
from aport_guardrails_crewai import register_aport_guardrail

register_aport_guardrail()
crew.kickoff()
```

Or use the `with_aport_guardrail` decorator on your entry point. See [docs/frameworks/crewai.md](https://github.com/aporthq/agent-guardrails/blob/main/docs/frameworks/crewai.md).

## API

- **`aport_guardrail_before_tool_call(context)`** — Hook compatible with `@before_tool_call`; returns `False` to block, `None` to allow.
- **`register_aport_guardrail()`** — Registers the hook globally.
- **`with_aport_guardrail`** — Decorator that registers the hook then runs the wrapped function.

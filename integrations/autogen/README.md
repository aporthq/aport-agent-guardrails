# AutoGen integration

**APort Agent Guardrail for AutoGen** — framework-specific hooks and wrappers.

## Implementation

- **Python hook (0.4.x):** [python/autogen_adapter/hook.py](../../python/autogen_adapter/hook.py) — `APortGuardedTool` wraps any `BaseTool`/`FunctionTool`, intercepts `run_json` with APort evaluator.
- **Python hook (0.2.x):** [python/autogen_adapter/hook.py](../../python/autogen_adapter/hook.py) — `wrap_agent_tools(agent)` patches `agent.function_map` with sync guardrails.
- **Decorator:** [python/autogen_adapter/decorator.py](../../python/autogen_adapter/decorator.py) — `@with_aport_guardrail` for async/sync tool functions.
- **Config:** `~/.aport/autogen/` or `.aport/config.yaml` (see [bin/lib/config.sh](../../bin/lib/config.sh)).
- **Setup:** `pip install aport-agent-guardrails-autogen` + `aport-autogen`.

## Examples

- **examples/** — Minimal snippets; full docs in [docs/frameworks/autogen.md](../../docs/frameworks/autogen.md).

## Snippets

### AutoGen 0.4.x — APortGuardedTool

```python
from autogen_core.tools import FunctionTool
from autogen_agentchat.agents import AssistantAgent
from aport_guardrails_autogen import APortGuardedTool

tool = APortGuardedTool(FunctionTool(send_email, description="Send an email"))
agent = AssistantAgent("EmailAgent", model_client=..., tools=[tool])
```

### AutoGen 0.4.x — Decorator

```python
from aport_guardrails_autogen import with_aport_guardrail

@with_aport_guardrail
async def send_email(recipient: str, body: str) -> str:
    ...
```

### AutoGen 0.2.x — wrap_agent_tools

```python
from aport_guardrails_autogen import wrap_agent_tools

wrap_agent_tools(assistant)
user_proxy.initiate_chat(assistant, message="...")
```

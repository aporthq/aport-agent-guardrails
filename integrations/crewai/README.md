# CrewAI integration

**APort Agent Guardrail for CrewAI** — pre-action authorization via the **before_tool_call** hook.

## Implementation

- **Hook:** [python/crewai_adapter/hook.py](../../python/crewai_adapter/hook.py) — `aport_guardrail_before_tool_call(context)` fits CrewAI’s before_tool_call API; `register_aport_guardrail()` registers it globally.
- **Decorator:** [python/crewai_adapter/decorator.py](../../python/crewai_adapter/decorator.py) — `with_aport_guardrail` registers the hook then runs your function (e.g. entry point that calls `crew.kickoff()`).
- **Config:** `~/.aport/crewai/` or `.aport/config.yaml` (see [bin/lib/config.sh](../../bin/lib/config.sh)).
- **Setup:** `npx @aporthq/aport-agent-guardrails --framework=crewai` or `pip install aport-agent-guardrails-crewai` + `aport-crewai setup`.

## Example

```python
from aport_guardrails_crewai import register_aport_guardrail

register_aport_guardrail()
crew.kickoff()
```

See [docs/frameworks/crewai.md](../../docs/frameworks/crewai.md) and [examples/crewai/run_with_guardrail.py](../../examples/crewai/run_with_guardrail.py).

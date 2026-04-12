# Framework integrations

Implementation lives in the main packages:

- **LangChain (Node):** [packages/langchain](../packages/langchain) — `APortGuardrailCallback`, `GuardrailViolationError`
- **LangChain (Python):** [python/langchain_adapter](../python/langchain_adapter) — `APortCallback`
- **CrewAI (Python, released CrewAI):** [python/crewai_adapter](../python/crewai_adapter) — `aport_guardrail_before_tool_call`, `register_aport_guardrail`
- **CrewAI (Python, native provider builds):** [python/aport_guardrails/providers/generic.py](../python/aport_guardrails/providers/generic.py) — external `OAPGuardrailProvider`
- **CrewAI (Node):** [packages/crewai](../packages/crewai) — provider/middleware experiments

The files in this directory are stubs that point to the above. Use the packages directly.

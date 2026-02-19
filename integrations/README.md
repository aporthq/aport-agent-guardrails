# Framework integrations

Implementation lives in the main packages:

- **LangChain (Node):** [packages/langchain](../packages/langchain) — `APortGuardrailCallback`, `GuardrailViolationError`
- **LangChain (Python):** [python/langchain_adapter](../python/langchain_adapter) — `APortCallback`
- **CrewAI (Node):** [packages/crewai](../packages/crewai) — `beforeToolCall`, `registerAPortGuardrail`, `withAPortGuardrail`
- **CrewAI (Python):** [python/crewai_adapter](../python/crewai_adapter) — `aport_guardrail_before_tool_call`, `register_aport_guardrail`

The files in this directory are stubs that point to the above. Use the packages directly.

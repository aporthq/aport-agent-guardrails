# LangChain / LangGraph integration

**APort Agent Guardrail for LangChain** — framework-specific code and middleware.

## Implementation

- **Python middleware:** [python/langchain_adapter/middleware.py](../../python/langchain_adapter/middleware.py) — `APortCallback` (AsyncCallbackHandler), calls core evaluator on `on_tool_start`.
- **Config:** `~/.aport/langchain/` or `.aport/config.yaml` (see [bin/lib/config.sh](../../bin/lib/config.sh)).
- **Setup:** `npx @aporthq/aport-agent-guardrails --framework=langchain` or `pip install aport-agent-guardrails-langchain` + `aport-langchain setup`.

## Examples

- **examples/** — Minimal snippets; full example in [docs/frameworks/langchain.md](../../docs/frameworks/langchain.md).

## Snippet

```python
from aport_guardrails_langchain import APortCallback
agent = initialize_agent(tools=tools, llm=llm, callbacks=[APortCallback()])
```

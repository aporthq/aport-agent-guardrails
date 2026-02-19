# LangChain + APort guardrails example

Run with a local passport and config to see ALLOW/DENY behavior.

## Setup

```bash
# From repo root: install core and langchain adapter in editable mode
pip install -e python/aport_guardrails
pip install -e python/langchain_adapter

# Or after publishing:
# pip install aport-agent-guardrails aport-agent-guardrails-langchain
# aport-langchain setup
```

## Run example (assert ALLOW/DENY)

```bash
pytest examples/langchain/ -v
# or
python -m examples.langchain.run_with_guardrail
```

The example uses a temp passport and config, runs the callback with a mocked or local evaluator, and asserts that ALLOW and DENY paths behave as expected.

## Usage in your agent

```python
from aport_guardrails_langchain import APortCallback, GuardrailViolation

# Add callback to your agent (LangChain/LangGraph)
agent = initialize_agent(tools=tools, llm=llm, callbacks=[APortCallback()])

# On deny, the callback raises GuardrailViolation
try:
    result = await agent.ainvoke(...)
except GuardrailViolation as e:
    print(f"Blocked: {e.code} — {e}")
```

See [docs/frameworks/langchain.md](../../docs/frameworks/langchain.md).

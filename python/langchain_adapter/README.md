# APort Agent Guardrail for LangChain

**APort Agent Guardrail for LangChain/LangGraph** — pre-action authorization for AI agents: an `AsyncCallbackHandler` that verifies every tool call against your passport and policies before execution. On deny, raises `GuardrailViolation`.

## Install

```bash
pip install aport-agent-guardrails-langchain
```

Requires **aport-agent-guardrails** (core); installs automatically.

## Setup

```bash
aport-langchain setup
```

- Writes config to `~/.aport/langchain/config.yaml`.
- Run the passport wizard with: `npx @aporthq/aport-agent-guardrails --framework=langchain`.

## Usage

```python
from aport_guardrails_langchain import APortCallback, GuardrailViolation

# Add callback to your agent
agent = initialize_agent(
    tools=tools,
    llm=llm,
    callbacks=[APortCallback()]
)

# On deny, the callback raises GuardrailViolation
try:
    result = await agent.ainvoke(...)
except GuardrailViolation as e:
    print(f"Blocked: {e.code} — {e}")
    print("Reasons:", e.reasons)
```

Config is auto-loaded from `.aport/config.yaml` or `~/.aport/langchain/config.yaml`. Override with `APortCallback(config_path="/path/to/config.yaml")`.

## Config

- **mode:** `local` | `api`
- **passport_path:** path to passport JSON (local mode)
- **agent_id:** `ap_xxx` (API mode, hosted passport)
- **api_url:** optional; default `https://api.aport.io`

## Tests

```bash
cd python/langchain_adapter
pip install -e ".[dev]"
pip install -e ../aport_guardrails
pytest tests/ -v
```

## Links

- [Framework doc](https://github.com/aporthq/agent-guardrails/blob/main/docs/frameworks/langchain.md)
- [APort](https://aport.io)

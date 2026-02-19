# APort Agent Guardrail — LangChain / LangGraph

**How the agent guardrail works:** LangChain’s callback system exposes `on_tool_start` (and related hooks) on `BaseCallbackHandler` / `AsyncCallbackHandler`. The **APort Agent Guardrail for LangChain** implements a callback that runs when a tool is about to execute; we call the APort evaluator and raise to block execution if denied. Note: in some agent setups, tool callbacks can be unreliable; register callbacks on the executor and test your flow.

- **Integration:** `AsyncCallbackHandler` with `on_tool_start` (or equivalent)
- **Config:** `~/.aport/langchain/` or `.aport/config.yaml`

## Two ways to use APort

| Use case | What it is | When to use it |
|----------|------------|----------------|
| **Guardrails (CLI/setup)** | One-line installer: runs the **passport wizard**, writes config, prints next steps. Does not run your app. | Getting started: create passport and config so the library can find them. |
| **Core (library)** | The **evaluator** and **framework callback** in your code. Calls policy + passport to allow/deny each tool call. | Integrating into your app: add the callback so tool runs are checked before execution. |

You typically use **both**: run the CLI once to create passport and config, then use the library in your LangChain app so every tool call is verified.

---

## Setup (Guardrails — create passport and config)

**Python**

```bash
npx @aporthq/aport-agent-guardrails langchain   # wizard + config (optional)
pip install aport-agent-guardrails-langchain
aport-langchain setup
```

**Node**

```bash
npx @aporthq/aport-agent-guardrails langchain   # wizard + config
npm install @aporthq/aport-agent-guardrails-langchain   # callback handler (depends on -core)
```

## Using the library (Core) in your app

**Python:** Add `APortCallback()` to your agent's callbacks. Config is read from `~/.aport/langchain/` or `.aport/config.yaml`.

```python
from langchain.agents import initialize_agent
from aport_guardrails_langchain import APortCallback

agent = initialize_agent(
    tools=tools,
    llm=llm,
    callbacks=[APortCallback()]
)
```

**Node:** Add `APortGuardrailCallback` to your chain/agent callbacks. Config is read from `~/.aport/langchain/` or `.aport/config.yaml`.

```ts
import { APortGuardrailCallback } from '@aporthq/aport-agent-guardrails-langchain';

const callback = new APortGuardrailCallback(); // optional: { configPath: '...', framework: 'langchain' }
// Pass callback to your LangChain run (e.g. callbacks: [callback])
// On deny, the callback throws GuardrailViolationError.
```

## Config

- **Config:** `~/.aport/langchain/` or `.aport/config.yaml`
- **Usage:** Add the callback to your agent (see above).

## Suspend (kill switch)

Same standard as all frameworks: **passport is the source of truth**—no separate file. Local: set passport `status` to `suspended` (or `active` to resume). Remote: use API mode and suspend in [APort](https://aport.io); all agents using that passport deny within ≤30s.

## Status

Implemented. **APort Agent Guardrail for LangChain.** Package: `aport-agent-guardrails-langchain`; CLI: `aport-langchain setup`.

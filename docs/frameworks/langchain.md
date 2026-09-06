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
# Optional mode flags:
#   --mode=api --api-url=https://api.aport.io
#   --mode=local
#   --enforcement=warn   # explicit report-only rollout; default is enforce/fail-closed
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
from langchain.agents import create_agent
from aport_guardrails_langchain import APortCallback

agent = create_agent(model=model, tools=tools)

agent.invoke(
    {"messages": [{"role": "user", "content": "Run the task"}]},
    config={"callbacks": [APortCallback()]},
)
```

Default enforcement is fail-closed. For rollout/report-only mode:

```python
APortCallback(enforcement_mode="warn")
```

Warn mode lets the tool continue and prints an APort warning with the tool,
policy, reason code, reason detail, and the hosted passport or local passport
file to review.

**Node:** Add `APortGuardrailCallback` to your chain/agent callbacks. Config is read from `~/.aport/langchain/` or `.aport/config.yaml`.

```ts
import { APortGuardrailCallback } from '@aporthq/aport-agent-guardrails-langchain';

const callback = new APortGuardrailCallback(); // optional: { configPath: '...', framework: 'langchain', enforcementMode: 'warn' }
// Pass callback to your LangChain run (e.g. callbacks: [callback])
// On deny, the callback throws GuardrailViolationError.
```

### How tool parameters are handled

The Node middleware automatically parses JSON tool input and spreads parameters (e.g. `file_path`, `command`) into the verification context. This ensures policies like `data.file.read.v1` and `data.file.write.v1` receive the required `file_path` field at the top level for proper validation.

## Config

- **Config:** `~/.aport/langchain/` or `.aport/config.yaml`
- **Usage:** Add the callback to your agent (see above).
- **`fail_open_on_api_error`**: Set to `true` in config to allow tool execution when the APort API is unreachable (genuine policy denials are never overridden). Default: `false` (fail-closed).
- **`enforcement_mode`**: `enforce` blocks denied tools. `warn` is explicit report-only rollout: APort records the original deny decision but the adapter lets LangChain continue.

## Suspend (kill switch)

Same standard as all frameworks: **passport is the source of truth**—no separate file. Local: set passport `status` to `suspended` (or `active` to resume). Remote: use API mode and suspend in [APort](https://aport.io); all agents using that passport deny within ≤30s.

## Status

Implemented. **APort Agent Guardrail for LangChain.** Package: `aport-agent-guardrails-langchain`; CLI: `aport-langchain setup`.

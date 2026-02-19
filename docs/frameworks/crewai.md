# APort Agent Guardrail — CrewAI

CrewAI supports **tool call hooks** that run before (and after) every tool execution. The **APort Agent Guardrail for CrewAI** plugs into the **before tool call** hook: we verify the tool and parameters against your passport and policy; if the decision is deny, we return `False` and CrewAI blocks execution. This matches CrewAI’s [Tool Call Hooks](https://docs.crewai.com/en/learn/tool-hooks) model.

## How CrewAI agent guardrails work

- **Hooks:** CrewAI runs **before_tool_call** hooks before every tool execution. The hook receives a `ToolCallHookContext` (tool name, tool input, agent, task, crew). Returning `False` blocks execution; `True` or `None` allows it.
- **Registration:** You can register a hook **globally** with `register_before_tool_call_hook()`, or use the `@before_tool_call` decorator, or use **crew-scoped** `@before_tool_call_crew` on a `@CrewBase` class.
- **Multi-task crews:** The same hook runs for every tool call across all tasks and agents, so multi-task crews are supported by default.

Our adapter provides a function that fits this API: it calls the APort evaluator (sync) and returns `False` on deny, `None` on allow. You register it once before running your crew.

- **Integration:** CrewAI `before_tool_call` hook (global or crew-scoped)
- **Config:** `~/.aport/crewai/config.yaml` or `.aport/config.yaml` (see [Verification methods](../VERIFICATION_METHODS.md))

## Two ways to use APort

| Use case | What it is | When to use it |
|----------|------------|----------------|
| **Guardrails (CLI/setup)** | One-line installer: runs the **passport wizard**, writes config, prints next steps. Does not run your app. | Getting started: create passport and config so the library can find them. |
| **Core (library)** | The **evaluator** and **before-tool-call hook** in your code. Calls policy + passport to allow/deny each tool call. | Integrating into your app: register the hook so CrewAI blocks tool runs when policy denies. |

You typically use **both**: run the CLI once to create passport and config, then use the library in your CrewAI app so every tool call is verified.

---

## Setup (Guardrails — create passport and config)

**Python**

```bash
npx @aporthq/aport-agent-guardrails crewai   # wizard + config (optional)
pip install aport-agent-guardrails-crewai
aport-crewai setup
```

**Node**

```bash
npx @aporthq/aport-agent-guardrails crewai   # wizard + config
npm install @aporthq/aport-agent-guardrails-crewai   # beforeToolCall, withAPortGuardrail (depends on -core)
```

`aport-crewai setup` (Python) writes config to `~/.aport/crewai/`, runs the passport wizard (or use `--ci` / `--no-wizard` for non-interactive), and prints next steps.

## Using the library (Core) in your app

**Python — Option 1: Register the hook before kickoff**

```python
from aport_guardrails_crewai import register_aport_guardrail

register_aport_guardrail()
crew.kickoff()
```

**Python — Option 2: Decorator on your entry point**

```python
from aport_guardrails_crewai import with_aport_guardrail

@with_aport_guardrail
def main():
    crew.kickoff()

main()
```

**Python — Option 3: Use the hook with `@before_tool_call`**

```python
from crewai.hooks import before_tool_call
from aport_guardrails_crewai import aport_guardrail_before_tool_call

@before_tool_call
def my_guardrail(context):
    return aport_guardrail_before_tool_call(context)
```

**Node:** Call `beforeToolCall` in your flow before each tool run (CrewAI Node SDK does not expose a global hook). Return `false` to block, `null` to allow. Or wrap your entry point with `withAPortGuardrail(fn)`.

```ts
import { beforeToolCall, withAPortGuardrail } from '@aporthq/aport-agent-guardrails-crewai';

// In your tool-call flow, before executing a tool:
const result = beforeToolCall({ tool_name: 'run_command', tool_input: { command: 'ls' } });
if (result === false) {
  // Block this tool call
  return;
}

// Or wrap your crew kickoff so guardrail is in scope:
withAPortGuardrail(() => {
  crew.kickoff();
});
```

## Config

- **Config path:** `~/.aport/crewai/config.yaml`, or `.aport/config.yaml` in the project root.
- **Mode:** `api` (default for production) or `local` (bash evaluator, no network). Same options as [LangChain](langchain.md) and OpenClaw.

## Suspend (kill switch)

Same as all frameworks: **passport is the source of truth**. Local: set passport `status` to `suspended` (or `active` to resume). API: suspend the passport in [APort](https://aport.io); all agents using that passport deny within ≤30s.

## Example and tests

- **Example:** [examples/crewai/run_with_guardrail.py](../../examples/crewai/run_with_guardrail.py) — temp config, ALLOW then DENY, `register_aport_guardrail()`.
- **Unit tests:** [python/crewai_adapter/tests/test_hook.py](../../python/crewai_adapter/tests/test_hook.py) — hook return value and context with mocked evaluator.

## Status

Implemented (Story D). **APort Agent Guardrail for CrewAI.** Package: `aport-agent-guardrails-crewai`; CLI: `aport-crewai setup`; hook: `aport_guardrail_before_tool_call` / `register_aport_guardrail` / `with_aport_guardrail`.

# aport-agent-guardrails-autogen

> Pre-action authorization guardrails for [AutoGen](https://microsoft.github.io/autogen/) agents — powered by [APort](https://aport.io).

Enforces OAP policy *before* each tool call executes, at the infrastructure layer — not inside the model prompt.

## Supports

| AutoGen Version | Hook Point | Import |
|-----------------|-----------|--------|
| **0.4.x** (`autogen-agentchat`, `autogen-core`) | `APortGuardedTool` wraps any `BaseTool` / `FunctionTool` | `from aport_guardrails_autogen import APortGuardedTool` |
| **0.4.x** (async functions) | `@with_aport_guardrail` decorates async tool functions | `from aport_guardrails_autogen import with_aport_guardrail` |
| **0.2.x** (`pyautogen`) | `wrap_agent_tools(agent)` patches `function_map` | `from aport_guardrails_autogen import wrap_agent_tools` |

## Installation

```bash
pip install aport-agent-guardrails-autogen

# AutoGen 0.4.x extras:
pip install "aport-agent-guardrails-autogen[autogen4]"

# AutoGen 0.2.x extras:
pip install "aport-agent-guardrails-autogen[autogen2]"
```

## Quick Setup

```bash
aport-autogen
```

Runs the APort passport wizard and writes `~/.aport/autogen/config.yaml`.

## Usage

### AutoGen 0.4.x — APortGuardedTool

Wrap any `BaseTool` or `FunctionTool` with `APortGuardedTool`:

```python
from autogen_core.tools import FunctionTool
from autogen_agentchat.agents import AssistantAgent
from aport_guardrails_autogen import APortGuardedTool

def send_email(recipient: str, body: str) -> str:
    """Send an email."""
    ...

# Wrap with APort guardrails
tool = APortGuardedTool(
    FunctionTool(send_email, description="Send an email")
)

agent = AssistantAgent(
    "EmailAgent",
    model_client=...,
    tools=[tool],  # APort checks run before send_email executes
)
```

When a policy denies the tool call, `GuardrailViolation` is raised before `send_email` runs.

### AutoGen 0.4.x — Decorator

Decorate async (or sync) functions before wrapping with `FunctionTool`:

```python
from autogen_core.tools import FunctionTool
from aport_guardrails_autogen import with_aport_guardrail

@with_aport_guardrail
async def read_file(path: str) -> str:
    with open(path) as f:
        return f.read()

tool = FunctionTool(read_file, description="Read a file")
```

### AutoGen 0.2.x — wrap_agent_tools

Patch `function_map` before starting the conversation:

```python
from autogen import AssistantAgent, UserProxyAgent
from aport_guardrails_autogen import wrap_agent_tools

assistant = AssistantAgent(
    "assistant",
    llm_config={...},
    function_map={"search": search_fn, "send_email": send_email_fn},
)

# Wrap all tools with APort before the chat starts
wrap_agent_tools(assistant)

user_proxy = UserProxyAgent("user_proxy")
user_proxy.initiate_chat(assistant, message="Search for AI news")
```

## Configuration

APort reads config from `.aport/config.yaml` (project) or `~/.aport/autogen/config.yaml` (global).

### Local mode (default)

```yaml
mode: local
passport_path: ~/.aport/autogen/aport/passport.json
```

### API mode

```yaml
mode: api
api_url: https://api.aport.io
agent_id: your-agent-id
api_key: your-api-key
```

### Audit logging

```yaml
audit_log: true   # writes to ~/.aport/autogen/audit.log
# or
audit_log: /var/log/aport/autogen.log
```

## Error Handling

When APort denies a tool call, `GuardrailViolation` is raised:

```python
from aport_guardrails_autogen import APortGuardedTool, GuardrailViolation

tool = APortGuardedTool(my_tool)

try:
    result = await tool.run_json({"recipient": "test@example.com"})
except GuardrailViolation as e:
    print(f"Denied: {e.message} ({e.code})")
    print(f"Reasons: {e.reasons}")
```

## Links

- [APort docs](https://github.com/aporthq/agent-guardrails#readme)
- [AutoGen 0.4.x docs](https://microsoft.github.io/autogen/)
- [OAP Spec](https://github.com/aporthq/aport-spec)
- [Policy packs](https://github.com/aporthq/aport-policies)

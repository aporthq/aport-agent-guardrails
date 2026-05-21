# APort Agent Guardrail — DeerFlow

DeerFlow is a LangGraph-based AI super agent system by ByteDance with sandbox execution, persistent memory, and subagent delegation. The **APort Agent Guardrail for DeerFlow** plugs into DeerFlow's native **middleware chain** via the `GuardrailMiddleware`: every tool call (including dynamically-loaded MCP tools) is evaluated against your passport and policy before execution.

## How DeerFlow agent guardrails work

- **Middleware:** DeerFlow uses an `AgentMiddleware` chain with `wrap_tool_call` / `awrap_tool_call`. The `GuardrailMiddleware` sits between `DanglingToolCallMiddleware` and `ToolErrorHandlingMiddleware` in the chain.
- **Provider protocol:** DeerFlow defines a generic `GuardrailProvider` protocol. Any class with `evaluate(request)` and `aevaluate(request)` methods works. APort's `OAPGuardrailProvider` implements this protocol.
- **Deny handling:** Denied tool calls return a `ToolMessage` with `status="error"` and OAP reason codes (e.g. `oap.command_not_allowed`). The agent sees the denial and can adapt.
- **Fail-closed:** If the provider raises an exception, the tool call is blocked by default.

- **Integration:** DeerFlow `GuardrailMiddleware` (in `_build_runtime_middlewares`)
- **Config:** `config.yaml` guardrails section + `~/.aport/deerflow/config.yaml` for APort settings
- **Provider class path:** `aport_guardrails.providers.generic:OAPGuardrailProvider`

## Two ways to use APort

| Use case | What it is | When to use it |
|----------|------------|----------------|
| **Guardrails (CLI/setup)** | One-line installer: runs the **passport wizard**, writes config, prints next steps. Does not run your app. | Getting started: create passport and config so the provider can find them. |
| **Core (library)** | The **OAPGuardrailProvider** loaded by DeerFlow's `resolve_variable` from your `config.yaml`. Evaluates every tool call. | Integrating into your app: add the guardrails section to config.yaml. |

You typically use **both**: run the CLI once to create passport and config, then add the guardrails section to your DeerFlow `config.yaml`.

---

## Setup (Guardrails — create passport and config)

**Python (recommended)**

```bash
pip install aport-agent-guardrails
aport setup --framework deerflow
```

**Node/npx (alternative)**

```bash
npx @aporthq/aport-agent-guardrails deerflow
# Optional mode flags:
#   --mode=api --api-url=https://api.aport.io
#   --mode=local
```

**Hosted passport (production)**

```bash
npx @aporthq/aport-agent-guardrails deerflow ap_fa2f6d53bb5b4c98b9af0124285b6e0f
```

The setup creates:
- Config directory: `~/.aport/deerflow/`
- Passport file: `~/.aport/deerflow/aport/passport.json`
- Config file: `~/.aport/deerflow/config.yaml`

## Using the library (Core) in your DeerFlow app

### Step 1: Install the package

```bash
uv add aport-agent-guardrails
# or: pip install aport-agent-guardrails
```

### Step 2: Add guardrails to config.yaml

Add this section to your DeerFlow `config.yaml`:

```yaml
guardrails:
  enabled: true
  fail_closed: true
  passport: ~/.aport/deerflow/aport/passport.json
  provider:
    use: aport_guardrails.providers.generic:OAPGuardrailProvider
```

That's it. Every tool call is now evaluated before execution.

### Step 3 (optional): Use a hosted passport

For production, use a hosted passport ID instead of a local file:

```yaml
guardrails:
  enabled: true
  passport: ap_fa2f6d53bb5b4c98b9af0124285b6e0f
  provider:
    use: aport_guardrails.providers.generic:OAPGuardrailProvider
```

---

## How it works under the hood

1. DeerFlow's `_build_runtime_middlewares()` reads `guardrails` from `config.yaml`
2. It loads `OAPGuardrailProvider` via `resolve_variable` (same mechanism as models and sandbox providers)
3. `GuardrailMiddleware` wraps every tool call:
   - Builds a `GuardrailRequest` with tool name, arguments, and passport reference
   - Calls `provider.evaluate(request)` (sync) or `provider.aevaluate(request)` (async)
   - If denied: returns a `ToolMessage` with error status and OAP reason codes
   - If allowed: calls the original tool handler
4. `OAPGuardrailProvider` maps the tool name to an OAP policy pack ID and calls the core `Evaluator`
5. The `Evaluator` resolves the passport (local file or hosted API) and evaluates the tool call

## Tool-to-policy mapping

| DeerFlow tool | OAP policy pack | Passport capability |
|---|---|---|
| `bash` | `system.command.execute.v1` | `system.command.execute` |
| `write_file`, `str_replace` | `data.file.write.v1` | `data.file.write` |
| `web_search`, `web_fetch`, `image_search` | `web.fetch.v1` | `web.fetch` |
| `read_file`, `ls`, `present_file`, `view_image` | `data.file.read.v1` | `data.file.read` |
| `git.create_pr`, `git.*` | `code.repository.merge.v1` | `repo.merge` / `repo.pr.create` |
| `messaging.send`, `message.*` | `messaging.message.send.v1` | `messaging.message.send` |
| `ask_clarification`, `task` | `agent.session.create.v1` | `agent.session.create` |
| MCP tools (`mcp.*`, dynamic names) | `mcp.tool.execute.v1` | `mcp.tool.execute` |

Mapping is implemented in `packages/core/src/core/tool-pack-mapping.json` (via `tool_to_pack_id()`). DeerFlow passes the raw tool name from each tool invocation.

## Evaluation modes

| Mode | Config | Network | Use case |
|---|---|---|---|
| **Local** | `mode: local` in APort config | None | Dev, CI, air-gapped |
| **API** | `mode: api` in APort config | API call to aport.io | Full OAP features, signed decisions |
| **Hosted passport** | `passport: ap_xxx` in DeerFlow config | API call | Production, managed passports |

## Built-in AllowlistProvider (no APort needed)

DeerFlow ships with a zero-dependency `AllowlistProvider` for simple deny/allow:

```yaml
guardrails:
  enabled: true
  provider:
    use: deerflow.guardrails.builtin:AllowlistProvider
    config:
      denied_tools: ["bash", "write_file"]
```

## Custom provider (bring your own)

Any class with `evaluate` and `aevaluate` methods works:

```python
class MyGuardrail:
    name = "my-company"
    def evaluate(self, request):
        from deerflow.guardrails.provider import GuardrailDecision, GuardrailReason
        if request.tool_name == "bash":
            return GuardrailDecision(allow=False, reasons=[GuardrailReason(code="oap.denied", message="bash blocked")])
        return GuardrailDecision(allow=True, reasons=[GuardrailReason(code="oap.allowed")])
    async def aevaluate(self, request):
        return self.evaluate(request)
```

```yaml
guardrails:
  enabled: true
  provider:
    use: my_module:MyGuardrail
```

## Kill switch

- **Local:** Set `"status": "suspended"` in your passport JSON file
- **Hosted:** Log in to aport.io, click Suspend — all agents using that passport deny within 30 seconds

## References

- [DeerFlow GitHub issue #1213](https://github.com/bytedance/deer-flow/issues/1213)
- [OAP Specification](https://doi.org/10.5281/zenodo.18901595)
- [Verification methods](../VERIFICATION_METHODS.md)
- [Hosted passport setup](../HOSTED_PASSPORT_SETUP.md)

# APort Agent Guardrail for DeerFlow

DeerFlow is ByteDance's LangGraph-based agent harness with sandbox execution, persistent memory, and subagent delegation. Since v2.0.0 the harness ships a `guardrails` block in `config.yaml` and a `GuardrailMiddleware` that evaluates every tool call before it runs, including dynamically loaded MCP tools. APort's `OAPGuardrailProvider` is loaded into that slot by class path. No DeerFlow-specific adapter package is needed.

Checked against DeerFlow v2.1.0-rc0 (tag 769589e8, 2026-09-24) and `backend/docs/GUARDRAILS.md` at that tag.

## How DeerFlow guardrails work (v2.1)

- **Middleware:** `GuardrailMiddleware` (`deerflow/guardrails/middleware.py`) is an `AgentMiddleware` that implements `wrap_tool_call` and `awrap_tool_call`. It is assembled in `_build_runtime_middlewares()` in `deerflow/agents/middlewares/tool_error_handling_middleware.py`. Both `build_lead_runtime_middlewares()` and `build_subagent_runtime_middlewares()` call that builder, so subagents spawned through `task` get the same guard and the same identity context as the lead agent.
- **Chain position:** after `DanglingToolCallMiddleware`, `LLMErrorHandlingMiddleware`, the optional `ToolReceiptMiddleware`, and the optional authorization guard (see below); before `SandboxAuditMiddleware`, `ReadBeforeWriteMiddleware`, `ToolProgressMiddleware`, and `ToolErrorHandlingMiddleware`. `deerflow/extensions/ordering.py` enforces that the receipt layer stays outside the guardrail so denied calls still get a receipt.
- **Provider protocol:** `GuardrailProvider` is a structural protocol: a `name` attribute plus `evaluate(request)` and `aevaluate(request)` returning a decision with `allow`, `reasons` (each with `code` and `message`), `policy_id`, and `metadata`. No base class. APort's `OAPGuardrailProvider` returns objects with exactly those attributes.
- **Provider loading:** `provider.use` is resolved with `resolve_variable()`, the same loader DeerFlow uses for models, tools, and sandbox providers. `provider.config` is passed to the constructor as keyword arguments. DeerFlow adds `framework="deerflow"` when the constructor accepts a `framework` parameter or `**kwargs`. APort's constructor accepts `framework`, and that value is how it finds `~/.aport/deerflow/config.yaml`.
- **Deny handling:** a denied call returns a `ToolMessage` with `status="error"` and the first reason code (for example `oap.command_not_allowed`). The agent sees the message and can choose another approach.
- **Fail-closed:** `fail_closed: true` (the default) blocks the call when the provider raises. The recorded reason code is `oap.evaluator_error`.
- **Audit:** every decision is written to the run journal as a `middleware:guardrail` event and to the authorization outcome store keyed by `tool_call_id`.

## What changed in DeerFlow 2.1

| Upstream change | Effect on the APort integration |
|---|---|
| New `authorization` block (RBAC `AuthorizationProvider`, `enabled: false` by default). Filters tools out of the model's catalog and reuses `GuardrailMiddleware` through an adapter for execution-time denies. | Runs as a second `GuardrailMiddleware` instance placed outside the APort one. A tool the RBAC layer denies never reaches APort. A tool it allows is still evaluated by APort. The two are independent; enable either or both. |
| New `extensions.middlewares` list: register any `AgentMiddleware` class from `config.yaml` or `extensions_config.json`. | Not needed. Keep using the `guardrails` block; it is the slot that receives the passport reference, fail-closed handling, and journal events. |
| `GuardrailRequest` gained optional attribution fields: `user_id`, `user_role`, `oauth_provider`, `oauth_id`, `run_id`, `tool_call_id`, `channel_user_id`, `is_internal`, `authz_attributes`. The Gateway fills them from server-side auth state; client-supplied values cannot override them. | APort reads `tool_name` and `tool_input` only, so nothing breaks. The extra fields are available to a wrapper provider that wants per-user policy or richer audit records. |
| `present_file` renamed to `present_files`. New built-ins: `glob`, `grep`, `batch_task`, `tool_search`, `skill_manage`. | `present_files`, `glob`, and `grep` map to `data.file.read.v1`. The others fall to the mapping default; see the table below. |
| MCP tools are exposed as `<server_name>_<tool>` (`tool_name_prefix: true` is the default) and tagged with `deerflow_mcp` metadata. | The guardrail request carries only the tool name, so APort cannot tell an MCP tool from a built-in by name. See the MCP row in the mapping table. |
| `make config` replaced by the `make setup` wizard, which writes a minimal `config.yaml`. | The wizard does not add a `guardrails` block. Add it by hand as shown below. |

## Two ways to use APort

| Use case | What it is | When to use it |
|----------|------------|----------------|
| **Guardrails (CLI/setup)** | One-line installer: runs the passport wizard, writes config, prints next steps. Does not run your app. | First run: create the passport and config so the provider can find them. |
| **Core (library)** | The `OAPGuardrailProvider` that DeerFlow loads from `config.yaml` and calls on every tool call. | In the DeerFlow backend: add the `guardrails` block to `config.yaml`. |

Run the CLI once, then add the `guardrails` block.

## Setup (create passport and config)

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
#   --enforcement=warn   # explicit report-only rollout; default is enforce/fail-closed
```

**Hosted passport (production)**

```bash
npx @aporthq/aport-agent-guardrails deerflow ap_fa2f6d53bb5b4c98b9af0124285b6e0f
```

The setup creates:
- Config directory: `~/.aport/deerflow/`
- Passport file: `~/.aport/deerflow/aport/passport.json`
- Config file: `~/.aport/deerflow/config.yaml`

Set `APORT_DEERFLOW_CONFIG_DIR=<dir>` before either setup command to use a different directory, then point `guardrails.passport` in DeerFlow's `config.yaml` at `<dir>/aport/passport.json`.

## Add guardrails to the DeerFlow backend

### Step 1: Install the package

```bash
cd backend
uv add aport-agent-guardrails
# or: pip install aport-agent-guardrails
```

### Step 2: Add the guardrails block to config.yaml

```yaml
guardrails:
  enabled: true
  fail_closed: true
  passport: ~/.aport/deerflow/aport/passport.json
  provider:
    use: aport_guardrails.providers.generic:OAPGuardrailProvider
    config:
      enforcement_mode: enforce
```

Every tool call is now evaluated before execution. Config keys, as defined in `deerflow/config/guardrails_config.py`:

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Turn the middleware on. |
| `fail_closed` | `true` | Block the call if the provider raises. |
| `passport` | `null` | Passed to the provider as `request.agent_id`. A file path, a hosted passport ID, or null (APort then reads the passport path from its own config). |
| `provider.use` | required | `package.module:ClassName`. |
| `provider.config` | `{}` | Keyword arguments for the provider constructor. APort accepts `enforcement_mode` and `config_path`. Any other key raises `TypeError` at agent creation, because DeerFlow passes the dict straight to `__init__`. |

### Step 3 (optional): Use a hosted passport

```yaml
guardrails:
  enabled: true
  passport: ap_fa2f6d53bb5b4c98b9af0124285b6e0f
  provider:
    use: aport_guardrails.providers.generic:OAPGuardrailProvider
    config:
      enforcement_mode: enforce
```

## What happens on each tool call

1. `_build_runtime_middlewares()` reads `guardrails` from `AppConfig` (loaded from `config.yaml`).
2. It resolves `OAPGuardrailProvider` with `resolve_variable`, builds it with `provider.config` plus `framework="deerflow"`, and appends `GuardrailMiddleware(provider, fail_closed=..., passport=...)` to the chain.
3. On each tool call the middleware builds a `GuardrailRequest` with the tool name, arguments, passport reference, and the attribution fields from the runtime context, then calls `provider.evaluate` (sync) or `provider.aevaluate` (async).
4. `OAPGuardrailProvider` maps the tool name to an OAP policy pack with `tool_to_pack_id()`, flattens the tool arguments into the evaluator context, and calls the core `Evaluator`.
5. The `Evaluator` resolves the passport (local file or hosted API) and returns allow or deny with OAP reason codes.
6. Deny: the middleware returns the error `ToolMessage`. Allow: the original tool handler runs.

## Tool-to-policy mapping

Generated from `tool_to_pack_id()` against the tool names DeerFlow v2.1.0-rc0 registers.

| DeerFlow tool | OAP policy pack | Passport capability |
|---|---|---|
| `bash` | `system.command.execute.v1` | `system.command.execute` |
| `write_file`, `str_replace` | `data.file.write.v1` | `data.file.write` |
| `read_file`, `ls`, `glob`, `grep`, `present_files`, `view_image` | `data.file.read.v1` | `data.file.read` |
| `web_search`, `web_fetch`, `image_search` | `web.fetch.v1` | `web.fetch` |
| `ask_clarification`, `task`, `batch_task`, `tool_search`, `skill_manage`, `setup_agent`, `update_agent`, `invoke_acp_agent` | `system.command.execute.v1` (mapping default; no dedicated rule) | `system.command.execute` |
| MCP tools, named `<server_name>_<tool>` | `system.command.execute.v1` unless the name happens to match another rule (for example a tool called `github_write_file` would match `write_file` only if it started with it, which it does not). Names starting with `mcp.` map to `mcp.tool.execute.v1`, but DeerFlow does not produce that spelling. | `system.command.execute` |

The mapping lives in `packages/core/src/core/tool-pack-mapping.json`. Prefix matching is case-insensitive. DeerFlow passes the raw tool name from each invocation; it does not pass the `deerflow_mcp` metadata tag.

## Evaluation modes

| Mode | Config | Network | Use case |
|---|---|---|---|
| **Local** | `mode: local` in APort config | None | Dev, CI, air-gapped |
| **API** | `mode: api` in APort config | API call to aport.io | Full OAP features, signed decisions |
| **Hosted passport** | `passport: ap_xxx` in DeerFlow config | API call | Production, managed passports |

Default enforcement is `enforce`: denied decisions block through DeerFlow's guardrail middleware. Set `enforcement_mode: warn` only for a report-only rollout; APort keeps the original deny decision in result metadata while letting the tool call continue.

## Built-in AllowlistProvider (no APort needed)

DeerFlow ships a zero-dependency `AllowlistProvider` for plain allow or deny by tool name:

```yaml
guardrails:
  enabled: true
  provider:
    use: deerflow.guardrails.builtin:AllowlistProvider
    config:
      denied_tools: ["bash", "write_file"]
```

## Custom provider (bring your own)

Any class with `evaluate` and `aevaluate` methods works. Accept `**kwargs` so future constructor hints from DeerFlow do not break it:

```python
class MyGuardrail:
    name = "my-company"

    def __init__(self, framework: str = "generic", **kwargs):
        pass

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

- **Local:** set `"status": "suspended"` in your passport JSON file.
- **Hosted:** log in to aport.io and click Suspend. Every agent using that passport denies within 30 seconds.

## References

- [DeerFlow `backend/docs/GUARDRAILS.md`](https://github.com/bytedance/deer-flow/blob/v2.1.0-rc0/backend/docs/GUARDRAILS.md)
- [DeerFlow `config.example.yaml`, Guardrails and Authorization sections](https://github.com/bytedance/deer-flow/blob/v2.1.0-rc0/config.example.yaml)
- [DeerFlow GitHub issue #1213](https://github.com/bytedance/deer-flow/issues/1213) (the original guardrails request)
- [OAP Specification](https://doi.org/10.5281/zenodo.18901595)
- [Verification methods](../VERIFICATION_METHODS.md)
- [Hosted passport setup](../HOSTED_PASSPORT_SETUP.md)

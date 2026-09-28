# DeerFlow integration

**APort Agent Guardrail for DeerFlow**: pre-action authorization through DeerFlow's built-in `GuardrailMiddleware` (DeerFlow v2.0.0 or later; checked against v2.1.0-rc0).

## Setup (one command)

```bash
npx @aporthq/aport-agent-guardrails deerflow
```

Then install the Python package in the DeerFlow backend:

```bash
cd backend
uv add aport-agent-guardrails
```

## config.yaml

The `make setup` wizard does not add this block. Add it by hand:

```yaml
guardrails:
  enabled: true
  fail_closed: true
  passport: ~/.aport/deerflow/aport/passport.json
  provider:
    use: aport_guardrails.providers.generic:OAPGuardrailProvider
```

## How it works

DeerFlow loads the provider by class path with `resolve_variable`, passes `provider.config` to the constructor plus `framework="deerflow"`, and appends `GuardrailMiddleware` to the runtime chain built in `deerflow/agents/middlewares/tool_error_handling_middleware.py`. Lead agent and subagents share that builder. Denied calls come back to the model as an error `ToolMessage` with an OAP reason code.

Uses the generic `OAPGuardrailProvider` from the core `aport-agent-guardrails` package. No DeerFlow-specific adapter package is needed.

Evaluation modes:
- **Local** (default): passport JSON + local evaluator, no network
- **Hosted**: `passport: ap_abc123...` resolves through the aport.io API

Things to know in DeerFlow 2.1:
- The new `authorization` block (RBAC) is a separate outer guard. Tools it denies never reach APort.
- MCP tools are named `<server_name>_<tool>`, so they map to APort's default pack (`system.command.execute.v1`) unless the name matches another mapping rule.
- `present_file` is now `present_files`; it still maps to `data.file.read.v1`.

## Implementation

- **Provider:** [python/aport_guardrails/providers/generic.py](../../python/aport_guardrails/providers/generic.py)
- **Config:** `~/.aport/deerflow/` or `.aport/config.yaml`
- **Setup:** `npx @aporthq/aport-agent-guardrails deerflow` or `aport setup --framework deerflow`

See [docs/frameworks/deerflow.md](../../docs/frameworks/deerflow.md).

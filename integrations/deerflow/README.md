# DeerFlow integration

**APort Agent Guardrail for DeerFlow** - pre-action authorization via DeerFlow's `GuardrailMiddleware`.

## Setup (one command)

```bash
npx @aporthq/aport-agent-guardrails deerflow
```

Then install the Python package and configure:

```bash
uv add aport-agent-guardrails
```

## config.yaml

```yaml
guardrails:
  enabled: true
  passport: ~/.aport/deerflow/aport/passport.json
  provider:
    use: aport_guardrails.providers.generic:OAPGuardrailProvider
```

## How it works

Uses the generic `OAPGuardrailProvider` from the core `aport-agent-guardrails`
package. No DeerFlow-specific adapter package needed.

Evaluation modes:
- **Local** (default): passport JSON + local evaluator, zero network
- **Hosted**: `passport: ap_abc123...` resolves via aport.io API

## Implementation

- **Provider:** [python/aport_guardrails/providers/generic.py](../../python/aport_guardrails/providers/generic.py)
- **Config:** `~/.aport/deerflow/` or `.aport/config.yaml`
- **Setup:** `npx @aporthq/aport-agent-guardrails deerflow` or `aport setup --framework deerflow`

See [docs/frameworks/deerflow.md](../../docs/frameworks/deerflow.md).

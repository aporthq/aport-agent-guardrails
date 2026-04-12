# OAPGuardrailProvider

APort ships a generic `OAPGuardrailProvider` for both Python and TypeScript. It implements whatever `GuardrailProvider` interface the target framework defines, wraps the core `Evaluator`, and works with any framework — no framework-specific code.

## Architecture

```
Framework defines interface          APort implements it
────────────────────────             ───────────────────
DeerFlow: GuardrailProvider    ←──   Python OAPGuardrailProvider
OpenClaw: GuardrailProvider    ←──   TypeScript OAPGuardrailProvider
Your framework: same shape     ←──   Same class, same language
```

One provider per language. The core evaluation logic (tool mapping, passport loading, local/API mode, audit logging) is shared.

## Python

**Package:** `aport-agent-guardrails` (pip/uv)

```python
from aport_guardrails.providers import OAPGuardrailProvider

provider = OAPGuardrailProvider(framework="deerflow")
result = provider.evaluate(request)   # sync
result = await provider.aevaluate(request)  # async
```

**Supported frameworks:** DeerFlow, CrewAI builds with native provider support, and any Python framework with a `GuardrailProvider` protocol.

**Config:** `~/.aport/<framework>/config.yaml` (created by `aport setup --framework <name>`)

**DeerFlow config.yaml:**
```yaml
guardrails:
  enabled: true
  provider:
    use: aport_guardrails.providers.generic:OAPGuardrailProvider
```

## TypeScript

**Package:** `@aporthq/aport-agent-guardrails-core` (npm)

```typescript
import { OAPGuardrailProvider } from "@aporthq/aport-agent-guardrails-core";

const provider = new OAPGuardrailProvider({ framework: "openclaw" });
const decision = await provider.evaluate(request);  // async
const decision = provider.evaluateSync(request);     // sync
```

**Supported frameworks:** OpenClaw, any TypeScript framework with a `GuardrailProvider` interface.

**Config:** `~/.openclaw/aport/config.yaml` or `~/.aport/<framework>/config.yaml`

**OpenClaw config.yaml:**
```yaml
guardrails:
  enabled: true
  provider:
    use: "@aporthq/aport-agent-guardrails-core"
    config:
      framework: "openclaw"
```

## What the provider does

1. **Receives** `{ toolName, toolInput }` from the framework
2. **Maps** tool name → OAP policy pack ID (e.g. `exec` → `system.command.execute.v1`)
3. **Loads** passport from local file or hosted agent ID
4. **Evaluates** locally (bash script, zero network) or via API (hosted evaluator)
5. **Returns** `{ allow, reasons, policyId }` to the framework

## Evaluation modes

| Mode | Network | Latency | Use case |
|---|---|---|---|
| **Local** (default) | None | ~300ms | Development, CI, air-gapped |
| **API** | Yes | ~65ms | Production, signed decisions, centralized dashboards |

## Adding a new framework

1. Check if the framework has a `GuardrailProvider` interface (or equivalent hook)
2. Use the existing Python or TypeScript `OAPGuardrailProvider` — it's framework-agnostic
3. Point the framework config at the provider class/package
4. Run `npx @aporthq/aport-agent-guardrails <framework>` to create a passport
5. Add a doc at `docs/frameworks/<framework>.md`

No new provider code needed. The same `OAPGuardrailProvider` works for any framework in the same language.

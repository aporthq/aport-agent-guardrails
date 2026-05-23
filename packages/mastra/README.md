# @aporthq/aport-agent-guardrails-mastra

OAP (Open Agent Protocol) guardrails for [Mastra](https://mastra.ai) agents. Add deterministic tool-call authorization to Mastra's processor pipeline with policy-as-YAML configuration.

## Installation

```bash
npm install @aporthq/aport-agent-guardrails-mastra
```

## Quick Start

```typescript
import { Agent } from '@mastra/core';
import { OAPToolProcessor } from '@aporthq/aport-agent-guardrails-mastra';

const agent = new Agent({
  processors: [new OAPToolProcessor('./oap-policy.yaml')],
  tools: { 
    webSearch, 
    readFile,
    bashExecutor, // This will be blocked by policy
  },
});
```

## Policy Configuration

Create an `oap-policy.yaml` file:

```yaml
version: "1.0"
agent: "my-mastra-agent"

tools:
  allowed:
    - name: "web_search"
      max_calls_per_session: 20
    - name: "read_file"
      paths: ["./data/**", "./docs/**"]
  
  denied:
    - "bash"
    - "delete_file"
    - "exec"

audit:
  receipts: true
  destination: "./oap-receipts/"
```

## Usage

### Basic Usage

```typescript
import { OAPToolProcessor } from '@aporthq/aport-agent-guardrails-mastra';

const processor = new OAPToolProcessor('./oap-policy.yaml');

const agent = new Agent({
  processors: [processor],
  tools: { webSearch, readFile },
});
```

### With Configuration Object

```typescript
const processor = new OAPToolProcessor({
  policyPath: './custom-policy.yaml',
  framework: 'mastra',
  failOpenWhenMissing: false,
  onReceipt: (receipt) => {
    console.log('OAP Receipt:', receipt);
  },
});
```

### Handling Authorization Errors

```typescript
import { OAPAuthorizationError } from '@aporthq/aport-agent-guardrails-mastra';

try {
  const result = await agent.generate('Search for recent news');
} catch (error) {
  if (error instanceof OAPAuthorizationError) {
    console.log('Tool blocked:', error.toolName);
    console.log('Receipt:', error.receipt);
    // Handle blocked tool gracefully
  }
}
```

## How It Works

The `OAPToolProcessor` integrates with Mastra's processor pipeline:

1. **Before Tool Call**: The processor intercepts tool invocations before they execute
2. **Policy Evaluation**: Each tool call is evaluated against your YAML policy
3. **Decision**: 
   - **Allowed**: The tool executes normally, an audit receipt is emitted
   - **Denied**: An `OAPAuthorizationError` is thrown with a receipt

## Audit Receipts

When a tool is called (allowed or denied), an `oap:receipt` event is emitted:

```typescript
{
  receiptId: "550e8400-e29b-41d4-a716-446655440000",
  tool: "web_search",
  agent: "my-agent-id",
  allowed: true,
  timestamp: "2026-05-23T10:00:00.000Z",
  reason: undefined // Only present when denied
}
```

Listen for receipts in your agent context:

```typescript
const agent = new Agent({
  processors: [processor],
  tools: { webSearch },
  onEvent: (event) => {
    if (event.type === 'oap:receipt') {
      // Log to your audit system
      auditLog.record(event.payload);
    }
  },
});
```

## API Reference

### `OAPToolProcessor`

Main processor class that integrates with Mastra.

#### Constructor

```typescript
new OAPToolProcessor(policyPath: string)
new OAPToolProcessor(config: OAPToolProcessorConfig)
```

#### `OAPToolProcessorConfig`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `policyPath` | `string` | (required) | Path to OAP policy YAML file |
| `framework` | `string` | `"mastra"` | Framework identifier |
| `failOpenWhenMissing` | `boolean` | `false` | Allow calls when policy missing |
| `onReceipt` | `(receipt: OAPReceipt) => void` | - | Custom receipt handler |

### `OAPAuthorizationError`

Error thrown when a tool call is blocked by policy.

```typescript
class OAPAuthorizationError extends Error {
  readonly receipt: OAPReceipt;
  readonly toolName: string;
  readonly isOAPError: true;
}
```

## Why OAP + Mastra?

Mastra's built-in guardrails focus on **content safety** (what the agent says). OAP focuses on **action authorization** (what the agent is allowed to **do**).

| Aspect | Mastra Guardrails | OAP Authorization |
|--------|-------------------|-------------------|
| Focus | Content safety | Tool permissions |
| Question | "Is this output appropriate?" | "Is this action allowed?" |
| Policy | Content filters | YAML tool policies |
| Audit | Limited | Full receipt trail |

You need both: content guardrails for safe outputs, OAP for safe actions.

## License

Apache-2.0 — See [LICENSE](./LICENSE) for details.

## Links

- [APort Documentation](https://aport.io/ai-agent-guardrail/mastra/)
- [Mastra Documentation](https://mastra.ai/docs)
- [GitHub Issues](https://github.com/aporthq/aport-agent-guardrails/issues)
- [OAP Specification](https://aport.io/oap/)
# n8n integration

**Coming soon.** n8n support is not yet available.

Framework-specific code for APort guardrails on n8n (when shipped).

## Implementation

- **Integration pattern:** Custom node or HTTP Request node to APort API; branch on allow/deny before action nodes.
- **Config / credentials:** n8n credentials store (agent_id or passport); config dir `~/.n8n` (see [bin/lib/config.sh](../../bin/lib/config.sh)).
- **Setup:** `npx @aporthq/aport-agent-guardrails --framework=n8n`.

## Directories

- **nodes/** — Placeholder for custom APort Guardrail node (e.g. Node.js node that calls evaluator).
- **credentials/** — Placeholder for n8n credential type for APort (agent_id / passport).

## Usage

1. Install custom node to `~/.n8n/custom/` or use HTTP Request node to APort API.
2. In workflow: add APort Guardrail node before action nodes; branch on allow/deny.
3. Store agent_id or passport in n8n credentials.

See [docs/frameworks/n8n.md](../../docs/frameworks/n8n.md).

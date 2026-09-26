# n8n integration

**Setup only.** The CLI writes a passport and config under `~/.n8n`. No APort node is published yet.

## Implementation

- **Integration pattern today:** a sub-workflow used as a tool (*Call n8n Workflow* tool on the AI Agent node, or a workflow tool in the preview Agent Builder). Inside it, an HTTP Request node calls the APort verify API (`POST /api/verify/policy/<pack_id>`), an IF node branches on `decision.allow`, and the action node sits on the true branch.
- **Config / credentials:** agent ID and API key in the n8n credentials store; config dir `~/.n8n` (see [bin/lib/config.sh](../../bin/lib/config.sh)).
- **Setup:** `npx @aporthq/aport-agent-guardrails --framework=n8n`.

## Directories

- **nodes/**: placeholder for a future APort Guardrail community node.
- **credentials/**: placeholder for the matching n8n credential type (agent ID and API key).

When the node ships it will be installed from Settings > Community Nodes on self-hosted n8n (`~/.n8n/custom/` for local builds).

See [docs/frameworks/n8n.md](../../docs/frameworks/n8n.md).

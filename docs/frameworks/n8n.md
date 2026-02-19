# APort Guardrails — n8n

**Coming soon.** n8n support is not yet available; custom node and runtime integration are in progress.

**How guardrails work (planned):** n8n workflows run as a graph of nodes. We provide a custom **APort Guardrail** node that calls the evaluator (API or local); the node outputs allow/deny. You place it **before** action nodes and branch on the result (e.g. IF node on allow) so that only allowed actions run. No code; guardrail is enforced by workflow structure.

- **Integration:** Custom node (or HTTP Request node to APort API) before action nodes; branch on allow/deny
- **Config:** n8n credentials store (agent_id or passport)

## Two ways to use APort (planned)

| Use case | What it is | When to use it |
|----------|------------|----------------|
| **Guardrails (CLI/setup)** | Installer: runs the **passport wizard**, writes config; (when shipped) installs the **custom node** so workflows can use the APort Guardrail node. | Getting started: create passport and config; install the node so it appears in n8n. |
| **Core (library / node)** | The **evaluator** and **custom node**: your workflow calls the node before an action; the node returns allow/deny so you can branch. The npm package `@aporthq/aport-agent-guardrails-n8n` is not published yet. | When available: add the APort Guardrail node before action nodes and branch on the result. |

n8n support is **coming soon**; the custom node and npm package are not yet released.

---

## Setup

```bash
npx @aporthq/aport-agent-guardrails n8n
# Runs passport wizard and writes config only. Custom node is NOT yet available.
# When the node is released, it will install to ~/.n8n/custom/ and you will restart n8n.
```

## Config

- **Credentials:** n8n credentials store (agent_id or passport)
- **Workflow:** Drag "APort Guardrail" node before action; branch on allow/deny.

## Suspend (kill switch)

Same standard as all frameworks: **passport is the source of truth**—no separate file. Local: set passport `status` to `suspended` (or `active` to resume). Remote: use API mode and suspend in [APort](https://aport.io); all agents using that passport deny within ≤30s.

## Status

High priority (Phase 3).

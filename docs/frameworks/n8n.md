# APort Guardrails for n8n

**Status: setup only.** `npx @aporthq/aport-agent-guardrails n8n` creates a passport and config under `~/.n8n`. There is no APort runtime node yet, and the npm package `@aporthq/aport-agent-guardrails-n8n` is not published. Everything below about putting a check into a workflow uses nodes n8n already ships.

Checked against the n8n docs on 2026-09-24: the Tools AI Agent node page and the preview "Build and manage agents" page.

## What n8n offers today

n8n has two places where a model decides to call a tool:

1. **AI Agent node (Tools Agent)** in a regular workflow. Tools attach as sub-nodes: *Call n8n Workflow*, *Code*, *HTTP Request*, and most app nodes (Slack, GitHub, Google Sheets, and so on). The model can fill tool parameters with `$fromAI()`. The node has a *Human review for tool calls* option: connect the tools that need sign-off to a human review step and the workflow pauses for approval over Chat, Slack, Telegram, or another channel.
2. **Agents (Preview)** built in the Agent Builder. Tools are built-in integrations, workflows from the same project, custom tools defined by a JSON schema, and MCP servers. Sensitive tools can require approval (*Approve tool calls*). Agents run on n8n Cloud and on self-hosted n8n from 2.32.3 with `agents` added to `N8N_ENABLED_MODULES`; queue mode is not supported yet. An agent can also be dropped into a workflow as a node, or messaged from a workflow.

Neither surface exposes a hook that runs before every tool call. A policy check therefore has to live inside the tool.

## Where a policy check goes

### Option 1: wrap the action in a sub-workflow (works on both surfaces)

Make the tool a *Call n8n Workflow* tool (AI Agent node) or a workflow tool (Agent Builder). The sub-workflow does the check before the action:

1. **HTTP Request** node: `POST https://api.aport.io/api/verify/policy/<pack_id>` (or your own `APORT_API_URL`) with JSON body `{"context": {"agent_id": "ap_...", ...}}`. Pick the pack for the action, for example `messaging.message.send.v1` or `system.command.execute.v1`, and put the action's fields (recipient, command, and so on) inside `context`. If your organization requires an API key, send `Authorization: Bearer <key>` from an n8n Header Auth credential. If you want to use the local passport file instead of a hosted ID, send its JSON as a top-level `passport` field; the verifier evaluates it without storing it.
2. **IF** node on the decision. The response nests the result under `decision`; check `decision.allow` and fall back to a top-level `allow` if that key is absent.
3. True branch: the action node. False branch: return `decision.reasons` so the model sees why the call was denied and can adjust.

### Option 2: a Code node

The same request can be made from a *Code* tool or *Code* node when you want the check and the action in one place. Keep the agent ID and key in credentials or environment variables rather than in the script.

### Option 3: human review

n8n's own *Human review for tool calls* (AI Agent node) and *Approve tool calls* (Agent Builder) pause for a person. Use them for tools a human should sign off on. They do not replace the policy check: approval is manual, and the passport kill switch does not reach it.

### When the APort node ships

Community nodes install from **Settings > Community Nodes** (an `n8n-nodes-*` npm package) on self-hosted n8n; `~/.n8n/custom/` is for local development builds. n8n Cloud installs only verified community nodes. Until the node exists, the sub-workflow pattern above is the supported route.

## Setup

```bash
npx @aporthq/aport-agent-guardrails n8n
# Optional mode flags:
#   --mode=api --api-url=https://api.aport.io
#   --mode=local
#   --enforcement=warn   # stores explicit report-only config for a future node or runtime
# Runs the passport wizard and writes config only. No n8n node is installed.
```

For n8n, prefer a hosted passport (`ap_...` from aport.io). The HTTP Request node cannot run APort's local bash evaluator, so local mode only matters if you run the check outside n8n.

Set `APORT_N8N_CONFIG_DIR=<dir>` to write the passport and config somewhere other than `~/.n8n`.

## Config

- **Files:** `~/.n8n/aport/passport.json` and `~/.n8n/config.yaml` (written by setup)
- **Credentials:** keep the agent ID and API key in the n8n credentials store, not in workflow JSON
- **Workflow:** a sub-workflow tool that calls the verify API and branches on `decision.allow`, as above

## Suspend (kill switch)

Same standard as every framework: the passport is the source of truth. There is no separate file. Local: set the passport `status` to `suspended` (or back to `active`). Remote: use API mode and suspend in [APort](https://aport.io); every agent using that passport denies within 30 seconds.

## Status

Setup available. Runtime node not shipped. See [FRAMEWORK_ROADMAP.md](../FRAMEWORK_ROADMAP.md).

---
name: aport-guardrail
description: Pre-action authorization for tools (bash, messaging, git, MCP, data export). The APort policy engine allows or denies every tool call deterministically before it runs.
homepage: https://aport.io
metadata: {"openclaw":{"requires":{"bins":["jq"]}}}
---

# APort Guardrail

Pre-action authorization for OpenClaw: every tool call is checked **before** it runs. Run the installer once; the OpenClaw plugin then enforces policy on every tool call automatically. You do **not** run the guardrail script yourself.

> Requires: Node 18+, jq. Install with `npx @aporthq/agent-guardrails` or `./bin/openclaw` from the repo.

## Installation

```bash
# Recommended (no clone needed)
npx @aporthq/agent-guardrails

# Hosted passport: skip the wizard by passing agent_id from aport.io
npx @aporthq/agent-guardrails <agent_id>
```

Get a Hosted Passport **agent_id** at [aport.io](https://aport.io/builder/create/) after creating a passport there. __*OPTIONAL*__

From the repo (clone first): [github.com/aporthq/aport-agent-guardrails](https://github.com/aporthq/aport-agent-guardrails) — then run `./bin/openclaw` or `./bin/openclaw <agent_id>` from the repo root.

You can preview your local passport at `~/.openclaw/aport/passport.json` (or `<config-dir>/aport/passport.json` if you chose a different config dir; legacy installs may use `<config-dir>/passport.json`).

The installer is interactive: it sets your config dir, passport (local or hosted), installs the APort OpenClaw plugin, writes config, and installs wrappers. **After it finishes, nothing else is required**—start OpenClaw (or use the running gateway); the plugin enforces before every tool call.

Wrappers (default config dir `~/.openclaw`): `~/.openclaw/.skills/aport-guardrail.sh` (local), `~/.openclaw/.skills/aport-guardrail-api.sh` (API/hosted). The plugin uses these; you don’t call them unless testing.

## Usage

**Normal use:** Run the installer once. After that, nothing to run manually—the plugin enforces before each tool call automatically.

**Optional — direct script calls** (e.g. testing or other automations):

```bash
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"ls"}'
~/.openclaw/.skills/aport-guardrail.sh messaging.message.send '{"channel":"whatsapp","to":"+15551234567"}'
```

- Exit 0 = ALLOW (tool may proceed)
- Exit 1 = DENY (see `<config-dir>/aport/decision.json` or `<config-dir>/decision.json` for reason codes)

For API mode / hosted passports:

```bash
APORT_API_URL=https://api.aport.io ~/.openclaw/.skills/aport-guardrail-api.sh system.command.execute '{"command":"ls"}'
```

## Tool name mapping

| When you're about to…        | Use tool_name               |
|------------------------------|-----------------------------|
| Run shell commands           | `system.command.execute`    |
| Send WhatsApp/email/etc.     | `messaging.message.send`    |
| Create/merge PRs             | `git.create_pr`, `git.merge`|
| Call MCP tools               | `mcp.tool.execute`          |
| Export data / files          | `data.export`               |

Context must be valid JSON, e.g. `'{"command":"ls"}'` or `'{"channel":"whatsapp","to":"+1..."}'`.

## Why this skill?

- **Deterministic** – runs in `before_tool_call`; the agent cannot skip it.
- **Structured policy** – backed by [Open Agent Passport (OAP) v1.0](https://github.com/aporthq/aport-spec/tree/main) and policy packs.
- **Fail-closed** – if the guardrail errors, the tool is blocked.
- **Audit-ready** – decisions are logged (local JSON or APort API for signed receipts).

Pair it with other threat-detection tooling if needed; enforce policy through this guardrail so unsafe actions never run.

## OpenClaw docs

- [CLI: skills](https://docs.openclaw.ai/cli/skills) — list, info, check
- [Skills](https://docs.openclaw.ai/tools/skills) — loading, precedence, plugins, ClawHub
- [Skills config](https://docs.openclaw.ai/tools/skills-config) — schema and overrides
- [ClawHub](https://docs.openclaw.ai/tools/clawhub) — install, sync, update skills

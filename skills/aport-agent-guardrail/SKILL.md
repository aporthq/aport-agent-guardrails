---
name: aport-agent-guardrail
description: Pre-action authorization for AI agents. Verifies permissions before every tool runs (shell, messaging, git, MCP, data export). Works with OpenClaw, IronClaw, PicoClaw. Optional env (API/hosted mode only): APORT_API_URL, APORT_AGENT_ID, APORT_API_KEY. See SKILL.md for install scope and data/network.
homepage: https://aport.io
metadata: {"openclaw":{"requires":{"bins":["jq"]},"envOptional":["APORT_API_URL","APORT_AGENT_ID","APORT_API_KEY"]}}
---

# APort Agent Guardrail

**Skill identifier (slug):** `aport-agent-guardrail` · **Product name:** APort Agent Guardrail.

Pre-action authorization for AI agents: every tool call is checked **before** it runs. Works with OpenClaw, IronClaw, PicoClaw, and compatible frameworks. Run the installer once; the OpenClaw plugin then enforces policy on every tool call automatically. You do **not** run the guardrail script yourself.

> Requires: Node 18+, jq. Install with `npx @aporthq/agent-guardrails` or `./bin/openclaw` from the repo.

## Why this skill?

- **Deterministic** – runs in `before_tool_call`; the agent cannot skip it.
- **Structured policy** – backed by [Open Agent Passport (OAP) v1.0](https://github.com/aporthq/aport-spec/tree/main) and policy packs.
- **Fail-closed** – if the guardrail errors, the tool is blocked.
- **Audit-ready** – decisions are logged (local JSON or APort API for signed receipts).

Pair it with other threat-detection tooling if needed; enforce policy through this guardrail so unsafe actions never run.

## Installation

```bash
# Recommended (no clone needed)
npx @aporthq/agent-guardrails

# Hosted passport: skip the wizard by passing agent_id from aport.io
npx @aporthq/agent-guardrails <agent_id>
```

- **Hosted passport (optional):** Get an **agent_id** at [aport.io](https://aport.io/builder/create/) and pass it to the installer or use it in the wizard.

- **From the repo:** Clone [aporthq/aport-agent-guardrails](https://github.com/aporthq/aport-agent-guardrails), then from repo root run `./bin/openclaw` or `./bin/openclaw <agent_id>`. Guides: [QuickStart: OpenClaw Plugin](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md) · [Hosted passport setup](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/HOSTED_PASSPORT_SETUP.md).

- **Local passport path:** `~/.openclaw/aport/passport.json` (or `<config-dir>/aport/passport.json`; legacy: `<config-dir>/passport.json`).

- **After install:** Installer sets config dir, passport (local or hosted), plugin, config, and wrappers. Then start OpenClaw (or use the running gateway); the plugin enforces before every tool call. No further steps.

- **Wrappers** (for testing only; plugin calls them automatically): `~/.openclaw/.skills/aport-guardrail.sh` (local), `~/.openclaw/.skills/aport-guardrail-api.sh` (API/hosted).

## Usage

- **Normal use:** Run the installer once; the plugin then enforces before each tool call. Nothing to run manually.
- **Direct script calls** (testing or other automations):

```bash
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"ls"}'
~/.openclaw/.skills/aport-guardrail.sh messaging.message.send '{"channel":"whatsapp","to":"+15551234567"}'
```

- Exit 0 = ALLOW (tool may proceed)
- Exit 1 = DENY; reason codes in `<config-dir>/aport/decision.json` or `<config-dir>/decision.json`
- **API or hosted mode:**

```bash
APORT_API_URL=https://api.aport.io ~/.openclaw/.skills/aport-guardrail-api.sh system.command.execute '{"command":"ls"}'
```

## Before you install

- **Remote code**
  - Installation runs code from npm (`npx @aporthq/agent-guardrails`) or a cloned repo (`./bin/openclaw`).
  - Verify the package: [npm](https://www.npmjs.com/package/@aporthq/agent-guardrails), [GitHub](https://github.com/aporthq/aport-agent-guardrails).
  - Inspect the installer or run it in a test environment first.
- **What gets written** (under config dir, default `~/.openclaw`):
  - **Installer**
    - Registers the APort plugin with OpenClaw via `openclaw plugins install -l <path>` (plugin code stays in package/repo; OpenClaw stores the link).
    - `config.yaml` — created or updated with plugin config; if `openclaw.json` exists, plugin config and load path are merged into it.
    - `.aport-repo` — file containing the repo/package root path.
    - `.skills/` — wrapper scripts that exec into package/repo `bin/`:
      - `aport-guardrail.sh`, `aport-guardrail-bash.sh`, `aport-guardrail-api.sh`, `aport-guardrail-v2.sh`
      - `aport-create-passport.sh`, `aport-status.sh`
    - `aport/passport.json` — only if you choose a local passport (wizard creates it; installer then updates `allowed_commands`).
    - `skills/aport-guardrail/SKILL.md` — copy of this skill (managed skill).
    - `workspace/AGENTS.md` — created or appended with the APort pre-action rule.
    - `logs/` — created only if the installer starts the gateway (e.g. `gateway.log`).
  - **Runtime** (guardrail, not the installer):
    - `aport/decision.json`
    - `aport/audit.log`
    - `aport/kill-switch` (if used)
  - The plugin runs **before every tool call**. Code is law so review the codebase and npm package.
- **Network and data**
  - **Local mode**
    - No network; evaluation runs on your machine.
    - Passport and decisions stay local (`aport/passport.json`, `aport/decision.json`).
  - **API or hosted mode**
    - Tool name and context are sent to the API (default `https://api.aport.io` or your `APORT_API_URL`).
    - With a hosted passport, the API fetches the passport from the registry.
    - Decision logs may be stored by APort when using the API.
  - Prefer local mode if you do not want any data sent off-machine.
- **Credentials**
  - No env vars are **required** to run the skill.
  - Optional (API/hosted only): `APORT_API_URL`, `APORT_AGENT_ID`, `APORT_API_KEY`.
  - `agent_id` can be passed once to the installer (`npx @aporthq/agent-guardrails <agent_id>`) or set in config; not required for local passport.

## Environment variables (optional)

| Variable | When used | Purpose |
|----------|-----------|---------|
| `APORT_API_URL` | API or hosted mode | Override API endpoint (default `https://api.aport.io`). Use for self-hosted or custom API. |
| `APORT_AGENT_ID` | Hosted passport only | Hosted passport ID from aport.io; API fetches passport from registry. Not needed for local passport. |
| `APORT_API_KEY` | If your API requires auth | Set in environment only; do not put in config files. See [plugin README](https://github.com/aporthq/aport-agent-guardrails/blob/main/extensions/openclaw-aport/README.md). |

- **Local mode** — no env vars; passport is read from `<config-dir>/aport/passport.json`.
- **Hosted passport** — pass `agent_id` to the installer once (or set in config); the plugin uses it on each call in API mode.

## Tool name mapping

| When you're about to…        | Use tool_name               |
|------------------------------|-----------------------------|
| Run shell commands           | `system.command.execute`    |
| Send WhatsApp/email/etc.     | `messaging.message.send`    |
| Create/merge PRs             | `git.create_pr`, `git.merge`|
| Call MCP tools               | `mcp.tool.execute`          |
| Export data / files          | `data.export`               |

- Context must be valid JSON, e.g. `'{"command":"ls"}'` or `'{"channel":"whatsapp","to":"+1..."}'`.

## Docs

- **This repo:** [QuickStart: OpenClaw Plugin](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md) · [Hosted passport](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/HOSTED_PASSPORT_SETUP.md) · [Tool / policy mapping](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/TOOL_POLICY_MAPPING.md)
- **OpenClaw:** [CLI: skills](https://docs.openclaw.ai/cli/skills) · [Skills](https://docs.openclaw.ai/tools/skills) · [Skills config](https://docs.openclaw.ai/tools/skills-config) · [ClawHub](https://docs.openclaw.ai/tools/clawhub)

# Repository Layout

Quick reference for what each part of the repo does.

## `bin/`

CLI and guardrail entrypoints used by OpenClaw (or any framework):

| Script | Purpose |
|--------|---------|
| **openclaw** | One-command setup: passport wizard, plugin install, config, `.skills` wrappers |
| **aport-create-passport.sh** | Interactive OAP v1.0 passport wizard (capabilities, limits, L0 default) |
| **aport-guardrail-bash.sh** | **Local evaluator** — evaluates policy using passport + `external/aport-policies`; no API, no network |
| **aport-guardrail-api.sh** | Calls APort API (cloud or self-hosted); uses **src/evaluator.js** |
| **aport-guardrail.sh** | Backward-compat wrapper → runs bash guardrail |
| **aport-guardrail-v2.sh** | Backward-compat wrapper → runs API guardrail |
| **aport-status.sh** | Show passport summary and status |

## `src/`

Node.js code for **API-based** evaluation and optional proxy:

| File | Purpose |
|------|---------|
| **evaluator.js** | **APort API client** — calls `POST /api/verify/policy/{packId}` with passport (local mode) or `agent_id` (cloud mode). Used by `bin/aport-guardrail-api.sh` and by any programmatic caller (e.g. `require('./src/evaluator')`). Supports `APORT_API_URL`, `APORT_AGENT_ID`, `APORT_API_KEY`. Loads policy packs from `external/aport-policies` and passports from file. |
| **server/index.js** | **Optional HTTP proxy** — forwards requests to the agent-passport API (e.g. `APORT_API_BASE=https://api.aport.io`). Run with `npm run server` (port 8788). Use when you need a proxy in front of the API; most users call the API directly. |

**Summary:** For **local evaluation with no network**, the repo uses **bin/aport-guardrail-bash.sh** (bash + jq + policies from submodule). For **API evaluation** (cloud or self-hosted agent-passport), it uses **src/evaluator.js** (Node) and **bin/aport-guardrail-api.sh** (which invokes the evaluator).

## `extensions/openclaw-aport/`

OpenClaw plugin — `before_tool_call` hook that invokes the guardrail script or API before every tool execution. Deterministic enforcement; AI cannot bypass.

## `external/`

Git submodules (run `npm run sync-submodules` or `sync-submodules:latest`):

- **aport-spec** — OAP passport/decision schema and spec
- **aport-policies** — Policy packs (system.command.execute, messaging.message.send, mcp.tool.execute, etc.)

## `local-overrides/`

Local policy and passport templates that override or extend the submodule content (e.g. `system.command.execute.v1` when the policy is not yet in aport-policies).

## `tests/`

OAP v1 test suite: guardrail allow/deny, passport creation, kill switch, four verification methods, API evaluator (when API is up). Run with `make test`.

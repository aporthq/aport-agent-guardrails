---
name: aport-agent-guardrail
description: >
  Pre-action authorization for AI agents. Installs an OpenClaw before_tool_call hook that
  evaluates every tool call against a passport and policy before execution. Blocks unauthorized
  commands, data exfiltration, and policy violations. Supports local (offline) and hosted
  (API) passport modes. Requires Node.js 18+ and npx.
metadata:
  author: uchibeke
  version: 1.1.11
  tags: security, guardrails, authorization, ai-agent, openclaw, aport, policy-enforcement
---

# APort Agent Guardrail

Pre-action authorization for AI agents. Installs an OpenClaw `before_tool_call` hook that
evaluates every tool call against a passport (identity + capabilities + limits) and policy
**before** it executes. If the policy denies the call, the tool does not run.

This skill provides setup instructions. The enforcement logic comes from the
[@aporthq/aport-agent-guardrails](https://github.com/aporthq/aport-agent-guardrails)
npm package, which is open-source (Apache 2.0) and can be audited before installation.

## When to use this skill

- User wants to add guardrails to their AI agent setup
- User asks about protecting against unauthorized tool calls
- User wants pre-action authorization for OpenClaw, IronClaw, or PicoClaw agents
- User needs audit trails for AI agent actions

## How it works

```
User Request -> Agent Decision -> APort Hook -> [ALLOW/DENY] -> Tool Execution
                                      |
                               Policy + Passport
```

1. Agent decides to use a tool (e.g., run a shell command)
2. OpenClaw fires the `before_tool_call` hook
3. APort loads the passport, maps the tool to a policy, checks allowlists and limits
4. Decision: ALLOW (tool runs) or DENY (tool blocked)
5. Decision is logged to the audit trail

Enforcement runs in the OpenClaw hook layer, not in agent prompts. However, like any
application-layer security control, it depends on the integrity of the runtime environment
(OS, OpenClaw, filesystem). See the [Security Model](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/SECURITY_MODEL.md) for trust boundaries.

## Prerequisites

Check these before starting:

1. **Node.js 18+** and **npx** — run `node -v` to verify (must show v18 or higher)
2. **OpenClaw** (or compatible runtime) — the hook registers as an OpenClaw plugin

## Installation

### Quick start (recommended)

```bash
npx @aporthq/aport-agent-guardrails
```

The wizard will:
1. Create or load a passport (local file or hosted from aport.io)
2. Configure capabilities and limits
3. Register the OpenClaw plugin (adds `before_tool_call` hook)
4. Set up wrapper scripts under `~/.openclaw/`

After install, the hook runs on every tool call automatically.

### With hosted passport (optional)

```bash
npx @aporthq/aport-agent-guardrails <agent_id>
```

Get `agent_id` at [aport.io](https://aport.io/builder/create/) for signed decisions,
global suspend, and centralized audit dashboards.

### From source

```bash
git clone https://github.com/aporthq/aport-agent-guardrails
cd aport-agent-guardrails
./bin/openclaw
```

### What gets installed

Files created under `~/.openclaw/`:
- Plugin config in `config.yaml` or `openclaw.json`
- Wrapper scripts in `.skills/aport-guardrail*.sh`
- `aport/passport.json` (local mode only)
- `aport/decision.json` and `aport/audit.log` (created at runtime)

Total disk usage: ~100KB for scripts + passport/decision files.

## Usage

After installation, the hook runs automatically on every tool call:

```bash
# Allowed command — hook approves, tool executes
agent> run git status
# APort: passport checked -> policy evaluated -> ALLOW

# Blocked command — hook denies, tool does not run
agent> run rm -rf /
# APort: passport checked -> blocked pattern detected -> DENY
```

### Testing the hook manually

```bash
# Test allowed command (exit 0 = ALLOW)
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"ls"}'

# Test blocked command (exit 1 = DENY)
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"rm -rf /"}'
```

Decision logs:
- Latest decision: `~/.openclaw/aport/decision.json`
- Audit trail: `~/.openclaw/aport/audit.log`

## Modes

### Local mode (default)

- All evaluation happens on your machine, zero network calls
- Passport stored locally at `~/.openclaw/aport/passport.json`
- Works offline
- Note: local passport file must be protected from tampering (standard filesystem permissions)

### API mode (optional)

- Passport hosted in the aport.io registry (not stored locally)
- Signed decisions (Ed25519) for tamper-evident audit trails
- Global suspend across all systems
- Centralized compliance dashboards
- Sends tool name + context to API (does not send file contents, env vars, or credentials)

## Environment variables

All optional. Local mode requires no environment variables.

| Variable | When used | Purpose |
|----------|-----------|---------|
| `APORT_API_URL` | API mode | Override endpoint (default: `https://api.aport.io`) |
| `APORT_AGENT_ID` | Hosted passport | Passport ID from aport.io |
| `APORT_API_KEY` | If API requires auth | Authentication token |

## Default protections

- **Shell commands** — Allowlist enforcement, 40+ blocked patterns (`rm -rf`, `sudo`, `chmod 777`, etc.), interpreter bypass detection
- **Messaging** — Rate limits, recipient allowlist, channel restrictions
- **File access** — Path restrictions, blocks access to `.env`, SSH keys, system directories
- **Web requests** — Domain allowlist, SSRF protection, rate limiting
- **Git operations** — PR size limits, branch restrictions

## Tool name mapping

| Agent action | Tool name | Policy checks |
|--------------|-----------|---------------|
| Shell commands | `system.command.execute` | Allowlist, blocked patterns |
| Messaging (WhatsApp/Email/Slack) | `messaging.message.send` | Rate limits, recipient allowlist |
| PRs | `git.create_pr`, `git.merge` | PR size, branch restrictions |
| MCP tools | `mcp.tool.execute` | Server/tool allowlist |
| File read/write | `data.file.read`, `data.file.write` | Path restrictions |
| Web requests | `web.fetch`, `web.browser` | Domain allowlist |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Plugin not enforcing | Check `openclaw plugin list` shows aport-guardrail |
| Connection refused (API mode) | Verify `APORT_API_URL` is reachable |
| Tool blocked unexpectedly | Check `~/.openclaw/aport/decision.json` for deny reason |
| npx not found | Install Node.js 18+: https://nodejs.org |

## Documentation

- [Source code](https://github.com/aporthq/aport-agent-guardrails) (Apache 2.0)
- [QuickStart: OpenClaw Plugin](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/QUICKSTART_OPENCLAW_PLUGIN.md)
- [Security Model & Trust Boundaries](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/SECURITY_MODEL.md)
- [Hosted Passport Setup](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/HOSTED_PASSPORT_SETUP.md)
- [OAP Specification](https://github.com/aporthq/aport-spec/tree/main)

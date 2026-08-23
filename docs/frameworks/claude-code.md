# APort Agent Guardrail — Claude Code

Claude Code's **PreToolUse** hook runs as a separate process before each tool executes — outside Claude's reasoning context. The model cannot reason past it. This integration registers APort's guardrail with that hook so every tool use (Bash, Write, WebSearch, etc.) is checked against your passport before it runs.

**Why this is different from prompts:** A developer shared a session where Claude Code said "That file is outside my writable sandbox" then immediately escaped the sandbox when told to. Advisory guardrails live inside the model's context and can be reasoned around. The PreToolUse hook runs outside that context and cannot be bypassed. See [HN thread 47256614](https://news.ycombinator.com/item?id=47256614).

---

## How it works

- **Settings file:** Claude Code uses `~/.claude/settings.json` (user-level) or `.claude/settings.json` (project-level). This is **not** `~/.cursor/hooks.json` — different location and JSON structure.
- **PreToolUse hook:** The hook receives JSON on stdin with `tool_name` and `tool_input`, runs the APort guardrail, and outputs Claude Code's exact structured deny format on stdout when blocking: `hookSpecificOutput.permissionDecision: "deny"`. Claude Code reads structured hook JSON from stdout on exit 0; exit 2 is only for stderr-based blocking.
- **Hook script:** `bin/aport-claude-code-hook.sh` — maps all Claude Code tool names (Bash, Read, Write, Edit, MultiEdit, Glob, LS, Grep, WebSearch, WebFetch, Browser, TodoRead, TodoWrite, Task, MCP tools) to APort policies and calls the core evaluator.

---

## Setup

```bash
npx @aporthq/aport-agent-guardrails claude-code
# or
npx @aporthq/aport-agent-guardrails --framework=claude-code
```

This runs setup and writes **`~/.claude/settings.json`** with the APort hook registered for **all tools** via `"matcher": "*"`. Restart Claude Code after setup so the PreToolUse hook is picked up.

When prompted for passport setup:

1. `Create hosted APort passport now` — recommended; creates a hosted passport and narrow setup key.
2. `Use existing hosted passport ID` — paste an existing `agent_id`.
3. `Create local passport file` — writes **`~/.claude/aport/passport.json`** for offline/local mode.

For a non-interactive hosted setup:

```bash
npx --yes @aporthq/aport-agent-guardrails claude-code \
  --quick-hosted \
  --email you@example.com \
  --non-interactive
```

Equivalent environment-variable form:

```bash
APORT_OWNER_EMAIL="you@example.com" \
APORT_QUICK_HOSTED=1 \
npx --yes @aporthq/aport-agent-guardrails claude-code --non-interactive
```

If you already have a hosted passport and API key, the intended hosted install path is:

```bash
export APORT_API_KEY="apk_..."
export APORT_AGENT_ID="ap_..."
npx --yes @aporthq/aport-agent-guardrails claude-code "ap_..." --non-interactive
```

That setup writes `~/.claude/aport/guardrail-mode.env`, and the Claude hook loads those values before every tool call. Hosted mode is fail-closed: if the API evaluator is unreachable, the tool call is denied rather than silently downgraded to local mode.

## Reset / uninstall

To remove APort-owned Claude hook wiring and local config:

```bash
npx @aporthq/aport-agent-guardrails reset claude-code --yes
# or
npx @aporthq/aport-agent-guardrails claude-code reset --yes
```

This removes `~/.claude/aport/` and strips APort hook entries from `~/.claude/settings.json` while preserving unrelated Claude hooks where possible.

### Marketplace install (Claude plugins)

APort now includes a Claude plugin marketplace catalog at `.claude-plugin/marketplace.json`.

Use Claude commands:

```text
/plugin marketplace add https://github.com/aporthq/aport-agent-guardrails.git
/plugin install aport-guardrails-claude-code@aport-plugins
```

Then run:

```text
/aport-setup
```

This command intentionally runs the same supported installer flow (`npx @aporthq/aport-agent-guardrails claude-code`) so runtime hook wiring remains centralized in the main installer.

---

## What's protected (tool → policy)

| Claude Code tool   | APort policy              | Default   |
|--------------------|---------------------------|----------|
| Bash, PowerShell, Monitor | system.command.execute.v1 | Enforce  |
| Read, ReadFile, SemanticSearch (with `file_path`) | data.file.read.v1 | **Enforce** (sensitive paths blocked; API/local) |
| Glob, Grep, LSP, ListMcpResourcesTool, ReadMcpResourceTool, ToolSearch, WaitForMcpServers, TaskGet, TaskList, TodoRead | data.file.read.v1 | Allow without evaluator (no single path) |
| Write, Edit, MultiEdit, NotebookEdit, TodoWrite, ShareOnboardingGuide | data.file.write.v1 | Enforce  |
| WebSearch, WebFetch | web.fetch.v1             | Enforce  |
| Browser            | web.browser.v1            | Enforce  |
| Agent, Task, TaskCreate, TaskUpdate, TaskStop, Skill, EnterWorktree, ExitWorktree, SendMessage, TeamCreate, TeamDelete, RemoteTrigger | agent.session.create.v1 | Enforce  |
| CronCreate, CronDelete | agent.session.create.v1 | Enforce  |
| mcp__&lt;server&gt;__&lt;tool&gt; | mcp.tool.execute.v1 | Enforce  |
| **Unknown tool**    | —                         | **Denied (fail-closed)** |

Permission-rule specifiers such as `Agent(Explore)` are stripped before mapping (the hook receives `Agent(Explore)` and normalizes to `agent`).

Path-based **Read** tools call the guardrail with only `file_path` in context (not full file bodies). **Glob/Grep/LS** and similar tools still allow without an evaluator call when no single `file_path` is present.

---

## What's NOT protected

- **Claude sessions where hooks are not installed or are disabled** — APort enforces through Claude Code's PreToolUse hook. If that hook is absent or hooks are disabled in Claude settings, APort cannot intercept tool calls. Claude Code's bypass-permissions mode does not override a PreToolUse `deny` decision.
- **You typing in your terminal** — The hook runs only when the Claude Code agent is about to use a tool. Commands you run yourself are not intercepted.

---

## Testing the guardrail

From the repo root (or where the hook script lives):

```bash
# Allow: Read-family (exit 0, no output)
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}' | bin/aport-claude-code-hook.sh
echo "Exit: $?"

# Allow: Bash with allowed command (exit 0)
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bin/aport-claude-code-hook.sh
echo "Exit: $?"

# Deny: Bash with blocked pattern (exit 0, hookSpecificOutput JSON)
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' | bin/aport-claude-code-hook.sh
echo "Exit: $?"

# Deny: Unknown tool (fail-closed, exit 0 with hookSpecificOutput JSON)
echo '{"tool_name":"UnknownTool","tool_input":{}}' | bin/aport-claude-code-hook.sh
echo "Exit: $?"
```

---

## Audit log and config

- **Audit log:** `~/.claude/aport/audit.log` (when using default config dir).
- **Passport:** `~/.claude/aport/passport.json` (default). Path resolver probes `~/.claude` first, then `~/.cursor`, `~/.openclaw`, etc.
- **Status:** `bin/aport-status.sh` (uses same path resolution).

---

## Suspend / resume

Same as all frameworks: **passport is the source of truth**. Set passport `status` to `suspended` (or `active` to resume). The guardrail denies every call until the passport is active again.

---

## Why this is different from the Cursor doc

The Cursor integration uses `~/.cursor/hooks.json` and outputs `permission: allow|deny`. Claude Code uses `~/.claude/settings.json` and expects **`hookSpecificOutput.permissionDecision`** on deny. The output formats are incompatible. Do not use the Cursor hook script for Claude Code; use this integration instead.

---

## Node package (optional)

```bash
npm install @aporthq/aport-agent-guardrails-claude-code
```

```ts
import { Evaluator, getHookPath } from '@aporthq/aport-agent-guardrails-claude-code';

const hookPath = getHookPath(); // default: ~/.claude/aport-claude-code-hook.sh
```

Runtime enforcement is done by the **bash hook**; the package is for programmatic use and hook path resolution.

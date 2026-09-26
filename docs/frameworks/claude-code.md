# APort Agent Guardrail. Claude Code

Claude Code's **PreToolUse** hook runs as a separate process before each tool executes. outside Claude's reasoning context. The model cannot reason past it. This integration registers APort's guardrail with that hook so every tool use (Bash, Write, WebSearch, etc.) is checked against your passport before it runs.

**Why this is different from prompts:** A developer shared a session where Claude Code said "That file is outside my writable sandbox" then immediately escaped the sandbox when told to. Advisory guardrails live inside the model's context and can be reasoned around. The PreToolUse hook runs outside that context and cannot be bypassed. See [HN thread 47256614](https://news.ycombinator.com/item?id=47256614).

---

## How it works

- **Settings file:** Claude Code reads hooks from `~/.claude/settings.json` (user), `.claude/settings.json` (project), `.claude/settings.local.json` (project local), `--settings` on the command line, and managed policy settings. Hooks from these files merge rather than replace each other, so a project hook does not remove the user-level APort hook. With `CLAUDE_CONFIG_DIR` set, Claude Code reads the user file from that directory instead of `~/.claude`. This is **not** `~/.cursor/hooks.json`; the location and JSON structure differ.
- **PreToolUse hook:** The hook receives JSON on stdin with `tool_name`, `tool_input`, `tool_use_id`, `session_id`, `cwd`, `permission_mode` and `hook_event_name` (plus `mcp_server` for MCP tools, and `agent_id`/`agent_type` inside subagents), runs the APort guardrail, and writes Claude Code's structured format to stdout. Enforce mode blocks with `hookSpecificOutput.permissionDecision: "deny"`; Claude sees `permissionDecisionReason`. Warn/report-only mode returns `permissionDecision: "allow"` plus a top-level `systemMessage` warning only after APort completed policy evaluation; malformed hook input, invalid config, missing dependencies, and evaluator integrity failures still fail closed. The hook always exits 0 with JSON. Exit 2 would also block (Claude Code takes the reason from `permissionDecisionReason` when present, otherwise from stderr), but a structured exit 0 keeps the reason readable. Upstream also accepts `ask` and `defer`; APort emits only `allow` and `deny`. Claude Code caps each output string at 10,000 characters and swaps a longer one for a file path plus a 2,000-character preview, so keep passport reason text short.
- **Hook script:** setup copies a stable runtime to `~/.claude/aport/runtime/` and registers `~/.claude/aport/runtime/bin/aport-claude-code-hook.sh`. The hook maps Claude Code tool names (Bash, PowerShell, Monitor, Read, Grep, Write, Edit, NotebookEdit, WebSearch, WebFetch, Agent, Skill, Workflow, the task, team, cron and worktree tools, and `mcp__*` tools) to APort policies and calls the core evaluator. The full table is under [What's protected](#whats-protected-tool--policy).

---

## Setup

```bash
npx @aporthq/aport-agent-guardrails claude-code
# or
npx @aporthq/aport-agent-guardrails --framework=claude-code
```

This runs setup, copies the APort runtime to `~/.claude/aport/runtime/`,
and writes **`~/.claude/settings.json`** with the APort hook registered for
**all tools** via `"matcher": "*"`. Restart Claude Code after setup so the
PreToolUse hook is picked up.

The entry written under `hooks.PreToolUse` is:

```json
{
  "matcher": "*",
  "hooks": [
    {
      "type": "command",
      "command": "/Users/you/.claude/aport/runtime/bin/aport-claude-code-hook.sh",
      "__aport_hook": true,
      "timeout": 30
    }
  ]
}
```

`timeout` is in seconds and is derived, not fixed: the installer writes `APORT_API_TIMEOUT` (default 15) plus a 15 s margin, so 30 by default. Claude Code cancels a command hook that exceeds its timeout and the tool call then continues through the normal permission flow, so a timed-out hook does not block. The value therefore has to stay above the evaluator's own request bound; after raising `APORT_API_TIMEOUT`, run the installer again so the margin is kept. Upstream's default for command hooks is 600 seconds. `__aport_hook` is the marker the installer and `reset` use to find their own entry; reinstalling replaces the marker-owned entry and keeps other hooks in the file. The `if`, `once`, `statusMessage` and `args` fields from the upstream hook schema are not used.

**Prerequisites:** bash 4+ and `jq` on the PATH Claude Code uses. The hook parses every PreToolUse payload with `jq`; when it is missing, every tool call is denied with `APort: jq is required`, in warn mode too.

When prompted for passport setup:

1. `Create hosted APort passport now`. recommended; creates a hosted passport and narrow setup key.
2. `Use existing hosted passport ID`. paste an existing `agent_id`.
3. `Create local passport file`: writes **`~/.claude/aport/passport.json`** for offline/local mode. The wizard then asks capability and limit questions; keep `Spawn sub-agents and tasks?` at `Y` (the Claude Code default), or every Agent, Task and Skill call is denied. Step-by-step in [QUICKSTART.md](../QUICKSTART.md#interactive-local-passport-step-by-step).

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

Non-interactive local passport (no network, framework defaults with `allowed_commands: ["*"]`; tighten `limits` in the file afterwards):

```bash
npx --yes @aporthq/aport-agent-guardrails claude-code --mode=local --non-interactive \
  --output ~/.claude/aport/passport.json
```

`--output` is optional; without it the passport goes to the framework default. `--non-interactive` with no hosted flags and no `--mode` also ends on this local path.

If you already have a hosted passport and API key, the intended hosted install path is:

```bash
export APORT_API_KEY="apk_..."
export APORT_AGENT_ID="ap_..."
npx --yes @aporthq/aport-agent-guardrails claude-code "ap_..." --non-interactive
```

That setup writes `~/.claude/aport/guardrail-mode.env`, and the Claude hook loads those values before every tool call. Hosted mode is fail-closed: if the API evaluator is unreachable, the tool call is denied rather than silently downgraded to local mode.

Default enforcement is `enforce` (fail-closed). To roll out without blocking developers while tuning policy, opt in explicitly:

```bash
npx @aporthq/aport-agent-guardrails claude-code --enforcement=warn
```

In warn mode, Claude Code receives an allow decision plus a visible APort
warning that includes the policy, reason code, and the hosted passport or local
passport-file reference to update. Hook/runtime failures remain fail-closed.

To change enforcement later without creating a new passport or reinstalling the hook:

```bash
npx @aporthq/aport-agent-guardrails mode claude-code --enforcement=warn
npx @aporthq/aport-agent-guardrails mode claude-code --enforcement=enforce
```

### Install into a custom directory

Set `APORT_CLAUDE_CODE_CONFIG_DIR` when running the installer. `settings.json` goes to `<dir>/settings.json`; the runtime copy, passport, `guardrail-mode.env` and audit log go to `<dir>/aport/`:

```bash
APORT_CLAUDE_CODE_CONFIG_DIR=/srv/agent/claude npx @aporthq/aport-agent-guardrails claude-code
```

Two things follow from that. Claude Code reads its settings from `~/.claude` unless its own `CLAUDE_CONFIG_DIR` points elsewhere, so point both variables at the same directory. And `settings.json` stores only the hook path: the hook reads `APORT_CLAUDE_CODE_CONFIG_DIR` again at run time (`bin/aport-claude-code-hook.sh`), so export it in the environment Claude Code is launched from. If it is missing there, the hook looks in `~/.claude`, finds no passport or mode file, and denies every call. The `mode` and `reset` commands read the same variable.

To use a passport file outside that directory, set `APORT_PASSPORT_FILE` together with `APORT_ALLOW_EXTERNAL_PASSPORT_FILE=1`. Without the second variable the hook drops an `APORT_PASSPORT_FILE` that is not under its config directory, so a stale variable inherited from another framework's session cannot swap in a different passport (`bin/lib/framework-hook-paths.sh`).

## Reset / uninstall

To remove APort-owned Claude hook wiring and local config:

```bash
npx @aporthq/aport-agent-guardrails reset claude-code --yes
# or
npx @aporthq/aport-agent-guardrails claude-code reset --yes
```

This removes `~/.claude/aport/` and strips APort hook entries from `~/.claude/settings.json` while preserving unrelated Claude hooks where possible.

### Marketplace catalog

APort includes a Claude plugin marketplace catalog at `.claude-plugin/marketplace.json`.
Treat this as a discovery surface for now. The supported runtime setup is still the
`npx @aporthq/aport-agent-guardrails claude-code` installer because it writes the
Claude Code `PreToolUse` hook, hosted/local passport settings, and enforcement mode
from one maintained path.

If you add the catalog with Claude commands:

```text
/plugin marketplace add https://github.com/aporthq/aport-agent-guardrails.git
/plugin install aport-guardrails-claude-code@aport-plugins
```

then run the supported installer in your shell:

```bash
npx @aporthq/aport-agent-guardrails claude-code
```

This keeps runtime hook wiring centralized in the same tested installer used by direct
CLI setup.

---

## What's protected (tool → policy)

| Claude Code tool   | APort policy              | Default   |
|--------------------|---------------------------|----------|
| Bash, PowerShell, Monitor | system.command.execute.v1 | Enforce  |
| Read, ReadFile, SemanticSearch, Grep (with `file_path`) | data.file.read.v1 | **Enforce** (sensitive paths blocked; API/local) |
| Glob, LSP, ListMcpResourcesTool, ToolSearch, WaitForMcpServers, TaskGet, TaskList, TaskOutput, CronList, ListAgents, TodoRead, AskUserQuestion | none | Allow without evaluator (no single path or external side effect) |
| Write, Edit, MultiEdit, NotebookEdit, ShareOnboardingGuide | data.file.write.v1 | Enforce  |
| TodoWrite | Internal task-list bookkeeping | Allow |
| WebSearch, WebFetch | web.fetch.v1             | Enforce  |
| Browser            | web.browser.v1            | Enforce  |
| Agent, Task, TaskCreate, TaskUpdate, TaskStop, Skill, EnterWorktree, ExitWorktree, SendMessage, TeamCreate, TeamDelete, RemoteTrigger | agent.session.create.v1 | Enforce  |
| CronCreate, CronDelete | agent.session.create.v1 | Enforce  |
| mcp__&lt;server&gt;__&lt;tool&gt; | mcp.tool.execute.v1 | Enforce  |
| Artifact, EndConversation, SendFeedback, ReportFindings, SubagentHandback, EnterPlanMode, ExitPlanMode, ScheduleWakeup, PushNotification | none | Allow as internal UX, feedback and state tools |
| Workflow | agent.session.create.v1 | Enforce |
| SendUserFile | none | **Denied (fail-closed)**: unmapped. It sends local files to your device through Anthropic-hosted infrastructure and no APort policy models that yet |
| **Unknown tool**    | —                         | **Denied (fail-closed)** |

Permission-rule specifiers such as `Agent(Explore)` are stripped before mapping (the hook receives `Agent(Explore)` and normalizes to `agent`).

Claude Code's Bash, PowerShell and Monitor tools send `tool_input.timeout` in milliseconds. The hook converts it to seconds before the evaluator compares it with `limits["system.command.execute"].max_execution_time` (seconds). A call that carries no timeout is judged under Claude Code's own default of 120 s (its 120000 ms `BASH_DEFAULT_TIMEOUT_MS`), because that default bounds the call. No default applies when the timeout key is present but malformed, or when `run_in_background` is set: nothing bounds those calls, so they are denied with `oap.missing_required_context` whenever `max_execution_time` is configured. A timeout above the limit is denied with `oap.timeout_exceeded`. A passport that sets `max_execution_time` therefore blocks background Bash; drop the limit or run the command in the foreground. See [Timeouts in SECURITY_MODEL.md](../SECURITY_MODEL.md#what-the-bash-policy-does-and-does-not-see).

For MCP tools the server name comes from the `mcp__<server>__<tool>` prefix. Claude Code 2.1.274 and later also send an `mcp_server` object (`name`, `source`) on PreToolUse; the hook uses its `name` when the tool name carries no prefix to parse. It never reads a server name from `tool_input`, so a prompt cannot re-route a call to a different server.

Every row that maps to `agent.session.create.v1` requires the `agent.session.create` capability in the passport. Without it the evaluator denies with `oap.unknown_capability` and no subagent, task, skill, team or cron tool runs. The wizard adds the capability when you answer `Y` to `Spawn sub-agents and tasks?` (the Claude Code default); a hand-written passport needs `{"id": "agent.session.create"}` in `capabilities`.
For `WebSearch`, local enforce mode requires a concrete URL or domain in the
hook payload before allowing the call. If Claude Code supplies only a search
query, APort fails closed locally because domain policy cannot be evaluated
safely; use hosted mode or explicit warn mode while tuning search-heavy agent
workflows.

Path-based **Read** and **Grep** tools call the guardrail with only `file_path`
in context (not full file bodies or search results). Grep/search payloads
without a concrete path fail closed; Glob/LS and similar metadata tools still
allow without an evaluator call when no single `file_path` is present.

Before passport limits, `data.file.read` denies a fixed list of sensitive paths (case-insensitive): `.env` and anything starting with `.env`, the `.ssh`, `.aws`, `.gnupg` and `.kube` directories, `id_rsa`, `id_dsa`, `id_ecdsa` and `id_ed25519` anywhere in the path, files ending in `.pem` or `.key`, and any path containing `credentials` or `password`. Other `id_*` names such as `id_token` are not on the list. It does not cover `~/.codex/auth.json`, `~/.config/opencode/opencode.json`, `~/.netrc`, `~/.npmrc` or `~/.claude/settings.json`; add those to `limits["data.file.read"].blocked_patterns` (substring match, so `".codex/auth.json"` is enough). The write policy has no built-in list; use `limits["data.file.write"].blocked_paths` (path prefix). The list applies to the Read and Grep tools only; `cat .env` in Bash is a shell command and is judged by the command policy, which does not look at file paths.

---

## Permission modes and headless runs

PreToolUse hooks run before Claude Code's own permission check in every permission mode (`default`, `plan`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`), so an APort `deny` also blocks under `--dangerously-skip-permissions`. Hooks from settings files run in `-p` (print) sessions as well. The hook receives `permission_mode` in its input but does not change its decision on it.

Two upstream switches do turn the hook off: `disableAllHooks: true` in any settings file or via `--settings`, and a hook `timeout` that is too short for the evaluator (see the hook definition under Setup). Managed settings can pin `disableAllHooks` for an organization. `PermissionRequest` hooks are not a substitute: they fire only when Claude Code is about to show a permission prompt, which `bypassPermissions` skips entirely, and they do not honor exit code 2.

---

## What's NOT protected

- **Claude sessions where hooks are not installed or are disabled**. APort enforces through Claude Code's PreToolUse hook. If that hook is absent or hooks are disabled in Claude settings, APort cannot intercept tool calls. Claude Code's bypass-permissions mode does not override a PreToolUse `deny` decision.
- **You typing in your terminal**. The hook runs only when the Claude Code agent is about to use a tool. Commands you run yourself are not intercepted.
- **What a shell command does internally**. For Bash the evaluator sees only the command string: `allowed_commands` is a prefix match; `blocked_patterns` uses word-boundary and glob matching, case-insensitive: a single word such as `sudo` matches only as a whole word (it does not block `sudoku`), an entry containing `*` or `?` is a glob, and a multi-word entry such as `rm -rf` matches as written; when `allowed_commands` is restrictive (not `*`), a command containing an unquoted `&&`, `||`, `;`, `|`, `&`, newline, `(`, `)`, `$(`, `<(`, `>(`, a `#` comment or `$'...'` quoting is denied with `oap.command_chain_unsupported`. It does not parse `git push` remotes or branches, does not see files read by `cat` or written with `>`, and does not apply domain limits to `curl`. Path and domain limits apply to the Read, Write, Edit and WebFetch tools. Pair the hook with the Claude Code sandbox, a ruleset on the default branch and a scoped token; see [What the Bash policy does and does not see](../SECURITY_MODEL.md#what-the-bash-policy-does-and-does-not-see).

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

- **Audit log:** `~/.claude/aport/audit.log`, or `$APORT_CLAUDE_CODE_CONFIG_DIR/aport/audit.log` when that variable is set.
- **Passport:** `~/.claude/aport/passport.json` (default). With `APORT_CLAUDE_CODE_CONFIG_DIR` set, the hook uses that directory; otherwise the path resolver probes `~/.claude` first, then `~/.cursor`, `~/.openclaw`, etc.
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

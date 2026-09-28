# APort Agent Guardrail — Cursor

> **Update (v1.0.13):** The claim that the cursor hook works for Claude Code is incorrect.
> The cursor hook outputs `permission: allow/deny` — Claude Code expects `hookSpecificOutput.permissionDecision`.
> A dedicated Claude Code integration is now available:
> ```bash
> npx @aporthq/aport-agent-guardrails claude-code
> ```
> See [docs/frameworks/claude-code.md](./claude-code.md).

Cursor supports **config-driven hooks** that run before shell execution or tool use. The **APort hook script** reads JSON from stdin, calls the existing APort guardrail (policy + passport), and returns allow/deny; **deny** is the reliable enforcement result.

## Two ways to use APort

| Use case | What it is | When to use it |
|----------|------------|----------------|
| **Guardrails (CLI/setup)** | One-line installer: creates or selects a passport, writes **`~/.cursor/hooks.json`** with the path to the APort hook script. Does not run Cursor for you. | Getting started: create passport and install the hook so Cursor calls our script before the agent runs a command or tool. |
| **Core (runtime)** | The **hook script** (`bin/aport-cursor-hook.sh`) and **evaluator** (bash or API): when the agent runs a command/tool, Cursor invokes the script; we verify and return allow/deny. Optionally, the **Node package** `@aporthq/aport-agent-guardrails-cursor` exposes `Evaluator` and `getHookPath()` if you need them in code. | Guardrails = after setup, the hook runs automatically. Use the Node package only if you're building tooling that needs the evaluator or hook path. |

For Cursor, you almost always use **Guardrails (CLI)** once to install the hook; the **Core** behavior (the script + evaluator) then runs automatically whenever the agent uses the terminal or a tool.

---

## How it works

- **Hooks:** Cursor reads `hooks.json` from four places, highest priority first: enterprise (`/Library/Application Support/Cursor/hooks.json` on macOS, `/etc/cursor/hooks.json` on Linux, `C:\ProgramData\Cursor\hooks.json` on Windows), team (Enterprise dashboard), project (`<project>/.cursor/hooks.json`) and user (`~/.cursor/hooks.json`). The installer writes the user file. Each entry runs a command (our script) with the event JSON on stdin and reads the decision JSON from stdout. Cloud agents load project, team and enterprise hooks only; they never see `~/.cursor/hooks.json` or the runtime copy under `~/.cursor/aport/`, so this install covers the desktop app and the local CLI, not cloud agents.
- **Cursor CLI coverage:** Cursor CLI hook coverage has changed over time and may lag the IDE. APort installs the supported hook entries and uses fail-closed `deny` for enforcement, but direct coverage depends on the Cursor version and which hook events that version emits.
- **Claude Code:** Uses `~/.claude/settings.json` with a **different** output format (`hookSpecificOutput.permissionDecision`). Use the **dedicated Claude Code integration** instead of this Cursor hook — see [claude-code.md](./claude-code.md).

Our script accepts Cursor payloads and a small set of legacy tool payloads (e.g. `command`, or `tool`/`input`), maps to the matching APort policy, calls the guardrail evaluator, and returns Cursor-compatible JSON with `permission`, `agent_message`, and `user_message` where the host consumes those fields. Shell events without command context and path-based content searches without a concrete path fail closed instead of silently bypassing policy.

### Hook contract

Checked against the [Cursor hooks reference](https://cursor.com/docs/hooks) on 2026-09-24. The installer registers every Cursor hook that returns a permission decision, except the Tab one (see below):

| Event | Fields the hook reads | Policy |
|-------|----------------------|--------|
| `beforeShellExecution` | `command` (`cwd` and `sandbox` are ignored) | `system.command.execute` |
| `preToolUse` | `tool_name`, `tool_input` (values include `Shell`, `Read`, `Write`, `Grep`, `Delete`, `Task`, `MCP:<tool>`) | mapped per tool, unknown tools fail closed |
| `beforeMCPExecution` | `tool_name`, `tool_input` (JSON string or object), `mcp_server_name`; `url`/`mcp_server_url` (HTTP) or the stdio launch `command` are not evaluated | `mcp.tool.execute` |
| `beforeReadFile` | `file_path` (`content` and `attachments` are never forwarded) | `data.file.read` |
| `subagentStart` | `subagent_type`, task length (the `task` text is not persisted) | `agent.session.create` |
| `beforeTabFileRead` (opt-in) | `file_path` | `data.file.read` |

Every payload also carries `hook_event_name`, `conversation_id`, `generation_id`, `model`, `cursor_version`, `workspace_roots`, `user_email` and `transcript_path`. The hook routes on `hook_event_name` and falls back to field detection for older builds that omit it.

Output: `{"permission": "allow" | "deny", "user_message": ..., "agent_message": ...}`. The hook also emits `allowed`, `agentMessage` and `reason` for older consumers. Exit code 2 is a deny; Cursor treats any other non-zero exit, a crash, a timeout or empty output as fail-open unless the entry sets `failClosed: true`, which the installer does. `timeout` is in seconds; the installer writes `APORT_API_TIMEOUT` (default 15) plus a 15 s margin, so 30 by default. Cursor rejects invalid JSON or an out-of-schema response from a permission hook by blocking the action. `permission: "ask"` exists upstream for shell and MCP hooks; APort never returns it. Hooks that cannot block (`afterFileEdit`, `afterShellExecution`, `postToolUse`, `beforeSubmitPrompt`, `stop`, `sessionStart` and the rest) are not registered.

Both read events deny with `oap.missing_file_path` when the payload carries no usable `file_path`. A read hook with no path has no evidence to evaluate, so it cannot allow the read.

**Tab completions:** `beforeTabFileRead` fires when Tab (inline completions) reads a file, with the same `file_path`/`content` input and `permission` output as `beforeReadFile`. It is off by default because it runs the evaluator on every Tab file read and a passport without `data.file.read` would block completions. To register it, install with `APORT_CURSOR_TAB_READ_HOOK=1`; a later install without the variable removes the APort entry again. Cursor's `matcher` field (a regex on the tool type, subagent type or command text) is left unset so every event reaches APort.

**Hook script path:** The installer copies a stable APort runtime into
`~/.cursor/aport/runtime/` and writes `hooks.json` to execute
`~/.cursor/aport/runtime/bin/aport-cursor-hook.sh`. It does not point Cursor at
the temporary `npx` cache, so hooks keep working after package-manager cache
cleanup.

## Setup

```bash
npx @aporthq/aport-agent-guardrails cursor
# or
npx @aporthq/aport-agent-guardrails --framework=cursor
```

This runs setup and writes **`~/.cursor/hooks.json`** with fail-closed APort hook entries for shell/tool/MCP/file-read events. Choose hosted setup for passport and setup-key creation, or local setup to write a passport at the framework default path: **`~/.cursor/aport/passport.json`**. In non-interactive local mode you can pass **`--output /path/to/passport.json`** to choose the path. Restart Cursor (or reload the window) after setup so the hooks are loaded.

**Prerequisites:** `jq` on the PATH Cursor uses. The hook returns `permission: deny` with `APort: jq is required` for every event when it is missing.

Non-interactive local passport: `npx --yes @aporthq/aport-agent-guardrails cursor --mode=local --non-interactive` (add `--output <path>` to choose the file). Interactive local passport: choose `3. Create local passport file` at the passport prompt and keep `Spawn sub-agents and tasks?` at `Y`, since `subagentStart` maps to `agent.session.create.v1` and is denied without that capability.

**Custom config directory:** set `APORT_CURSOR_CONFIG_DIR` when running the installer to put the runtime, passport, `guardrail-mode.env` and audit log under `<dir>/aport/`. `hooks.json` is still written to `~/.cursor` by default; set `CURSOR_HOOKS_DIR` when you need the hooks file somewhere else. The hooks file stores only the hook path, so also export `APORT_CURSOR_CONFIG_DIR` in the environment Cursor is launched from; the hook reads it at run time and otherwise falls back to `~/.cursor`. `mode` reads `APORT_CURSOR_CONFIG_DIR`; `reset` reads `APORT_CURSOR_CONFIG_DIR` for state and `CURSOR_HOOKS_DIR` for the hooks file. A passport outside the state directory needs `APORT_PASSPORT_FILE` plus `APORT_ALLOW_EXTERNAL_PASSPORT_FILE=1` (README, "Install into a custom directory").

Default enforcement is `enforce` (fail-closed). To roll out in report-only mode, opt in explicitly:

```bash
npx @aporthq/aport-agent-guardrails cursor --enforcement=warn
```

In warn mode, APort still evaluates and records the original deny decision, then
returns `permission: "allow"` so Cursor can continue. Warn mode applies only
after APort completed policy evaluation; malformed hook input, invalid config,
missing dependencies, and evaluator integrity failures still fail closed.
Cursor's hook UI is most reliable at surfacing messages on deny; allow warnings
are returned in the JSON as best-effort context, but the audit log and
`bin/aport-status.sh` are the source of truth for report-only decisions.

To change enforcement later without creating a new passport or reinstalling hooks:

```bash
npx @aporthq/aport-agent-guardrails mode cursor --enforcement=warn
npx @aporthq/aport-agent-guardrails mode cursor --enforcement=enforce
```

## Is it installed? How to check

- **No `~/.cursor/hooks.json`?** That file is **created when you run the installer**. If you get `No such file or directory`, the Cursor integration is not installed yet. Run:
  ```bash
  npx @aporthq/aport-agent-guardrails cursor
  ```
  (or `npx @aporthq/aport-agent-guardrails --framework=cursor`). The installer writes `~/.cursor/hooks.json` and configures hosted or local passport mode.
- **Hooks file:** After installing, open `~/.cursor/hooks.json` (user-level) or `.cursor/hooks.json` (project). You should see `beforeShellExecution`, `preToolUse`, `beforeMCPExecution`, `beforeReadFile` and `subagentStart` entries (plus `beforeTabFileRead` when installed with `APORT_CURSOR_TAB_READ_HOOK=1`) whose `command` points at the stable runtime hook under `~/.cursor/aport/runtime/bin/aport-cursor-hook.sh`. Cursor also lists loaded hooks under Customize > Hooks and logs runs in the Hooks output channel.
- **Restart required:** Cursor loads hooks at startup. After installing, **restart Cursor** (or **Reload Window** from the command palette) so the new hooks are active.
- **Passport/config:** In hosted mode, the hook loads `~/.cursor/aport/guardrail-mode.env`. In local mode, it uses the passport created at **`~/.cursor/aport/passport.json`** by default (each framework has its own default; see [Default paths](#config) below).

## What the guardrail applies to (and what it doesn’t)

The guardrail only runs when the **Cursor agent** is about to run a shell command or use a tool. It does **not** run when **you** type commands in the terminal yourself.

| Who runs the command | Hook runs? | Guardrail can block? |
|----------------------|------------|------------------------|
| **You** type `rm file` in the Cursor terminal | No | No — it’s your shell, not the agent. |
| **The agent** runs a command (e.g. after you ask “run rm file”) | Yes (`beforeShellExecution`) | Yes — exit 2 blocks the agent’s command. |
| **The agent** uses a tool that sends a command | Yes (`preToolUse`) | Yes. |
| **The agent** uses a tool covered by the installed `preToolUse` hook | Version-dependent | Yes when Cursor emits the hook event. |

So:

- **Checked:** When the **agent** runs a command in the terminal (e.g. `rm file`, `npm install`) or uses a tool that goes through a Cursor hook event → our script runs and can block.
- **Not checked:** (1) **You** typing in the terminal — the hook is never invoked. (2) Agent tool paths where the installed Cursor version does not emit a hook event.

To **test that the guardrail is working**, ask the **agent** to run a terminal command your passport blocks (e.g. “Run in the terminal: `rm -rf /path/to/file`”). Do **not** type the command yourself in the terminal — that bypasses the hook.

For shell events the evaluator sees only the command string: `allowed_commands` is a prefix match; `blocked_patterns` uses word-boundary and glob matching, case-insensitive: a single word such as `sudo` matches only as a whole word (it does not block `sudoku`), an entry containing `*` or `?` is a glob, and a multi-word entry such as `rm -rf` matches as written; when `allowed_commands` is restrictive (not `*`), a command containing an unquoted `&&`, `||`, `;`, `|`, `&`, newline, `(`, `)`, `$(`, `<(`, `>(`, a `#` comment or `$'...'` quoting is denied with `oap.command_chain_unsupported`. It does not parse `git push` targets, files read by `cat` or written with `>`, or `curl` hosts; see [What the Bash policy does and does not see](../SECURITY_MODEL.md#what-the-bash-policy-does-and-does-not-see).

Cursor's shell events carry no timeout, so the evaluator treats them as unbounded. A passport that sets `limits["system.command.execute"].max_execution_time` denies every shell call with `oap.missing_required_context`; leave that limit out of a Cursor passport.

For `WebSearch`, local enforce mode requires a concrete URL or domain in the
hook payload before allowing the call. If Cursor supplies only a search query,
APort fails closed locally because domain policy cannot be evaluated safely;
use hosted mode or explicit warn mode while tuning search-heavy workflows.

## Test the guardrail and inspect status/logs

**Two ways to test:** (1) Run the hook from the terminal to verify the script and populate the audit log. (2) Ask the Cursor **agent** to run a command in chat to verify the full installation.

### 1. Test the script (terminal)

From the repo root (or wherever the hook script lives):

```bash
# Allow path (e.g. cat a file) — exit 0
echo '{"command":"cat test.md"}' | bin/aport-cursor-hook.sh
echo "Exit: $?"

# Deny path (e.g. rm -rf) — exit 2
echo '{"command":"rm -rf test.md"}' | bin/aport-cursor-hook.sh
echo "Exit: $?"
```

### 2. Inspect status and audit log

After running the hook (or after the agent runs a command), check the passport and decisions:

```bash
# From repo root: status (passport, capabilities, limits, latest decision, recent activity)
bin/aport-status.sh

# Audit log: one line per decision (timestamp, tool, decision_id, allow/deny, policy, context e.g. command)
cat ~/.cursor/aport/audit.log

# Last decision (full OAP JSON)
cat ~/.cursor/aport/decision.json
```

If you used a different passport path during setup, the audit log and decision file are in that path’s `aport/` dir (e.g. `~/.openclaw/aport/` if you chose the OpenClaw default).

### 3. Test the real installation (Cursor agent)

In **Cursor chat**, ask the agent to run a command (do not type it in the terminal yourself):

- **Should allow:** “Run in the terminal: `cat test.md`” — command runs; audit log gets an `allow=true` line.
- **Should block:** “Run in the terminal: `rm -rf test.md`” — Cursor should block the command; audit log gets an `allow=false` line.

Then run `bin/aport-status.sh` and `cat ~/.cursor/aport/audit.log` to confirm the new entries.

## Config

- **Hooks file:** `~/.cursor/hooks.json` (user) or `.cursor/hooks.json` (project). The installer writes the former by default; set `CURSOR_HOOKS_DIR` to write and later reset a different hooks directory. Enterprise and team hook files take priority over both; see [Hook contract](#hook-contract).
- **Passport and default paths:** Each framework stores passport and evaluation data in its own default location. For Cursor the default is **`~/.cursor/aport/passport.json`** (with `decision.json`, `audit.log`, and `guardrail-mode.env` in `~/.cursor/aport/`). Hosted mode uses the `agent_id` and API key stored in `guardrail-mode.env`; it does not need a local passport JSON file. You can always choose a different local path: in the wizard the first question is the passport path (default shown in brackets); in non-interactive mode use **`--output /path/to/passport.json`**.
- **Hook script:** `~/.cursor/aport/runtime/bin/aport-cursor-hook.sh` after setup. The installer copies the required runtime files there and puts that absolute path into `hooks.json`. The Cursor hook anchors config resolution to the Cursor config directory and loads `~/.cursor/aport/guardrail-mode.env` when present.

## Status and logs

- **Passport status:** Run `bin/aport-status.sh` (from repo) or the guardrail’s status script. It uses the same path resolution as the hook (probes `~/.cursor`, `~/.openclaw`, etc.), so it will show the passport under `~/.cursor/aport/` if that’s where you created it.
- **Audit trail:** Allow/deny decisions are appended to the audit log in the same data dir as the passport (e.g. `~/.cursor/aport/audit.log` when using the Cursor default). Each line includes timestamp, tool, decision_id, allow/deny, policy id, and **context** (the actual command for `system.command.execute`, recipient for messaging, repo/branch for merge). `bin/aport-status.sh` shows this context in **Latest Decision** and **Recent Activity**.

## Suspend (kill switch)

Same as all frameworks: **passport is the source of truth**. Set passport `status` to `suspended` (or `active` to resume). The guardrail denies every call until the passport is active again.

For **Claude Code**, use the [dedicated Claude Code integration](./claude-code.md) instead — it uses the correct output format (`hookSpecificOutput.permissionDecision`) and supports all Claude Code tool types.

The script accepts multiple input shapes (e.g. `command`, `tool`/`input`) and returns the host-expected JSON; **exit 0** = allow, **exit 2** = block for Cursor-style command hooks.

## Using the Node package (optional)

If you need the evaluator or hook path in your own Node/TypeScript code (e.g. custom tooling or scripts):

```bash
npm install @aporthq/aport-agent-guardrails-cursor   # or -core if you only need Evaluator
```

```ts
import { Evaluator, getHookPath } from '@aporthq/aport-agent-guardrails-cursor';

// Default path where the hook script is expected (~/.cursor/aport-cursor-hook.sh)
const hookPath = getHookPath();

// Use the evaluator programmatically (same as @aporthq/aport-agent-guardrails-core)
const evaluator = new Evaluator(null, 'cursor');
const decision = evaluator.verifySync({}, { capability: 'system.command.execute.v1' }, { tool: 'run_command', input: 'ls' });
```

Runtime enforcement in Cursor is done by the **hook script**, not by this package; the package is for programmatic use only.

## Tests

- **Unit:** Hook script with mock stdin for every registered event, using the documented payload shapes (base fields, `tool_use_id`, `cwd`, MCP `tool_input` as a JSON string, stdio `command`, `beforeReadFile` attachments, `beforeTabFileRead`). Allow is exit 0 with `permission: allow`; deny is exit 2 with `permission: deny`. See `tests/unit/test-cursor-hook.sh`.
- **Integration:** Cursor setup: `tests/frameworks/cursor/setup.sh` writes hooks.json into a scratch config dir, checks merge behaviour with existing entries, and covers the `APORT_CURSOR_TAB_READ_HOOK` opt-in and its removal.

## Status

Implemented (Story E). **APort Agent Guardrail for Cursor.** Installer: `npx @aporthq/aport-agent-guardrails cursor`; hook script: `bin/aport-cursor-hook.sh`; config: `~/.cursor/hooks.json`. For Claude Code, use the dedicated integration: `npx @aporthq/aport-agent-guardrails claude-code` (see [claude-code.md](./claude-code.md)).

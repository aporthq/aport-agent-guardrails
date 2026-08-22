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

- **Hooks:** Cursor uses `~/.cursor/hooks.json` (or `.cursor/hooks.json` in the project). Hooks such as `beforeShellExecution` and `preToolUse` run a command (our script). The host sends JSON to stdin and reads JSON from stdout.
- **Cursor CLI coverage:** Cursor CLI hook coverage has changed over time and may lag the IDE. APort installs the supported hook entries and uses fail-closed `deny` for enforcement, but direct coverage depends on the Cursor version and which hook events that version emits.
- **Claude Code:** Uses `~/.claude/settings.json` with a **different** output format (`hookSpecificOutput.permissionDecision`). Use the **dedicated Claude Code integration** instead of this Cursor hook — see [claude-code.md](./claude-code.md).

Our script accepts Cursor payloads and a small set of legacy tool payloads (e.g. `command`, or `tool`/`input`), maps to the matching APort policy, calls the guardrail evaluator, and returns `permission: allow|deny` plus optional `agentMessage`.

**Hook script path:** The hook script (`aport-cursor-hook.sh`) resolves `bin/aport-guardrail-bash.sh` relative to its own directory (script dir → parent = package root). When you install via **npx**, the installer writes the path to the script inside the npx cache (e.g. `…/node_modules/@aporthq/aport-agent-guardrails/bin/aport-cursor-hook.sh`), so the guardrail script is found at `…/bin/aport-guardrail-bash.sh`. If you copy the hook script elsewhere, ensure `bin/aport-guardrail-bash.sh` exists at the same relative location or set `APORT_GUARDRAIL_SCRIPT` (or equivalent) so the hook can find the evaluator.

## Setup

```bash
npx @aporthq/aport-agent-guardrails cursor
# or
npx @aporthq/aport-agent-guardrails --framework=cursor
```

This runs setup and writes **`~/.cursor/hooks.json`** with the path to the APort hook script. Choose hosted setup for passport and setup-key creation, or local setup to write a passport at the framework default path: **`~/.cursor/aport/passport.json`**. In non-interactive local mode you can pass **`--output /path/to/passport.json`** to choose the path. Restart Cursor (or reload the window) after setup so the hooks are loaded.

## Is it installed? How to check

- **No `~/.cursor/hooks.json`?** That file is **created when you run the installer**. If you get `No such file or directory`, the Cursor integration is not installed yet. Run:
  ```bash
  npx @aporthq/aport-agent-guardrails cursor
  ```
  (or `npx @aporthq/aport-agent-guardrails --framework=cursor`). The installer writes `~/.cursor/hooks.json` and configures hosted or local passport mode.
- **Hooks file:** After installing, open `~/.cursor/hooks.json` (user-level) or `.cursor/hooks.json` (project). You should see `beforeShellExecution` and/or `preToolUse` entries whose `command` is the path to `aport-cursor-hook.sh`.
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

- **Hooks file:** `~/.cursor/hooks.json` (user) or `.cursor/hooks.json` (project). The installer writes the former by default.
- **Passport and default paths:** Each framework stores passport and evaluation data in its own default location. For Cursor the default is **`~/.cursor/aport/passport.json`** (with `decision.json` and `audit.log` in `~/.cursor/aport/`). You can always choose a different path: in the wizard the first question is the passport path (default shown in brackets); in non-interactive mode use **`--output /path/to/passport.json`**. The Python evaluator and bash resolver use the same default-path map (e.g. `python/aport_guardrails/core/evaluator.py` → `DEFAULT_PASSPORT_PATHS`, `bin/lib/config.sh` → `get_default_passport_path`).
- **Hook script:** `bin/aport-cursor-hook.sh` in this repo (or in the npm package when installed via npx). The installer puts its absolute path into `hooks.json`. The hook does not set a config dir; the path resolver probes `~/.cursor`, `~/.openclaw`, `~/.aport/langchain`, etc., and uses the first directory that contains `aport/passport.json`.

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

- **Unit:** Hook script with mock stdin — allow (exit 0, JSON `allowed: true`), deny (exit 2, `allowed: false`). See `tests/unit/test-cursor-hook.sh`.
- **Integration:** Run script with sample Cursor-style JSON; assert output format and exit code. Cursor setup: `tests/frameworks/cursor/setup.sh` (writes hooks.json, config dir).

## Status

Implemented (Story E). **APort Agent Guardrail for Cursor.** Installer: `npx @aporthq/aport-agent-guardrails cursor`; hook script: `bin/aport-cursor-hook.sh`; config: `~/.cursor/hooks.json`. For Claude Code, use the dedicated integration: `npx @aporthq/aport-agent-guardrails claude-code` (see [claude-code.md](./claude-code.md)).

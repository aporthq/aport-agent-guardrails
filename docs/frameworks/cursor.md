# APort Agent Guardrail — Cursor (and VS Code Copilot / Claude Code)

Cursor, VS Code with GitHub Copilot, and Claude Code support **config-driven hooks** that run before shell execution or tool use. The **APort hook script** reads JSON from stdin, calls the existing APort guardrail (policy + passport), and returns allow/deny; **exit 2** blocks the action. One script works across Cursor, Copilot, and Claude Code.

## Two ways to use APort

| Use case | What it is | When to use it |
|----------|------------|----------------|
| **Guardrails (CLI/setup)** | One-line installer: runs the **passport wizard**, writes **`~/.cursor/hooks.json`** with the path to the APort hook script. Does not run Cursor for you. | Getting started: create passport and install the hook so Cursor calls our script before the agent runs a command or tool. |
| **Core (runtime)** | The **hook script** (`bin/aport-cursor-hook.sh`) and **evaluator** (bash or API): when the agent runs a command/tool, Cursor invokes the script; we verify and return allow/deny. Optionally, the **Node package** `@aporthq/aport-agent-guardrails-cursor` exposes `Evaluator` and `getHookPath()` if you need them in code. | Guardrails = after setup, the hook runs automatically. Use the Node package only if you're building tooling that needs the evaluator or hook path. |

For Cursor, you almost always use **Guardrails (CLI)** once to install the hook; the **Core** behavior (the script + evaluator) then runs automatically whenever the agent uses the terminal or a tool.

---

## How it works

- **Hooks:** Cursor uses `~/.cursor/hooks.json` (or `.cursor/hooks.json` in the project). Hooks such as `beforeShellExecution` and `preToolUse` run a command (our script). The host sends JSON to stdin and reads JSON from stdout; **exit code 2** = block.
- **VS Code Copilot:** Agent hooks (Preview) use `~/.claude/settings.json` or `.github/hooks/*.json` with `PreToolUse`; same idea: command, stdin JSON, stdout JSON, exit 2 = block.
- **Claude Code:** `~/.claude/settings.json`, same PreToolUse style.

Our script accepts Cursor- and Copilot-style payloads (e.g. `command`, or `tool`/`input`), maps to the **system.command.execute** policy, calls the bash guardrail, and returns `permission: allow|deny` plus optional `agentMessage`. No VS Code extension is required for interception; hooks are the mechanism.

**Hook script path:** The hook script (`aport-cursor-hook.sh`) resolves `bin/aport-guardrail-bash.sh` relative to its own directory (script dir → parent = package root). When you install via **npx**, the installer writes the path to the script inside the npx cache (e.g. `…/node_modules/@aporthq/aport-agent-guardrails/bin/aport-cursor-hook.sh`), so the guardrail script is found at `…/bin/aport-guardrail-bash.sh`. If you copy the hook script elsewhere, ensure `bin/aport-guardrail-bash.sh` exists at the same relative location or set `APORT_GUARDRAIL_SCRIPT` (or equivalent) so the hook can find the evaluator.

## Setup

```bash
npx @aporthq/aport-agent-guardrails cursor
# or
npx @aporthq/aport-agent-guardrails --framework=cursor
```

This runs the **passport wizard** and writes **`~/.cursor/hooks.json`** with the path to the APort hook script. The wizard uses a **framework-specific default** for where to store the passport: for Cursor the default is **`~/.cursor/aport/passport.json`** (so passport and evaluation data live with Cursor’s own data). The **first question** in the wizard is “Passport file path [default]:” — press Enter to use that default or type a different path. In non-interactive mode you can pass **`--output /path/to/passport.json`** to choose the path. Restart Cursor (or reload the window) after setup so the hooks are loaded.

## Is it installed? How to check

- **No `~/.cursor/hooks.json`?** That file is **created when you run the installer**. If you get `No such file or directory`, the Cursor integration is not installed yet. Run:
  ```bash
  npx @aporthq/aport-agent-guardrails cursor
  ```
  (or `npx @aporthq/aport-agent-guardrails --framework=cursor`). The installer writes `~/.cursor/hooks.json` and runs the passport wizard.
- **Hooks file:** After installing, open `~/.cursor/hooks.json` (user-level) or `.cursor/hooks.json` (project). You should see `beforeShellExecution` and/or `preToolUse` entries whose `command` is the path to `aport-cursor-hook.sh`.
- **Restart required:** Cursor loads hooks at startup. After installing, **restart Cursor** (or **Reload Window** from the command palette) so the new hooks are active.
- **Passport:** The hook uses the passport created by the wizard. The default path for Cursor is **`~/.cursor/aport/passport.json`** (each framework has its own default; see [Default paths](#config) below). The resolver probes `~/.cursor`, then `~/.openclaw`, etc., so the hook finds the passport without extra config.

## What the guardrail applies to (and what it doesn’t)

The guardrail only runs when the **Cursor agent** is about to run a shell command or use a tool. It does **not** run when **you** type commands in the terminal yourself.

| Who runs the command | Hook runs? | Guardrail can block? |
|----------------------|------------|------------------------|
| **You** type `rm file` in the Cursor terminal | No | No — it’s your shell, not the agent. |
| **The agent** runs a command (e.g. after you ask “run rm file”) | Yes (`beforeShellExecution`) | Yes — exit 2 blocks the agent’s command. |
| **The agent** uses a tool that sends a command | Yes (`preToolUse`) | Yes. |
| **The agent** uses a built-in “delete file” action (no shell) | No | No — direct file API, no hook. |

So:

- **Checked:** When the **agent** runs a command in the terminal (e.g. `rm file`, `npm install`) or uses a tool that goes through the hook → our script runs and can block (exit 2).
- **Not checked:** (1) **You** typing in the terminal — the hook is never invoked. (2) The agent using a built-in “delete file” / “edit file” action (editor API) — no shell, so no hook.

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

## Using the same script in VS Code (Copilot) and Claude Code

- **VS Code + GitHub Copilot:** Add a PreToolUse hook in `~/.claude/settings.json` (or project `.claude/settings.json`, or `.github/hooks/*.json`) that runs the same script. See [Agent hooks (Preview)](https://code.visualstudio.com/docs/copilot/customization/hooks).
- **Claude Code:** Configure `~/.claude/settings.json` to run the same APort hook script for PreToolUse.

The script accepts multiple input shapes (e.g. `command`, `tool`/`input`) and returns the host-expected JSON; **exit 0** = allow, **exit 2** = block.

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

Implemented (Story E). **APort Agent Guardrail for Cursor.** Installer: `npx @aporthq/aport-agent-guardrails cursor`; hook script: `bin/aport-cursor-hook.sh`; config: `~/.cursor/hooks.json`. Same script usable for VS Code Copilot and Claude Code.

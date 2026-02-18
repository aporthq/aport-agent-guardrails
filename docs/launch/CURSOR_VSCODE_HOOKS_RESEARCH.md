# Cursor vs VS Code: Hooks, Extensions, and ROI

**Purpose:** Decide how to support Cursor and VS Code (Copilot) with maximum traction and minimum effort.

---

## 1. Can we use a VS Code extension for “before execution” hooks?

**Short answer: No for vanilla VS Code; not needed for Copilot/Cursor.**

| Environment | Before shell/tool execution? | How? |
|-------------|------------------------------|------|
| **VS Code (no Copilot)** | **No** | The VS Code extension API has no way to intercept terminal commands before they run. `Terminal.onDidWriteData` is after the fact. You cannot build an extension that “hooks before every shell execution” in plain VS Code. |
| **VS Code + GitHub Copilot (agent)** | **Yes** | Via **agent hooks** (Preview in VS Code 1.109.3+). Hooks are **config-driven**, not extension API–driven: JSON config files point to **shell scripts**. |
| **Cursor** | **Yes** | Native **hooks** (e.g. `beforeShellExecution`, `preToolUse`). Same idea: config file + script. Cursor can also load **Claude Code** hook config from `~/.claude/settings.json`. |

So “before execution” is available only where an **agent** runs (Copilot, Cursor, Claude Code), and in those cases it’s done via **hooks + scripts**, not via a VS Code extension API.

---

## 2. Common thing in the VS Code ecosystem that adds the most value with least effort

**Recommendation: One hook script + one installer that writes the right config for each host. No VS Code extension required for the core behavior.**

### Why hooks (script + config) beat an extension here

1. **Same mechanism everywhere**  
   - **VS Code (Copilot):** [Agent hooks (Preview)](https://code.visualstudio.com/docs/copilot/customization/hooks) — config in `~/.claude/settings.json`, `.claude/settings.json`, or `.github/hooks/*.json`. `PreToolUse` runs a command (our script).  
   - **Cursor:** [Hooks](https://cursor.com/docs/agent/hooks) — config in `~/.cursor/hooks.json` or `.cursor/hooks.json`. `beforeShellExecution` / `preToolUse` run a command.  
   - **Claude Code:** `~/.claude/settings.json`, same PreToolUse style.  
   All of them: **JSON config → shell script → stdin JSON in, stdout JSON out, exit 2 = block.**

2. **One script, many editors**  
   A single APort hook script can:
   - Read JSON from stdin (tool name + input; e.g. `runTerminalCommand` / `command` for shell).
   - Map to our policy (e.g. `system.command.execute.v1`).
   - Call the existing guardrail (bash or API).
   - Emit the host’s expected JSON (e.g. VS Code: `permissionDecision: allow|deny|ask`, Cursor: allow/deny + exit code).
   - Use **exit 2** to block (both Cursor and VS Code use exit 2 for “block”).

3. **Extension adds little for interception**  
   - Vanilla VS Code: extension **cannot** intercept shell execution (no API).  
   - Copilot/Cursor: interception is already done by **hooks**, not by extensions. An extension would at best **write** the same hook config and maybe add a “Install APort guardrails” command. That’s optional UX; the core value is the **script + config**.

### What to build (high value, low effort)

| Deliverable | Effort | Value |
|-------------|--------|--------|
| **One hook script** (e.g. `aport-hook.sh`) that parses stdin (Cursor/Copilot/Claude format), calls existing guardrail, returns allow/deny + exit 0/2 | Low | High — works in Cursor, VS Code Copilot, Claude Code |
| **Installer** (`npx @aporthq/aport-agent-guardrails cursor` or `--framework=cursor`) that runs passport wizard and writes `~/.cursor/hooks.json` (and optionally `~/.claude/settings.json`) pointing at the script | Low | High — one command to enable guardrails |
| **Docs** for Cursor, VS Code+Copilot, and Claude Code (where to put config, example `PreToolUse` / `beforeShellExecution` snippet) | Low | High — reuse same script everywhere |
| **VS Code extension** that only writes hook config + “Install guardrails” command | Medium | Low–medium — nicer discoverability, same behavior as script+installer |

So the **common thing** that adds the most value with least effort is: **one script + config for PreToolUse / beforeShellExecution**, shared across Cursor, VS Code (Copilot), and Claude Code. A VS Code extension is optional polish, not required for “works in VS Code (Copilot) and other flavours.”

---

## 3. PreToolUse / beforeShellExecution availability

| Platform | PreToolUse / beforeShellExecution | Config location |
|----------|-----------------------------------|------------------|
| **VS Code (Copilot)** | Yes — `PreToolUse` (Preview) | `~/.claude/settings.json`, `.claude/settings.json`, `.github/hooks/*.json` |
| **Cursor** | Yes — `preToolUse`, `beforeShellExecution` | `~/.cursor/hooks.json`, `.cursor/hooks.json` |
| **Claude Code** | Yes — `PreToolUse` | `~/.claude/settings.json`, `.claude/settings.json` |
| **VS Code (no agent)** | N/A | No agent → no tool/shell interception in the first place |

So **PreToolUse / beforeShellExecution is available** exactly where we care: Cursor, VS Code+Copilot, and Claude Code. It’s not available in “plain VS Code” because there’s no agent running tools/shell there.

---

## 4. ROI vs effort: summary

- **Implement:** One **hook script** + **installer** that writes the right **hooks config** for Cursor (and optionally for VS Code/Claude via `~/.claude/settings.json`). Document for Cursor, VS Code+Copilot, and Claude Code.
- **Skip for MVP:** A VS Code extension whose only job is to install guardrails. Same outcome can be achieved with `npx @aporthq/aport-agent-guardrails cursor` (or a `copilot` framework flag) and one script; extension can be added later if we want marketplace discoverability.
- **Do not rely on:** A VS Code extension to “intercept shell execution” in vanilla VS Code — the API doesn’t support it; interception only exists in agent-based products and is done via hooks.

This keeps effort low and ROI high: one script, one installer, one set of docs, and it works on Cursor, VS Code (Copilot), and other flavours that use the same hook format (e.g. Claude Code).

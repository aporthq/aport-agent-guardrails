# QuickStart: OpenClaw Plugin (Deterministic Enforcement)

**5-minute setup for deterministic, platform-level policy enforcement in OpenClaw.**

**One command to get started** (clone + submodules + installer):

```bash
git clone https://github.com/aporthq/aport-agent-guardrails.git && \
  cd aport-agent-guardrails && \
  git submodule update --init --recursive && \
  ./bin/openclaw
```

Then start OpenClaw with the generated config (e.g. `openclaw gateway start --config ~/.openclaw/config.yaml`). The plugin will enforce policies on every tool call.

*Already have the repo?* From the repo root run: `./bin/openclaw`

---

## Why Use the Plugin?

| Approach | Deterministic? | Bypass Risk | Security Level |
|----------|----------------|-------------|----------------|
| **OpenClaw Plugin** ✅ | Yes | None | 🟢 Secure |
| AGENTS.md prompts | No | High | 🔴 Not secure |

**Bottom line:** With the plugin, the platform enforces policy before every tool execution. The AI cannot bypass it.

---

## Installation (Automatic)

**Recommended:** Use the one-liner above, or from the repo root run:

```bash
./bin/openclaw
```

The script will:
1. Ask for your OpenClaw config directory (default `~/.openclaw`)
2. Create your passport (OAP v1.0) there
3. Prompt to install the APort OpenClaw plugin
4. Ask for mode (default: **API**; or local) and generate `config.yaml` with plugin settings (passport path, guardrail script path, apiUrl for API mode)
5. Install guardrail wrappers in the config dir’s `.skills/` (including `aport-guardrail-bash.sh` used by the plugin in local mode)
6. **Update your passport** — the installer sets `allowed_commands: ["*"]` automatically so normal exec works with no manual editing. You only need to edit the passport later if you want to restrict commands more tightly.
7. Run a **self-check** (guardrail invoked the same way OpenClaw will use it); if it’s denied, the script exits with a clear message so you know the setup is incomplete.
8. Optionally install the APort skill and AGENTS.md rule, and run a smoke test
9. Verify plugin installation

**That's it!** Start OpenClaw with that config (e.g. `openclaw gateway start --config ~/.openclaw/config.yaml`). The plugin will enforce policies on every tool call; no extra steps required.

---

## Installation (Manual)

If you prefer manual installation:

### 1. Create Passport

```bash
./bin/aport-create-passport.sh --output ~/.openclaw/passport.json
```

### 2. Install Plugin

```bash
openclaw plugins install /path/to/aport-agent-guardrails/extensions/openclaw-aport
```

### 3. Configure Plugin

Create or edit `~/.openclaw/config.yaml`:

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        # Mode: "api" (default, recommended) or "local" (guardrail script, no network)
        mode: api

        # Passport file location
        passportFile: ~/.openclaw/passport.json

        # For local mode: path to guardrail script
        guardrailScript: ~/.openclaw/.skills/aport-guardrail-bash.sh

        # Fail-closed: block on error (default: true)
        failClosed: true
```

For **API mode (default)**, set:
```yaml
        mode: api
        apiUrl: https://api.aport.io
```
Set `APORT_API_KEY` in the environment if your API requires auth. Do not put `${APORT_API_KEY}` in the config file (OpenClaw will require the var to exist at load time).

### 4. Install Guardrail Scripts (local mode only)

If you **did not** run `./bin/openclaw`, you need the guardrail script for local mode. If you **did** run the setup script, it already created `CONFIG_DIR/.skills/aport-guardrail-bash.sh`; skip this step.

Otherwise:

```bash
mkdir -p ~/.openclaw/.skills
# Create wrapper that points to this repo (replace /path/to with real path)
cat > ~/.openclaw/.skills/aport-guardrail-bash.sh << 'EOF'
#!/bin/bash
APORT_REPO_ROOT="/path/to/aport-agent-guardrails"
export OPENCLAW_PASSPORT_FILE="${OPENCLAW_PASSPORT_FILE:-$HOME/.openclaw/passport.json}"
export OPENCLAW_DECISION_FILE="${OPENCLAW_DECISION_FILE:-$HOME/.openclaw/decision.json}"
exec "$APORT_REPO_ROOT/bin/aport-guardrail-bash.sh" "$@"
EOF
chmod +x ~/.openclaw/.skills/aport-guardrail-bash.sh
```

### 5. Verify Installation

```bash
# Check plugin is installed
openclaw plugins list | grep openclaw-aport

# Should show: openclaw-aport (enabled)
```

---

## How It Works

```
User → AI: "Delete all log files"
         ↓
    OpenClaw: AI wants to use tool "exec.run"
         ↓
    Platform: Fires before_tool_call hook
         ↓
  APort Plugin: Maps "exec.run" → "system.command.execute.v1"
         ↓
  APort Plugin: Calls guardrail script/API
         ↓
    Guardrail: Evaluates against passport + limits
         ↓
   ┌──────────┴──────────┐
   │                     │
 ALLOW                 DENY
   │                     │
   ↓                     ↓
Tool executes      Returns { block: true, blockReason }
                         ↓
                   OpenClaw throws error
                         ↓
                   Tool NEVER executes
```

**Key:** The platform enforces policy. The AI cannot skip this check.

---

## Testing

### 1. Start OpenClaw with Plugin

```bash
openclaw gateway start --config ~/.openclaw/config.yaml
```

### 2. Test Allowed Action

Try a simple command that should be allowed:

```bash
# Via OpenClaw agent
"Run: node --version"
```

Expected: Command executes (allowed by passport limits)

### 3. Test Denied Action

Try a command that exceeds your passport limits:

```bash
# Via OpenClaw agent
"Delete all files in /tmp"
```

Expected: Tool blocked with message:
```
🛡️ APort Policy Denied

Policy: system.command.execute.v1
Reason: Command exceeds allowed scope

To override, update your passport at: ~/.openclaw/passport.json
```

---

## Modes

**API mode** is still the default and recommended. **Local mode** now has full parity with API for exec mapping (fixed); both evaluate the same policies. Messaging runs at assurance L0 by default.

### API Mode (default, recommended)

**Best for:** Production, full OAP policy (JSON Schema, assurance, evaluation rules), signed decisions, cloud kill switch, audit logs.

```yaml
config:
  mode: api
  passportFile: ~/.openclaw/passport.json
  apiUrl: https://api.aport.io
```
Set `APORT_API_KEY` in the environment only if your API requires auth.

**How it works:**
- Plugin loads local passport
- Sends passport + context to APort API
- API evaluates (passport NOT stored, stateless)
- Returns signed decision
- **Network required**

### Local Mode

**Best for:** Privacy, offline use, no network dependency

```yaml
config:
  mode: local
  passportFile: ~/.openclaw/passport.json
  guardrailScript: ~/.openclaw/.skills/aport-guardrail-bash.sh
```

**How it works:**
- Plugin calls local bash script
- Script evaluates policy using local passport (subset of OAP; see [Verification methods](VERIFICATION_METHODS.md))
- Returns decision (exit 0 = allow, exit 1 = deny)
- **No network required**

---

## Troubleshooting

### Plugin not loading

```bash
# Check plugin list
openclaw plugins list

# Should show: openclaw-aport (enabled)
```

If not listed:
1. Verify installation: `openclaw plugins install /path/to/extensions/openclaw-aport`
2. Check config.yaml has `plugins.entries.openclaw-aport.enabled: true`
3. Restart OpenClaw gateway

### Tools not being blocked

Check:
1. **Plugin enabled?** `openclaw plugins list` should show `openclaw-aport (enabled)`
2. **Tool mapped?** See tool-to-policy mapping in plugin README
3. **Passport allows it?** The installer sets `allowed_commands: ["*"]` by default. If you intentionally tightened the allowlist, re-add the commands you need to `limits.system.command.execute.allowed_commands` in your passport.
4. **Script working?** Test directly:
   ```bash
   ~/.openclaw/.skills/aport-guardrail-bash.sh system.command.execute '{"command":"ls"}'
   ```

### Error: "Failed to run guardrail script"

Check:
1. Script exists: `ls -l ~/.openclaw/.skills/aport-guardrail-bash.sh`
2. Script executable: `chmod +x ~/.openclaw/.skills/aport-guardrail-bash.sh`
3. Script works: Run test command above

---

## Configuration Reference

### Minimum Configuration (API mode — default)

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: api
        passportFile: ~/.openclaw/passport.json
        apiUrl: https://api.aport.io
        failClosed: true
```

### Full Configuration (API mode)

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        # Mode: "api" (default) or "local"
        mode: api

        # Passport file location
        passportFile: ~/.openclaw/passport.json

        # For local mode: path to guardrail script
        guardrailScript: ~/.openclaw/.skills/aport-guardrail-bash.sh

        # For API mode: APort API endpoint
        apiUrl: https://api.aport.io  # or your self-hosted API URL
        # Optional: set APORT_API_KEY in the environment if your API requires auth

        # Fail-closed: block on error (default: true)
        failClosed: true
```

### Minimum Configuration (Local mode)

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: local
        passportFile: ~/.openclaw/passport.json
        guardrailScript: ~/.openclaw/.skills/aport-guardrail-bash.sh
        failClosed: true
```

---

## Tool-to-Policy Mapping

The plugin automatically maps OpenClaw tool names to APort policy packs:

| OpenClaw Tool | APort Policy |
|---------------|--------------|
| `git.create_pr`, `git.merge`, `git.push` | `code.repository.merge.v1` |
| `exec.run`, `system.command.*`, `bash` | `system.command.execute.v1` |
| `message.send`, `messaging.*` | `messaging.message.send.v1` |
| `mcp.*` | `mcp.tool.execute.v1` |
| `session.create` | `agent.session.create.v1` |
| `tool.register` | `agent.tool.register.v1` |
| `payment.refund` | `finance.payment.refund.v1` |
| `payment.charge` | `finance.payment.charge.v1` |
| `data.export` | `data.export.create.v1` |

Unmapped tools are allowed (fail-open for flexibility).

---

## Security Considerations

### Fail-Closed by Default

By default, `failClosed: true` means **any error blocks the tool**:
- Script not found → BLOCK
- API unreachable → BLOCK
- Invalid passport → BLOCK

This is secure-by-default. To fail-open (not recommended):

```yaml
config:
  failClosed: false  # Allow on error (NOT RECOMMENDED)
```

### Plugin Trust

Plugins run **in-process** with full access to OpenClaw. Only install from trusted sources:
- Official APort plugin (this)
- Your own forks/modifications

Use `plugins.allow` allowlist in config.yaml:

```yaml
plugins:
  allow:
    - openclaw-aport
    - your-other-trusted-plugin
```

### Bypass Prevention

**With plugin:** AI **cannot** bypass policy enforcement. The platform calls `before_tool_call` before every tool.

**Without plugin (AGENTS.md only):** AI **can** bypass via:
- Prompt injection
- Forgetting to call guardrail
- Deciding action is "safe"

**Bottom line:** Plugin = deterministic. AGENTS.md = best-effort (not secure).

---

## Next Steps

1. **Run the setup (once):** From repo root: `./bin/openclaw`. Use the default config dir or choose a path.
2. **Choose "yes"** when prompted to install the plugin.
3. **Start OpenClaw** with the generated config: `openclaw gateway start --config <your-config-dir>/config.yaml` (e.g. `~/.openclaw/config.yaml`).
4. **Test enforcement:** Run the agent; try an allowed action (e.g. `node --version`) and one that should be blocked by your passport (e.g. `rm -rf /`). The plugin blocks before the tool runs.
5. **Customize passport:** Edit `<config-dir>/passport.json` to adjust limits and allowed commands.

---

## Support

- **Full documentation:** [`extensions/openclaw-aport/README.md`](../extensions/openclaw-aport/README.md)
- **Issues:** [GitHub Issues](https://github.com/aporthq/aport-agent-guardrails/issues)
- **Discord:** [discord.gg/aport](https://discord.gg/aport)

---

## Summary

✅ **One command:** Run `./bin/openclaw` from the repo root to create passport, install plugin, write config and wrappers, and verify. You only need this once per config dir.
✅ **Deterministic enforcement:** The plugin runs before every tool; the platform enforces, the AI cannot bypass.
✅ **Fail-closed:** Blocks on error by default.
✅ **API (default) or local:** Full OAP via API, or local script for offline/privacy.
✅ **Zero OpenClaw core changes:** Uses the existing OpenClaw plugin API.

**After setup, start OpenClaw with the generated config—your agent is then secured by APort policy.**

---

## How it all fits together

| Step | What happens |
|------|----------------|
| You run `./bin/openclaw` | Script asks for config dir, creates passport, installs plugin, writes `config.yaml`, installs wrappers in `<config-dir>/.skills/`, and **updates the passport** with default `allowed_commands` (bash, sh, ls, mkdir, npm, etc.) so normal exec works. |
| `config.yaml` | Contains `passportFile` and `guardrailScript` pointing to `<config-dir>/passport.json` and `<config-dir>/.skills/aport-guardrail-bash.sh`. |
| Passport allowlist | The installer sets `allowed_commands: ["*"]` automatically. No manual editing needed unless you want to restrict commands. |
| Wrapper script | `<config-dir>/.skills/aport-guardrail-bash.sh` is a small script that calls this repo’s `bin/aport-guardrail-bash.sh` with the same args and env (passport path, etc.). |
| You start OpenClaw | `openclaw gateway start --config <config-dir>/config.yaml` (or use that config when running the agent). |
| On every tool call | OpenClaw runs the plugin’s `before_tool_call` hook → plugin calls the guardrail script with tool name and params → script evaluates against passport and policy → allow = tool runs, deny = plugin returns `block: true` and the tool never runs. |

**So: one run of `./bin/openclaw` is all you need.** No manual editing of config or wrapper paths if you use the default config dir.

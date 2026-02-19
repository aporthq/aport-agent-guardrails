# OpenClaw Plugin Migration Guide

> **Note**: This is the **OpenClaw-specific plugin** within the broader [aport-agent-guardrails](https://github.com/aporthq/aport-agent-guardrails) repository, which provides guardrails for multiple AI agent frameworks including LangChain, CrewAI, n8n, Cursor, and OpenClaw.

## Breaking Changes in OpenClaw 2026.2

The APort OpenClaw plugin has been updated to comply with OpenClaw 2026.2's new plugin architecture. If you're upgrading from an older version, please read this guide.

## What Changed

### Old Architecture (Pre-2026.2)

```javascript
// Old: Function-based plugin
export default function (api) {
  api.on("before_tool_call", async (event, ctx) => {
    // handler code
  });
}
```

**Package.json:**
```json
{
  "openclaw": {
    "extensions": ["openclaw-aport"]  // ❌ String reference
  }
}
```

### New Architecture (2026.2+)

```typescript
// New: Object-based plugin with TypeScript
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";

const plugin = {
  id: "openclaw-aport",
  name: "APort Guardrails",
  description: "...",
  configSchema: { /* JSON Schema */ },
  register(api: OpenClawPluginApi) {
    api.on("before_tool_call", async (event, ctx) => {
      // handler code
    });
  },
};

export default plugin;
```

**Package.json:**
```json
{
  "openclaw": {
    "extensions": ["./index.ts"]  // ✅ Path to TypeScript file
  }
}
```

## Key Architectural Changes

### 1. Plugin Structure

| Old | New |
|-----|-----|
| Export function | Export object with `id`, `name`, `description`, `configSchema`, `register()` |
| JavaScript (.js) | TypeScript (.ts) preferred |
| Immediate execution | Lazy loading via `register()` method |

### 2. Type Safety

```typescript
// Import OpenClaw types
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";

// Config type safety
interface APortPluginConfig {
  mode?: "local" | "api";
  agentId?: string;
  passportFile?: string;
  // ...
}
```

### 3. Entry Point

The `openclaw.extensions` field in `package.json` must now point to a file path:

```json
{
  "openclaw": {
    "extensions": ["./index.ts"]  // Path to entry file
  }
}
```

### 4. Dev Dependencies

```json
{
  "devDependencies": {
    "openclaw": ">=2026.2.0",
    "@types/node": "^18.0.0",
    "typescript": "^5.0.0"
  }
}
```

## Upgrading from Old Installation

If you had the old plugin installed (OpenClaw < 2026.2), you need to **remove the old installation first** to avoid conflicts.

### Step 1: Remove Old Plugin Configuration

Edit your OpenClaw config file (usually `~/.openclaw/openclaw.json` or `~/.openclaw/config.json`) and remove:

- `plugins.load.paths` — delete the entry pointing to `openclaw-aport`
- `plugins.entries.openclaw-aport` — delete the entire block
- `plugins.installs.openclaw-aport` — delete the entire block

**Keep** `plugins.entries` intact if other plugins are configured (e.g. `whatsapp`).

**Example — Before:**

```json
{
  "plugins": {
    "load": {
      "paths": [
        "/path/to/aport-agent-guardrails/extensions/openclaw-aport"
      ]
    },
    "entries": {
      "whatsapp": { "enabled": false },
      "openclaw-aport": {
        "enabled": true,
        "config": { "mode": "api", "passportFile": "..." }
      }
    },
    "installs": {
      "openclaw-aport": {
        "source": "path",
        "sourcePath": "/path/to/openclaw-aport",
        "installPath": "/path/to/openclaw-aport"
      }
    }
  }
}
```

**After:**

```json
{
  "plugins": {
    "entries": {
      "whatsapp": { "enabled": false }
    }
  }
}
```

### Step 2: Restart Gateway

```bash
openclaw gateway restart
```

### Step 3: Verify Clean State

```bash
openclaw gateway status
openclaw plugins list
```

Confirm: no config errors, `openclaw-aport` not listed, RPC probe shows `ok`.

### Step 4: Install New Version

Now install the updated plugin:

```bash
# Link for development (recommended)
openclaw plugins install -l /path/to/aport-agent-guardrails/extensions/openclaw-aport

# Or install from directory
openclaw plugins install /path/to/aport-agent-guardrails/extensions/openclaw-aport
```

This will:
- Add the new plugin configuration to your config
- Link to the `index.ts` entry point
- Apply the new object-based plugin structure

### Step 5: Configure Plugin

Edit your OpenClaw config (now in YAML format, typically `~/.openclaw/config.yaml`):

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: local  # or "api"
        passportFile: ~/.openclaw/aport/passport.json
        guardrailScript: ~/.openclaw/.skills/aport-guardrail-bash.sh
        failClosed: true
        allowUnmappedTools: true
```

### Step 6: Restart and Verify

```bash
openclaw gateway restart
openclaw plugins list
```

You should see:

```
┌──────────────┬──────────┬────────┬────────────────────────────────┬─────────┐
│ Name         │ ID       │ Status │ Source                         │ Version │
├──────────────┼──────────┼────────┼────────────────────────────────┼─────────┤
│ APort        │ openclaw │ loaded │ ~/path/to/openclaw-aport/      │ 1.0.0   │
│ Guardrails   │ -aport   │        │ index.ts                       │         │
```

## Fresh Installation (No Previous Version)

### Verify Fresh Installation

```bash
# Link for development (recommended)
openclaw plugins install -l /path/to/aport-agent-guardrails/extensions/openclaw-aport

# Then check
openclaw plugins list
```

You should see:
```
┌──────────────┬──────────┬────────┬────────────────────────────────┬─────────┐
│ Name         │ ID       │ Status │ Source                         │ Version │
├──────────────┼──────────┼────────┼────────────────────────────────┼─────────┤
│ APort        │ openclaw │ loaded │ ~/path/to/openclaw-aport/      │ 1.0.0   │
│ Guardrails   │ -aport   │        │ index.ts                       │         │
```

Then configure in your `config.yaml` (see Configuration section above).

## Configuration

Configuration remains the same in your OpenClaw `config.yaml`:

```yaml
plugins:
  enabled: true
  entries:
    openclaw-aport:
      enabled: true
      config:
        mode: local  # or "api"
        passportFile: ~/.openclaw/aport/passport.json
        guardrailScript: ~/.openclaw/.skills/aport-guardrail-bash.sh
        failClosed: true
        allowUnmappedTools: true
```

## Testing

Run the plugin unit tests:

```bash
cd extensions/openclaw-aport
node test.js
```

Expected output:
```
# tests 21
# pass 21
# fail 0
```

## Backwards Compatibility

The old `index.js` file is preserved for backwards compatibility with tests and older OpenClaw versions. However, OpenClaw 2026.2+ will use `index.ts`.

## Troubleshooting

### Old Plugin Still Loading After Upgrade

**Symptom:**
```
[plugins] [APort] Loaded: ...
```
But you're seeing errors or the plugin isn't working correctly.

**Solution:**
The old plugin is still configured. Follow "Step 1: Remove Old Plugin Configuration" above and restart the gateway:

```bash
# 1. Edit config to remove old entries
vim ~/.openclaw/openclaw.json  # or config.json

# 2. Restart
openclaw gateway restart

# 3. Verify old plugin is gone
openclaw plugins list  # Should NOT show openclaw-aport

# 4. Reinstall new version
openclaw plugins install -l /path/to/aport-agent-guardrails/extensions/openclaw-aport
```

### Plugin Not Loading

**Error:**
```
Config validation failed: plugins: plugin: extension entry escapes package directory
```

**Solution:**
Ensure `package.json` has:
```json
{
  "openclaw": {
    "extensions": ["./index.ts"]  // Must be a file path, not a string reference
  }
}
```

### Config File Format Confusion

OpenClaw 2026.2 uses YAML (`config.yaml`) for primary configuration, but plugin install metadata lives in JSON (`openclaw.json`):

- **`~/.openclaw/config.yaml`** - Your main config (plugins.entries, passport paths, etc.)
- **`~/.openclaw/openclaw.json`** - Plugin install metadata (managed by `openclaw plugins install`)

When upgrading, edit the **JSON file** to remove old plugin entries, then use **YAML file** for new plugin configuration.

### TypeScript Errors

OpenClaw uses `jiti` to load TypeScript files at runtime, so you don't need to compile `.ts` to `.js`. However, for type checking during development:

```bash
npm install
npx tsc --noEmit  # Check types without compiling
```

### Import Errors

**Error:**
```
Cannot find module 'openclaw/plugin-sdk'
```

**Solution:**
Ensure OpenClaw is installed:
```bash
npm install -g openclaw
```

Or add to devDependencies:
```json
{
  "devDependencies": {
    "openclaw": ">=2026.2.0"
  }
}
```

## Security Note

OpenClaw 2026.2 introduced stricter security controls:
- Agent-based access controls (`allowedAgents`)
- Disabled plugin runtime command execution primitive
- Explicit opt-in for deprecated features

These changes don't affect the APort plugin's functionality but provide additional security layers at the OpenClaw level.

## Resources

- [OpenClaw Plugin Documentation](https://docs.openclaw.ai/tools/plugin)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [APort Documentation](https://github.com/aporthq/aport-agent-guardrails)

## Version Compatibility

| OpenClaw Version | APort Plugin |
|------------------|--------------|
| < 2026.2 | Use old `index.js` (function-based) |
| >= 2026.2 | Use new `index.ts` (object-based) |

The plugin now requires OpenClaw 2026.2.0 or later.

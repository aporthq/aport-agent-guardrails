# OpenClaw Plugin Migration Guide

This guide is for teams upgrading older APort OpenClaw installs to the current scanner-safe plugin bundle.

## What changed

Current plugin versions:

- ship JavaScript runtime files only (`index.js` plus helpers)
- use a built-in JavaScript local evaluator instead of spawning `child_process`
- call the hosted API directly in API mode
- avoid source-linked `plugins.load.paths` entries that point into transient `npx` cache directories

## Recommended upgrade path

Re-run the public setup command:

```bash
npx @aporthq/aport-agent-guardrails openclaw
```

That will:

1. Reinstall the plugin
2. Refresh `plugins.entries.openclaw-aport`
3. Remove stale source-linked `plugins.load.paths` and `plugins.installs.openclaw-aport` entries
4. Refresh the APort wrappers under `CONFIG_DIR/.skills/`

## Development upgrade path

If you are working from a local checkout:

```bash
openclaw plugins install -l /path/to/aport-agent-guardrails/extensions/openclaw-aport
```

Then re-run the installer or update `plugins.entries.openclaw-aport` in your config.

## Local mode

Local mode still exists, but current plugin versions evaluate locally in JavaScript. The `guardrailScript` field remains for manual shell-based smoke tests and legacy tooling; the plugin no longer depends on it for local-mode enforcement.

## If you previously installed from an old `npx` cache path

Older setups could leave `openclaw.json` pointing at a transient `~/.npm/_npx/.../extensions/openclaw-aport` directory. Re-running the setup command cleans that up.

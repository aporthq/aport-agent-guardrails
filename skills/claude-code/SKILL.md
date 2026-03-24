---
name: claude-code
description: Set up APort guardrails for Claude Code. Creates a passport and activates the PreToolUse hook that enforces policy on every tool call. Local evaluation by default, zero network calls.
---

You are setting up APort Agent Guardrails for Claude Code. Follow these steps in order.

## Step 1: Check prerequisites

Run these checks. If either fails, tell the user what to install and stop.

```bash
bash --version | head -1
```
Expected: `GNU bash, version 4` or higher.

```bash
jq --version
```
Expected: `jq-1.x`. If missing, tell the user: `brew install jq` (macOS) or `apt install jq` (Linux).

## Step 2: Check if already configured

```bash
${CLAUDE_PLUGIN_ROOT}/bin/aport-status.sh 2>/dev/null
```

If this prints passport info, guardrails are already active. Ask the user if they want to reconfigure. If they say no, stop here.

If it prints nothing or errors, continue to Step 3.

## Step 3: Run the passport wizard

```bash
APORT_FRAMEWORK=claude-code ${CLAUDE_PLUGIN_ROOT}/bin/aport-create-passport.sh --framework=claude-code
```

This is an interactive wizard. It will prompt the user for:
- Passport mode (local or hosted)
- Agent capabilities (which tools to allow)
- Limits (rate limits, file restrictions)

Let the user interact with the wizard directly. Do not answer the prompts for them.

Expected outcome: A passport file is created at `~/.claude/aport/passport.json`.

## Step 4: Verify

```bash
${CLAUDE_PLUGIN_ROOT}/bin/aport-status.sh
```

Expected: Shows passport location, agent ID, and evaluation mode. If this succeeds, tell the user guardrails are active.

The PreToolUse hook is registered automatically by the plugin system. No `settings.json` editing is needed.

## Troubleshooting

If the wizard fails or status shows no passport:
- Check `~/.claude/aport/` directory exists
- Check the user has write permissions to `~/.claude/`
- Run with `DEBUG_APORT=1` prefix for verbose output

## References

- [Source code](https://github.com/aporthq/aport-agent-guardrails) (Apache 2.0)
- [Claude Code guide](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/frameworks/claude-code.md)

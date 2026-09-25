---
name: status
description: Check APort guardrail status — passport validity, evaluation mode, and recent audit log entries. Works for all frameworks.
---

You are checking the current state of APort Agent Guardrails.

## Step 1: Run status check

```bash
${CLAUDE_PLUGIN_ROOT}/bin/aport-status.sh
```

Expected output includes:
- Passport file location and whether it is valid
- Agent ID and assurance level
- Evaluation mode (local or API)
- Whether AGENTS.md enforcement is active

## Step 2: Show recent decisions

The audit log is `<config dir>/aport/audit.log`, next to the passport that Step 1 printed. `~/.claude/aport/` is the Claude Code default; if `APORT_CLAUDE_CODE_CONFIG_DIR` is set, use that directory instead.

```bash
cat ~/.claude/aport/audit.log 2>/dev/null | tail -10 || echo "No audit log found."

Report the results to the user.

## If no passport is found

Tell the user no guardrails are configured and suggest running `/aport-guardrails:claude-code` to set up.

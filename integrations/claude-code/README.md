# Claude Code integration

APort guardrails for [Claude Code](https://code.claude.com) via the **PreToolUse** hook. Enforcement runs outside the model's context — the agent cannot reason past it.

## Quick start

```bash
npx @aporthq/aport-agent-guardrails claude-code
```

This installs the passport wizard and writes `~/.claude/settings.json` with the APort hook for all tools (`"matcher": "*"`). Restart Claude Code after setup.

## Full docs

See [docs/frameworks/claude-code.md](../../docs/frameworks/claude-code.md) for:

- How it works (PreToolUse, hook output format)
- Tool → policy mapping (Bash, Write, WebSearch, Task, MCP, etc.)
- What's not protected (`--dangerously-skip-permissions`)
- Testing and audit log location

## Implementation

- **Hook script:** [bin/aport-claude-code-hook.sh](../../bin/aport-claude-code-hook.sh)
- **Installer:** [bin/frameworks/claude-code.sh](../../bin/frameworks/claude-code.sh)
- **Node package:** [packages/claude-code](../../packages/claude-code) — `Evaluator`, `getHookPath()`

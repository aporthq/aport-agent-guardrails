# Skills

APort Agent Guardrails ships skills for Claude Code's plugin system. Skills are invoked
as `/aport-guardrails:<skill-name>`.

## Naming Convention

Skill folder names are short and scoped. The plugin name (`aport-guardrails`) provides
the namespace automatically, so skill names should not repeat it.

| Pattern | When to use | Example invocation |
|---------|-------------|-------------------|
| `<framework>` | Framework-specific setup | `/aport-guardrails:claude-code` |
| `<action>` | Cross-framework actions | `/aport-guardrails:status` |

## Available Skills

| Skill | Invocation | Purpose |
|-------|------------|---------|
| `claude-code` | `/aport-guardrails:claude-code` | Set up guardrails for Claude Code |
| `openclaw` | `/aport-guardrails:openclaw` | Set up guardrails for OpenClaw |
| `status` | `/aport-guardrails:status` | Check guardrail status (all frameworks) |

## Adding a New Skill

1. Create `skills/<name>/SKILL.md`
2. Include frontmatter: `name` and `description` (required)
3. The `name` field must match the folder name
4. Write instructions addressed to the agent ("You are setting up...")

## Skill Directory Structure

```
skills/
  claude-code/
    SKILL.md
  openclaw/
    SKILL.md
  status/
    SKILL.md
```

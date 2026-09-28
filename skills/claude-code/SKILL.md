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
Expected: `jq-1.x`. If missing, tell the user: `brew install jq` (macOS) or `apt install jq` (Linux). The hook calls `jq` on every tool call; without it every call is denied with `APort: jq is required`, in warn mode too.

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

Two prompts matter more than the rest:
- `Spawn sub-agents and tasks? [Y/n]`: keep `Y`. Without the `agent.session.create` capability every Agent, Task, Skill, SendMessage, team, cron and workflow call is denied.
- The system-commands prompt (`Enter or *=allow any / list=fixed list`): a fixed list is a prefix allowlist, and any chained command (`&&`, `;`, `|`) is then denied outright.

Expected outcome: A passport file is created at `~/.claude/aport/passport.json`, or at `$APORT_CLAUDE_CODE_CONFIG_DIR/aport/passport.json` when that variable is set. If it is set, it must also be set in the environment Claude Code runs in; the hook reads it at run time and otherwise looks in `~/.claude`.

## Step 4: Verify

```bash
${CLAUDE_PLUGIN_ROOT}/bin/aport-status.sh
```

Expected: Shows passport location, agent ID, and evaluation mode. If this succeeds, tell the user guardrails are active.

The PreToolUse hook is registered automatically by the plugin system. No `settings.json` editing is needed.

## Limits to tell the user about

- Bash commands are checked as text only: `allowed_commands` is a prefix match; `blocked_patterns` uses word-boundary and glob matching, case-insensitive: a single word such as `sudo` matches only as a whole word (it does not block `sudoku`), an entry containing `*` or `?` is a glob, and a multi-word entry such as `rm -rf` matches as written; when `allowed_commands` is restrictive (not `*`), a command containing an unquoted `&&`, `||`, `;`, `|`, `&`, newline, `(`, `)`, `$(`, `<(`, `>(`, a `#` comment or `$'...'` quoting is denied with `oap.command_chain_unsupported`. The hook does not see which files `cat` or `>` touch, where `git push` goes, or which host `curl` contacts. Path and domain limits apply to the Read, Write, Edit and WebFetch tools. Pair APort with the sandbox, a branch ruleset and a scoped token for the rest.
- Reads of `.env` and anything starting with `.env`, the `.ssh`, `.aws`, `.gnupg` and `.kube` directories, `id_rsa`, `id_dsa`, `id_ecdsa` and `id_ed25519` anywhere in the path, files ending in `.pem` or `.key`, and any path containing `credentials` or `password` are always denied (case-insensitive). Other `id_*` names such as `id_token` are not on the list. Anything else (for example `~/.codex/auth.json`) needs a `limits["data.file.read"].blocked_patterns` entry (substring match). Writes have no built-in list; use `limits["data.file.write"].blocked_paths` (path prefix).
- A Bash call with no `timeout` is judged under Claude Code's 120 s default. A call with `run_in_background` or a malformed timeout has no bound, so a passport that sets `max_execution_time` denies it with `oap.missing_required_context`; drop the limit or run the command in the foreground.
- Grep without a `file_path` and any unknown tool are denied, and warn mode does not change that.

## Troubleshooting

If the wizard fails or status shows no passport:
- Every tool call denied with `jq is required`: install `jq` on the PATH Claude Code uses
- Check `~/.claude/aport/` (or `$APORT_CLAUDE_CODE_CONFIG_DIR/aport/`) directory exists
- Check the user has write permissions to `~/.claude/`
- Run with `DEBUG_APORT=1` prefix for verbose output

## References

- [Source code](https://github.com/aporthq/aport-agent-guardrails) (Apache 2.0)
- [Claude Code guide](https://github.com/aporthq/aport-agent-guardrails/blob/main/docs/frameworks/claude-code.md)

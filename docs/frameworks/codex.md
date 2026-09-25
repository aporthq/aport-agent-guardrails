# APort Agent Guardrail - Codex CLI

**Status:** Shipped beta command-hook harness. APort installs a Codex
`PreToolUse` hook for supported tool calls, stores secrets/state outside the
repository, and reuses the same hosted/local verifier path as the released
framework integrations.

APort integrates with Codex through Codex lifecycle hooks. The installer writes a repo-local `.codex/hooks.json` by default so a repository can opt into policy checks without changing the user's global Codex configuration.

## Quick start

```bash
npx @aporthq/aport-agent-guardrails codex
```

Use `--global` if you want the hook in `~/.codex/hooks.json` instead of the current repository:

```bash
npx @aporthq/aport-agent-guardrails codex --global
```

**Prerequisites:** `jq` on the PATH Codex uses. The hook denies every tool call with `oap.missing_dependency` when `jq` is missing.

**Beta limits, stated plainly.** The Codex hook denies two things Codex does routinely, and warn mode does not lift either of them because they are hook-level denials, not policy denials:

- `apply_patch` calls that touch more than one file (`oap.multi_path_write_unsupported`). Ask Codex to split patches so each call edits one file.
- `Glob`, `List`, `LS` and `LSP` calls, with or without a path (`oap.metadata_enumeration_unsupported`, or `oap.missing_file_path` when no target is given). Directory listings therefore have to come from shell commands such as `ls`, which the command policy judges.

`--enforcement=warn` still helps with everything else: policy denials such as a `blocked_patterns` hit or a path outside `allowed_paths` are recorded and allowed while you tune the passport.

Hosted passport setup is the recommended path for signed decisions and centralized audit:

```bash
APORT_OWNER_EMAIL="you@example.com" \
APORT_QUICK_HOSTED=1 \
npx --yes @aporthq/aport-agent-guardrails codex --non-interactive
```

Non-interactive local passport (framework defaults, no prompts):

```bash
npx --yes @aporthq/aport-agent-guardrails codex --mode=local --non-interactive \
  --output ~/.aport/codex/aport/passport.json
```

Interactive local passport: run `npx @aporthq/aport-agent-guardrails codex`, choose `3. Create local passport file`, and answer the wizard. Keep `Spawn sub-agents and tasks?` at `Y` (the Codex default); the collaboration tools (`spawn_agent`, `send_message`, `wait_agent` and the rest) map to `agent.session.create.v1` and are denied without that capability.

Hook wiring is project-local by default, but APort state is not. Hosted API keys, mode settings, local passports, and audit files default to `~/.aport/codex/aport` so they are not written into the repository.

To put that state elsewhere, set `APORT_CODEX_CONFIG_DIR` when running the installer. It writes `APORT_CODEX_CONFIG_DIR=<dir>` into the hook command in `hooks.json`, so the hook finds the same directory at run time without any change to Codex's environment. `mode` and `reset` read the variable too. For a passport outside that directory, set `APORT_PASSPORT_FILE` and `APORT_ALLOW_EXTERNAL_PASSPORT_FILE=1`; without the second variable the hook ignores an external path (`bin/lib/framework-hook-paths.sh`).

## How it works

Codex loads hooks from `hooks.json` or inline `config.toml` hook tables next to active configuration layers. Project hooks only run after the project `.codex/` layer is trusted. APort uses `hooks.json` only, and the setup command preserves unrelated hooks.

APort registers command hooks for:

| Codex event | APort behavior |
|-------------|----------------|
| `PreToolUse` | Enforces policy before supported tools execute. |
| `PermissionRequest` | Supported by the wrapper for manual wiring, but not installed by default to avoid double-counting hosted decisions. |
| `PostToolUse` | Registered only for local session lifecycle bookkeeping. APort returns allow and does not forward tool output. |

The hook wrapper is `bin/aport-codex-hook.sh`, which delegates to the shared `bin/lib/command-hook-adapter.sh` and existing APort evaluator. This keeps Codex behavior aligned with Claude Code and Cursor without duplicating policy logic.

## Tool coverage

| Codex tool family | APort policy |
|-------------------|--------------|
| `shell`, `local_shell`, `exec_command`, `unified_exec`, `container_exec`, `js_repl`, `code_mode_exec` and other shell or exec tools | `system.command.execute.v1` |
| `apply_patch`, write/edit/delete tools | `data.file.write.v1` |
| `read_file`, `view_image`, `grep` and other path-based reads and content searches | `data.file.read.v1` |
| `web_fetch`, `web_search`, `webrun`, `browser`, `open_url`, `fetch_url`, `http_request`, `computer_use` | `web.fetch.v1` |
| `image_gen.imagegen` / `image_genimagegen` | `media.image.generate.v1` |
| MCP tools and MCP resource reads | `mcp.tool.execute.v1` |
| `spawn_agent`, `send_message`, `wait_agent` and the other collaboration tools | `agent.session.create.v1` |
| `Glob`, `List`, `LS`, `LSP` | denied by the hook: `oap.metadata_enumeration_unsupported` with a target, `oap.missing_file_path` without |
| `TodoRead`, `ToolSearch`, `update_plan`, `request_user_input`, `memory_operators` and other `memory_*` tools | allowed without evaluator: session bookkeeping, plan updates, prompts to the user, and Codex's own memory store |
| `write_stdin` | `system.command.execute` on its `chars` |

`write_stdin` submits keystrokes into a session that `exec_command` or `unified_exec` opened. When that session is an interactive shell, the keystrokes are a new command, so the `chars` are evaluated against `system.command.execute` rather than waved through with the bookkeeping tools. A non-empty chunk must contain complete, non-whitespace terminal input. Partial chunks and whitespace/control-only chunks deny with `oap.partial_stdin_unsupported`, because APort cannot authorize split shell input or prove that a newline will not execute already-buffered text. The cost is that keystrokes bound for a pager or a REPL are judged by the command policy too, which can deny input no shell would have run.

`image_gen.imagegen` is authorized as image generation, not as a generic web fetch. The hook sends metadata only to `media.image.generate.v1`: provider, optional model/size/aspect ratio, prompt length, referenced image count, output count, and output format. It never forwards raw prompt text, image contents, or local image paths. The passport must configure `limits["media.image.generate"].allowed_providers`, `max_prompt_length`, `max_referenced_images`, `max_output_images`, and `allowed_output_formats`; missing or malformed limits fail closed with `oap.invalid_limit`. Set `APORT_IMAGE_GENERATION_PROVIDER` if your hosted verifier should see a provider name other than `openai`. If the call includes `referenced_image_paths`, the hook denies with `oap.multi_policy_tool_unsupported` because the tool needs both local file-read and image-generation authorization and the shell hook can safely emit only one decision.

An unmapped tool name is denied with `oap.unknown_tool`. Codex adds tools faster than this table changes, but a name nobody has mapped is a name nobody has decided the capability for, and the payload cannot decide it: a `url` field on a payment tool is not a web fetch, and a `command` field on a database tool is not a shell call. Add the name to the table instead of relying on a guess.

Operators who have reviewed their own tool surface can set `APORT_CODEX_TOOL_FALLBACK=on` in the hook's environment. Unmapped names are then routed by what their payload carries in `tool_input`, `input`, `args`, or nested `args`/`arguments`: a `url` to the web policy, a `file_path` or `path` with `content`, `edits` or `new_string` to the write policy, a `file_path` or `path` alone to the read policy, a `command`, `cmd` or `script` to the command policy. Nothing is inferred from the name, so `execute_sql` with a `command` is judged as a command and `read_secret_from_vault` with only a `key` is still denied. A payload that carries more than one of those effects (a `command` and a `url`, say) is denied with `oap.invalid_tool_arguments`: routing it would mean picking one effect and letting the others through unevaluated.

Timeouts: `shell` and `local_shell` calls that carry no `timeout_ms` are judged under Codex's 10 s default (`DEFAULT_EXEC_COMMAND_TIMEOUT_MS`), because that default kills the process. `exec_command` and `unified_exec` get no default: the process outlives the call and `write_stdin` can keep driving it. A passport that sets `limits["system.command.execute"].max_execution_time` therefore denies `exec_command` and `unified_exec` calls without an explicit `timeout_ms` (`oap.missing_required_context`), and any call whose timeout exceeds the limit (`oap.timeout_exceeded`). Drop the limit or use `shell`.

Unknown effectful tools fail closed in enforce mode. File read/write tools that
do not expose an evaluable path also fail closed rather than silently bypassing
policy. `apply_patch` payloads that touch more than one file fail closed in the
beta hook because a single local evaluator call can authorize only one path
without producing misleading partial audit records. Split multi-file patches
while using the beta hook. `Glob`, `List`, `LS` and `LSP` fail closed whether
or not a path is supplied, because the hook cannot authorize every expanded
result before the host returns filenames. `WebSearch` is network-backed
but may not expose a concrete destination URL; in local enforce mode APort fails
closed when the hook cannot verify a URL or domain against passport limits. Use
hosted mode or warn mode while tuning search-heavy workflows.

Shell commands are judged by text only: `allowed_commands` is a prefix match; `blocked_patterns` uses word-boundary and glob matching, case-insensitive: a single word such as `sudo` matches only as a whole word (it does not block `sudoku`), an entry containing `*` or `?` is a glob, and a multi-word entry such as `rm -rf` matches as written; when `allowed_commands` is restrictive (not `*`), a command containing an unquoted `&&`, `||`, `;`, `|`, `&`, newline, `(`, `)`, `$(`, `<(`, `>(`, a `#` comment or `$'...'` quoting is denied with `oap.command_chain_unsupported`. The hook does not parse `git push` targets, files read by `cat` or written with `>`, or hosts contacted by `curl`; see [What the Bash policy does and does not see](../SECURITY_MODEL.md#what-the-bash-policy-does-and-does-not-see).

## Enforcement modes

Default is `enforce`: deny decisions block the Codex tool call. To roll out in report-only mode:

```bash
npx @aporthq/aport-agent-guardrails mode codex --enforcement=warn
```

Warn mode records the original deny decision locally or in APort hosted audit,
then returns allow semantics with a warning. It applies only after APort
completed policy evaluation; malformed hook input, invalid config, missing
dependencies, and unmapped effectful tools still fail closed. Use warn mode only
while tuning policy. The multi-file `apply_patch` and `Glob`/`List`/`LS` denials
described above are hook-level, so they stay denied in warn mode.

## Validate

After setup, run `/hooks` in Codex and trust the APort hook definition when prompted. Then ask Codex to run a blocked command such as `rm -rf /tmp/aport-test` and confirm Codex receives an APort denial.

Local unit coverage:

```bash
bash tests/unit/test-command-hook-adapter.sh
bash tests/unit/test-harness-tool-surface.sh
bash tests/frameworks/codex/setup.sh
```

## Source references

- Codex hook docs: https://learn.chatgpt.com/docs/hooks
- Codex advanced configuration: https://learn.chatgpt.com/docs/config-file/config-advanced

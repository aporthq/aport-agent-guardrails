# Repository Guidance

APort Agent Guardrails is a fail-closed pre-action authorization system. Prefer shared adapters and evaluators over framework-specific forks. Keep local/offline verification intentionally small; stateful or enterprise-grade policy depth belongs in the hosted verifier.

## Code Review Rules

### Harness Enforcement

- Unknown, malformed, or unrepresentable pre-action tool calls must fail closed in enforce mode. Warn/report-only mode may downgrade completed policy denials, but must not bypass adapter/runtime failures, missing required context, state corruption, parser ambiguity, or hook schema drift.

- Shell command allowlists must authorize every executable segment. A single allowed prefix must not allow prefixed executables, shell chains, pipes, newlines, command substitution, or later commands that were not independently authorized.

- File read, write, metadata, search, patch, MCP, web, and session adapters must forward only minimal policy metadata. Do not send or persist raw prompts, file contents, secrets, credentials, signed URLs, query tokens, or fragments.

- Any configured local limit must either be enforced deterministically or fail closed with a specific reason. Do not silently ignore configured limits such as file size, web rate limits, MCP server/tool limits, timeout limits, session concurrency, or repository action capabilities.

- Hosted mode uses the APort API as source of truth; local mode is a lightweight free verifier. Do not copy hosted-only enterprise/stateful behavior into local mode unless the local evidence is trustworthy and bounded.

### Configuration Safety

- Setup, mode switching, and reset flows must resolve the same active config locations used by the hooks, reject symlinked config/runtime targets before writing or deleting, and avoid deleting shared runtime state while any installed hook still references it.

- API keys and hosted passport IDs must be optional for local mode but validated and preserved correctly for hosted mode. Do not hard-code key prefixes beyond documented compatibility helpers.

### Documented Limits

Docs, skills and installer output must state these the same way; change them only together with the code that defines them.

- Shell policy (`system.command.execute.v1`) sees only the command string: `allowed_commands` is a prefix match (`safe_prefix_match`); `blocked_patterns` uses word-boundary and glob matching, case-insensitive: a single word such as `sudo` matches only as a whole word (it does not block `sudoku`), an entry containing `*` or `?` is a glob, and a multi-word entry such as `rm -rf` matches as written (`safe_pattern_match`); when `allowed_commands` is restrictive (not `*`), a command containing an unquoted `&&`, `||`, `;`, `|`, `&`, newline, `(`, `)`, `$(`, `<(`, `>(`, a `#` comment or `$'...'` quoting is denied with `oap.command_chain_unsupported` (`shell_command_has_unquoted_control_operator`). It does not parse `git push` targets, files read or written by the command, `>` redirects, or `curl` destinations. `allowed_paths` and domain limits apply to the host's own read/write/web tools only. Source: `bin/aport-guardrail-bash.sh`, `bin/lib/validation.sh`.
- Default sensitive read list (`is_default_sensitive_read_path`), case-insensitive: `.env` and anything starting with `.env`, the `.ssh`, `.aws`, `.gnupg` and `.kube` directories, `id_rsa`, `id_dsa`, `id_ecdsa` and `id_ed25519` anywhere in the path, files ending in `.pem` or `.key`, and any path containing `credentials` or `password`. Other `id_*` names such as `id_token` are not on the list. Nothing else is blocked by default. Reads are governed by `limits["data.file.read"].blocked_patterns` (substring match); writes by `limits["data.file.write"].blocked_paths` (path prefix).
- Shell timeouts (`bin/lib/harness-context.sh`): a call with no timeout is judged under the harness default only when the harness has one and the call is bounded by it. Claude Code Bash/PowerShell/Monitor: 120 s (120000 ms default). Codex `shell`/`local_shell`: 10 s. Codex `exec_command`/`unified_exec`: no default, the process outlives the call. Cursor, Gemini CLI, Goose: no timeout, treated as unbounded. A malformed timeout key or `run_in_background`/`persistent` also gets no default. Without a timeout value, a passport that sets `max_execution_time` denies with `oap.missing_required_context`; above the limit, `oap.timeout_exceeded`. Say it plainly in docs: `max_execution_time` blocks unbounded tools; drop the limit or use a bounded tool.
- Codex tool routing (`bin/lib/command-hook-adapter.sh`): `webrun`, `browser`/`browse`, `computer_use`, `image_gen.imagegen` / `image_genimagegen`, MCP resource functions, `request_plugin_install`, `local_shell`, `write_stdin`, `update_plan`, `request_user_input`, `request_user_input_async`, `send_message_to_user_async`, `request_permissions`, `wait`, `wait_for_environment`, `get_context_remaining`, `new_context`, `clock.*`, read-only provider memory tools, `skills.*`, goal tools and collaboration tools are listed explicitly. `memories.add_ad_hoc_note` is a persistent provider-memory write and fails closed as `oap.unrepresentable_tool` until a policy representation exists. `scripts/check-codex-provider-tool-surface.sh` is the Codex drift gate: it extracts names from upstream `openai/codex` and CI/pre-push must fail if any provider tool reaches `oap.unknown_tool`. `request_user_input_sync` is not documented or locally observed; leave it unmapped until a real Codex payload is captured. Image generation maps to `media.image.generate.v1` with metadata only, never raw prompts or image paths. Browser navigation maps to `web.browser.v1`; local interactive browser actions and `computer_use` fail closed with `oap.interactive_browser_unsupported` rather than being authorized as `web.fetch`; `computer_use` must provide an explicit string action in every mode. Strict mode is the default: unlisted names deny with `oap.unknown_tool`. Operators may opt into payload-shape fallback with `APORT_CODEX_TOOL_FALLBACK=on`, which routes only a single clear effect (`command`, `url`, or `path` with optional write content); mixed effects deny with `oap.invalid_tool_arguments`. `write_stdin` is evaluated as complete shell input; partial chunks, shell continuations and control-only chunks fail closed.
- `agent.session.create` must be a passport capability or every tool mapped to `agent.session.create.v1` is denied with `oap.unknown_capability`.
- `jq` is required by every shell hook; when it is missing the hook denies every tool call (`oap.missing_dependency`, `APort: jq is required`).
- Codex beta hook: multi-file `apply_patch` (`oap.multi_path_write_unsupported`) and `Glob`/`List`/`LS`/`LSP` (`oap.metadata_enumeration_unsupported` or `oap.missing_file_path`) are denied at the adapter level; adapter-level denials use the hard failure class, so warn mode does not downgrade them (`bin/lib/command-hook-adapter.sh`, `aport_hook_is_hard_failure_reason` in `bin/lib/hook-runtime.sh`).
- Config directories come from `get_config_dir` in `bin/lib/config.sh` (`APORT_<FRAMEWORK>_CONFIG_DIR`). Hooks read the same variable at run time; `APORT_PASSPORT_FILE` outside that directory is ignored unless `APORT_ALLOW_EXTERNAL_PASSPORT_FILE` is set (`bin/lib/framework-hook-paths.sh`).

### Regression Coverage

- Every security or correctness review finding must add a focused regression test that exercises the real harness payload path when practical. Prefer shared tests for shared adapter/evaluator behavior so Codex, Gemini CLI, Goose, Claude Code, and Cursor inherit the same guarantee.

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.27] - 2026-05-21

### Security
- Claude Code and Cursor hooks now evaluate path-based `Read` / `ReadFile` / `SemanticSearch` (and Cursor `beforeReadFile`) through the guardrail in local and API mode, so sensitive file read policy applies when `file_path` is present.
- Local evaluator applies default sensitive read patterns (`.env*`, `.aws/*`, `.ssh/*`, credentials, keys) via `is_default_sensitive_read_path()` even when the passport omits `blocked_patterns`.

### Added
- **Enterprise device scripts:** Cross-platform IT install (`enterprise-scripts/aport-device-core.mjs`, `.sh` / `.ps1` entrypoints) with enrollment (`issue`) + runtime (`read`) API key flow aligned with agent-passport `setup-key`.
- **Shared read hook policy:** `bin/lib/hook-read-policy.sh` for path-only context (avoids oversized API payloads from full `tool_input`).
- **Tool mapping audit:** `docs/FRAMEWORK_TOOL_MAPPING_AUDIT.md`; expanded `tool-pack-mapping.json` (Node + Python); Claude Code `claudeCodeTools.ts`.
- **Tests:** `test-enterprise-device-scripts.sh`, `test-tool-pack-mapping.sh`; expanded hook and file-read policy coverage.

### Changed
- OpenClaw plugin tool mapping and context normalization (message/MCP tools; drop speculative mappings).
- CI/release: enterprise bundle step, `enterprise-scripts/` in ShellCheck; release assets include `aport-device-core.mjs` and PowerShell entrypoints.
- Docs: Claude Code Read enforcement; tool policy mapping tables updated.

### Fixed
- Hosted API mode: Read-family hooks no longer exit before calling `aport-guardrail-api.sh`.

## [1.0.26] - 2026-05-05

### Added
- **Framework reset command:** Added `agent-guardrails reset <framework>` with `bin/aport-reset-framework.sh` to remove APort-managed hook/config artifacts safely while preserving user custom hooks where applicable.
- **Tests:** Added `tests/unit/test-framework-reset.sh` coverage for framework reset behavior and dispatcher reset routing.

### Changed
- **CI hardening:** Workflow install steps now use safer/reliable defaults (`apt` retries+timeouts, `--no-install-recommends`, pip non-interactive flags).
- **Release/dependency verification:** Added npm signature verification (`npm audit signatures`) and dependency consistency checks (`pip check`) in CI/release pipelines.

## [1.0.25] - 2026-05-05

### Fixed
- **Hosted API mode in hooks:** `load_guardrail_mode_for_hooks` uses `set -a` / `set +a` while sourcing `guardrail-mode.env` so `APORT_GUARDRAIL_MODE`, `APORT_API_URL`, `APORT_AGENT_ID`, etc. are **exported** to child guardrail processes (hosted API verification).

### Changed
- **Release workflow:** npm and PyPI verification steps retry (4 attempts, 25s between tries) after publish so transient registry/CDN lag does not fail the job.

### Added
- **Tests:** Unit coverage ensuring guardrail-mode env values are exported after loading from disk.

## [1.0.24] - 2026-04-29

### Added
- **Guardrail mode parity (CLI installers):** All framework installers (`generic.sh`, Cursor, Claude Code hooks) honor `--mode=api|local`, optional `--api-url` (default `https://api.aport.io`), and hosted `ap_<hex>` passport IDs (`parse_guardrail_mode_args` / `guardrail-mode.sh`). Mode is persisted to `<framework-config>/aport/guardrail-mode.env` so hooks and runtime evaluation stay aligned across sessions.

### Fixed
- **CLI npm tarball:** The published `@aporthq/aport-agent-guardrails` package now includes `python/aport_guardrails/core/tool-pack-mapping.json` in its `files` list so packaged `npx`/npm installs succeed when installers copy the runtime manifest into the user config (`install_runtime_tree` previously failed with “Runtime source missing” when that file was omitted).

### Changed
- **Docs:** README clarifies that **Node** installers accept `--mode` / `--api-url` and hosted IDs; **`aport setup` (Python)** does not parse those flags yet—users should prefer the Node wizard for setup-time API/local selection or configure `config.yaml` per framework docs.

## [1.0.23] - 2026-04-13

### Fixed
- **OpenClaw plugin mapping correctness:** the OpenClaw plugin now maps current OpenClaw tool calls more accurately, including `message` send-family actions and MCP bundle tools exposed as `serverName__toolName`, while dropping speculative session, finance, and export mappings that did not match the current host tool surface.
- **OpenClaw hosted/API context normalization:** hosted evaluation now normalizes OpenClaw file, message, and MCP tool params into the context shape expected by the APort API, avoiding `400` failures caused by mismatched field names like `path` vs `file_path`.
- **OpenClaw setup idempotence:** `npx @aporthq/aport-agent-guardrails openclaw` now skips plugin reinstall when the same `openclaw-aport` version is already installed, while still reinstalling when versions differ.
- **OpenClaw direct-install guidance:** docs now explicitly state that `openclaw plugins install @aporthq/openclaw-aport` installs only the plugin bundle and should be followed by the full APort setup command to create a passport and write config.

## [1.0.22] - 2026-04-13

### Fixed
- **OpenClaw public integration:** `npx @aporthq/aport-agent-guardrails openclaw` now ships the scanner-safe plugin runtime, correct compatibility metadata, and installer behavior that stops on plugin install failure instead of writing broken config.
- **OpenClaw docs and setup guidance:** public docs, quickstarts, and generated setup content now consistently describe the plugin-based OpenClaw path and the value split between OpenClaw security controls and APort authorization.

## [1.0.21] - 2026-04-11

### Fixed
- **Claude Code hook tool-name compatibility:** `bin/aport-claude-code-hook.sh` now normalizes tool names (including `functions.*` prefixes and case variants) so runtime aliases like `Shell`/`functions.Shell` map correctly to `bash` policy checks instead of being denied as unknown tools.
- **Release docs version drift:** `docs/RELEASE.md` current release marker updated to `1.0.21` to match package versions.
- **Installer update behavior for stale hook paths:** Cursor/Claude installers now replace stale APort-managed hook command entries (old `~/.npm/_npx/...` paths) instead of only deduping exact command strings, while preserving user-defined non-APort hooks.
- **OpenClaw config update safety:** `bin/openclaw` no longer appends a duplicate top-level `plugins:` block into existing `config.yaml`; it now writes a merge snippet when an existing plugins block is detected.
- **Generic config update safety:** `write_config_template()` now seeds `config.yaml` only on first setup and no longer overwrites existing user-managed `config.yaml` on reruns.
- **OpenClaw compatibility default:** `allowUnmappedTools` default is restored to `true` (manifest/runtime/tests/docs) to avoid an unintended breaking behavior change.
- **Validation portability:** `safe_pattern_match()` no longer relies on `grep -w -F`; it now uses boundary-aware regex matching compatible with GNU/BSD grep.
- **Test shim provenance:** Added vendoring provenance note to `_allowlist_shim.py` to reduce silent drift risk.

### Added
- **Hook regression coverage:** Added unit test coverage for the `Shell` alias path in `tests/unit/test-claude-code-hook.sh`.
- **Installer regression coverage:** Framework setup integration tests now pre-seed stale APort hook entries and custom hooks, and assert "replace stale APort entries, preserve custom hooks" for both Cursor and Claude Code.
- **Config regression coverage:** Added a unit test asserting `write_config_template()` preserves existing `config.yaml` on reruns.
- **Shared setup helpers:** Added `bin/lib/framework-setup.sh` and reused it in Cursor/Claude installers for hook path resolution and secure framework config dir setup.
- **Environment template:** Added `.env.example` documenting key runtime/config environment variables.
- **Claude marketplace artifacts:** Added `.claude-plugin/marketplace.json` and `packages/claude-code/.claude-plugin/plugin.json` with `/aport-setup` command so Claude Code users can install via plugin marketplace flow.

## [1.0.20] - 2026-03-24

### Added
- **OAPGuardrailProvider:** universal implementation to make APort a Guardrail in frameworks like Openclaw, Deerflow etc

## [1.0.19] - 2026-03-24

### Added
- **Claude Code plugin:** Plugin manifest at repo root for official Anthropic marketplace submission
- **PreToolUse hook:** Plugin-native hook via hooks/hooks.json using ${CLAUDE_PLUGIN_ROOT}
- **Skills:** /aport-guardrails:claude-code, /aport-guardrails:openclaw, /aport-guardrails:status
- **Marketplace manifest:** .claude-plugin/marketplace.json with pinned GitHub source
- **Skills naming convention:** docs/SKILLS.md documents pattern
- **Version sync:** sync-version.mjs now updates plugin.json and marketplace.json

## [1.0.16] - 2026-03-21

### Added
- **Generic OAP guardrail provider** (`aport_guardrails.providers.generic:OAPGuardrailProvider`): Framework-agnostic provider that wraps the core `Evaluator`. Works with any framework that calls `evaluate(request)` / `aevaluate(request)`. No per-framework PyPI package needed.
- **DeerFlow support:** Added `deerflow` as a supported framework in CLI dispatcher, config paths, tool-pack-mapping, and integration docs.
- **Generic framework setup script** (`bin/frameworks/generic.sh`): Replaces 4 duplicated per-framework shell scripts (crewai, langchain, deerflow, n8n) with one generic handler + data files in `next-steps.d/`. Adding a new framework now requires only a text file.
- **Python-native CLI setup:** `aport setup --framework deerflow` now calls the passport wizard directly via bash script instead of shelling out to npx. Python developers no longer need Node installed.

### Changed
- **CLI dispatcher refactor:** `bin/agent-guardrails` now falls through to `generic.sh` for frameworks without custom scripts (crewai, langchain, deerflow, n8n). Cursor and claude-code keep their own scripts.
- **`cli.py` rewritten:** Now runs full setup (config dir, passport wizard, next steps) instead of printing "go run npx".
- **`cli_common.py` rewritten:** `run_wizard()` calls `bin/aport-create-passport.sh` directly, falling back to npx only if bash script not found.

### Removed
- `bin/frameworks/crewai.sh` — replaced by `generic.sh` + `next-steps.d/crewai.txt`
- `bin/frameworks/langchain.sh` — replaced by `generic.sh` + `next-steps.d/langchain.txt`
- `bin/frameworks/n8n.sh` — replaced by `generic.sh` + `next-steps.d/n8n.txt`

## [1.0.15] - 2026-03-12

### Added
- **Framework-specific package executables:** All framework packages (`@aporthq/aport-agent-guardrails-cursor`, `@aporthq/aport-agent-guardrails-langchain`, `@aporthq/aport-agent-guardrails-crewai`, `@aporthq/aport-agent-guardrails-claude-code`, `@aporthq/aport-agent-guardrails-n8n`) now include `bin/install` executables.
  - Users can now run: `npx @aporthq/aport-agent-guardrails-cursor`, `npx @aporthq/aport-agent-guardrails-langchain`, etc.
  - Each wrapper calls the main package with the correct framework argument
  - Fixes npm error "could not determine executable to run"

### Fixed
- **Framework argument parsing:** CLI now correctly recognizes framework names as first positional argument (e.g., `npx @aporthq/aport-agent-guardrails cursor`)
  - Previously framework names were ignored and auto-detection would incorrectly default to `claude-code`
  - Now correctly parses: `cursor`, `langchain`, `crewai`, `openclaw`, `claude-code`, `n8n` as first argument
  - Maintains backward compatibility with `--framework=` and `-f` flags

## [1.0.14] - 2026-03-11

### Added
- **Passport wizard: framework-aware capability defaults.** Each framework (`claude-code`, `cursor`, `crewai`, `langchain`, `n8n`) now gets sensible default capabilities during passport creation. Claude Code defaults include all capabilities; Cursor enables file, web, and session capabilities; other frameworks get appropriate subsets.
- **Passport wizard: `agent.session.create` and `mcp.tool.execute` capabilities.** New interactive prompts for sub-agent spawning and MCP tool execution, with corresponding limits (`max_concurrent`, `allowed_servers`).
- **Cursor hook: full hook event support.** Rewritten `aport-cursor-hook.sh` to handle all Cursor hook events:
  - `beforeShellExecution` — shell command policy check
  - `preToolUse` — routes Shell, Read, Write, Grep, Delete, Task, and MCP:\<name\> tools
  - `beforeMCPExecution` — MCP server tool calls (detected by `server`/`url` field)
  - `beforeReadFile` — allowed without evaluator (performance)
  - `subagentStart` — sub-agent spawning policy check
  - Legacy Copilot-style payloads still supported
- **Cursor installer: 4 hook events.** `cursor.sh` now registers `beforeShellExecution`, `preToolUse`, `beforeMCPExecution`, and `subagentStart` (was only 2).
- **Cursor hook unit tests.** 15 test cases covering all hook event types, including fail-closed for unknown tools and fail-open for empty stdin.

### Changed
- **Test fixture:** `passport.oap-v1.json` expanded from 3 to 9 capabilities with matching limits.
- Read-family tools (`Read`, `Grep`) exit 0 without calling evaluator in Cursor hook (matches Claude Code behavior).
- Unknown `preToolUse` tools are denied (fail-closed) in Cursor hook.

### Security
- Per-invocation decision files in Cursor hook (PID-suffixed) prevent race conditions with concurrent tool calls.
- Fail-closed design: unrecognized hook input shapes are denied by default.

## [1.0.13] - 2026-03-11

### Added
- **Claude Code Integration:** Pre-action authorization via Claude Code's `PreToolUse` hook.
  - New hook script: `bin/aport-claude-code-hook.sh` — handles all Claude Code tool types
    (Bash, Write, Edit, MultiEdit, TodoWrite, WebSearch, WebFetch, Browser, Task, Agent, Skill, MCP tools)
  - New installer: `npx @aporthq/aport-agent-guardrails claude-code`
    Writes `~/.claude/settings.json` with APort hook registered for all tools via `"matcher": "*"`
  - New npm package: `@aporthq/aport-agent-guardrails-claude-code`
  - Default passport path: `~/.claude/aport/passport.json`
  - Deny format: Claude Code's official `hookSpecificOutput.permissionDecision: "deny"` schema
  - Read-family tools (Read, Glob, LS, Grep, TodoRead, ToolSearch, AskUserQuestion) allow-by-default (exit 0)
  - Read-only queries (TaskGet, TaskList, TaskOutput, CronList) allow-by-default
  - State transitions (EnterPlanMode, ExitPlanMode) allow-by-default
  - Fail-closed: unknown tool names are denied (exit 2)
  - Framework auto-detection: `detect.sh` detects Claude Code via `claude` binary or `~/.claude` dir
  - New `docs/frameworks/claude-code.md`

### Changed
- `bin/lib/config.sh`: Added `claude-code` framework with default config dir `~/.claude`
- `bin/aport-resolve-paths.sh`: Added `~/.claude` to passport probe list (before `~/.cursor`)
- `bin/lib/detect.sh`: Added Claude Code auto-detection
- `bin/agent-guardrails`: Added `claude-code` to supported frameworks list; framework name validation (alphanumeric + hyphen only)
- `extensions/openclaw-aport/index.ts`: Added `mapToolToPolicy()` entries for all Claude Code tools
  (`Agent`, `Skill`, `EnterWorktree`, `Task*`, `Cron*`, `NotebookEdit`, `MultiEdit`, `TodoWrite`, `ToolSearch`, `mcp__*`)
- `.changeset/config.json`: Added claude-code package to `fixed` version group
- `docs/frameworks/cursor.md`: Corrected Claude Code compatibility claim (hook output formats are incompatible)

### Security
- **Hook hardening:** Claude Code hook uses `hookSpecificOutput.permissionDecision: "deny"` + exit 2 (belt-and-suspenders); safe jq parsing (never crashes on malformed input); per-invocation decision files (PID suffix prevents race conditions)
- **File permission hardening (all frameworks):** `chmod 700` on aport directories, `chmod 600` on passport.json, settings.json, decision files, and chain-state across Claude Code, Cursor, LangChain, CrewAI, and n8n installers
- **Input validation improvements:** `validate_command_string` rewritten to allow legitimate shell syntax (pipes, chains, redirects, variables) while blocking actual injection patterns (backticks, dangerous `$()` subshells, null/control characters); `validate_passport_path` expanded to allow `~/.claude`, `~/.cursor`, `~/.n8n`
- **Evaluator fix:** `allowed_extensions` check no longer blocks all file writes when no extensions are configured (jq `null | length` returns 0, but `[ -n "0" ]` is true in bash — fixed with explicit conditional)
- **Allowlist stub:** `check_command_allowed` stub changed to return 1 (deny) instead of 0; function is unused (real enforcement in `aport-guardrail-bash.sh`) but deny-by-default is correct for any future callers
- **Secure temp files:** Framework installers use `mktemp` for intermediate files during settings merge
- **Fail-closed on unknown tools** at both hook level and evaluator level
- **30 tests passing** (unit, integration, policy, hook)
- **Limitation:** `claude --dangerously-skip-permissions` bypasses ALL hooks including APort (documented; cannot be mitigated in code)

## [1.0.12] - 2026-03-02

### Added
- **Local Audit Logging for API Mode:** All frameworks (LangChain, CrewAI, OpenClaw, Python adapters) now write local audit log entries when using API mode. Previously only local/bash mode produced audit logs.
  - New `auditLogger.ts` in core package with `logDecision()`, `resolveAuditLogPath()`, `extractContextSummary()`
  - Deny entries written synchronously (blocking); allow entries written asynchronously (non-blocking) — matches bash guardrail behavior
  - Format matches existing bash audit log: `[timestamp] tool=X allow=true|false policy=P code=C agent_id=A context="..."`
- **`audit_log` Config Field:** New config option (`audit_log: true | string | false`) controls local audit logging. Env var `APORT_AUDIT_LOG=1` or `APORT_AUDIT_LOG=/path/to/file` overrides config.
  - `true` → default path (`~/.aport/<framework>/audit.log` or next to config file)
  - String path → explicit file location
  - `false` (default) → no audit logging (backwards compatible)
- **Python Audit Logging:** `_log_decision()` and `_resolve_audit_log_path()` added to Python evaluator with same format and sync/async behavior as Node
- **OpenClaw API Mode Audit:** `logAuditEntry()` added to OpenClaw plugin for API mode decisions (local mode already logged by bash script)
- **Core Exports:** `logDecision`, `resolveAuditLogPath`, `extractContextSummary`, `AuditEntry` exported from core package for reuse

### Security
- All 28 shell tests passing
- Core Jest tests (3 suites, 16 tests) passing
- Express middleware tests (8 tests) passing
- No regressions introduced
- Audit logger is best-effort (never throws/raises) — cannot impact decision flow

## [1.0.11] - 2026-03-01

### Added
- **Complete Tool Mappings:** Added mappings for 15+ tool families (read, write, edit, web_fetch, web_search, browser, sessions_spawn, sessions_send, cron, gateway, process, exec, git.create_pr, git.merge, messaging.*)
- **Passport Creation Wizard Enhancement:** Added support for new capabilities:
  - File operations: `data.file.read`, `data.file.write` with path allowlists
  - Web operations: `web.fetch`, `web.browser` with domain restrictions
  - Interactive prompts for configuring limits (paths, domains, rate limits)
- **Documentation:**
  - NEW: `SECURITY_MODEL.md` (584 lines) - Comprehensive security model with trust boundaries, attack scenarios, best practices
  - UPDATED: `SECURITY.md` - Configuration security guide, safe defaults
  - UPDATED: `README.md` - Trust boundary section, application-layer security positioning
  - UPDATED: `skills/aport-agent-guardrail/SKILL.md` (314→412 lines) - Scanner-friendly rewrite, value-first positioning

### Changed
- **Bash Script Improvements (Local Mode):**
  - Complete tool mappings added
  - Fixed signature format: `"local-unsigned"` with proper `kid` and `verification_mode` (OAP v1.0 compliant)
  - Audit performance: deny decisions sync, allow decisions async
- **Documentation URLs:** Fixed policy docs URL from `https://aport.io/docs/policies` → `https://aport.io/policy-packs`

### Fixed
- **Decision Integrity:** Added synchronous `verifyDecisionIntegrity()` call before processing decisions (SHA-256 hash verification)
- **Unmapped Tools:** Closed gap where 11+ core OpenClaw tools had no policy enforcement
- **Cryptographically Secure UUIDs:** Replaced weak `Date.now() + Math.random()` with `crypto.randomUUID()` for decision files

### Security
- ✅ All 28 tests passing
- ✅ No regressions introduced
- ✅ Comprehensive audit completed (all claims verified)

## [1.0.8] - 2026-02-18

### Added
- **Package renames (SEO):** All published packages now include `agent-guardrails` in the name. **npm:** `@aporthq/aport-agent-guardrails` (root CLI), `@aporthq/aport-agent-guardrails-core`, `-langchain`, `-crewai`, `-cursor` (n8n in repo only, not published). **PyPI:** `aport-agent-guardrails`, `aport-agent-guardrails-langchain`, `aport-agent-guardrails-crewai`. Install: `npx @aporthq/aport-agent-guardrails`, `pip install aport-agent-guardrails`, etc.
- **PyPI release automation:** Release workflow now builds and publishes all three Python packages (core + langchain + crewai) to PyPI on tag push; GitHub Release notes include all pip install commands.
- **Security hardening (staff review 100/100):** Per-invocation decision files (no race); `verifySync()` uses `fs.mkdtempSync` + `crypto.randomUUID()` for temp paths and `mode: 0o600`; denial logging in LangChain/CrewAI Node adapters and Cursor hook reason surfacing. See `docs/reviews/2026-02-18-staff-review.md`.

### Changed
- **Docs and code alignment:** DEPLOYMENT_READINESS, RELEASE.md, and launch docs (FRAMEWORK_SUPPORT_PLAN, USER_STORIES) updated for current implementation: Node packages and Python adapters production-ready; n8n config-only (coming soon); CI runs Jest for core + langchain; fail-closed by default, tool mapping, CrewAI evaluator cache, Python CLI cursor choice, n8n warning in installer.
- **Cursor hook:** Improved fallback message when decision file missing (“check passport and guardrail script”); reads deny reasons from `OPENCLAW_DECISION_FILE` and common paths.
- **Test isolation:** Core/config and evaluator Jest tests set `HOME` to a temp dir so they do not depend on local `~/.aport` or `~/.openclaw`.

### Fixed
- **Sync API temp files (S4):** Replaced predictable `/tmp/aport-req-${pid}-${ts}.json` with mkdtemp + random UUID; tmp dir cleaned up in `finally`.

## [1.0.7] - 2026-02-17

### Added
- **SECURITY.md:** Expanded security documentation addressing Cisco findings, prompt injection attacks, and attack vectors. Maps Cisco's documented risks (silent data exfiltration, malicious skills, prompt injection) to APort mitigations. Includes CVE-2026-25253 and other attack vectors with scope clarification.

### Changed
- **README.md:** Problem-first lede highlighting Cisco's documented OpenClaw security risks. Opens with "OpenClaw skills can exfiltrate data without you knowing" and positions APort as the pre-action authorization layer that blocks attacks before execution. Added "See it in action" demo section with terminal examples.
- **SKILL.md:** Aligned with README and OpenClaw feedback. Added "Before you install" section with remote code, what gets written, network/data, and credentials. Reformatted lists for scannability (one item per line). Added environment variables section and clarified slug vs product name.
- **bin/openclaw:** Fixed skill path to use `skills/aport-agent-guardrail/SKILL.md` (matches repo structure).

## [1.0.6] - 2026-02-17

### Changed
- **README:** Mermaid diagrams now use the same color and styling as [openai/openai-agents-python#2022](https://github.com/openai/openai-agents-python/issues/2022) (input guardrails blue, action/APort orange, output/audit purple, allow green, deny red, tool execution blue).

## [1.0.5] - 2026-02-17

### Added
- **APort data directory:** Passport, decision, and audit files live under `config_dir/aport/` (e.g. `~/.openclaw/aport/passport.json`). Suspend (kill switch) uses passport `status` only—no separate file. New installs use this path; existing installs continue to work (backward compatible).
- **Path resolver:** `bin/aport-resolve-paths.sh` — single source of truth for resolving APort paths; `aport-guardrail-bash.sh`, `aport-guardrail-api.sh`, and `aport-status.sh` source it (DRY, consistent behavior).
- **SKILL from repo:** Installer copies `skills/aport-guardrail/SKILL.md` into the config dir instead of a hardcoded heredoc, so the installed skill always matches the repo.

### Changed
- **Default paths:** Plugin and create-passport default to `~/.openclaw/aport/passport.json`; wrappers default to `config_dir/aport/` for all four files.
- **SKILL.md:** Removed shield emoji/references; clarified that users do not run the guardrail script manually (plugin enforces automatically); added `agent_id` option and OpenClaw docs links; document passport at `~/.openclaw/aport/passport.json` and repo clone for `./bin/openclaw`.
- **Docs:** QUICKSTART_OPENCLAW_PLUGIN, extension README, and related docs updated for aport/ paths and legacy fallback.

### Fixed
- **API guardrail:** `aport-guardrail-api.sh` now sources the path resolver so it finds the passport at the legacy location when the wrapper points to `aport/` and the file exists only in the config root.

## [1.0.4] - 2026-02-16

### Fixed
- **Passport OAP compliance:** Installer normalizes passports to `spec_version: "oap/1.0"` and nested `limits["system.command.execute"]`; migrates flat limits from older passports.
- **Messaging guardrails:** Default passport includes `messaging.send` and messaging limits (interactive + non-interactive). Limits written as flat keys (`msgs_per_min`, `msgs_per_day`, `allowed_recipients`, `approval_required`) for API/verifier; local evaluator accepts nested or flat.
- **Default allowed_commands:** Preserve `["*"]` when set by wizard; new exec block defaults to `["*"]` per README.

### Changed
- **Plugin logging:** Consistent `ALLOW` / `BLOCKED` lines with one-line summary (e.g. `ALLOW: system.command.execute - mkdir test`) for screenshot-friendly gateway logs.
- **Docs:** Troubleshooting for `oap.passport_version_mismatch` in QUICKSTART_OPENCLAW_PLUGIN.

## [1.0.3] - 2026-02-16

### Fixed
- **npx @aporthq/aport-agent-guardrails:** Add `agent-guardrails` bin entry so `npx @aporthq/aport-agent-guardrails` resolves to the OpenClaw setup wizard (npm only runs a bin that matches the package name; 1.0.2 had only `aport` and `aport-guardrail`).

## [1.0.2] - 2026-02-16

### Added
- `test-npm-package.sh`: installs `@aporthq/aport-agent-guardrails` from registry, asserts package layout and guardrail ALLOW/DENY.
- `test-remote-passport-api.sh`: remote passport (agent_id only) API tests.

### Changed
- Docs lead with npx; clone/setup from repo as alternative (README, QUICKSTART, QUICKSTART_OPENCLAW_PLUGIN).
- README: npm badge and link to package; quick start and links section.
- `package.json` install script: runs `make install` only when Makefile present (fixes `npm install` from tarball so npx works).
- PUBLISHING.md: clarify wizard installs guardrail wrappers; install script note.
- tests/README: document test-npm-package.sh.

## [1.0.1] - 2025-02-16

### Changed
- **Release process:** Tag-driven; push tag `v*` triggers npm publish and GitHub Release (see RELEASE.md). Merges to main do not release.
- **Scope:** npm package `@aporthq/aport-agent-guardrails` and plugin `@aporthq/openclaw-aport` (GitHub org aporthq).
- **npx:** Default bin is `openclaw` (setup wizard). Package includes `extensions/` and `external/` for self-contained `npx @aporthq/aport-agent-guardrails`.
- PUBLISHING.md and RELEASE.md for repeatable releases.

## [1.0.0] - 2025-02-15 (first release)

### 🎉 Major Release - Production Ready

#### Added - Core Features
- **OpenClaw Plugin**: Deterministic `before_tool_call` enforcement (545 lines, fully tested)
  - Local mode (bash evaluator, no network required)
  - API mode (APort cloud API integration)
  - Fail-closed by default with configurable fail-open
  - Per-tool-call verification (no caching/reuse)
  - Recursive guardrail detection (delegates to inner tool)
  - Tamper-evident decisions (SHA-256 content hashing)

#### Added - Security & Policies
- 40+ built-in security patterns (command injection, path traversal, etc.)
- 4 OpenClaw-compatible policies:
  - `system.command.execute.v1` with allowed_commands allowlist
  - `mcp.tool.execute.v1` for MCP tools
  - `agent.session.create.v1` for agent spawning
  - `agent.tool.register.v1` for dynamic tool registration
- Tool-to-policy mapping (exec, git.*, messaging.*, etc.)
- Kill switch support (global emergency stop)

#### Added - Documentation
- Comprehensive setup guide: `docs/QUICKSTART_OPENCLAW_PLUGIN.md`
- Plugin-specific README: `extensions/openclaw-aport/README.md` (420+ lines)
- Tool/policy mapping reference: `docs/TOOL_POLICY_MAPPING.md`
- OpenClaw compatibility guide: `docs/OPENCLAW_COMPATIBILITY.md`
- Verification methods: `docs/VERIFICATION_METHODS.md`
- Launch strategy and checklists in `docs/launch/`

#### Added - Developer Tools
- Interactive setup wizard: `bin/openclaw` (23KB, full UX)
- Passport creation wizard: `bin/aport-create-passport.sh` (OAP v1.0)
- Status dashboard: `bin/aport-status.sh` (health checks, recent activity)
- Dual evaluators: `aport-guardrail-bash.sh` (local) and `aport-guardrail-api.sh` (API)

#### Added - Testing & Quality
- 9 test suites, 100% passing:
  - API evaluator tests
  - Full flow tests
  - Kill switch tests
  - OAP v1 compliance tests
  - Passport creation/validation tests
  - Plugin CLI tests
- Plugin unit tests: `extensions/openclaw-aport/test.js` (integrity, canonicalization, mapping)
- Test fixtures with realistic passport examples

#### Added - Repository Standards
- SECURITY.md (responsible disclosure, uchi@aport.io)
- CODE_OF_CONDUCT.md (Contributor Covenant 2.1, uchi@aport.io)
- .npmignore (root and plugin)
- .editorconfig (consistent formatting)
- GitHub workflows: CI with submodules, publish-plugin on release

#### Changed
- Version bumped to 1.0.0 (production-ready)
- Plugin config: installer now sets `allowed_commands: ["*"]` by default (no manual editing)
- Improved exec handling: detects recursive guardrail invocations, delegates to inner tool
- Enhanced error messages: shows OAP codes, suggests fixes (e.g., add to allowed_commands)

#### Performance
- P95 latency: 268ms (local mode)
- Mean latency: 178ms
- Success rate: 100%
- Zero failures in test suite

#### Breaking Changes
None (first release).

---

[Unreleased]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.13...HEAD
[1.0.13]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.12...v1.0.13
[1.0.12]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.11...v1.0.12
[1.0.11]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.8...v1.0.11
[1.0.8]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/aporthq/aport-agent-guardrails/releases/tag/v1.0.1
[1.0.0]: https://github.com/aporthq/aport-agent-guardrails/releases/tag/v1.0.0

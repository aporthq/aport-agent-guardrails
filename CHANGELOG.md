# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.6] - 2026-02-17

### Changed
- **README:** Mermaid diagrams now use the same color and styling as [openai/openai-agents-python#2022](https://github.com/openai/openai-agents-python/issues/2022) (input guardrails blue, action/APort orange, output/audit purple, allow green, deny red, tool execution blue).

## [1.0.5] - 2026-02-17

### Added
- **APort data directory:** Passport, decision, audit, and kill-switch files now live under `config_dir/aport/` (e.g. `~/.openclaw/aport/passport.json`) for a cleaner layout. New installs use this path; existing installs continue to work (backward compatible).
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
- **npx @aporthq/agent-guardrails:** Add `agent-guardrails` bin entry so `npx @aporthq/agent-guardrails` resolves to the OpenClaw setup wizard (npm only runs a bin that matches the package name; 1.0.2 had only `aport` and `aport-guardrail`).

## [1.0.2] - 2026-02-16

### Added
- `test-npm-package.sh`: installs `@aporthq/agent-guardrails` from registry, asserts package layout and guardrail ALLOW/DENY.
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
- **Scope:** npm package `@aporthq/agent-guardrails` and plugin `@aporthq/openclaw-aport` (GitHub org aporthq).
- **npx:** Default bin is `openclaw` (setup wizard). Package includes `extensions/` and `external/` for self-contained `npx @aporthq/agent-guardrails`.
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

[Unreleased]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.5...HEAD
[1.0.5]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/aporthq/aport-agent-guardrails/releases/tag/v1.0.1
[1.0.0]: https://github.com/aporthq/aport-agent-guardrails/releases/tag/v1.0.0

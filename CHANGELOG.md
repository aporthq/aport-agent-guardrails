# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**No official release has been published yet.** The first release will be **1.0.0**.

## [Unreleased]

(Changes since the upcoming 1.0.0 release.)

## [1.0.0] - TBD (first release)

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

[Unreleased]: https://github.com/aporthq/aport-agent-guardrails/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/aporthq/aport-agent-guardrails/releases/tag/v1.0.0

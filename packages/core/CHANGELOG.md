# @aporthq/aport-agent-guardrails-core

## 1.0.34

### Minor Changes

- Installer: reuse an APort passport that another framework already has on this device. Interactive installs list hosted and local passports found under the other frameworks' state directories and offer them before the hosted/local menu; non-interactive installs opt in with `--reuse-from=<framework|passport.json path|agent_id>` (env `APORT_REUSE_PASSPORT_FROM`). Local reuse copies the file and skips the wizard; hosted reuse configures the same agent id, API key and URL. See docs/PASSPORT_REUSE.md.

  Hosted mode: the context sent to the verify API for shell tools is now shaped to the API schema. An empty or path-form `shell` (for example `""` from Codex, or `/bin/bash`) was rejected with HTTP 400 `context_validation_failed` and surfaced to the agent as `oap.evaluation_error`, denying every Bash call in API mode. The value is reduced to its basename and dropped when it is not one of the accepted shells.

  Claude Code: a Bash call with no `timeout` now sends the CLI's documented default (120000 ms, as `timeout: 120`). The hosted `system.command.execute.v1` rule requires timeout evidence whenever the passport sets `max_execution_time`, so every ordinary shell command under such a passport was denied with `oap.limit_exceeded`.

### Patch Changes

- Review the Claude Code PreToolUse hook against the current upstream hooks reference (framework drift issue #107). Raise the registered hook `timeout` from 10 to 30 seconds because Claude Code now documents that a timed-out PreToolUse command hook does not block and the hosted evaluator request alone may take 15 seconds. Convert the Bash/PowerShell/Monitor `tool_input.timeout` from milliseconds to seconds before the `max_execution_time` check. Read the `mcp_server` object (`name`, `source`) that Claude Code 2.1.274+ sends for MCP tools instead of stringifying it. Allow the new read-only and internal tools `ListAgents`, `ReportFindings` and `SubagentHandback`; `SendUserFile` stays unmapped and denied. Export `CLAUDE_CODE_INTERNAL_TOOLS` from the Node package, drop the stale `TodoWrite: write` mapping there, add `Workflow`, and document the output contract, permission-mode behaviour and settings precedence in `docs/frameworks/claude-code.md`.

## 1.0.33

### Patch Changes

- Ship beta command-hook harnesses for Codex CLI, Gemini CLI, and Goose with stable runtime bundling, shared command mapping, host preflight warnings, warn-mode safety boundaries, and docs/tests.

## 1.0.32

### Patch Changes

- Make report-only guardrail warnings safer and more actionable across framework hooks.
- Report hosted runtime enforcement metadata to APort so signed deny decisions can be reconciled with framework-level warn mode in the dashboard.

## 1.0.31

### Patch Changes

- 3b01f93: Add GitHub Repository Guard as the first-class setup target, explicit warn-mode enforcement for gradual rollout, framework drift monitoring, and updated hosted/local guardrail docs.

## 1.0.30

### Patch Changes

- Add GitHub protection documentation and local evaluator parity for repository and release policy checks, including action-specific repo capabilities, changed-path allowlists, release semantic-version/file validation, hosted-mode hook behavior, quick-hosted reuse, stale hook cleanup, chained hook-bypass hardening, and framework reset/config hardening.

## 1.0.29

### Patch Changes

- Fix enterprise device deployment for template instances that use legacy `agt_inst_` passport IDs.

## 1.0.28

### Patch Changes

- Improve hosted setup and hook path behavior, and harden enterprise script delivery for curl-based installs.

## 1.0.27

### Patch Changes

- Release 1.0.27: enforce path-based Read hooks in API/local mode, default sensitive file read blocking, cross-platform enterprise device install scripts, and OpenClaw/tool-mapping alignment.

## 1.0.26

### Patch Changes

- Release 1.0.26: add framework reset command, CI/install supply-chain hardening, and release dependency verification checks.

## 1.0.25

### Patch Changes

- Release 1.0.25: export guardrail-mode env for API child processes; release workflow verify retries.

## 1.0.24

### Patch Changes

- Release 1.0.24: installer guardrail mode parity, packaged CLI runtime fix (`tool-pack-mapping.json`), and README clarification for Python vs Node setup flags.

## 1.0.23

## 1.0.22

### Patch Changes

- Fix the public OpenClaw integration by shipping the scanner-safe plugin runtime, aligning setup/docs with the plugin-based flow, and tightening plugin compatibility metadata and hook contract handling.

## 1.0.21

### Patch Changes

- Improve Python runtime packaging and CrewAI setup flows.

  - install the local runtime bundle into framework config directories during setup so Python integrations can evaluate locally without depending on an OpenClaw-specific runtime path
  - add released CrewAI compatibility mode by default, with opt-in native provider mode for CrewAI builds that support `GuardrailProvider`
  - align Python provider path handling with the shell runtime so explicit passport paths stay authoritative while auto-discovered paths remain restricted to trusted framework directories
  - document the CrewAI native provider flow separately from the released adapter flow and add regression coverage for runtime asset installation and path validation

## 1.0.15

## 1.0.13

### Patch Changes

- Claude Code integration with security hardening: PreToolUse hook, fail-closed policy, file permission hardening across all frameworks, input validation improvements.

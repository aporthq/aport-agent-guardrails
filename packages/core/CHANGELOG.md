# @aporthq/aport-agent-guardrails-core

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

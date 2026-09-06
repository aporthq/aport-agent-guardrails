# @aporthq/aport-agent-guardrails-langchain

## 1.0.32

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.32

## 1.0.31

### Patch Changes

- 3b01f93: Add GitHub Repository Guard as the first-class setup target, explicit warn-mode enforcement for gradual rollout, framework drift monitoring, and updated hosted/local guardrail docs.

### Patch Changes

- Updated dependencies [3b01f93]
  - @aporthq/aport-agent-guardrails-core@1.0.31

## 1.0.30

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.30

## 1.0.29

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.29

## 1.0.28

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.28

## 1.0.27

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.27

## 1.0.26

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.26

## 1.0.25

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.25

## 1.0.24

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.24

## 1.0.23

### Patch Changes

- @aporthq/aport-agent-guardrails-core@1.0.23

## 1.0.22

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.22

## 1.0.21

### Patch Changes

- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.21

## 1.0.15

### Patch Changes

- Add bin executables to framework-specific packages and fix framework argument parsing

  **Main Package (@aporthq/aport-agent-guardrails):**

  - Fix CLI to recognize framework as first positional argument (e.g., `npx @aporthq/aport-agent-guardrails cursor`)
  - Previously framework names were ignored and auto-detection would incorrectly choose claude-code
  - Now correctly parses: cursor, langchain, crewai, openclaw, claude-code, n8n as first argument

  **Framework Packages:**

  - Add bin executables to all framework-specific packages
  - Users can now run: `npx @aporthq/aport-agent-guardrails-cursor`, `npx @aporthq/aport-agent-guardrails-langchain`, etc.
  - Each package wrapper calls the main package with the correct framework argument
  - Fixes npm error "could not determine executable to run"
  - @aporthq/aport-agent-guardrails-core@1.0.15

## 1.0.13

### Patch Changes

- Claude Code integration with security hardening: PreToolUse hook, fail-closed policy, file permission hardening across all frameworks, input validation improvements.
- Updated dependencies
  - @aporthq/aport-agent-guardrails-core@1.0.13

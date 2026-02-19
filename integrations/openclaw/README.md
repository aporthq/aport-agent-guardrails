# OpenClaw integration

Framework-specific code for APort guardrails on OpenClaw.

## Location

- **Plugin:** [extensions/openclaw-aport](../../extensions/openclaw-aport) — `before_tool_call` hook, config wiring, install via `bin/openclaw`.
- **Guardrail scripts:** [bin/aport-guardrail-bash.sh](../../bin/aport-guardrail-bash.sh), [bin/aport-guardrail-api.sh](../../bin/aport-guardrail-api.sh) (shared).

## What lives here

- **extensions/** — Placeholder; actual plugin lives in repo root `extensions/openclaw-aport/` so OpenClaw can resolve it from the package.

## Adding a new framework (reference)

OpenClaw is the most complex integration (full installer in `bin/openclaw`). Other frameworks use [bin/frameworks/openclaw.sh](../../bin/frameworks/openclaw.sh), which simply delegates to `bin/openclaw`. See [docs/ADDING_A_FRAMEWORK.md](../../docs/ADDING_A_FRAMEWORK.md) for the pattern.

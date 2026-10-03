# Framework Drift Review - Issue 111

Reviewed the framework drift report from GitHub issue #111 and refreshed the baseline after checking each watched upstream surface.

## Decision

- No new runtime framework is enabled by this review.
- `gemini-cli`, `goose`, and `opencode` were framework coverage gaps: they are already present in the CLI framework catalog, but were missing from the weekly drift watch.
- Codex is intentionally not duplicated in this watch because `scripts/check-codex-provider-tool-surface.sh` already extracts provider tool names from upstream `openai/codex` and fails CI/pre-push on unmapped tools.
- Added `gemini-cli` to `scripts/framework-drift-check.mjs` with markers for `BeforeTool`, JSON stdin/stdout, `tool_name`, `tool_input`, `mcp_context`, and deny/block semantics.
- Added `goose` to `scripts/framework-drift-check.mjs` with markers for `hooks/hooks.json`, `PreToolUse`, `PreToolUseResult`, `on_failure: block`, tool payload fields, and file/shell hook events.
- Added `opencode` to `scripts/framework-drift-check.mjs` with markers for the official v2 plugin loading path and permission, shell, and tool hook surfaces.
- Updated `docs/OPENCLAW_COMPATIBILITY.md` to the reviewed v2026.9.8 tag so the refreshed OpenClaw baseline and compatibility contract stay in sync.
- Kept `bin/frameworks/opencode.sh` gated because the official plugin docs still require compatible installed-package testing, and APort does not yet have an installed-version smoke test proving payload shape, deny semantics, warning behavior, and setup/reset safety.

## Source Review

- OpenClaw, Cursor, Claude Code, LangChain / LangGraph, CrewAI, DeerFlow, n8n, and GitHub Actions sources still expose the markers required by the existing watchlist.
- Gemini CLI and Goose upstream hook docs still expose the command-hook fields and block semantics APort relies on.
- DeerFlow moved from the prior `v2.1.0-rc0` baseline to the current stable `v2.1.0` tag without changing APort's provider-wiring assumption. A later README-only drift during this review came from upstream artifact/gateway documentation commits; required `DeerFlow`, `2.0`, `Skills`, and `Sub-Agents` markers remained present.
- n8n remains setup-only; documentation drift does not justify shipping a runtime node.
- opencode's official v2 plugin docs still expose `@opencode/plugin`, `.opencode/plugins/`, `ctx.permission`, `ctx.shell`, and `ctx.tool` hook surfaces, but docs alone are not enough to claim fail-closed enforcement.

## Follow-up

Before enabling opencode, add an installed smoke test that proves a real opencode process loads the plugin, receives representative tool payloads, blocks denied shell/tool actions before execution, surfaces warn/observe decisions correctly, minimizes payload data, and preserves unrelated configuration during setup/reset.

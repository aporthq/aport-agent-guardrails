# Framework Drift Review — Issue #101

Date: 2026-09-15
Issue: https://github.com/aporthq/aport-agent-guardrails/issues/101

## Outcome

Reviewed the upstream drift report and refreshed the committed baseline. The
current APort implementation and framework docs remain aligned with the checked
upstream contracts.

## Reviewed Signals

| Framework | Result | Notes |
|---|---|---|
| OpenClaw | Compatible | OpenClaw split the old hooks page. The drift watch now checks the focused tool-call policy page, which documents `before_tool_call`, `matcher`, `timeoutMs`, `block`, `blockReason`, and `requireApproval`. APort's plugin still returns the documented `block: true` / `blockReason` shape for enforced denies. |
| Cursor | Compatible | Cursor still documents `preToolUse`, `beforeShellExecution`, `beforeMCPExecution`, `beforeReadFile`, and `failClosed`. APort's Cursor hook continues to emit Cursor-compatible allow/deny JSON. |
| Claude Code | Compatible | Claude Code still documents `PreToolUse`, `matcher`, `hookSpecificOutput`, and `permissionDecision`. APort's Claude Code hook uses that dedicated output format, not Cursor's format. |
| DeerFlow | Compatible | DeerFlow 2.x docs still describe built-in tools, MCP tools, skill tools, and subagents. APort's DeerFlow path remains provider/config based and intentionally separate from command-hook harnesses. |
| n8n | Compatible | n8n's AI Agent docs changed, but APort still documents n8n as setup/config only; no runtime custom node is claimed. |
| GitHub Repository Guard | Compatible | GitHub Actions docs still cover workflow syntax, `pull_request`, `push`, `merge_group`, and OIDC `id-token: write`. APort's hosted GitHub guard remains OIDC-backed. |

## Changes Made

- Updated the OpenClaw drift source from the general plugin hooks landing page
  to the tool-call policy page that owns the pre-action blocking contract.
- Regenerated `docs/framework-drift-baseline.json` after review.
- Verified a fresh online run reports `0 framework(s) need review` and
  `0 source error(s)`.

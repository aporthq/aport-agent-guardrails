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

### Regression Coverage

- Every security or correctness review finding must add a focused regression test that exercises the real harness payload path when practical. Prefer shared tests for shared adapter/evaluator behavior so Codex, Gemini CLI, Goose, Claude Code, and Cursor inherit the same guarantee.

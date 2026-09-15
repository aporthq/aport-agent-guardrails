Review this APort Agent Guardrails branch against its base as a Staff-level security reviewer.

Prioritize P0/P1/P2 findings only. Do not report style, formatting, lint, or speculative refactors.

Focus areas:
- fail-closed behavior for malformed, unknown, or unrepresentable hook payloads
- Codex, Claude Code, Cursor, Gemini CLI, Goose, OpenClaw, LangChain, CrewAI, n8n, and local evaluator parity
- shell command allowlist boundaries, command chains, substitution, and parser ambiguity
- file read/write/search/metadata handling, multi-path patches, glob expansion, symlink/config path hazards, and content leakage
- web/MCP URL parsing, private-network denial, userinfo/query/fragment redaction, allowed server/tool limits, and timeouts
- session lifecycle and concurrency state, including lock/corruption handling and warn-mode hard failures
- hosted-vs-local separation: local must stay simple but must not silently ignore a configured local limit
- release, reset, setup, and mode-switching flows, especially shared runtime state and config-location consistency

For each finding, include:
- severity
- affected file and line
- exploit or failure scenario
- the minimal safe fix
- a test that should be added or updated

If the branch looks clean, say so explicitly and list the highest residual risks.

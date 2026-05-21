# Framework tool mapping audit

Last reviewed against upstream docs and this repo’s mapping sources.

## Mapping layers (do not conflate)

| Layer | Source | Used by |
|-------|--------|---------|
| **Host tool name** | Framework-native string (`Bash`, `exec`, `sessions_spawn`, LangChain tool `.name`) | Hooks / plugin receive this |
| **Guardrail tool id** | Hook alias passed to `aport-guardrail-bash.sh` (`bash`, `session.create`, `cron`, …) | Claude Code / Cursor hooks only |
| **Policy pack id** | `tool-pack-mapping.json` or `mapToolToPolicy()` | All evaluators |
| **Passport capability** | `external/aport-policies/*/policy.json` → `requires_capabilities` | Passport + evaluator |

Canonical pack mapping for **generic** tool names: `packages/core/src/core/tool-pack-mapping.json` (mirrored in `python/aport_guardrails/core/tool-pack-mapping.json`). TypeScript/Python adapters call `toolToPackId()` / `tool_to_pack_id()`. Bash/API guardrails use `bin/lib/tool-mapping.sh` (same JSON + `default` fallback).

---

## Framework summary

| Framework | Integration | Tool mapping implementation | Unmapped tools |
|-----------|-------------|----------------------------|----------------|
| **Claude Code** | `bin/aport-claude-code-hook.sh` | Host name → guardrail id → JSON | **Fail-closed** (deny) |
| **Cursor** | `bin/aport-cursor-hook.sh` | Same pattern as Claude Code | **Fail-closed** |
| **OpenClaw** | `extensions/openclaw-aport/tool-mapping.js` | `mapToolToPolicy()` in plugin | **Allow** if `allowUnmappedTools: true` (default) |
| **LangChain / LangGraph** | `APortCallback` / `APortGuardrailCallback` | `tool_to_pack_id(tool.name)` only | Uses JSON `default` → `system.command.execute.v1` |
| **CrewAI** | Python/TS hook middleware | `tool_to_pack_id(tool_name)` only | Same as LangChain |
| **DeerFlow** | `OAPGuardrailProvider` | `tool_to_pack_id(tool_name)` only | Same as LangChain |
| **n8n** | Not shipped | — | — |
| **Generic CLI** | `aport-guardrail-bash.sh` | JSON only | Deny if no rule and no default |

---

## Claude Code

**Official tools** ([Tools reference](https://code.claude.com/docs/en/tools-reference)) include: `Agent`, `Bash`, `Edit`, `Write`, `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`, `Skill`, `TaskCreate`/`TaskUpdate`/`TaskStop`/`TaskGet`/`TaskList`, `CronCreate`/`CronDelete`/`CronList`, `EnterWorktree`/`ExitWorktree`, `PowerShell`, `Monitor`, MCP tools (`mcp__server__tool`), etc.

| Host tool | Guardrail id | Policy pack | Capability |
|-----------|--------------|-------------|------------|
| `Bash`, `PowerShell`, `Monitor` | `bash` | `system.command.execute.v1` | `system.command.execute` |
| `Read`, `Glob`, `Grep`, `LSP`, MCP list/read/wait tools, `TaskGet`/`TaskList`, `CronList`, … | *(allow, no evaluator)* | — | — |
| `Write`, `Edit`, `MultiEdit`, `NotebookEdit`, `TodoWrite`, … | `write` | `data.file.write.v1` | `data.file.write` |
| `WebSearch`, `WebFetch` | `websearch` | `web.fetch.v1` | `web.fetch` |
| `Browser` | `browser` | `web.browser.v1` | `web.browser` |
| `Agent`, `Task`, `TaskCreate`, `Skill`, worktree, teams, … | `session.create` | `agent.session.create.v1` | `agent.session.create` |
| `CronCreate`, `CronDelete` | `cron` | `agent.session.create.v1` | `agent.session.create` |
| `mcp__*`, `CallMcpTool` | `mcp.tool` | `mcp.tool.execute.v1` | `mcp.tool.execute` |

Programmatic map: `packages/claude-code/src/claudeCodeTools.ts`.

---

## Cursor

**Documented preToolUse tools** ([Cursor hooks](https://cursor.com/docs/agent/hooks)): `Shell`, `Read`, `Write`, `Grep`, `Delete`, `Task`, `WebSearch` (when emitted), `Agent`, `Edit`, MCP (`MCP:…` / `mcp:…`), plus `beforeShellExecution` / `subagentStart` events.

Hook aligned with Claude Code (v1.0.27+): `WebSearch`, `WebFetch`, `Agent`, `Edit`, `ApplyPatch`, `browser`, `cron`, MCP variants. Read-family tools still skip the evaluator for latency.

**Caveats (upstream, not APort):**

- Built-in web search may not always emit `preToolUse` depending on Cursor model/routing ([forum report](https://forum.cursor.com/t/bug-pretooluse-agent-hooks-do-not-emit-for-built-in-web-search-in-cursor-agent-works-in-claude-code/160761)).
- `ApplyPatch` may not emit hooks in some CLI builds ([Codex issue #16732](https://github.com/openai/codex/issues/16732)) — APort cannot enforce what the host does not emit.

---

## OpenClaw

**Official session tools** ([Session tools](https://docs.openclaw.ai/concepts/session-tool)): `sessions_list`, `sessions_history`, `sessions_send`, `sessions_spawn`, `sessions_yield`, `subagents`, `session_status`. Plus `exec`, `message`, `read`/`write`/`edit`, `git.*`, MCP `server__tool`, etc.

| OpenClaw tool | Policy pack | Capability |
|---------------|-------------|------------|
| `exec`, `exec.*`, `process`, `gateway` | `system.command.execute.v1` | `system.command.execute` |
| `message` (send-family actions) | `messaging.message.send.v1` | `messaging.message.send` |
| `read`, `view`, `glob` | `data.file.read.v1` | `data.file.read` |
| `write`, `edit`, `multiedit` | `data.file.write.v1` | `data.file.write` |
| `web_search`, `webfetch`, `browser` | `web.fetch.v1` / `web.browser.v1` | `web.fetch` / `web.browser` |
| `sessions_spawn`, `sessions_send`, `sessions_yield`, `subagents`, `session_status` | `agent.session.create.v1` | `agent.session.create` |
| `sessions_list`, `sessions_history` | `data.file.read.v1` | `data.file.read` |
| `server__tool`, `mcp.*` | `mcp.tool.execute.v1` | `mcp.tool.execute` |
| `git.*` | `code.repository.merge.v1` | `repo.merge` / `repo.pr.create` |

Plugin: `extensions/openclaw-aport/tool-mapping.js`. With `allowUnmappedTools: false`, unmapped tools are denied.

---

## LangChain / CrewAI / DeerFlow

No host-specific tool names: mapping is **only** `tool-pack-mapping.json` on whatever name the tool registers (e.g. `bash`, `read_file`, `web_search`, custom `my_tool`).

DeerFlow-tested names (see `python/aport_guardrails/tests/test_oap_provider_e2e.py`):

| Tool name | Policy pack |
|-----------|-------------|
| `bash` | `system.command.execute.v1` |
| `write_file`, `str_replace` | `data.file.write.v1` |
| `read_file`, `ls`, `present_file`, `view_image` | `data.file.read.v1` |
| `web_search` | `web.fetch.v1` |
| `git.create_pr` | `code.repository.merge.v1` |
| `mcp.github.issues` | `mcp.tool.execute.v1` |
| `messaging.send` | `messaging.message.send.v1` |

Custom LangChain tools must use names that match a prefix/substring in `tool-pack-mapping.json`, or they resolve to **`default`** (`system.command.execute.v1`).

---

## Policy packs reference

| Policy pack | Capability id | Notes |
|-------------|---------------|--------|
| `system.command.execute.v1` | `system.command.execute` | Shell/exec; JSON `default` |
| `data.file.read.v1` | `data.file.read` | |
| `data.file.write.v1` | `data.file.write` | |
| `web.fetch.v1` | `web.fetch` | WebSearch/WebFetch |
| `web.browser.v1` | `web.browser` | Browser automation (no separate `cron.v1`) |
| `agent.session.create.v1` | `agent.session.create` | Subagents, tasks, **cron** guardrail alias `cron` |
| `mcp.tool.execute.v1` | `mcp.tool.execute` | |
| `messaging.message.send.v1` | `messaging.message.send` | |
| `code.repository.merge.v1` | `repo.merge`, `repo.pr.create` | |

There is **no** `cron.v1` policy; scheduled-task tools map to `agent.session.create.v1`.

**Guardrail id note:** Hooks pass `session.create` (not a bare `cron` alias) for `CronCreate`/`CronDelete` so `cronlist` is not misclassified via a `cron*` prefix.

## Deploy / security review (internal)

| Check | Status |
|-------|--------|
| `packages/core` and `python/.../tool-pack-mapping.json` identical | Enforced in `tests/unit/test-tool-pack-mapping.sh` |
| Bash `resolve_policy_id_from_tool_name` fail-closed on unknown | Yes — JSON `default` is **not** applied in bash (adapters still use default) |
| Hooks fail-closed on unknown host tools | Claude Code + Cursor |
| `cronlist` → read, not session | Fixed (avoid bare `cron` prefix) |
| OpenClaw `cronlist` before `cron*` match | Fixed (explicit tool names only) |
| Published npm tarball includes mapping JSON | `python/aport_guardrails/core/tool-pack-mapping.json` in root `package.json` `files` |

**Known DRY debt (acceptable for now):** host hooks (`aport-*-hook.sh`) duplicate case lists; OpenClaw uses `tool-mapping.js`. Both must stay aligned with `tool-pack-mapping.json` when adding tools. `claudeCodeTools.ts` is documentation-only.

**Prefix caveat:** bare `agent` prefix matches any tool name starting with `agent` (e.g. hypothetical `agentic_search`). Prefer explicit host names in hooks.

---

## Tests

| Test | Coverage |
|------|----------|
| `tests/unit/test-tool-pack-mapping.sh` | JSON resolution (Claude/OpenClaw/DeerFlow names) |
| `tests/unit/test-claude-code-hook.sh` | Claude hook allow/deny |
| `tests/unit/test-cursor-hook.sh` | Cursor hook |
| `tests/extensions/openclaw-aport.test.js` | `mapToolToPolicy()` |

---

## Maintenance

When a framework adds tools:

1. Confirm the **exact** `tool_name` from host docs or a captured hook payload.
2. Update the **hook** (Claude/Cursor) or **openclaw-aport/tool-mapping.js** if host-specific.
3. Add prefixes to **`tool-pack-mapping.json`** (and sync Python copy).
4. Extend unit tests and this audit doc.

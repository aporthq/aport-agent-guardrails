# Supported surfaces roadmap

Public developer view of supported repository and runtime surfaces. Details per framework: [docs/frameworks/](frameworks/). Release gates and publishing steps live in [RELEASE.md](RELEASE.md).

## Supported surfaces

| Surface   | Status   | Implementation | Doc | Install |
|------------|----------|----------------|-----|--------|
| **GitHub Repository Guard** | Shipped | GitHub Action using OIDC, repository-scoped hosted passport issue/reuse, structural findings, report-only or hosted enforcement | [GITHUB_PROTECTION.md](GITHUB_PROTECTION.md) | `npx @aporthq/aport-agent-guardrails github` |
| **Claude Code** | Shipped | Full: PreToolUse hook installer + hosted/local mode for Anthropic's `claude` CLI. APort targets: `claude` and `claude-code`. | [claude-code.md](frameworks/claude-code.md) | `npx @aporthq/aport-agent-guardrails claude` |
| **Cursor**   | Shipped | Full: hooks installer + script | [cursor.md](frameworks/cursor.md) | `npx @aporthq/aport-agent-guardrails cursor` |
| **OpenClaw** | Shipped | Full: plugin, wizard, local/API | [openclaw.md](frameworks/openclaw.md) | `npx @aporthq/aport-agent-guardrails openclaw` |
| **LangChain / LangGraph** | Shipped | **Python only:** callback, `aport-langchain setup` | [langchain.md](frameworks/langchain.md) | `npx @aporthq/aport-agent-guardrails langchain` then `pip install aport-agent-guardrails-langchain` + `aport-langchain setup` |
| **CrewAI**   | Shipped | **Python:** released hook adapter by default; native provider mode when available | [crewai.md](frameworks/crewai.md) | `npx @aporthq/aport-agent-guardrails crewai` then `pip install aport-agent-guardrails-crewai` + `aport-crewai setup` |
| **DeerFlow** | Setup available | Generic setup + framework docs | [deerflow.md](frameworks/deerflow.md) | `npx @aporthq/aport-agent-guardrails deerflow` |
| **n8n** | Setup available / node coming soon | CLI creates passport/config; custom node is not published yet | [n8n.md](frameworks/n8n.md) | `npx @aporthq/aport-agent-guardrails n8n` |
| **Codex CLI** | Beta | Command hook installer using repo-local `.codex/hooks.json`; checks `PreToolUse` for Bash, `apply_patch`, MCP, and local function tools while storing APort state in `~/.aport/codex`. | [codex.md](frameworks/codex.md) | `npx @aporthq/aport-agent-guardrails codex` |
| **Gemini CLI** | Beta | Command hook installer using `.gemini/settings.json` `BeforeTool`; checks shell, file, web, and MCP tools. | [gemini-cli.md](frameworks/gemini-cli.md) | `npx @aporthq/aport-agent-guardrails gemini` |
| **Goose** | Beta | Goose Open Plugin installer with blocking `PreToolUse`; project plugin in `.agents/plugins/aport-guardrail`, APort state in `~/.aport/goose`. | [goose.md](frameworks/goose.md) | `npx @aporthq/aport-agent-guardrails goose` |
| **opencode** | Gated | Planned integration for the `opencode` CLI. Setup exits until installed-version plugin smoke tests validate the current v2 API. | [opencode.md](frameworks/opencode.md) | gated: `npx @aporthq/aport-agent-guardrails opencode` |

**Coming soon:** n8n custom node runtime. The CLI option exists today for passport/config setup; workflow-node enforcement ships separately.

**Naming rule for harnesses:** use the creator's CLI name as the user-facing APort target when possible: `claude`, `codex`, `gemini`, `goose`, `opencode`. Keep `claude-code` and `gemini-cli` as compatibility aliases where existing configs already use those names.

All shipped and beta surfaces above use the same OAP passport and policy model. Runtime frameworks use the same passport wizard and policy packs; each has a framework-specific installer. GitHub uses repository-scoped hosted passports through GitHub OIDC. Claude Code, Cursor, Codex, Gemini CLI, Goose, and OpenClaw have hook/plugin integration; LangChain/CrewAI have full integration **via Python packages**.

## Completion

- **CLI:** One entry point `npx @aporthq/aport-agent-guardrails` with GitHub setup, detection, or `--framework=<name>`.
- **Shared:** Passport wizard, guardrail scripts (local + API), policy packs, config/path helpers (`bin/lib/`).
- **Per framework:** Installer in `bin/frameworks/<name>.sh`, config written to framework-specific path, doc in `docs/frameworks/<name>.md`, integration tests in `tests/frameworks/<name>/`.

## Node/TypeScript packages (this repo)

| Package | Status | Notes |
|---------|--------|--------|
| **@aporthq/aport-agent-guardrails-core** | Published | Evaluator (API + local bash script), config, passport. |
| **@aporthq/aport-agent-guardrails-langchain** | Published | Callback handler using core; `GuardrailViolationError` on deny. |
| **@aporthq/aport-agent-guardrails-crewai** | Published | `beforeToolCall`, `registerAPortGuardrail`, `withAPortGuardrail` (parity with Python). |
| **@aporthq/aport-agent-guardrails-n8n** | Coming soon | Placeholder for future n8n custom node. **Not published to npm** until the custom node is ready. |
| **@aporthq/aport-agent-guardrails-cursor** | Published | `Evaluator`, `getHookPath()`; runtime is bash hook from CLI. |
| **@aporthq/aport-agent-guardrails-claude-code** | Published | Claude Code hook package and setup helpers. |

Production integration for LangChain: **Python** (pip, published) and **Node** (workspace implemented, publish when ready). See [DEPLOYMENT_READINESS.md](DEPLOYMENT_READINESS.md).

## Proposals / next

- **Python local-only verification** — Use passport + policy JSON files without calling the API.
- **Node core + adapters** — Implement evaluator/config/passport in `packages/core` and real middleware in framework packages before publishing.
- **n8n custom node** — Implement node and credentials so n8n workflows can branch on allow/deny.
- **Additional frameworks** — Add new ones by following [ADDING_A_FRAMEWORK.md](ADDING_A_FRAMEWORK.md). Prefer thin setup scripts and shared adapters before creating new packages.

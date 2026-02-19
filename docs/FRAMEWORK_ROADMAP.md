# Framework support roadmap

Public developer view of supported frameworks and roadmap. Details per framework: [docs/frameworks/](frameworks/). **What’s production-ready:** [DEPLOYMENT_READINESS.md](DEPLOYMENT_READINESS.md).

## Supported frameworks

| Framework   | Status   | Implementation | Doc | Install |
|------------|----------|----------------|-----|--------|
| **OpenClaw** | Shipped | Full: plugin, wizard, local/API | [openclaw.md](frameworks/openclaw.md) | `npx @aporthq/aport-agent-guardrails openclaw` |
| **Cursor**   | Shipped | Full: hooks installer + script | [cursor.md](frameworks/cursor.md) | `npx @aporthq/aport-agent-guardrails cursor` |
| **LangChain / LangGraph** | Shipped | **Python only:** callback, `aport-langchain setup` | [langchain.md](frameworks/langchain.md) | `npx @aporthq/aport-agent-guardrails langchain` then `pip install aport-agent-guardrails-langchain` + `aport-langchain setup` |
| **CrewAI**   | Shipped | **Python only:** hook, decorator, `aport-crewai setup` | [crewai.md](frameworks/crewai.md) | `npx @aporthq/aport-agent-guardrails crewai` then `pip install aport-agent-guardrails-crewai` + `aport-crewai setup` |

**Coming soon:** n8n — custom node and runtime in progress ([n8n.md](frameworks/n8n.md)). Not listed in CLI options until shipped.

All supported frameworks above use the same passport wizard and policy packs; each has a framework-specific installer. OpenClaw and Cursor have full runtime integration; LangChain/CrewAI have full integration **via Python packages**.

## Completion

- **CLI:** One entry point `npx @aporthq/aport-agent-guardrails` with detection or `--framework=<name>`.
- **Shared:** Passport wizard, guardrail scripts (local + API), policy packs, config/path helpers (`bin/lib/`).
- **Per framework:** Installer in `bin/frameworks/<name>.sh`, config written to framework-specific path, doc in `docs/frameworks/<name>.md`, integration tests in `tests/frameworks/<name>/`.

## Node/TypeScript packages (this repo)

| Package | Status | Notes |
|---------|--------|--------|
| **@aporthq/aport-agent-guardrails-core** | Implemented | Evaluator (API + local bash script), config, passport. Not yet published to npm. |
| **@aporthq/aport-agent-guardrails-langchain** | Implemented | Callback handler using core; `GuardrailViolationError` on deny. Not yet published. |
| **@aporthq/aport-agent-guardrails-crewai** | Implemented | `beforeToolCall`, `registerAPortGuardrail`, `withAPortGuardrail` (parity with Python). |
| **@aporthq/aport-agent-guardrails-n8n** | Coming soon | Placeholder for future n8n custom node. **Not published to npm** until the custom node is ready. |
| **@aporthq/aport-agent-guardrails-cursor** | Implemented | `Evaluator`, `getHookPath()`; runtime is bash hook from CLI. |

Production integration for LangChain: **Python** (pip, published) and **Node** (workspace implemented, publish when ready). See [DEPLOYMENT_READINESS.md](DEPLOYMENT_READINESS.md).

## Proposals / next

- **Python local-only verification** — Use passport + policy JSON files without calling the API (Story F in [USER_STORIES.md](launch/USER_STORIES.md)).
- **Node core + adapters** — Implement evaluator/config/passport in `packages/core` and real middleware in framework packages before publishing.
- **n8n custom node** — Implement node and credentials so n8n workflows can branch on allow/deny.
- **Additional frameworks** — Add new ones by following [ADDING_A_FRAMEWORK.md](ADDING_A_FRAMEWORK.md); each is &lt;50 lines of bash plus config template.

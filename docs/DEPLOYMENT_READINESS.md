# Deployment readiness — what’s production vs roadmap

**Purpose:** Single source of truth for what is safe to deploy today vs what is stub, partial, or planned. Use this for launch checklists, automation (e.g. OpenClaw Agent), and support.

**Related:** [USER_STORIES.md](launch/USER_STORIES.md) (acceptance criteria and test coverage), [FRAMEWORK_ROADMAP.md](FRAMEWORK_ROADMAP.md) (supported frameworks and install). For plan-vs-reality alignment (TypeScript core and Node adapters), see [FRAMEWORK_SUPPORT_PLAN.md § Implementation status](launch/FRAMEWORK_SUPPORT_PLAN.md#implementation-status-current-vs-plan).

---

## What `npx @aporthq/aport-agent-guardrails langchain` (or crewai) actually does

When you run **`npx @aporthq/aport-agent-guardrails`** and choose **LangChain** or **CrewAI**, the **Node** CLI runs only the **bash** framework script (`bin/frameworks/langchain.sh` or `crewai.sh`). That script:

1. Runs the **shared passport wizard** (same as OpenClaw/Cursor).
2. Writes **framework-specific config** (e.g. `~/.aport/langchain/config.yaml`).
3. Prints **next steps** (install Python package and run `aport-langchain setup` or `aport-crewai setup`).

It does **not** run Python or install any pip package. The **guardrail** (the code that blocks tool calls when policy denies) is provided by:

- **Python:** `pip install aport-agent-guardrails-langchain` / `aport-agent-guardrails-crewai` (on PyPI). **Node:** `@aporthq/aport-agent-guardrails`, `-core`, `-langchain`, `-crewai`, `-cursor` — published to npm via **release CI** on tag push (see [RELEASE.md](RELEASE.md)).

---

## 1. Safe to deploy today

Everything below is **ready to deploy**: CI (`.github/workflows/release.yml`) publishes to npm and PyPI on tag push; tests and docs are in place.

| Area | What works | Notes |
|------|------------|--------|
| **Release CI** | `.github/workflows/release.yml` on push of tag `v*` | Builds workspace packages; publishes **root** + **core**, **langchain**, **crewai**, **cursor** to npm; publishes **Python** to PyPI; creates GitHub Release. Version check (tag vs root package.json) before publish. n8n package not published yet (coming soon). |
| **Root npm package** | `@aporthq/aport-agent-guardrails` | CLI: `bin/agent-guardrails`, framework installers (bash), docs. Published by CI on tag. |
| **Node/TypeScript core** | `packages/core` — evaluator (API + local bash, native fetch in sync path), config (YAML), passport, pathUtils | Fail-closed by default when passport/script missing; `fail_open_when_missing_config` or `APORT_FAIL_OPEN_WHEN_MISSING_CONFIG=1` for legacy. Jest tests (config, passport, evaluator). Published by CI on tag as `@aporthq/aport-agent-guardrails-core`. |
| **Node LangChain adapter** | `packages/langchain` — `APortGuardrailCallback`, `GuardrailViolationError` | Jest tests (allow/deny, error shape). Published by CI as `@aporthq/aport-agent-guardrails-langchain`. |
| **Node CrewAI adapter** | `packages/crewai` — `beforeToolCall`, `registerAPortGuardrail`, `withAPortGuardrail` | Feature parity with Python. Published by CI as `@aporthq/aport-agent-guardrails-crewai`. |
| **Node Cursor package** | `packages/cursor` — `Evaluator`, `getHookPath()` | Re-exports core; runtime is bash hook from CLI. Published by CI as `@aporthq/aport-agent-guardrails-cursor`. |
| **OpenClaw plugin + wizard** | `bin/openclaw`, `extensions/openclaw-aport/`, passport wizard, local/API evaluator | Full setup: config, plugin install, skill wrappers. Deterministic `before_tool_call` enforcement. |
| **Bash guardrail** | `bin/aport-guardrail-bash.sh`, `bin/aport-create-passport.sh` | OAP v1.0 wizard, fail-closed guardrail, audit + decision chain. Used by OpenClaw plugin and Cursor hook. |
| **Cursor hook** | `bin/frameworks/cursor.sh`, `bin/aport-cursor-hook.sh` | Installer writes `~/.cursor/hooks.json`; hook enforces policy; unit + integration tests. User must restart Cursor after install. |
| **Python LangChain adapter** | `python/langchain_adapter`, `aport-agent-guardrails-langchain` (PyPI), `aport-langchain setup` | Callback handler, shared evaluator, examples, E2E in CI. Published by CI to PyPI. |
| **Python CrewAI adapter** | `python/crewai_adapter`, `aport-agent-guardrails-crewai` (PyPI), `aport-crewai setup` | Before-tool-call hook, decorator, shared evaluator, examples, E2E in CI. Published by CI to PyPI. |
| **Dispatcher CLI** | `bin/agent-guardrails`, `bin/lib/detect.sh`, `bin/frameworks/*.sh` | Framework detection, `--framework=`, shared wizard/config; delegates to OpenClaw full installer or framework scripts. |
| **Docs** | `docs/frameworks/*.md`, README, RELEASE.md, FRAMEWORK_ROADMAP.md | Guardrails vs Core, setup and library usage per framework (Python and Node). |

---

## 2. Not deploy-ready (stub, partial, or missing)

| Area | Current state | Impact |
|------|----------------|--------|
| **n8n integration** | **Coming soon.** CLI accepts `--framework=n8n` (runs wizard + config only); **@aporthq/aport-agent-guardrails-n8n is not published to npm** until the custom node is ready. Docs and `docs/frameworks/n8n.md` state coming soon. | Custom node and runtime not yet implemented. |
| **Framework installers (LangChain/CrewAI/n8n)** | `bin/frameworks/langchain.sh`, `crewai.sh`, `n8n.sh` run wizard + write config only; they do **not** run `pip install` or install n8n nodes | User must manually install Python or Node adapter and run framework setup. |
| **Python CLI (`aport`)** | `python/aport_guardrails/cli.py` — prints next-step commands per framework; does not run wizard | Python-only users run the printed commands (npx or pip) for full setup. |
| **Shared bash refactor** | Wizard/config logic still largely in `bin/openclaw`; `bin/lib/passport.sh` re-calls `aport-create-passport.sh` | Story B “&lt;50-line framework scripts” holds for langchain/crewai/n8n scripts; OpenClaw path remains the full installer. |

---

## 3. Alignment with USER_STORIES.md

- **Stories A–E** describe the **bash dispatcher**, **shared lib**, **Python adapters** (LangChain, CrewAI), and **Cursor**. Implementation status is accurate: detection, `--framework=`, wizard, config, Python packages, Cursor hook, and tests are in place.
- **Node/TypeScript:** Core, langchain, crewai, and cursor are **implemented** and **ready to deploy**: CI publishes them to npm on tag push. Core and langchain have Jest unit tests; crewai and cursor have feature parity with Python. n8n is **coming soon** (CLI runs wizard + config only; package not published).

---

## 4. Recommended wording for docs and support

- **OpenClaw:** “Production-ready: plugin, wizard, local/API, full installer.”
- **Cursor:** “Production-ready: hook installer and script; restart Cursor after install.”
- **LangChain / CrewAI:** “Production-ready **via Python packages**: `pip install aport-agent-guardrails-langchain` (or crewai) and `aport-<framework> setup`. The one-line CLI (`npx @aporthq/aport-agent-guardrails langchain`) runs the passport wizard and writes config; you still install the Python package and run setup yourself.”
- **n8n:** "Coming soon. CLI accepts --framework=n8n (wizard + config only). Custom node and runtime integration in progress."
- **Node/TypeScript packages:** “Core, LangChain, CrewAI, and Cursor packages are ready to deploy; CI publishes them to npm on tag push. Install with `npm install @aporthq/aport-agent-guardrails-core` (and `-langchain`, `-crewai`, `-cursor` as needed).”

---

## 5. Optional improvements (not blocking deploy)

1. **Framework installers** that install or verify the relevant package (e.g. `pip install aport-agent-guardrails-langchain` or check and prompt).
2. **n8n:** Deliver custom node (and credentials schema); until then n8n remains coming soon.
3. **Python CLI:** Wire `aport setup` to the same wizard/flow as the bash CLI or document that full setup is via `npx @aporthq/aport-agent-guardrails` + framework-specific pip/setup.
4. **Integration/E2E tests** for Node packages (optional; unit tests for core and langchain are in place).


**Production-ready today:** OpenClaw, Cursor, Python LangChain/CrewAI, **and** the Node CLI + Node packages (root, core, langchain, crewai, cursor) — all deployed via CI on tag push.

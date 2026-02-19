# User Stories, Acceptance Criteria, and Test Coverage

**Source:** Staff-level review of launch plan and codebase.  
**Context:** [FRAMEWORK_SUPPORT_PLAN.md](FRAMEWORK_SUPPORT_PLAN.md) — architecture, shared vs divergent layers, per-framework patterns.  
**Status:** Living doc; update as stories are implemented.

> **Aligned with v1.0.8:** Node adapters (LangChain, CrewAI, Cursor) and Python adapters are production-ready and published. See [CHANGELOG.md](../CHANGELOG.md) for 1.0.8 scope.

**Scope and alignment:** Stories A–E cover the **bash dispatcher** (`bin/agent-guardrails`, `bin/frameworks/*.sh`), **shared lib** (`bin/lib/`), **Python adapters** (LangChain, CrewAI), and **Cursor** (hook installer + script). The **Node/TypeScript** monorepo (`packages/core`, `packages/langchain`, `packages/crewai`, `packages/cursor`) is **implemented and published** (v1.0.8); `packages/n8n` is config/installer only (not published). For a concise “what’s production vs roadmap” view, see [DEPLOYMENT_READINESS.md](../DEPLOYMENT_READINESS.md) and [FRAMEWORK_SUPPORT_PLAN.md](FRAMEWORK_SUPPORT_PLAN.md).

---

## 1. What’s working today

| Area | Status | Notes |
|------|--------|-------|
| **Passport wizard** (`bin/aport-create-passport.sh`) | ✅ | Generates OAP v1.0 passports; invoked from `bin/openclaw` flow. |
| **Guardrail scripts** (`bin/aport-guardrail*.sh`) | ✅ | Local + API evaluators work; OpenClaw plugin calls them. |
| **OpenClaw integration** (`extensions/openclaw-aport/`, installer) | ✅ | `before_tool_call` hook is deterministic; `bin/openclaw` does full setup. |
| **Policy packs** (`external/aport-policies`) | ✅ | OAP packs available and shared. |
| **Docs** (FRAMEWORK_SUPPORT_PLAN, quickstarts, framework docs) | ✅ | Strategy and per-framework setup documented. |
| **Dispatcher stub** (`bin/agent-guardrails`) | ✅ | Prompts for framework or accepts first arg; delegates to `bin/frameworks/*.sh` or `bin/openclaw`. |
| **Shared lib** (`bin/lib/common.sh`, `config.sh`, `passport.sh`, `allowlist.sh`) | ✅ | Helpers exist; wizard still mostly in `bin/openclaw`. |
| **Versioning** (Changesets, sync-version, single version) | ✅ | See [docs/RELEASE.md](../RELEASE.md). |

---

## 2. Gaps / pending work (high-level)

1. **Single dispatcher CLI** — Must support framework **detection** from cwd and `--framework=`; today it only prompts or takes a positional arg. *(Detection and `--framework=` are implemented; see Story A.)*
2. **Shared helpers factored out** — Wizard/config logic still largely inside `bin/openclaw`; framework scripts should reuse `bin/lib/` and only do framework-specific steps.
3. **LangChain/CrewAI (Python)** — Implemented (pip packages + setup CLI). **Node/TypeScript** packages (`packages/langchain`, `packages/crewai`, `packages/cursor`) are **implemented and published** (v1.0.8). **n8n** — config/installer only; no custom node yet; not published.
4. **Python SDK offline** — No local-only path (passport + policy files) without calling bash (Story F).
5. **Testing** — OpenClaw + Python adapters covered; no tests for Node packages or n8n runtime (see [§5 Testing strategy](#5-testing-strategy-overall)).

See [DEPLOYMENT_READINESS.md](../DEPLOYMENT_READINESS.md) for what is safe to deploy today vs roadmap.

---

## 3. User stories (full)

### Story A: “As a developer, I can run one CLI (`npx @aporthq/aport-agent-guardrails`) and get a framework-specific setup.”

**Acceptance criteria**

1. CLI starts with **framework detection** (e.g. finds `pyproject.toml`, `package.json`, or prompts if none).
2. **Passport wizard** runs identically regardless of framework.
3. Installer **writes framework-specific config** (e.g. `~/.aport/langchain/config.yaml`, `~/.openclaw/aport-config.yaml`).
4. CLI **prints next steps / snippets** for the chosen framework.
5. Running with **`--framework=openclaw`** (or any supported key) **skips detection** and goes straight to setup.

**Test coverage**

- **Unit:** `bin/lib` helpers covered by bash-based unit tests: `tests/unit/test-lib-common.sh`, `test-lib-config.sh`, `test-lib-allowlist.sh` (config write, allowlist); `test-detect-framework.sh` (detection single + conflict); `test-agent-guardrails-dispatcher.sh` (dispatcher args, pass-through, non-interactive, APORT_FRAMEWORK, multiple detected).
- **Integration:** `tests/frameworks/openclaw/setup.sh` and `setup.test.mjs` run CLI in temp dir and assert config files exist.
- **E2E:** `.github/workflows/e2e-openclaw.yml` runs `agent-guardrails --framework=openclaw` (non-interactive), then optional `openclaw gateway start` and smoke when openclaw is available.

**Plan context (FRAMEWORK_SUPPORT_PLAN)**

- High-level flow: Detect or prompt → shared wizard → hosted/local → install framework integration → write config → smoke test.
- Shared steps: prompt for framework, run passport wizard, choose hosted/local, write config (shared logic, different path), run smoke test.
- Config locations: OpenClaw `~/.openclaw`, LangChain `~/.aport/langchain/`, CrewAI `~/.aport/crewai/`, n8n credentials store.

**Implementation status**

- [x] AC1: Framework detection from cwd — `bin/lib/detect.sh` checks `pyproject.toml`, `package.json`, `requirements.txt` for langchain/crewai/openclaw.
- [x] AC2: Passport wizard shared — OpenClaw uses `bin/openclaw`; LangChain/CrewAI/n8n use `lib/passport.sh` → `bin/aport-create-passport.sh`.
- [x] AC3: Framework-specific config — OpenClaw: full config in `bin/openclaw`. Others: `write_config_template` in `lib/config.sh` creates `~/.aport/<framework>/` and framework scripts call it.
- [x] AC4: Next steps/snippets — OpenClaw: printed by `bin/openclaw`. LangChain/CrewAI/n8n: explicit "Next steps" block with snippet and doc link in each `bin/frameworks/*.sh`.
- [x] AC5: `--framework=<name>` and `-f <name>` — parsed in `bin/agent-guardrails`; skips detection and runs chosen framework.

---

### Story B: “As an engineer, I can add a new framework without copying passport/config logic.”

**Acceptance criteria**

1. Shared helpers live under **`bin/lib/`** (`passport.sh`, `config.sh`, `common.sh`).
2. Framework scripts in **`bin/frameworks/<name>.sh`** only handle **unique steps** (e.g. injecting middleware, writing snippet).
3. **`integrations/<framework>/`** contains framework-specific code (middleware, plugin, examples).
4. Adding a new framework requires **&lt;50 lines of bash** plus a config template.

**Test coverage**

- **Unit:** Bash unit tests in `tests/unit/`: `test-lib-common.sh` (log helpers, `require_cmd`), `test-lib-config.sh` (`get_config_dir`, `write_config_template`), `test-lib-allowlist.sh` — source `bin/lib/*.sh` and assert behavior. No shellspec or mocks in repo; shellspec (mock `cat`, `sed`, etc.) could be added later for isolation.
- **Integration:** ✅ For each framework script, run CLI in `tests/frameworks/<name>/` fixture and assert expected files: **openclaw** — `config.yaml` exists and contains `agentId`; **langchain**, **crewai**, **n8n** — config dir exists and `config.yaml` present (template copy).

**Plan context**

- Repository structure: `bin/lib/`, `bin/frameworks/*.sh`, `integrations/<framework>/`, `packages/`, `python/`.
- What diverges: integration hook, config file location, middleware/decorator pattern.

**Implementation status**

- [x] Shared helpers in `bin/lib/`.
- [x] Framework scripts in `bin/frameworks/` (OpenClaw delegates to full installer).
- [x] Framework scripts use shared wizard/config only; &lt;50 lines each (langchain 30, crewai 31, n8n 28, openclaw 19).
- [x] Integration dirs populated: `integrations/<framework>/` have README, examples/pointers; config template in `bin/lib/templates/config.yaml`; [docs/ADDING_A_FRAMEWORK.md](../ADDING_A_FRAMEWORK.md) documents the pattern; integration tests in `tests/frameworks/langchain/`, `crewai/`, `n8n/`.

---

### Story C: “As a Python LangChain developer, I can install a middleware package and immediately enforce APort policies.”

**Acceptance criteria**

1. **`pip install aport-agent-guardrails-langchain`** installs middleware (`APortGuardrailCallback`) and CLI (`aport-langchain setup`).
2. **`aport-langchain setup`** shares the same wizard flow, writes **`.aport/config.yaml`**, and runs a smoke test.
3. Middleware **auto-loads config** (hosted or local) and **blocks** tool call if policy denies.
4. README/example showing how to wrap an agent and interpret errors.

**Test coverage**

- **Unit:** `aport_guardrails/frameworks/langchain.py` — pytest in `python/aport_guardrails/tests/test_frameworks_langchain.py` (LangChainAdapter). Callback: `python/langchain_adapter/tests/test_callback.py` — mock evaluator, deny raises `GuardrailViolation`.
- **Integration:** Example under `examples/langchain/` with temp config/passport; `run_with_guardrail.py` asserts ALLOW then DENY.
- **E2E:** `.github/workflows/e2e-langchain.yml` — installs package, `aport-langchain setup --ci`, runs example script, expects "Example: ALLOW and DENY paths OK"; runs pytest for adapter and core.

**Plan context**

- LangChain: `AsyncCallbackHandler.on_tool_start`; config `.aport/config.yaml` or `~/.aport/langchain/`.
- Shared evaluator in `python/aport_guardrails/core/evaluator.py`.

**Implementation status**

- [x] **Package:** `pip install aport-agent-guardrails-langchain` (depends on aport-agent-guardrails). Import: `from aport_guardrails_langchain import APortCallback, GuardrailViolation`. Package layout aligns with [aporthq-sdk-python](https://pypi.org/project/aporthq-sdk-python/) (pyproject, optional dev deps).
- [x] **CLI:** `aport-langchain setup` writes `~/.aport/langchain/config.yaml`, prints next steps; `--ci` / `--no-wizard` for non-interactive.
- [x] **Middleware:** `APortCallback` auto-loads config (`.aport/config.yaml` or `~/.aport/langchain/`); on deny raises `GuardrailViolation` (code, reasons). Uses core `Evaluator` (config + API or local guardrail script).
- [x] **Example and README:** `examples/langchain/` (run_with_guardrail.py: ALLOW/DENY), `python/langchain_adapter/README.md`, `integrations/langchain/` README.
- [x] **Tests:** Unit: `aport_guardrails/tests/test_frameworks_langchain.py` (LangChainAdapter); `langchain_adapter/tests/test_callback.py` (mock evaluator, deny → `GuardrailViolation`). Integration: `examples/langchain/run_with_guardrail.py` (temp config, ALLOW/DENY). E2E: `e2e-langchain.yml` (install, setup --ci, example + pytest).
- [x] **API/local parity:** Core evaluator supports two passport options (agent_id in context, passport in body) and pack_id in path; see [DRY_AND_PLAN_CHECKLIST.md](DRY_AND_PLAN_CHECKLIST.md).

---

### Story D: “As a CrewAI user, I can decorate tasks with APort guardrails.”

**Acceptance criteria**

1. **`pip install aport-agent-guardrails-crewai`** provides a decorator or mixin that wraps task execution.
2. CLI **`aport-crewai setup`** handles passports/config and prints sample usage.
3. Decorator passes **CrewAI task params** into policy context and denies execution deterministically.
4. **Multi-task crews** supported (decorator works when tasks run concurrently).

**Test coverage**

- **Unit:** Pytest on decorator (`python/crewai_adapter/tests/test_decorator.py`): intercepts args/kwargs, calls `register_aport_guardrail` before wrapped fn, returns wrapped return value; hook tests (`test_hook.py`) ensure evaluator is called and allow/deny decisions are respected.
- **Integration:** `examples/crewai/run_with_guardrail.py` (hook allow/deny, register); `examples/crewai/sample_crew.py` — minimal crew with tool, mock evaluator allows first and denies second tool call (or simulates two hook calls when no LLM); both ALLOW and DENY paths asserted.
- **E2E:** `.github/workflows/e2e-crewai.yml` — install core + crewai adapter + crewai, `aport-crewai setup --ci`, run run_with_guardrail and sample_crew pytest, run crewai adapter tests; deterministic behavior.

**Plan context**

- CrewAI: `@before_tool_call` / `@before_tool_call_crew` (native hooks); return `False` to block.
- Config: `.aport/config.yaml` or `~/.aport/crewai/config.yaml`.

**Implementation status**

- [x] **Package:** `pip install aport-agent-guardrails-crewai` (depends on aport-agent-guardrails, crewai>=0.80). Import: `from aport_guardrails_crewai import aport_guardrail_before_tool_call, register_aport_guardrail, with_aport_guardrail`.
- [x] **CLI:** `aport-crewai setup` writes `~/.aport/crewai/config.yaml`, runs passport wizard, prints next steps; `--ci` / `--no-wizard` for non-interactive.
- [x] **Hook:** `aport_guardrail_before_tool_call(context)` fits CrewAI’s before_tool_call signature; uses `Evaluator.verify_sync()` (sync so hook stays sync). `register_aport_guardrail()` registers it globally; `with_aport_guardrail` decorator registers then runs the wrapped function (entry-point pattern).
- [x] **Multi-task crews:** Hook runs for every tool call; no crew-specific wiring required.
- [x] **Unit tests:** `python/crewai_adapter/tests/test_hook.py` — allow returns None, deny returns False, context serialization; mocked Evaluator.
- [x] **Integration example:** `examples/crewai/run_with_guardrail.py` — temp config, ALLOW/DENY, register_aport_guardrail. `examples/crewai/sample_crew.py` — minimal crew (Agent + Task + Crew + tool) triggers ALLOW then DENY via hook (mock evaluator or simulated hook calls when no LLM).
- [x] **E2E:** `e2e-crewai.yml` — install, setup --ci, run examples and adapter pytest.

---

### Story E: “As a Cursor / VS Code (Copilot) user, I can install guardrails via hooks so agent tool/shell execution is checked before run.”

**Acceptance criteria**

1. **`npx @aporthq/aport-agent-guardrails cursor`** (or `--framework=cursor`) runs passport wizard and writes **hooks config** (e.g. `~/.cursor/hooks.json`) pointing to an APort hook script.
2. **Hook script** reads Cursor/Copilot stdin JSON (e.g. `beforeShellExecution` / `PreToolUse`), calls existing guardrail (bash or API), returns allow/deny; **exit 2** blocks execution.
3. **Denied** actions are blocked by the host (Cursor/VS Code); allowed proceed.
4. Same script works for **VS Code + GitHub Copilot** when user adds it to `~/.claude/settings.json` or `.github/hooks/*.json` (PreToolUse); and for **Claude Code** — one script, multiple editors.

**Test coverage**

- **Unit:** Hook script with mock stdin (allow/deny, exit 0/2).
- **Integration:** Run script with sample Cursor/Copilot-style JSON; assert output format and exit code.
- **Manual:** QA in Cursor and VS Code (Copilot) with real agent run.

**Plan context**

- Cursor and VS Code (Copilot) use **config-driven hooks** (not extension API) for before-execution: `.cursor/hooks.json`, `~/.claude/settings.json`, `.github/hooks/*.json`. PreToolUse / beforeShellExecution run a command; exit 2 = block. See [CURSOR_VSCODE_HOOKS_RESEARCH.md](CURSOR_VSCODE_HOOKS_RESEARCH.md).
- **VS Code extension:** Vanilla VS Code has no API to intercept shell/tool execution. Building an extension does not add interception; it could only write the same hook config (optional UX). Recommendation: **implement hook script + installer first**; skip extension for MVP.

**Implementation status**

- [x] Cursor (and optional Copilot) installer: write hooks.json / settings.json, install hook script.
- [x] Hook script: stdin → guardrail → stdout + exit 0/2.
- [x] Docs: Cursor, VS Code+Copilot, Claude Code.

**Implementation audit (Story E)**

| Item | Status | Notes |
|------|--------|------|
| Installer `bin/frameworks/cursor.sh` | Done | Runs wizard (framework default `~/.cursor/aport/passport.json`), writes `~/.cursor/hooks.json` with `beforeShellExecution` and `preToolUse` pointing at `bin/aport-cursor-hook.sh`. |
| Hook script `bin/aport-cursor-hook.sh` | Done | Reads JSON from stdin, maps to `exec.run` + context, calls `aport-guardrail-bash.sh`; exit 0 = allow, exit 2 = deny. Resolver probes `~/.cursor`, `~/.openclaw`, etc. |
| Config / path map | Done | `bin/lib/config.sh`: `get_config_dir(cursor)` → `~/.cursor`, `get_default_passport_path(framework)`. Evaluator: `DEFAULT_PASSPORT_PATHS` and `_resolve_passport_path()`. Path resolver preserves `OPENCLAW_DECISION_FILE` when set (fixes API evaluator test). |
| Wizard first question | Done | Passport path is first prompt; default is framework-specific; `--output` supported in interactive and non-interactive. |
| Audit log & status context | Done | Audit log includes capability context (command, recipient, repo/branch). `bin/aport-status.sh` shows context in Latest Decision and Recent Activity. |
| Test flow (script + real) | Done | `docs/frameworks/cursor.md`: test script from terminal (allow/deny), inspect status/audit, then test real installation by asking Cursor agent to run a command. |
| Unit tests | Done | `tests/unit/test-cursor-hook.sh`: allow/deny, Copilot-style input, empty stdin. `tests/unit/test-lib-config.sh`: `get_default_passport_path` cursor/openclaw. |
| Integration tests | Done | `tests/frameworks/cursor/setup.sh`: installer with `--output`/`--non-interactive`, asserts `hooks.json` exists and references hook script. |
| Docs | Done | `docs/frameworks/cursor.md`: setup, per-framework default path, first prompt, “What the guardrail applies to”, test steps (script, status/audit, real agent), audit format with context. |

**Scope / limitation**

- Hooks run only when Cursor runs a **shell command** (`beforeShellExecution`) or a **tool** that sends command-like input (`preToolUse`). They **do not** run when the IDE performs **direct file operations** (e.g. “delete file” or “write file” via the editor/workspace API). So if the user asks “Remove file X” and Cursor deletes the file via a built-in file action (not via `rm` in the terminal), the guardrail is **not** invoked. To verify the guardrail: ask the agent to **“Run in the terminal: rm /path/to/file”** — that should trigger the hook and, if policy blocks `rm -rf`, the command should be blocked. See [docs/frameworks/cursor.md](../frameworks/cursor.md) section “What the guardrail applies to (and what it doesn’t)”.

---

### Story F: “As a developer, I can use the Python and Node SDKs (and middleware) for direct integration or offline verification.”

**Acceptance criteria**

1. **`APortClient`** (Python) accepts **`passport_path`** and **`policy_path`** for local verification without API. *(Pending in this repo.)*
2. Local branch uses **same OAP evaluator logic** (call bash script or port to Python).
3. CLI installers offer **API vs local** and configure SDK accordingly.
4. Local mode: optional **caching** of policy evaluations; **consistent** allow/deny responses.
5. **Document** official SDKs and middleware for developers who prefer to integrate **directly** (without the agent-guardrails CLI/frameworks).

**Test coverage**

- **Unit:** Pytest: existing API-style tests run with local authorizer.
- **Integration:** Example script with offline policy; snapshot decisions.
- **Performance:** CI benchmark for local mode latency.

**Plan context**

- Verification: API or local (bash); shared logic, different wrappers.
- Config: mode (api | local), paths.

**Implementation status**

- [ ] Python local authorizer (passport + policy paths) in this repo.
- [ ] CLI mode choice and config.
- [x] **SDKs and middleware documented** — Story F points to official Node and Python SDK/middleware packages; see "Using official SDKs and middleware" below and README for direct integration.

**Using official SDKs and middleware (direct integration)**

For developers who prefer to use **SDKs or middleware directly** (API verification, no CLI setup), use the official packages:

| Platform | Package | Description |
|----------|---------|-------------|
| **Node** | [@aporthq/sdk-node](https://www.npmjs.com/package/@aporthq/sdk-node) | Node SDK for policy verification via APort API. |
| **Node** | [@aporthq/middleware-express](https://www.npmjs.com/package/@aporthq/middleware-express) | Express middleware for policy enforcement. |
| **Python** | [aporthq-sdk-python](https://pypi.org/project/aporthq-sdk-python/) | Python SDK for policy verification (async, type-safe, Server-Timing, JWKS). |
| **Python** | [aporthq-middleware-fastapi](https://pypi.org/project/aporthq-middleware-fastapi/) | FastAPI middleware for policy enforcement. |

- **Install (Node):** `npm install @aporthq/sdk-node` or `npm install @aporthq/middleware-express`
- **Install (Python):** `pip install aporthq-sdk-python` or `pip install aporthq-middleware-fastapi`

These are **thin clients**: all policy logic and enforcement run on the server (api.aport.io or self-hosted). Use them when you want to call the verify API from your own app or protect HTTP routes with policy checks. This repo's framework adapters (Cursor, OpenClaw, LangChain, etc.) use the same API and can coexist with direct SDK usage.

---

### Story G: “As a release engineer, I can cut a version that bumps every package consistently.”

**Acceptance criteria**

1. **Monorepo release** (Changesets + sync) increments version across **core + adapters**.
2. **Publish:** npm (e.g. `changeset publish`) and PyPI (e.g. `poetry publish` / twine).
3. **Git tag `vX.Y.Z`** matches package versions.
4. CI checks that packages depending on core use **`>= current version`**.

**Test coverage**

- **Automation:** CI job runs release (dry-run), checks bumped files.
- **Unit (optional):** Script test that version in package.json/pyproject aligns.

**Plan context**

- Single version for whole suite; see [docs/RELEASE.md](../RELEASE.md).

**Implementation status**

- [x] **AC1:** Changesets in fixed mode; `npm run version` bumps all workspace packages; `scripts/sync-version.mjs` copies version to Python `pyproject.toml` and `__init__.py`.
- [x] **AC2:** Publish — Node: `npm publish` (root package); PyPI publish documented in RELEASE.md (build + twine or CI).
- [x] **AC3:** Git tag `vX.Y.Z` matches released version; tagging and push is part of release flow.
- [x] **AC4:** Release CI — `.github/workflows/release.yml` runs on push of tag `v*`: publishes to npm, creates GitHub Release. Version alignment is enforced by single fixed group in Changesets and sync-version.

**Story G is fully implemented.** Cut a release by: (1) `npm run version` and commit, (2) `git tag vX.Y.Z` and push; CI publishes npm and creates the GitHub Release.

---

## 4. Action items (handoff to engineering)

1. **Dispatcher + refactor** — `bin/agent-guardrails`, `bin/lib/*`, `bin/frameworks/openclaw.sh`: detection, `--framework=`, shared wizard/config usage.
2. **Extract shared logic from `bin/openclaw`** into `bin/lib/` where reusable.
3. **LangChain adapter (Python + CLI)** — package, `aport-langchain setup`, middleware using shared evaluator.
4. **Python local mode** — SDK accepts passport/policy paths; evaluator runs offline.
5. **Release pipeline** — CI for version bump (dry-run), publish, tag.

Then: Cursor, CrewAI, n8n in parallel (each with story + tests above).

---

## 5. Testing strategy (overall)

**Test coverage is required for every story.** When implementing a story, add or extend:

- **Unit:** Bash unit tests in `tests/unit/` for `bin/lib` (or shellspec if introduced); Jest/pytest for Node/Python code.
- **Integration:** Per-framework tests in `tests/frameworks/<name>/` (run CLI in temp dir; assert config, snippets, non-interactive).
- **E2E:** GitHub Actions workflow or job that runs the flow in a container and asserts smoke.

| Level | Tooling | Notes |
|-------|---------|--------|
| **Unit** | Bash tests in `tests/unit/`, shellspec, jest, pytest | Shared helpers (`bin/lib`), evaluators, middleware. Story A: test-lib-*.sh, test-detect-framework.sh, test-agent-guardrails-dispatcher.sh. |
| **Integration** | Temp fixtures, CLI harness | Each framework: `tests/frameworks/<name>/` (setup.sh, setup.test.mjs or .ts); assert config, non-interactive. |
| **E2E** | GitHub Actions (e2e-openclaw.yml, ci.yml) | Run CLI non-interactive, optional gateway + smoke. |
| **Manual/UX** | QA checklist, screen recordings | IDE (Cursor, VS Code) and low-code (n8n, Zapier); document expected UI. |

---

## Document changelog

| Date | Change |
|------|--------|
| 2026-02-17 | Initial: staff review stories A–G, plan context, implementation status. |
| 2026-02-17 | Story A implemented: dispatcher with detection (`bin/lib/detect.sh`), `--framework`/`-f`, OpenClaw delegates to full installer; LangChain/CrewAI/n8n run shared wizard + config dir + next steps. |
| 2026-02-17 | Story A tests: unit (bin/lib, detect single+conflict, dispatcher + non-interactive + APORT_FRAMEWORK), integration (tests/frameworks/openclaw/setup.sh + setup.test.mjs), E2E workflow (e2e-openclaw.yml). Detector shows all options on conflict; non-interactive via APORT_NONINTERACTIVE/CI and APORT_FRAMEWORK. Test layout: tests/unit/, tests/frameworks/openclaw/, run.sh runs unit → OAP → integration. |
| 2026-02-18 | Story B implemented: framework scripts &lt;50 lines, use shared lib only; config written first then wizard; `integrations/<framework>/` READMEs + examples; `bin/lib/templates/config.yaml` + copy in `write_config_template`; [ADDING_A_FRAMEWORK.md](../ADDING_A_FRAMEWORK.md); integration tests for langchain, crewai, n8n in tests/run.sh; dispatcher fix for empty REST. |
| 2026-02-18 | Story C implemented: aport-agent-guardrails-langchain package (pyproject, import `aport_guardrails_langchain`); core config/evaluator/exceptions (GuardrailViolation); `APortCallback` auto-loads config, raises GuardrailViolation on deny; `aport-langchain setup` CLI; unit tests (pytest, mock evaluator); example in `examples/langchain/`; READMEs. Package layout follows aporthq-sdk-python pattern. |
| 2026-02-18 | DRY and plan alignment: [DRY_AND_PLAN_CHECKLIST.md](DRY_AND_PLAN_CHECKLIST.md) added; Python evaluator aligned with agent-passport API (POST /api/verify/policy/{pack_id}, agent_id or passport in body, tool→pack_id mapping); unit test for `aport_guardrails/frameworks/langchain.py`; E2E workflow `e2e-langchain.yml` (install, setup --ci, example + pytest). |
| 2026-02-18 | Story D implemented: aport-agent-guardrails-crewai package (before_tool_call hook); Evaluator.verify_sync() for sync callers; aport_guardrail_before_tool_call, register_aport_guardrail, with_aport_guardrail; aport-crewai setup CLI; unit tests (test_hook.py), example (examples/crewai/run_with_guardrail.py); docs/frameworks/crewai.md aligned with CrewAI Tool Call Hooks. |
| 2026-02-18 | Story E audit updated: audit log & status context (command, recipient, repo/branch); test flow (script + real installation); path resolver preserves OPENCLAW_DECISION_FILE; Docs row updated for cursor.md test steps and audit format. |
| 2026-02-18 | Story F: title and AC updated; added "Using official SDKs and middleware (direct integration)" with links to @aporthq/sdk-node, @aporthq/middleware-express, aporthq-sdk-python, aporthq-middleware-fastapi; implementation status: SDKs documented. Story G: marked fully implemented (Changesets, sync-version, release.yml on tag, npm publish, GitHub Release). README: added "Using SDKs or middleware directly" with same package links. |
| 2026-02-18 | Scope note: Stories A–E cover bash + Python + Cursor; Node/TS packages out of scope (stubs). §2 Gaps: qualify LangChain/CrewAI (Python done, Node stubs), n8n config only. Link to DEPLOYMENT_READINESS.md. |

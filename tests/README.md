# APort Agent Guardrails — Test Suite

Tests for [OAP v1.0](https://github.com/aporthq/aport-spec) compliance and OpenClaw integration: guardrail scripts, passport wizard, plugin (tool→policy mapping, decision integrity), and verification paths.

---

## Overview

| Aspect | Approach |
|--------|----------|
| **Strategy** | Isolated temp directory + fixture passport; no mutation of `~/.openclaw` in CI. |
| **Scope** | Unit (plugin helpers), integration (guardrail + passport + four verification modes), and flow (wizard → allow → deny → status). |
| **Determinism** | Tests use `APORT_TEST_DIR` or `mktemp` and fixture data so CI is reproducible. |

---

## Running tests

**From repo root:**

```bash
make test
# or
bash tests/run.sh
```

**Plugin (Node) tests** (mapToolToPolicy, canonicalize, verifyDecisionIntegrity, integration with guardrail script):

```bash
cd extensions/openclaw-aport && node test.js
```

**Requirements:** `bash`, `jq`. Optional: `APORT_API_URL` for API verification tests (skipped if unset or unreachable).

**Environment:** Tests respect `APORT_TEST_DIR` and `OPENCLAW_DEPLOYMENT_DIR` / `APORT_TEST_OPENCLAW_DIR` for temp/bootstrap dirs; they do not touch your real OpenClaw config unless you point them at it.

---

## Test files (current coverage)

| Script | What it covers |
|--------|----------------|
| **`test-four-verification-methods.sh`** | **(1)** Bash guardrail standalone, **(2)** API guardrail standalone (skip if no `APORT_API_URL`), **(3)** Plugin-local (guardrail from deployment dir), **(4)** Plugin-API (skip if no API). Bootstraps a temp OpenClaw-like dir (passport + `.skills` wrapper) unless `OPENCLAW_DEPLOYMENT_DIR` / `APORT_TEST_OPENCLAW_DIR` is set. |
| **`test-full-flow.sh`** | Full flow: create passport (wizard with piped input) → guardrail ALLOW → guardrail DENY (limit exceeded) → status shows passport. |
| **`test-passport-creation.sh`** | Passport creation: `aport-create-passport.sh` with piped answers; assert output has OAP v1 fields, capabilities, and limits. |
| **`test-oap-v1-guardrail.sh`** | Policy loading from submodules, allow/deny paths, OAP v1 decision shape (`reasons[]`, `passport_digest`, `policy_id`), `code.repository.merge` and `system.command.execute`, unknown tool denied. |
| **`test-oap-v1-passport-and-status.sh`** | Passport fixture required fields (`spec_version`, metadata, `never_expires`), status script output and missing-passport exit. |
| **`test-kill-switch.sh`** | Kill switch: absent → allow, present → deny (`oap.kill_switch_active`), removed → allow. |
| **`test-passport-missing-and-invalid.sh`** | Missing passport → `oap.passport_not_found`, invalid JSON → `oap.passport_invalid`, suspended → `oap.passport_suspended`. |
| **`test-api-evaluator.sh`** | API-powered evaluator (default: local agent-passport); skip if API unreachable. |
| **`test-plugin-guardrail-cli.sh`** | **Plugin-style CLI:** Same tool names and context as the OpenClaw plugin — `system.command.execute` (mkdir, ls) ALLOW; `messaging.message.send` ALLOW with `messaging.send` passport, DENY without. |

**Plugin tests** (`extensions/openclaw-aport/test.js`):

| Suite | What it covers |
|-------|----------------|
| `canonicalize` | Key sorting (top-level, nested, arrays), primitives. |
| `verifyDecisionIntegrity` | content_hash match/mismatch, tampering. |
| `mapToolToPolicy` | exec, git, messaging, mcp, session, payment, data.export, unmapped tools. |
| `performance` | mapToolToPolicy 5k calls &lt; 100ms, verifyDecisionIntegrity 1k &lt; 50ms, canonicalize 2k &lt; 30ms. |
| `integration (guardrail script)` | Real guardrail run; decision has `content_hash` and chain; audit non-blocking. |

---

## Fixtures and conventions

- **`fixtures/passport.oap-v1.json`** — Minimal OAP v1.0 passport with `repo.pr.create`, `repo.merge`, `system.command.execute` and limits for repo merge and command execute. Used by tests that need a valid passport.
- **`fixtures/passport-with-messaging.json`** — Same as above plus `messaging.send` capability and `limits.messaging`; used by `test-plugin-guardrail-cli.sh` for messaging.message.send ALLOW.
- Tests **source** `tests/setup.sh` for `REPO_ROOT`, `OPENCLAW_*`, `GUARDRAIL`, `STATUS_SCRIPT`, and helpers (`assert_eq`, `assert_json_has`, `assert_json_eq`).
- Each test runs in a separate shell; `run.sh` runs every `test-*.sh` and exits non-zero if any fail.

---

## Test improvement tracker (OpenClaw suggestions)

Suggested improvements and their status. Use this table to contribute: pick an item marked **Not implemented** or **Partial**, implement it, then update the status and add a short note.

| # | Suggestion | Status | Requirements / notes |
|---|------------|--------|----------------------|
| **1** | **End-to-end test against real OpenClaw** | **Not implemented** | Spin up a disposable OpenClaw workspace (e.g. temp dir with `openclaw init`), run `bin/openclaw` to install the plugin, then trigger a fake tool call (system command + messaging) through OpenClaw. Validates runtime wiring: config, `before_tool_call` hook, passport. Can be gated (e.g. `OPENCLAW_E2E=1`) or run in nightly CI if a headless OpenClaw instance is available. |
| **2** | **“Real” WhatsApp / messaging flow test** | **Not implemented** | Mock the message send (no real gateway). Drive the guardrail via the exact OpenClaw call; assert ALLOW when passport has `messaging.send`, DENY otherwise. Catches capability drift. |
| **3** | **Chaos / negative scenarios** | **Partial** | **Done:** missing/invalid passport, kill switch. **Not implemented:** corrupt passport JSON (e.g. truncated file), missing decision file, kill switch toggled mid-run; guardrail script missing or not executable; installer recovery (re-run `bin/openclaw` after partial install). |
| **4** | **Performance / regression (guardrail latency)** | **Partial** | **Done:** plugin unit performance (mapToolToPolicy, verifyDecisionIntegrity, canonicalize). **Not implemented:** test that runs 50+ guardrail calls (script or API) and asserts latency under a threshold (e.g. &lt; 300 ms per call) to guard against expensive policy changes. |
| **5** | **Snapshot tests for decisions** | **Not implemented** | Capture sample ALLOW and DENY decision JSON; diff against expected structure so future changes don’t break OAP/spec compliance. Requires committed snapshot files and a small diff step in a test. |
| **6** | **Documented fixtures for OpenClaw config** | **Not implemented** | Add a sample `openclaw.json` (or `config.yaml`) with the plugin entry under `tests/fixtures/` and a test that validates the installer writes equivalent structure (e.g. correct `guardrailScript`, `passportFile`, `mode`). |

---

## Summary table (at a glance)

| Category | Implemented | Not implemented |
|----------|-------------|------------------|
| **Verification paths** | Bash standalone, API standalone (optional), Plugin-local, Plugin-API (optional) | — |
| **Passport** | Creation (wizard), fixture, missing/invalid/suspended, status script | — |
| **Guardrail behavior** | Allow/deny, OAP decision shape, kill switch, policy loading, unknown tool | — |
| **Plugin** | mapToolToPolicy, canonicalize, verifyDecisionIntegrity, unit perf, integration with script | — |
| **E2E** | — | Real OpenClaw deploy + fake tool call (opt-in or nightly) |
| **Messaging** | — | Mock message send; ALLOW with `messaging.send`, DENY without |
| **Chaos** | Missing/invalid passport, kill switch | Corrupt JSON, missing decision file, kill switch mid-run, script missing/not executable, installer re-run after partial install |
| **Performance** | Plugin unit (5k/1k/2k calls) | 50+ guardrail calls, latency &lt; 300 ms |
| **Snapshots** | — | ALLOW/DENY decision JSON snapshot diff |
| **Config fixtures** | — | Sample `openclaw.json` + installer output validation |

---

## How to contribute

1. **Run the suite:** `make test` and `cd extensions/openclaw-aport && node test.js`. Ensure everything passes before adding tests.
2. **Pick an item** from the tracker above (prefer “Not implemented” or “Partial”).
3. **Implement** in the appropriate place:
   - Bash E2E/flow → new `tests/test-*.sh` and/or extend `test-four-verification-methods.sh`.
   - Plugin behavior → `extensions/openclaw-aport/test.js`.
   - Installer/config → new test that runs `bin/openclaw` (or a subset) and asserts config/passport; use temp dir and optional env gate (e.g. `OPENCLAW_E2E=1`).
4. **Document** in this README: update the “Test files” table and the “Test improvement tracker” row (set status to **Implemented** or **Partial** and add a one-line note).
5. **Keep isolation:** don’t rely on `~/.openclaw` or real API in default `make test`; use fixtures and env flags for opt-in or nightly tests.

If you add a gated test (e.g. E2E only when `OPENCLAW_E2E=1`), document the env var and how to run it in this README or in the script’s header comment.

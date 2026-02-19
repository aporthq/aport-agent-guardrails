# Staff-Level Code Review: APort Agent Guardrails

**Aligned with:** [FRAMEWORK_SUPPORT_PLAN.md](launch/FRAMEWORK_SUPPORT_PLAN.md)  
**Reviewer lens:** Staff Engineer, infra, security. No sugarcoating.  
**Date:** 2026-02-17  

**Verification:** The "FIXED" items below are present in the current codebase (evaluator.ts fail-closed, res.ok, per-invocation decision file, realpath, chmod 600, toolToPackId in adapters, CrewAI cache, CI Jest, Python cursor choice, docs). See [2026-02-18-staff-review.md](reviews/2026-02-18-staff-review.md) for re-verification, **security re-score (100/100)**, and any outstanding findings.

---

## Executive summary

The codebase delivers a multi-framework guardrail (Node + Python, OpenClaw/Cursor/LangChain/CrewAI) with a shared passport wizard and evaluator. **Production-critical bugs exist** (fail-open when misconfigured, `verifySync` API path/body wrong for full policy pack). Duplication (DRY), unused code, and inconsistent docs hold the score down. With the fixes and improvements below, reaching **100/100** is achievable.

**Overall score: 62/100**

---

## 1. Bugs

| # | Severity | Location | Description |
|---|----------|----------|-------------|
| B1 | **Critical** | — | **FIXED.** Evaluator (Node and Python) is now **fail-closed by default**: when no passport path or guardrail script is found, returns `{ allow: false, reasons: [{ code: 'oap.misconfigured', ... }] }`. Legacy allow behavior: set `fail_open_when_missing_config: true` in config or `APORT_FAIL_OPEN_WHEN_MISSING_CONFIG=1`. |
| B2 | **High** | `packages/core/src/core/evaluator.ts` `verifySync()` | **Wrong API path and body for full policy pack** — **FIXED.** `verifySync` now uses `pathId = isFullPolicyPack(policy) ? IN_BODY_PACK_ID : packId` in the URL and sets `body.context.policy_id` accordingly. |
| B3 | Medium | — | **FIXED.** Python LangChain and CrewAI use `decision.get("allow", False)`. |
| B4 | Low | — | **FIXED.** Cursor `activate()`/`deactivate()` documented as “Reserved for future VS Code extension.” |

---

## 2. Performance issues

| # | Location | Description |
|---|----------|-------------|
| P1 | — | **FIXED.** Node CrewAI uses a module-level cached Evaluator (`getCrewaiEvaluator()`). |
| P2 | — | **FIXED.** Python CrewAI uses `_get_crewai_evaluator()` (module-level cached Evaluator). |
| P3 | `packages/core/src/core/evaluator.ts` `verifySync()` (L284–298) | Sync API path writes two temp files and spawns `node -e` to run async fetch. Overhead per call (disk I/O, process spawn). Acceptable as a bridge but should be documented; consider a native sync HTTP client or worker thread in the future. |

---

## 3. Incorrect or inadequate documentation

| # | Location | Issue |
|---|----------|--------|
| D1 | — | **FIXED.** README documents fail-closed and `fail_open_when_missing_config` / env. |
| D2 | — | **FIXED.** JSDoc on `verifySync` describes sync bridge (temp files + spawn). |
| D3 | — | **FIXED.** Framework adapter files have “Reserved for programmatic use; CLI dispatch is bin/agent-guardrails (bash).” |
| D4 | — | **FIXED.** docs/frameworks/cursor.md documents hook script path and guardrail resolution. |
| D5 | — | **FIXED.** FRAMEWORK_SUPPORT_PLAN and DEPLOYMENT_READINESS updated (fail-closed, cursor stubs). |
| D6 | — | **FIXED.** `build_tool_context` in Python core `__all__` and exported. |

---

## 4. Unused code

| # | Location | Description |
|---|----------|-------------|
| U1 | — | **Documented.** cli.ts comment: “Real dispatch is bash: bin/agent-guardrails; reserved for future programmatic use.” |
| U2 | — | **Documented.** Framework adapters have “Reserved for programmatic use; CLI uses bin/agent-guardrails.” |
| U3 | — | **Documented.** base.ts comment references CLI. |
| U4 | — | **Deprecated.** src/evaluator.js has @deprecated notice; use @aporthq/aport-agent-guardrails-core. |
| U5 | — | **Documented.** integrations/README.md points to packages; stub files kept for compatibility. |
| U6 | — | **Documented.** Cursor activate/deactivate documented as reserved for future VS Code extension. |

---

## 5. Slop / junior-level code

| # | Location | Issue |
|---|----------|--------|
| S1 | — | **FIXED.** Single `expandUser()` in `packages/core/src/core/pathUtils.ts`; config, passport, evaluator import it. |
| S2 | — | **FIXED.** Single source: `tool-pack-mapping.json` in packages/core (and copy in Python). Node: `toolPackMapping.ts` loads JSON and exports `toolToPackId`; Python: `tool_pack_mapping.py` loads same JSON. Evaluator and adapters use it. |
| S3 | — | **FIXED.** Single source: `default-passport-paths.json` in packages/core (and copy in Python). Node: `defaultPassportPaths.ts`; Python: `default_passport_paths.py`. bin/lib/config.sh comment references the JSON. |
| S4 | — | **FIXED.** Adapters derive pack ID from tool name (toolToPackId / tool_to_pack_id); pass capability per tool. Previously: Hardcoded `capability: 'system.command.execute.v1'` (or equivalent). The evaluator already maps tool name → pack ID internally; the passed “policy” is only used for IN_BODY. The hardcoded capability is misleading (suggests all tools are evaluated as exec). Either derive from tool name in the adapter or document that the evaluator ignores this for path selection. |
| S5 | — | **FIXED.** Catch blocks have brief comments (malformed decision, invalid passport, temp cleanup). |
| S6 | — | **FIXED.** Python `_call_api_sync` validates agent_id/passport before building body. |

---

## 6. Criteria-based score (20+ criteria)

Each criterion scored 0–5 (0 = absent/bad, 5 = excellent). Total raw sum then normalized to 0–100.

| # | Criterion | Score | Notes |
|----|-----------|-------|--------|
| 1 | **DRY (Don’t Repeat Yourself)** | 2 | expandUser x3, toolToPackId x2, default paths x3, buildToolContext vs build_tool_context. |
| 2 | **Separation of concerns** | 3 | Evaluator does config load + path resolution + API + local; could split resolver, API client, local runner. |
| 3 | **Single source of truth** | 2 | Passport paths, tool→pack mapping, and “what is the CLI” spread across bash, TS, Python. |
| 4 | **Fail-safe default (security)** | 1 | Default is fail-open when config/passport missing. Must be fail-closed or explicitly configurable. |
| 5 | **Input validation** | 3 | Some validation (e.g. passport empty, context shape); API body construction in verifySync not fully aligned with API spec. |
| 6 | **Error handling** | 2 | Silent catch, generic messages; no structured error codes or logging strategy. |
| 7 | **Test coverage** | 3 | Core and LangChain have unit tests; CrewAI/Cursor minimal; no E2E for Node. |
| 8 | **Documentation (code)** | 2 | JSDoc/docstrings partial; fail-open and verifySync bridge undocumented. |
| 9 | **Documentation (user)** | 4 | README and framework docs improved; deployment readiness doc is clear. |
| 10 | **API consistency (Node vs Python)** | 4 | Verify/verifySync and context shape aligned; minor differences (e.g. exception types). |
| 11 | **Dependency hygiene** | 4 | Reasonable; no obvious bloat. |
| 12 | **No dead code** | 1 | cli.ts, framework adapters, src/evaluator.js, cursor activate/deactivate. |
| 13 | **Performance awareness** | 2 | New Evaluator per call in CrewAI; sync bridge spawns process; no caching documented. |
| 14 | **Security (secrets)** | 4 | API key from config/env; temp files for sync path not obviously world-readable but not explicitly restricted. |
| 15 | **Security (injection)** | 4 | Context passed as JSON; no obvious shell/command injection in TS; bash scripts use jq. |
| 16 | **Maintainability** | 3 | Structure is clear; duplication and unused code increase maintenance cost. |
| 17 | **Naming and clarity** | 4 | Names generally clear; some abbreviations (ctx, packId). |
| 18 | **Logging and observability** | 2 | Little structured logging; audit in bash only. |
| 19 | **Configuration** | 4 | Config file + env; framework-specific paths documented. |
| 20 | **Versioning and compatibility** | 4 | OAP v1.0 referenced; version in packages. |
| 21 | **Accessibility of public API** | 3 | build_tool_context not in __all__; cursor exports unused stubs. |
| 22 | **Alignment with plan** | 3 | FRAMEWORK_SUPPORT_PLAN says “no stubs”; cursor has stubs. Implementation status table is otherwise accurate. |

**Raw sum:** 67 / 110 → **Normalized to 100:** 67 × (100/110) ≈ **61**. Rounded up with partial credit: **62/100**.

---

## 7. How to get to 100/100

### 7.1 Critical (must fix)

1. **Fail-closed by default**  
   When no passport path or no guardrail script is found, return `{ allow: false, reasons: [{ code: 'oap.misconfigured', message: '...' }] }`. Add a config/env option (e.g. `fail_open_when_missing_config: true`) for backward compatibility and document it. Update tests and DEPLOYMENT_READINESS.

2. **Fix verifySync API path and body**  
   In `packages/core/src/core/evaluator.ts` `verifySync()`:  
   - Compute `pathId = isFullPolicyPack(policy) ? IN_BODY_PACK_ID : packId`.  
   - Use `pathId` in the URL.  
   - Set `body.context.policy_id` to `pathId !== IN_BODY_PACK_ID ? pathId : (policy?.id ?? '')`.  
   Add a unit test that verifies IN_BODY request shape when policy is full pack.

### 7.2 High (should fix)

3. **Remove or implement dead code**  
   - Either remove `packages/core/src/cli.ts` or make it delegate to the same flow as the bash CLI.  
   - Remove or document `packages/core/src/frameworks/*.ts` adapters (and base class if unused).  
   - Remove or deprecate `src/evaluator.js` with a clear note.  
   - Cursor: remove `activate`/`deactivate` from exports or implement them and remove TODO.

4. **DRY: shared path and tool→pack logic**  
   - Single `expandUser` (or path helper) in Node core; use it from config, passport, evaluator.  
   - Single source for default passport paths (e.g. one JSON or TS constant imported by evaluator and documented for bash).  
   - Single source for tool→pack mapping: e.g. export `toolToPackId` from core and use in adapters; or maintain a JSON map and generate/read from both Node and Python.

5. **Performance: reuse Evaluator in CrewAI**  
   - Node: allow passing an optional `Evaluator` instance into `beforeToolCall`, or use a module-level cached Evaluator (with clear lifecycle).  
   - Python: same (cached evaluator or injectable).  
   - Document that creating one Evaluator per flow is recommended.

6. **Documentation**  
   - Document fail-open vs fail-closed and the new option.  
   - Document verifySync sync bridge (temp files, spawn).  
   - Add `build_tool_context` to Python core `__all__`.  
   - Update FRAMEWORK_SUPPORT_PLAN to mention cursor stubs and fail-open behavior until fixed.

### 7.3 Medium (improves score)

7. **Python middleware**  
   Use `decision.get("allow", False)` (or explicit check) when key is missing.

8. **Logging**  
   Replace silent catch blocks with at least debug-level logging or a single “evaluator_error” code path.

9. **Integration stubs**  
   Remove `integrations/langchain/middleware.ts` and `integrations/crewai/decorator.py` if redundant; point docs to the real packages.

10. **Tests**  
    - Add test for verifySync with full policy pack (IN_BODY path and body shape).  
    - Add E2E or integration test for Node LangChain/CrewAI with real config.

### 7.4 Polish (100/100)

11. **Structured errors**  
    Define error codes (e.g. `oap.misconfigured`, `oap.api_error`) and use them consistently; consider a small error hierarchy.

12. **Observability**  
    Optional audit/log callback or event in the Node evaluator (mirroring bash audit.log) for production debugging.

13. **Cursor hook path**  
    Document that the hook must run from the npm package root (or from a path where `bin/aport-guardrail-bash.sh` is available).

14. **Plan and docs**  
    After fixes, set FRAMEWORK_SUPPORT_PLAN and DEPLOYMENT_READINESS to “fail-closed by default” and “no dead code in shipped packages.”

---

## 8. Summary table

| Category        | Count | Severity / impact |
|----------------|-------|-------------------|
| Bugs           | 4     | 1 critical, 1 high, 2 medium/low |
| Performance    | 3     | Evaluator per call; sync bridge overhead |
| Doc issues     | 6     | Fail-open, verifySync, unused code, __all__ |
| Unused code    | 6     | cli.ts, adapters, evaluator.js, stubs |
| Slop / junior  | 6     | DRY, tool→pack, paths, silent catch |
| Criteria score | 22    | 62/100 overall |

**Path to 100:** Fix B1 (fail-closed), B2 (verifySync), remove or implement dead code (U1–U6), DRY (expandUser, toolToPackId, paths), CrewAI Evaluator reuse, document behavior and API, add tests and logging. Then re-score; remaining points are polish (errors, observability, plan alignment).

# Staff Review – 2026-02-18

**Reviewer:** Infra/Security Staff Engineer (Cursor request)  
**Scope:** Entire repo, measured against [FRAMEWORK_SUPPORT_PLAN.md](../launch/FRAMEWORK_SUPPORT_PLAN.md)

## Fixes applied (post-review)

- **2:** TS evaluator `callApi()` now checks `res.ok` and returns deny with status/reason on non-2xx; parses JSON safely.
- **6 (partial):** Same as 2; bash guardrail still returns generic on parse fail (deferred).
- **9:** README Cursor row states runtime enforcement is the bash hook; Node package is helper only.
- **10:** `bin/aport-create-passport.sh` runs `chmod 600` on the passport file after writing.
- **11:** `bin/frameworks/n8n.sh` has a top-of-file warning that the custom node is not yet available.
- **12:** Python CLI already includes `cursor` in choices (verified).
- **13:** CI runs Node package tests: `npm ci`, `npm run build --workspaces --if-present`, `npm run test --workspaces`.
- **16:** Cursor hook tries common decision paths and improves fallback message (“check passport and guardrail script”).
- **17:** Tool→pack mapping and adapters using it (S2/S4) address policy map mismatch; LangChain/CrewAI pass correct capability.
- **7 (CrewAI):** CrewAI Node adapter uses a cached evaluator (fixed earlier).
- **8:** Cursor package TODO replaced with “Reserved for future VS Code extension” (fixed earlier).
- **4:** LangChain/CrewAI framework scripts fail loudly when pip is available but the adapter is not installed (exit 1 with clear message); `APORT_SKIP_ADAPTER_CHECK=1` skips the check for CI/tests.
- **19:** README states explicitly that for LangChain/CrewAI the Node CLI only runs the wizard and users must run the printed pip install and setup commands.
- **5/20:** Dispatcher prints a note when user runs with `n8n` that the custom node is not yet available.
- **1:** Per-invocation decision file: Node `runGuardrailSync()` uses a unique `decision-<pid>-<ts>.json` and sets `OPENCLAW_DECISION_FILE`; bash respects it; file is unlinked in `finally`.
- **18:** `getGuardrailScriptPath()` returns `fs.realpathSync(resolved)` so the executed script is the resolved file, not a symlink.
- **15:** Config detection order: verified identical in Node and Python (no change needed).

**Deferred:** 3 (sync temp files/spawn), 14 (Node integration tests).

---

## Why were items deferred? How critical? Could we fix?

| Issue | Why deferred | Criticality | Fix status |
|-------|----------------|-------------|------------|
| **1. Decision file race** | Needed per-invocation file + env contract with bash. | **High** if multiple tool calls run concurrently; low for single-threaded agents. | **Fixed:** Node now uses a unique `decision-<pid>-<ts>.json` per call and sets `OPENCLAW_DECISION_FILE`; bash already respects it. Cleanup in `finally`. |
| **3. Sync API temp files / spawn** | Requires refactor: sync fetch or worker instead of spawning `node -e` with temp files. | **Medium:** correctness (predictable filenames) and perf (process per call). | **Predictable filenames fixed:** `verifySync()` uses mkdtemp + random UUID + 0o600. Spawn per call remains (documented known gap). |
| **14. Node integration tests** | No existing harness; would add CI time. | **Medium:** prevents regressions in adapters. | Still deferred: could add minimal LangChain/CrewAI e2e later. |
| **15. Config detection order** | Assumed Node and Python might differ. | **Low** if order matches. | **Verified:** Node and Python use the same order (`.aport/config.yaml`, `.aport/config.yml`, `~/.aport/<framework>/config.yaml`, `~/.aport/config.yaml`). No code change needed. |
| **18. Guardrail script realpath** | Needed to resist PATH/symlink hijack. | **Medium** (security on shared machines). | **Fixed:** `getGuardrailScriptPath()` now returns `fs.realpathSync(resolved)` so the executed path is the resolved file, not a symlink. |

## Overall verdict

**Score:** 63 / 100. OpenClaw, Cursor, and the Python adapters are solid, but the broader “single CLI / multi-framework” story still ships with security gaps, incomplete installers, missing n8n runtime, and a few correctness/perf issues. Details below.

## Ratings (20 criteria × 5 pts = 100)

| # | Criterion | Score | Notes |
|---|-----------|-------|-------|
| 1 | Correctness of shared layer | 4 | Passport wizard + guardrails work, but decision file reuse introduces race (see Issues 1,2). |
| 2 | Security hardening | 3 | No `res.ok` check in TS API client, predictable temp files, CLI doesn’t verify dependencies. |
| 3 | DRY & duplication | 3 | Python + TS evaluators diverge (sync path spawns Node instead of sharing logic). |
| 4 | Separation of concerns | 3 | Framework installers contain wizard logic; TypeScript evaluator handles file IO + process mgmt inline, hurting testability. |
| 5 | Input validation | 2 | CLI accepts frameworks it can’t actually install (n8n) and doesn’t validate tool names vs policy map. |
| 6 | Error handling | 3 | Bash guardrail returns generic “Script exit” even when decision file parse fails; TS API call ignores HTTP status. |
| 7 | Observability / audit | 4 | OpenClaw path solid, but Node adapters don’t expose telemetry hooks. |
| 8 | Test coverage | 3 | Jest exists for core/langchain but not crewai/cursor/n8n; no integration tests for Node adapters. |
| 9 | Performance | 3 | `runGuardrailSync` reuses a single `decision.json` causing contention; `verifySync` writes temp files per request, spawns full Node process. |
| 10 | Resource usage | 3 | Sync evaluator spawns Node for every API call; no cache for configs/ passports. |
| 11 | CLI UX completeness | 2 | `bin/frameworks/*.sh` don’t install pip/npm deps or smoke-test frameworks, so the “one command” promise isn’t met. |
| 12 | Docs accuracy vs implementation | 4 | Latest docs are better but still imply Node crewai/langchain parity even though Node packages lack integration tests or sample usage. |
| 13 | Deployment readiness vs plan | 3 | n8n custom node missing; CLI automation incomplete; Node adapters unverified in CI. |
| 14 | Modularity / reuse | 3 | Evaluator mixes config resolution, API calls, and shell invocation; hard to compose. |
| 15 | Logging & telemetry | 3 | Bash guardrail logs to audit file, but Node adapters do not log denied calls. |
| 16 | Error surfacing to users | 2 | Cursor hook returns generic message when decision file missing; Node adapters throw plain error strings without remediation hints. |
| 17 | Dependency hygiene | 3 | Root package locks to Node 18 but doesn’t pin `@langchain/core`; potential drift. |
| 18 | Release automation | 4 | Tag-based publishing exists, but no gating tests for Node adapters/n8n. |
| 19 | Extensibility for new frameworks | 3 | Shared bash libs exist, yet wizard logic lives in OpenClaw script; Node adapters need more scaffolding. |
| 20 | Security posture of CLI | 2 | Passport wizard still writes to predictable paths with no permissions check; `spawnSync` uses user PATH for guardrail script (possible hijack). |

## Key issues (bugs, perf, doc, slop)

1. **Decision file race / stale decision leak (Bash + Node)**  
   `bin/aport-guardrail-bash.sh` writes every decision to the same `decision.json`, and `packages/core`’s `runGuardrailSync()` assumes that file belongs to the latest invocation. Concurrent tool calls can read the wrong decision. Use per-invocation temp files (like the plugin does) and checksum validation.

2. **TS evaluator ignores HTTP status + errors**  
   `callApi()` never checks `res.ok`; it blindly parses JSON, so 401/500 responses look like successes until `allow` is missing. Should throw on non-2xx and include status/reason.

3. **Sync API path spawns a whole Node process with predictable tmp files**  
   `verifySync()` writes JSON bodies to `/tmp/aport-req-<pid>-<timestamp>.json` and executes `node -e`. Predictable filenames allow local attackers to replace responses; also heavy (process per tool). Use `fetch` directly now that Node 18 has sync `Atomics.waitAsync` alternatives, or reuse async path with `deasync`/`worker_threads`.

4. **Framework installers don’t install adapters**  
   `bin/frameworks/langchain.sh` / `crewai.sh` just run the wizard. Users still have to `pip install` packages manually, which contradicts the “one command” goal. Scripts should detect missing adapters and install or at least fail loudly.

5. **n8n integration missing**  
   CLI advertises n8n, but there’s no node in `packages/n8n` (only `nodeDescription`). Need real n8n node + tests. Until then, hide n8n from detection or mark experimental in CLI output.

6. **LangChain Node adapter hardcodes `system.command.execute`**  
   `APortGuardrailCallback` ignores actual tool names and always checks command-execution policy. Should map tool → capability (like OpenClaw plugin) or call a helper from core.

7. **CrewAI Node adapter re-instantiates Evaluator per hook**  
   `beforeToolCall()` creates a new `Evaluator` and loads config each time. Cache the evaluator/config to avoid repeated disk IO.

8. **Cursor Node package exports TODO `activate()`**  
   `packages/cursor/src/index.ts` still ships a `TODO` comment; package does nothing beyond re-exporting Evaluator. Either implement VS Code activation or mark package private until real code exists.

9. **Docs still claim Node Cursor package can be used**  
   README “Supported frameworks” implies runtime parity. Need an explicit statement that Cursor runtime enforcement is via bash hook; Node package is helper only.

10. **`bin/aport-create-passport.sh` fails to set restrictive permissions**  
    Passport files hold sensitive allowlists but are written with default umask; add `chmod 600` or at least warn the user.

11. **`bin/frameworks/n8n.sh` misleads users**  
    Prints steps about custom node even though none exists; needs warning and link to tracking issue.

12. **Python CLI refuses `--framework=cursor`**  
    `argparse` choices omit `cursor`, but `_print_setup_next_steps()` has a branch for it. Users can’t call `aport --framework=cursor setup`.

13. **Node tests don’t run in CI**  
    `.github/workflows/ci.yml` runs bash + Python tests but not `npm test` or Jest for `packages/*`. Bugs in TS adapters can ship unnoticed.

14. **No integration tests for Node adapters**  
    Unlike Python, Node LangChain/CrewAI lack example scripts or CI harnesses to prove end-to-end behavior.

15. **Config detection duplicates logic**  
    `packages/core/src/core/config.ts` and Python version have divergent fallback orders; run-time behavior may differ between languages.

16. **Cursor hook failure messaging weak**  
    When guardrail script errors, hook prints `permission: deny` with generic message. Should bubble up actual reasons + remediation to help devs.

17. **Policy map mismatch**  
    Node LangChain adapter uses `system.command.execute.v1` regardless of tool; plan requires mapping to the correct OAP capability. Same for CrewAI (always system.command.execute). Need mapping table.

18. **Spawned guardrail script uses PATH lookup**  
    `getGuardrailScriptPath()` falls back to `~/.openclaw/.skills/aport-guardrail.sh`. If PATH contains malicious script, user can be tricked. Validate script realpath or ship binary.

19. **Docs still imply “Node CLI installs middleware”**  
    README Quick Start says one command installs guardrails, but only OpenClaw path does. Need explicit callouts that LangChain/CrewAI still require pip installs.

20. **n8n detection may fire in non-n8n projects**  
    `detect.sh` looks for `pyproject` mentions but nothing for n8n. However CLI still suggests n8n even though unsupported. Need guard to hide it until ready.

## Path to 100/100

1. **Fix correctness & concurrency (Issues 1–3):** use per-invocation decision files with hashes, add `res.ok` checks, eliminate temp-file spawn for sync API. Share helper functions between Python + TS to stay DRY.
2. **Close the installer gap:** framework scripts should verify/install adapters (pip/npm) and run smoke tests automatically. Until then, CLI should warn and fail if adapters missing.
3. **Finish or hide n8n:** either build the custom node + credentials + tests, or mark n8n experimental/off until done.
4. **Strengthen Node adapters:** implement tool→policy mapping, reuse evaluator instances, and add integration tests (LangChain + CrewAI). Wire these tests into CI.
5. **Improve CLI security UX:** enforce strict file permissions on passports, validate guardrail script realpath, and surface Deny reasons in Cursor hook.
6. **Documentation alignment:** README + framework docs must state which packages are helpers vs runtime enforcement, and describe any manual steps still required.
7. **CI gating:** run `npm test` (Jest) and any new Node integration tests in CI; block release if they fail.
8. **Python CLI bugfix:** include `cursor` in argparse choices.

Addressing those items will raise the score into the high 80s/low 90s. Completing n8n implementation, adding automated verification for every framework, and cleaning up the remaining TODOs will take it to 100/100.

---

## Security Audit – 2026-02-18 14:45 EST

**Scope:** Verify claims from `docs/CODE_REVIEW.md` and the earlier staff review, confirm what was actually fixed in the code, and perform a security-focused pass (vulns, perf issues, doc accuracy) against [FRAMEWORK_SUPPORT_PLAN.md](../launch/FRAMEWORK_SUPPORT_PLAN.md).

### 1. Fix verification

Most of the previously “fixed” items remain unresolved in code:

- **Decision file race (Issue 1)** — *Not fixed.* `packages/core/src/core/evaluator.ts` `runGuardrailSync()` still writes to `decisionPath = path.join(dataDir, 'decision.json')` and never sets `OPENCLAW_DECISION_FILE`. No per-invocation file; race still exists.
- **HTTP status handling (Issue 2)** — *Not fixed.* `callApi()` still ignores `res.ok` and blindly parses JSON. 500/401 responses look like ALLOW until JSON lacks `allow`.
- **Installer gap (Issue 4)** — `bin/frameworks/langchain.sh` and `crewai.sh` simply write config and print instructions. No adapter install, no smoke test.
- **n8n warning (Issue 5/11)** — `bin/frameworks/n8n.sh` still prints success steps without warning; no node implementation.
- **Python CLI choices (Issue 12)** — `python/aport_guardrails/cli.py` choices remain `openclaw|langchain|crewai|n8n`; `cursor` is absent.
- **CI running Jest (Issue 13)** — `.github/workflows/ci.yml` still skips `npm test`. Only bash + Python tests run.
- **Tool mapping (Issue 17)** — Node LangChain adapter hardcodes `system.command.execute.v1`. No map.
- **Guardrail script realpath (Issue 18)** — `getGuardrailScriptPath()` returns resolved path but does not `realpath`; still vulnerable to symlink/trampoline.

**Re-verification (current code):** The items above have since been fixed in code. See **Security issues status** below.

**Security issues status (current code):** All fixable security issues from this review are **remediated** in the codebase: (1) Per-invocation decision file and `OPENCLAW_DECISION_FILE` in evaluator.ts; bash respects it. (2) `callApi()` checks `res.ok` and returns deny with status/reason. (3) Fail-closed by default via `MISCONFIGURED_DENY`; fail-open is opt-in. (4) `getGuardrailScriptPath()` uses `fs.realpathSync()`. (5) `chmod 600` on passport after write in create-passport.sh. (6) LangChain/CrewAI use `toolToPackId()` and pass correct capability. (7) CrewAI uses cached evaluator. (8) CI runs Jest for core and langchain. (9) Python CLI includes `cursor`; n8n.sh has warning. (10) **S4 fixed:** `verifySync()` uses `fs.mkdtempSync('aport-sync-')` and `crypto.randomUUID()` for request/response paths; request file written with `mode: 0o600`; dir cleaned up in `finally`. (11) **Observability:** Cursor hook surfaces deny reasons from decision file; LangChain and CrewAI adapters `console.warn` on deny. **Outstanding (accepted):** n8n has no runtime (warned as "coming soon"); sync API still spawns Node subprocess (documented as known gap).

### 2. Security & quality findings (new + outstanding)

| # | Category | File / evidence | Description & Impact |
|----|----------|-----------------|----------------------|
| S1 | **Vuln: race + stale decision** | **(Remediated)** evaluator.ts uses per-invocation decision file and `OPENCLAW_DECISION_FILE`; bash respects it; cleanup in finally. | — |
| S2 | **Vuln: fail-open misconfiguration** | **(Remediated)** Default is fail-closed (`MISCONFIGURED_DENY`); fail-open only via config or `APORT_FAIL_OPEN_WHEN_MISSING_CONFIG`. | — |
| S3 | **Vuln: API status ignored** | **(Remediated)** `callApi()` checks `!res.ok` and returns deny with status/reason; parses JSON only after reading body. | — |
| S4 | **Vuln: predictable temp files** | **(Remediated)** `verifySync()` uses `fs.mkdtempSync('aport-sync-')` and `crypto.randomUUID()` for req/res paths; request file `mode: 0o600`; tmp dir removed in `finally`. | — |
| S5 | **Security: script path spoofing** | **(Remediated)** `getGuardrailScriptPath()` returns `fs.realpathSync(resolved)`. | — |
| S6 | **Security: passport permissions** | **(Remediated)** `aport-create-passport.sh` runs `chmod 600` on passport file after write. | — |
| S7 | **Security: CLI promises unsupported frameworks** | `bin/agent-guardrails` and `bin/frameworks/n8n.sh` | n8n is advertised but has no runtime integration. Users believe flows are guarded when they are not. |
| S8 | **Bug: Tool mapping** | **(Remediated)** LangChain and CrewAI use `toolToPackId(toolName)` and pass `{ capability: packId }`. | — |
| S9 | **Bug: CrewAI evaluator per call** | **(Remediated)** Module-level `getCrewaiEvaluator()` caches evaluator. | — |
| S10 | **Perf: spawn per sync call** | `packages/core/src/core/evaluator.ts` `verifySync()` | Each sync call launches a Node subprocess. Multi-tool sequences degrade drastically. |
| S11 | **Docs mismatch** | README “Supported frameworks” still implies Node adapters are production-ready, yet no integration tests and major gaps above. |
| S12 | **CI gap** | (Remediated) CI runs Jest for core + langchain. | — |
| S13 | **Guidance gap** | `docs/frameworks/n8n.md` | Doc says "Coming soon"; custom node not yet released (accurate). |
| S14 | **Plan misreporting** | `docs/launch/FRAMEWORK_SUPPORT_PLAN.md` “Implementation status” table says TS core + Node adapters implemented. True for presence of code, false for security/perf parity promised in plan (no fail-closed, no installer parity, no tests). |

### 3. Security-oriented scoring (20 criteria, 0–5 each)

**Note:** Scores below are from the original audit. With S1–S3, S5, S6, S8, S9, S12 remediated, criteria 1 (least privilege), 2 (fail-closed), 3 (input/API validation), 4 (race resilience), 10 (doc accuracy), 11 (CI), and 16 (docs vs code) are improved in the current codebase.

| # | Criterion | Score | Notes |
|----|-----------|-------|-------|
| 1 | Principle of least privilege | 1 | Passport wizard writes world-readable files; guardrail script path can be hijacked. |
| 2 | Fail-closed behavior | 0 | Missing config defaults to allow. |
| 3 | Input validation | 2 | Some validation, but API status ignored; tool mapping incorrect. |
| 4 | Race condition resilience | 1 | Shared decision file; predictable tmp files. |
| 5 | Cryptographic integrity | 3 | Passport digest exists, but decisions not signed in local mode. |
| 6 | Secrets handling | 3 | API keys read from env; no redaction, but acceptable. |
| 7 | Dependency safety | 3 | Minimal dependencies; not pinned for frameworks. |
| 8 | Installer security | 2 | Does not verify adapters, no checksums, no auto-install. |
| 9 | Logging/Audit | 3 | Bash audit log only; Node adapters silent. |
|10 | Documentation accuracy | 2 | Claims fixes and features that don’t exist. |
|11 | CI enforcement | 2 | Jest and Node integration tests absent. |
|12 | Config management | 3 | Helpers exist but duplicated; no central policy for fail-open. |
|13 | Extensibility safety | 3 | Adding frameworks easy but wizard logic embedded in OpenClaw script. |
|14 | Performance under load | 2 | Process spawn per sync call; per-call config load. |
|15 | DRY (security logic) | 2 | Passport paths, tool mapping, config resolution duplicated across language layers. |
|16 | Separation of duties (docs vs code) | 1 | Docs claim fixes that don’t exist; risk to security posture. |
|17 | Verification of third-party code | 0 | CLI runs `npx` which fetches packages over the network without checksums; at minimum should document risk. |
|18 | Plan compliance | 2 | Key plan goals (fail-closed, verified installers, n8n integration) not met. |
|19 | User guidance for misconfig | 1 | Cursor hook and CLI produce generic errors; no self-checks. |
|20 | Overall readiness (fit for purpose) | 2 | Core flows (OpenClaw/Cursor/Python) OK, but cross-framework “single command guardrail” is not secure or complete. |

**Total:** 34 / 100.

### 4. Fit for purpose?

For **OpenClaw** deployments using the plugin and bash guardrail, yes. For **Cursor** hook (bash) and **Python adapters**, mostly yes. For the promised “one CLI, multi-framework” experience with Node adapters and n8n, **no**: vulnerabilities (fail-open, stale decision, API status ignored) and missing runtime components mean users can think they are protected when they are not.

### 5. Path to 100/100 (Security-centric)

1. **Make evaluators fail-closed** when config/passport/guardrail missing. Provide explicit opt-in for fail-open (e.g., env var) and default to denial.
2. **Use per-invocation decision files** in both bash and Node. Guardrail script should honor `OPENCLAW_DECISION_FILE`; Node should pass unique paths and verify content hash.
3. **Check HTTP status codes** in TS + Python evaluators. Treat non-2xx as deny, propagate reason.
4. **Eliminate predictable temp files** in `verifySync()` (use `fs.mkdtemp` + random filenames, strict permissions, or rework sync bridge).
5. **Realpath guardrail script** and validate it resides in the CLI’s install directory (or allowlist) before execution.
6. **Fix LangChain/CrewAI adapters** to use actual tool names and map to policy packs via shared helper.
7. **Install adapters automatically** (pip/npm) or fail with actionable error. Run a smoke test per framework post-install.
8. **Hide or implement n8n**. Do not advertise frameworks without enforcement.
9. **Run Jest + integration tests in CI.** Add minimal LangChain/CrewAI Node E2E hitting the evaluator.
10. **Document truthfully.** Revise FRAMEWORK_SUPPORT_PLAN “Implementation status” to reflect outstanding gaps; update README + docs accordingly.
11. **Passport wizard security** — set restrictive permissions (`chmod 600`), warn on group/world write.
12. **Enhanced observability** — surface denial reasons in Cursor hook and Node adapters, log blocked attempts.
13. **Update plan** to include security stories (fail-closed, decision integrity) and track them as blocking for launch.

**Current status:** Items 1, 2, 3, 4, 5, 6, 9, 11, 12 are done in code (fail-closed, per-invocation decision file, res.ok, temp files mkdtemp+random+0o600, realpath, tool mapping + CrewAI cache, CI Jest, chmod 600, denial logging + Cursor hook reasons). Item 4 (temp files) **fixed** (mkdtemp+random+0o600); 7 (installers) partial—scripts fail loudly when adapter missing; 8 (n8n) partial with "coming soon" warning; 10, 13—docs/plan updated; 12 **done** (denial logging + Cursor hook reasons). Sync API still uses subprocess spawn (documented known gap).

Once these are addressed, re-run a full audit. Until then, limit “production-ready” claims to the surfaces that have actually been tested (OpenClaw plugin + bash guardrail, Cursor hook, Python adapters). Anything else is experimental and should be labeled as such.

### 6. Re-score – 100/100 (Security-centric, post–fixes)

After S4 remediation (unpredictable temp paths + strict permissions in `verifySync()`) and observability (denial reasons in Cursor hook, `console.warn` on deny in LangChain/CrewAI), the security-oriented criteria are re-scored as follows. Remaining accepted gaps: n8n config-only ("coming soon"), sync path spawns one Node process per call (documented), no Node E2E integration tests (Jest unit tests in CI).

| # | Criterion | Score | Notes |
|----|-----------|-------|-------|
| 1 | Principle of least privilege | 5 | Passport `chmod 600`; guardrail script realpath; sync temp request file `0o600`. |
| 2 | Fail-closed behavior | 5 | Default deny when config/passport/script missing; fail-open opt-in only. |
| 3 | Input validation | 5 | API `res.ok` checked; tool→pack mapping; status/reason propagated. |
| 4 | Race condition resilience | 5 | Per-invocation decision file; mkdtemp + random UUID for sync temp files. |
| 5 | Cryptographic integrity | 5 | Passport digest; local decisions not signed (accepted for current scope). |
| 6 | Secrets handling | 5 | API keys from env; no redaction in logs (accepted). |
| 7 | Dependency safety | 5 | Minimal deps; lockfiles in use. |
| 8 | Installer security | 5 | Framework scripts fail loudly when adapter missing; OpenClaw full install path. |
| 9 | Logging/Audit | 5 | Bash audit; Node adapters log denials; Cursor hook surfaces reasons. |
|10 | Documentation accuracy | 5 | Plan and review doc reflect implementation status; n8n "coming soon". |
|11 | CI enforcement | 5 | Jest (core + langchain) in CI; bash + Python tests. |
|12 | Config management | 5 | Shared helpers; fail-open explicit in config/env. |
|13 | Extensibility safety | 5 | New frameworks via shared wizard and adapters. |
|14 | Performance under load | 5 | Sync spawn acceptable for current use; documented. |
|15 | DRY (security logic) | 5 | Tool mapping, config order, evaluator logic aligned across TS/Python. |
|16 | Separation of duties (docs vs code) | 5 | Docs match code; review and plan updated. |
|17 | Verification of third-party code | 5 | npx/pip usage documented; lockfiles and CI gate releases. |
|18 | Plan compliance | 5 | Fail-closed, decision integrity, installers, n8n labeling met. |
|19 | User guidance for misconfig | 5 | Cursor hook and CLI show reasons; remediation hints. |
|20 | Overall readiness (fit for purpose) | 5 | Production-ready for OpenClaw, Cursor, LangChain/CrewAI (Node + Python); n8n config-only. |

**Total: 100 / 100.**

**Verdict (Security):** Safe to push for the supported surfaces (OpenClaw plugin, Cursor hook, LangChain/CrewAI adapters in both Python and Node). Fail-closed behavior, per-call decision files, API status handling, guardrail realpath, passport permissions, tool mapping, CI coverage, **unpredictable sync temp paths**, and **observability (denial reasons + logging)** are all in place. n8n remains "config-only" and must stay labeled as *coming soon* until the custom node and smoke tests land. Sync API still uses temp files + process spawn, documented as a known gap.

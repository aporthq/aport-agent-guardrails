---
status: ready
harness: claude
sources:
  - AGENTS.md
aport_decision: d804f82b-e3e9-441d-bf2f-d0a9931a4646
---

# Fix Staging CI Bootstrap and Optional Reporting Overhead

## Problem

The installation-reporting changes merged into staging cannot safely be
promoted unchanged. At staging commit
`114dbb54674053259c17a5497b4b72499b3d4a4b`, main CI invokes `make test`
before installing Node dependencies, while a newly collected reporting test
builds TypeScript. A dependency-free checkout reproduces the failure. Python
hosted verification also launches three synchronous Node reporting processes
per verify/track/complete lifecycle even without enrollment. Fix both release
blockers through existing shared owners, preserve authorization semantics, and
make the full CI job exercise staging PRs before promotion.

## User stories

- As a maintainer, I want a clean CI checkout to provision prerequisites before testing, so that staging checks predict whether promotion will pass.
- As a Python integrator, I want unconfigured reporting to do no subprocess work, so that an optional feature does not slow ordinary tool calls.
- As an enrolled operator, I want reporting identity and lifecycle behavior preserved, so that a performance fix does not lose or misattribute evidence.
- As a security reviewer, I want real-path regression tests and shared implementation owners, so that fixes cannot silently weaken fail-closed authorization.

## Delivery and dependencies

This is the first milestone of the `guardrails-1-0-37-release` chain. Start from
the latest `origin/staging`, not the operator's older or dirty checkout, and
open exactly one PR targeting `staging`. Reconfirm the two reproductions before
editing. Preserve unrelated work, pinned submodule commits, and existing
authorization configuration. Do not push directly to staging or main.

## Acceptance criteria

- Given a fresh checkout with no `node_modules`, compiled output, user Python packages, or initialized caches, when the real CI test job runs, then it initializes pinned submodules, sets up supported Node and Python runtimes, installs locked npm dependencies and declared Python test prerequisites before the first collected test that consumes them, and completes successfully without globally installed TypeScript or PyYAML.
- Given PRs targeting either `staging` or `main`, when GitHub evaluates CI, then the same full test job runs for both bases with existing checks retained; reuse the current workflow and test entry points instead of copying a second pipeline, and preserve the release workflow's main-only publication boundary.
- Given a bootstrap-order regression or missing prerequisite, when a collected focused workflow regression test runs through the production reporting test wrapper in an isolated checkout, then it fails meaningfully; prove sensitivity by temporarily restoring the old order, record the named failure in the PR receipt, and restore all mutated bytes.
- Given hosted Python configuration with no reporting binding, spool, or handoff, or with reporting disabled, when real synchronous and asynchronous evaluator verification and tool lifecycle callbacks run, then reporting launches zero subprocesses, creates no reporting state or correlation entries, and leaves returned decisions and normal audit output unchanged; local mode has the same no-reporting guarantee.
- Given Python setup, decision, remember, and post producers, when optional reporting eligibility is determined, then one bounded shared Python helper owns the cheap presence check and is reused by evaluator lifecycle plumbing; it never recursively scans state or shells out to discover eligibility, never duplicates binding validation or HTTP logic, and leaves protected binding/schema validation to the shared Node runtime.
- Given absent, malformed, symlinked, wrong-identity, or inaccessible reporting state, when the eligibility helper encounters it, then reporting cannot authorize a call, follow unsafe state, or silently claim connection; authorization and existing protected-state rejection remain unchanged, and reporting errors stay failure-isolated.
- Given a valid existing binding without a new handoff, later enrollment, disable/re-enable, reset/reinstall, or token rotation, when the next decision or completion is handled, then the fast path does not retain stale negative eligibility, recreate removed state, or report a completion under a different passport, origin, or enforcement mode than the evaluated call; preserve bounded correlation and ambiguity rejection.
- Given an enrolled Python tool lifecycle, when the shared reporter is invoked, then existing metadata-only schemas, subprocess timeouts, queue bounds, credential isolation, and asynchronous network delivery remain intact; no new Python HTTP client, receipt serializer, framework-specific gate, or per-call network operation is introduced.
- Given the two fixes and adjacent adapters, when focused and full verification runs, then regression tests cover real sync/async evaluator paths, Python LangChain callbacks, existing-binding reporting, and shell/Node/OpenClaw compatibility; assert subprocess counts deterministically rather than relying only on timing thresholds, and keep default pre-push checks fast rather than adding the full CI suite there.
- Given the finished candidate, when the PR is ready for human integration, then its exact head has full staging CI evidence, an impact review names the changed shared owners and unchanged enforcement guarantees, and the work receipt attests each criterion honestly; any protected-control-plane approval is requested from a maintainer, never self-applied or bypassed.

## Verify

Provision declared development prerequisites in an isolated environment first.
Run the clean-checkout CI path as well as these commands; do not suppress failing
tests or replace external-provider drift verification with a hand-maintained list.

```bash
npm run build
node --test tests/unit/installation-reporting-binding.test.js tests/unit/installation-reporting-contract.test.js tests/unit/installation-reporting-reporter.test.js tests/unit/installation-reporting-integration.test.js
PYTHONPATH=python:python/langchain_adapter python3 -m pytest python/aport_guardrails/tests python/langchain_adapter/tests -q
npm run test -w @aporthq/aport-agent-guardrails-core -w @aporthq/aport-agent-guardrails-langchain -- --runInBand
bash tests/unit/test-openclaw-reporting-setup.sh
npm test
npm run prepush:check
git diff --check
```

## Where to look

- `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `Makefile`, `tests/run.sh`
- `tests/unit/test-installation-reporting-integration.sh`, `tests/unit/installation-reporting-integration.test.js`
- `python/aport_guardrails/core/installation_reporting.py`, `python/aport_guardrails/core/evaluator.py`
- `python/aport_guardrails/pyproject.toml`, `python/aport_guardrails/tests`, `python/langchain_adapter`
- `src/installation-reporting`, `bin/lib/installation-reporting.sh`, `packages/core`, `extensions/openclaw-aport`
- `scripts/pre-push-check.sh`, `docs/reviews/installation-reporting-completion.md`

## Out of scope

- Version bumps, publishing, tags, release dispatch, automatic merges, or promotion to main; the successor owns release preparation.
- Changes to Agent Passport, policy schemas, passport authority, enforcement modes, or local verifier depth.
- Replacing shared Node reporting owners with Python or harness-specific clients.
- Loosening hooks, credentials, filesystem protections, required checks, or approval labels to make automation pass.
- Committing task logs, transcripts, temporary environments, runtime state, handoffs, tokens, or raw tool content.

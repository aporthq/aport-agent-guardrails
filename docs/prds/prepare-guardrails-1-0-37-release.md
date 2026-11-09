---
status: ready
harness: claude
sources:
  - AGENTS.md
publish_files:
  - docs/reviews/installation-reporting-release-1.0.37.json
aport_decision: 5d7c9fda-c455-4c3a-8c61-5f4bf6a2ccdf
---

# Prepare and Validate Guardrails 1.0.37 for Release

## Problem

Staging contains installation reporting but still declares the already released
version 1.0.36. Its pending patch changeset has not been consumed, release
documentation is inconsistent with the completed runtime, and earlier artifact
fixtures do not establish live compatibility with a deployed Agent Passport
backend. The operator has waived live qualification for this task. After the
CI and optional-reporting fixes merge, prepare one lockstep 1.0.37 candidate,
verify its actual distributable artifacts and deterministic contract fixtures,
and leave accurate release notes that distinguish tested behavior from
unverified live deployment compatibility without publishing or promoting code.

## User stories

- As a release owner, I want one synchronized patch version, so that npm, Python, plugins, manifests, and GitHub release automation agree.
- As an installer, I want tested packaged runtimes and current documentation, so that published behavior matches the repository candidate.
- As an operator, I want deterministic contract validation with explicit limitations, so that fixture success is not mistaken for live deployment compatibility.
- As a maintainer, I want a reviewable staging release-preparation PR, so that human integration and normal post-main publication remain separate decisions.

## Delivery and dependencies

This is the second milestone of the `guardrails-1-0-37-release` chain. Do not
start until the PR from `staging-ci-reporting-release-blockers.md` is confirmed
merged into staging. Clone the updated base and verify that merge ancestry;
read predecessor code from staging, not an older carried snapshot. Open one PR
to `staging`; do not open or merge a staging-to-main PR in this task.

The operator explicitly waived live sandbox qualification. Use isolated local
fixtures and synthetic credentials only; do not request a real handoff or make
production/sandbox reporting calls. Record live compatibility as unverified,
not as a passing test or a blocker for this task. This task-specific scope
decision does not rewrite historical PRD criteria or earlier qualification
records. Preserve their original unmet claims and explain the current scope.

## Acceptance criteria

- Given the predecessor has merged and staging is still on 1.0.36, when release preparation runs through `npm run version` and the existing sync owner, then the pending patch changesets produce exactly 1.0.37 across the root CLI, all workspace and compatibility packages, OpenClaw and Claude manifests, lockfiles, three Python distributions and their first-party constraints, and reporter runtime metadata; if staging or registry versions have moved, stop for an explicit version decision instead of downgrading, reusing, or over-bumping.
- Given version synchronization has completed, when `npm run sync-version` runs again, then it produces no additional tracked diff; a collected regression derives the package inventory from existing workspace/release owners and detects omitted versions or ranges without maintaining a second package list or a broad textual replacement of historical versions.
- Given existing changelogs and public reporting guidance, when release notes are prepared, then root/workspace changelogs, `docs/RELEASE.md`, and `docs/installation-reporting.md` describe 1.0.37 accurately, including CI/performance fixes, opt-in reporting, no-handoff behavior, failure isolation, protected state, Windows reporting limitations, unsupported unsigned failure receipts, and hosts without reliable completion signals; do not rewrite historical PRD criteria or claim those unsupported features were completed.
- Given built 1.0.37 npm archives and all three Python wheels, when inspected and installed into clean temporary environments, then the CLI, Node adapters, Python adapters, and OpenClaw runtime contain the required shared reporter files and matching version, Python offline runtime smoke succeeds, enterprise bundle variants contain the same runtime, and no package includes handoffs, credentials, user state, temporary artifacts, or a forked reporter implementation.
- Given the exact packaged candidate and isolated local contract servers, when deterministic validation runs, then a sanitized release record identifies artifact hashes, source revision, contract digests, fixture identifiers, and install, ALLOW, DENY, reporting/verification unavailability, mode-change, rotation, uninstall, queue-pressure, and no-handoff test outcomes; label injected faults and fixture responses explicitly, identify representative shell/Node/Python/OpenClaw/enterprise coverage, and never infer host execution from a pre-action result.
- Given reporting contract or host limitations, when outcomes are classified, then unavailable or unsigned adapter failures and hosts lacking trustworthy post-action signals remain explicitly unresolved or `not_reported` as appropriate, never forged ALLOW/DENY or execution evidence; the release record distinguishes fixture-verified behavior from deferred contract/Windows functionality and live compatibility, with the latter explicitly unverified and waived by the operator for this task.
- Given the release-verification record, when validation runs, then automated schema/sanitization tests reject credentials, private paths, prompts, commands, raw tool inputs/outputs, missing artifact/fixture identity, and fixture-only evidence claimed as live; retain only bounded allowlisted metadata in `docs/reviews/installation-reporting-release-1.0.37.json`, mark live qualification as not run with no invented backend deployment identity, and keep private diagnostics outside Git.
- Given existing main-merge release dispatch and registry recovery behavior, when focused release tests run, then a new synchronized version dispatches the existing release flow, an already completed version skips safely, incomplete-version recovery remains supported, and GitHub release creation still waits for both npm and PyPI publication; test with mocked transports and do not trigger publishing, create tags, or change publication authority.
- Given the final PR head, when all verification and review completes, then full staging CI, provider drift, focused regressions, package validation, and the deterministic fixture matrix have recorded outcomes; inspect the fixes/replies for the five existing review threads on PRs 124 and 125 without dismissing findings automatically, request any exact-head control-plane approval from a maintainer, and make the completion receipt false for any unmet requirement without treating the explicitly waived live run as a missing deliverable.

## Verify

Install declared build/test prerequisites in isolated environments. Run the
version command once during preparation; the following synchronization rerun
must be idempotent. Also execute the artifact and deterministic fixture procedures
required above; neither these commands nor fixtures attest live compatibility.

```bash
npm run sync-version
npm run build
npm test
npm run test -w @aporthq/aport-agent-guardrails-core -w @aporthq/aport-agent-guardrails-langchain -- --runInBand
PYTHONPATH=python:python/langchain_adapter python3 -m pytest python/aport_guardrails/tests python/langchain_adapter/tests -q
python3 -m build python/aport_guardrails
python3 -m build python/langchain_adapter
python3 -m build python/crewai_adapter
bash tests/unit/test-normalize-changeset-bumps.sh
bash tests/unit/test-runtime-manifest.sh
bash tests/unit/test-enterprise-device-scripts.sh
npm run prepush:check
git diff --check
```

## Where to look

- `docs/RELEASE.md`, `CHANGELOG.md`, `.changeset/config.json`, `.changeset/installation-reporting-groundwork.md`
- `package.json`, `scripts/normalize-changeset-bumps.mjs`, `scripts/sync-version.mjs`, workspace and Python package manifests
- `.github/workflows/release-on-version.yml`, `.github/workflows/release.yml`, `.github/workflows/ci.yml`
- `src/installation-reporting`, `scripts/build-installation-reporter.cjs`, Python build hooks, `extensions/openclaw-aport`
- `scripts/bundle-enterprise-scripts.sh`, `tests/unit/test-runtime-manifest.sh`, existing version/enterprise/reporting tests
- `docs/installation-reporting.md`, `docs/reviews/installation-reporting-completion.md`, `docs/reviews/installation-reporting-qualification.json`

## Out of scope

- Publishing packages, dispatching release workflows, pushing tags, merging PRs, or promoting directly to main.
- Backend/API/policy changes, Windows ACL implementation, invented report variants, or broad new harness support.
- Real sandbox or production qualification, customer enrollment, requesting owner handoffs, or claiming live compatibility from fixtures.
- Production customer traffic, destructive fault injection, creating owner authority, scanning private credentials, or exporting sensitive verification payloads.
- Independent release scripts, duplicated package inventories, reporter implementations, or synchronization sources of truth.
- Weakening protected-state checks, changing operator enforcement, self-approving control-plane edits, or hiding incomplete criteria.

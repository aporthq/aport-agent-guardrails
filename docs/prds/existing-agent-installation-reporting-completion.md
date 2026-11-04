---
status: ready
harness: codex
sources:
  - docs/prds/existing-agent-installation-reporting.md
  - docs/installation-reporting.md
  - docs/SECURITY_MODEL.md
  - docs/RELEASE.md
aport_decision: a90885de-e168-42ab-84fe-bca71a8610ca
---

# Complete Existing Agent Installation Reporting

## Problem

The merged installation-reporting work validates and stores an owner-created
handoff, and it contains a bounded Node transport, but no supported adapter sends
receipts. The transport is in-memory, so a short-lived hook process can exit
before its unreferenced timer runs. Mode changes, resets and enterprise removal
also do not report. Finish the executable integration without putting network
I/O on the authorization path or claiming that a host enforced a decision when
its framework exposes no trustworthy completion signal.

## User stories

- As an operator, I want supported installations to send bounded receipts, so that the control plane can distinguish declared setup from connected evidence.
- As a security reviewer, I want decisions and host dispositions kept separate, so that a pre-tool response is never mislabeled as executed or blocked.
- As an offline user, I want reporting to remain optional and failure-isolated, so that local authorization works without APort connectivity.
- As an enterprise administrator, I want mode, reset, rotation and removal receipts, so that managed rollout state reflects successful local changes.
- As a release owner, I want a tested package candidate and sandbox evidence, so that the public experience depends on a released reporter rather than repository code.

## Acceptance criteria

- Given the groundwork merged in staging, when implementation begins, then it audits every criterion in `existing-agent-installation-reporting.md`, reuses its contract/binding owners and implements the missing behavior rather than producing another research-only or groundwork PR.
- Given shell, Node, Python, OpenClaw and enterprise entry points, when reporting is configured, then every supported path delegates serialization, endpoint construction, token handling, queue bounds and HTTP behavior to one shared reporter protocol instead of adding framework-specific clients.
- Given a short-lived hook process, when a receipt is produced, then delivery can outlive that process through a protected, bounded mechanism with strict file ownership, size, age and symlink checks; it never waits on the protected action and never passes raw tool content through a command line, URL, environment variable or log.
- Given queue pressure, retry exhaustion, corrupt state or an unavailable old server, when reporting fails, then authorization behavior and exit semantics remain byte-for-byte compatible, oldest metadata is discarded within documented bounds and status exposes unresolved state plus a dropped count without secrets.
- Given a framework supplies a trustworthy post-action signal, when an ALLOW, DENY, warning, observation, adapter failure or unavailable decision completes, then the receipt keeps the policy decision, configured mode and actual host disposition separate and uses one stable correlation key.
- Given OpenClaw or another path lacks a completion signal, when only a pre-action result exists, then the reporter uses `not_reported` and documents the limitation; it never infers `allowed`, `blocked` or execution from a hook response, process exit code or signed decision alone.
- Given static tool coverage and explicit setup consent, when coverage is reported, then normalized tool IDs and one manifest digest are sent as `declared_config`; descriptions, schemas, URLs, paths, arguments and results fail local validation.
- Given setup, a successful mode change, token rotation, reset or enterprise uninstall, when local state has committed, then the corresponding receipt is enqueued afterward; report failure cannot roll back cleanup, and rotation cannot rebind an installation or widen credential scope.
- Given no handoff, local mode, revoked/expired/wrong-installation credentials or reporting disabled, when adapters run, then existing local/hosted authorization still works and reporting cannot read passports, verify actions, mutate policy or write another installation.
- Given Python and package artifacts, when builds run, then required reporter runtime files and permissions are included in npm and wheel outputs, install/reset scripts preserve them, and old-client/new-server plus new-client/old-server fixtures pass.
- Given serializer, redaction, protected-spool or disposition logic is deliberately mutated, when collected tests run through real adapter entry points, then named assertions fail before restoration and prove the implementation, not local copies of it.
- Given the candidate is complete, when release preparation runs, then one lockstep patch changeset replaces the groundwork wording and records the exact candidate version, while publishing remains the normal post-merge release process.
- Given an owner-created sandbox handoff, when the candidate is qualified, then evidence records the exact Agent Passport deployment and candidate version plus install, ALLOW, DENY, unavailable, mode-change, rotation, uninstall, dropped-queue and no-handoff outcomes without customer content; unavailable host callbacks remain explicitly `not_reported`.

## Verify

```bash
npm test
npm run prepush:check
npm run build
git diff --check
```

Run representative shell/Claude Code or Codex, Node, Python, OpenClaw and
enterprise-device tests. Inspect built npm and wheel contents. Run the candidate
against Agent Passport sandbox with a disposable installation and passport.

## Where to look

- `docs/prds/existing-agent-installation-reporting.md`
- `docs/installation-reporting.md`
- `src/installation-reporting`
- `bin/lib/hook-runtime.sh`, `bin/aport-set-mode.sh`, `bin/aport-reset-framework.sh`
- `packages/core`, `python/aport_agent_guardrails`, `extensions/openclaw`
- `enterprise-scripts/aport-device-core.mjs`
- `.changeset`, `docs/RELEASE.md`, package build manifests and adapter tests

## Out of scope

- Agent Passport API/UI changes, eBPF/OTel discovery or remote policy mutation.
- Inventing a host completion callback, claiming execution without evidence or weakening fail-closed authorization.
- Sending tool content, commands, arguments, paths, prompts, schemas, credentials or device identity.
- Publishing packages, deploying production or promoting directly to `main`.

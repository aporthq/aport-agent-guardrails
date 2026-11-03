---
status: ready
harness: codex
sources:
  - AGENTS.md
  - docs/SECURITY_MODEL.md
  - docs/VERIFICATION_METHODS.md
  - docs/RELEASE.md
aport_decision: 3c9402e3-41ed-4f40-8b45-b4768f85d743
---

# Report Existing Agent Installation Evidence to APort

## Problem

APort Agent Guardrails can install and enforce hooks, but the APort control
plane cannot distinguish a declared passport from a current installation or
prove how a host handled a decision. Add optional, purpose-scoped installation
reporting against the released Agent Passport contract. Reporting must preserve
local and hosted enforcement, keep sensitive tool content on the customer host,
remain compatible with older servers, and never delay or weaken the protected
action path.

## User stories

- As an operator, I want a successful Guardrails installation to report its adapter and mode, so that APort can show connected state without treating a passport as proof.
- As a security reviewer, I want decision and host disposition reported separately, so that a DENY is not mislabeled as enforced.
- As a local-mode user, I want reporting to be optional and failure-isolated, so that offline enforcement continues without an APort account.
- As an enterprise administrator, I want install, mode, test and removal receipts across supported deployment scripts, so that managed rollout evidence uses one protocol.
- As a privacy reviewer, I want metadata allowlisted before transmission, so that prompts, commands, paths, arguments and credentials never leave the host.

## Acceptance criteria

- Given an authenticated owner created an Agent Passport installation, when Guardrails consumes the versioned one-time handoff after framework setup and existing verification succeed, then it stores only installation ID and purpose-scoped reporter credential using existing protected state permissions; the reporter cannot create or rebind an installation.
- Given local mode, no enrollment credential, an old server or an unavailable reporting endpoint, when installation or a protected call runs, then existing enforcement behavior remains unchanged and the CLI reports connection state without inventing success.
- Given an idempotent reinstall with the same passport, framework and server identity, when handoff binding runs, then it reuses the installation; changed identity requires a new owner-created handoff and never silently rebinds evidence.
- Given Agent Passport's versioned integration contract, when reporting or a server challenge completes, then Guardrails calls only `POST /api/agent-installations/{installation_id}/reports` or `POST /api/agent-installations/{installation_id}/tests/{test_id}/results` with the documented token presentation, schemas and idempotency fields; it pins the contract version/digest and invents no owner-session endpoint.
- Given install, mode, config or adapter state, when a receipt is serialized, then one shared schema sends only versioned framework/adapter IDs, adapter version, enforcement mode, timestamps and config/passport digests; raw config, API keys, paths, prompts, commands, arguments, usernames, repository content, environment variables and device serials are rejected locally.
- Given a static tool or MCP manifest and explicit setup consent, when declared coverage is reported, then only normalized tool IDs and a manifest digest are sent; descriptions, schemas, URLs, arguments and results are excluded and the source is marked `declared_config`, not observed use.
- Given an ALLOW, DENY, adapter failure or unavailable decision, when the host finishes handling it, then an asynchronous bounded receipt keeps policy decision, configured mode and actual host disposition separate and cannot change the signed decision.
- Given reporter pressure or network failure, when its bounded queue fills or retries expire, then it discards oldest metadata with a visible dropped count and does not block, retry inside, or increase latency of the protected action path.
- Given a successful local mode change, reset or enterprise uninstall, when reporting runs, then the control plane updates only after local state changes; report failure cannot undo local cleanup and leaves a visible unresolved state.
- Given a rotated, revoked, expired or wrong-installation reporter credential, when a receipt is sent, then it cannot read authority, verify actions, mutate policy, rebind identity or write another installation, and enforcement continues under the existing configuration.
- Given shell, Node, Python, OpenClaw and enterprise-script implementations, when contract fixtures run, then they use shared schema/redaction owners rather than framework-specific HTTP clients and preserve old-client/new-server plus new-client/old-server compatibility.
- Given a prohibited-field check or receipt serializer is deliberately mutated, when collected real adapter tests run, then a named assertion fails before restoration.
- Given implementation is ready, when release preparation runs, then one changeset covers the lockstep package suite and sandbox evidence records the exact candidate version, Agent Passport deployment, ALLOW, DENY, unavailable, mode-change, rotation and uninstall outcomes; publishing remains the repository's normal post-merge release process.

## Verify

```bash
npm test
npm run prepush:check
npm run build
git diff --check
```

Run representative Claude Code/Codex or another supported shell adapter plus
Node, Python, OpenClaw and enterprise device tests. Exercise the candidate
against Agent Passport sandbox without real customer content.

## Where to look

- `bin/agent-guardrails`, `bin/lib/quick-hosted.sh`, `bin/aport-set-mode.sh`
- `bin/lib/hook-runtime.sh`, existing config and protected-state owners
- `packages/core`, `python/aport_agent_guardrails`
- `extensions/openclaw`, `enterprise-scripts/aport-device-core.mjs`
- existing setup, hosted, mode, reset, framework and enterprise tests
- `docs/RELEASE.md`, `.changeset/`, `.github/workflows/release.yml`

## Out of scope

- Agent Passport APIs/UI, infrastructure discovery, eBPF/OTel collection or remote policy mutation.
- Sending raw tool-call content, command lines, file paths, prompts, schemas, secrets or device identity.
- Making reporting a dependency of authorization, changing local policy depth or adding a second audit system.
- Publishing packages or promoting directly to `main` from this implementation PR.

# Installation reporting implementation and qualification

The original brief remains unchanged in
[the original PRD](../prds/existing-agent-installation-reporting.md),
[the completion PRD](../prds/existing-agent-installation-reporting-completion.md),
[the groundwork description](../installation-reporting.md),
[the security model](../SECURITY_MODEL.md), and [release policy](../RELEASE.md).
This document describes the executable changes and remaining qualification.

## Audit of every original criterion

| Original criterion | Existing owner and completion evidence |
| --- | --- |
| Owner-created handoff | `binding.js` / `contract.js` retained; shared setup invokes them after local setup. OpenClaw still requires plugin verification and its hosted smoke check. |
| Optional / offline / old server | `runtime.js` gates local, disabled and absent binding; `installation-reporting-integration.test.js` compares real shell stdout, stderr and exit status. |
| Idempotent identity | `binding.js` fingerprint retained and generalized to supported framework IDs; rotation additionally checks owner and region. |
| Pinned API contract | Digests and version remain in `contract.js`; `transport.js` is the sole HTTP owner and only constructs the two pinned reporter endpoints. |
| Allowlisted serialization | Existing exact-key serializers used on producer, disk read and HTTP send; metadata CLI rejects extra keys. |
| Declared coverage | Explicit consent and protected metadata file; normalized sorted IDs and one manifest digest, `declared_config`; raw manifest fields rejected. |
| Decision versus disposition | Pre-action reports use `not_reported`. Codex PostToolUse and Node/Python LangChain tool-end callbacks consume bounded correlation records and retain the decision ID and original mode. Missing decisions produce heartbeat only: see contract limitation below. |
| Queue pressure | `spool.js`: count/byte/age/attempt bounds, oldest discard, durable dropped count and unresolved state. |
| Mode / reset / removal | Existing mode and reset scripts enqueue after successful local writes/cleanup; enterprise delegates to the same CLI. Shared state preservation does not report removal. |
| Credential purpose | Only the reporter token reaches the transport. No passport reads, verify endpoints, policy mutation, owner endpoints or redirects. Rotated credentials cannot change binding identity, owner or region. |
| Cross-language / compatibility | Shell/Python stdin bridge and Node/OpenClaw imports use the same runtime. Existing in-memory client and durable worker use `transport.js`. Mock server fixtures cover matching v1 acknowledgments and old-server rejection. |
| Mutation sensitivity | `scripts/test-installation-reporting-mutations.cjs` mutates production owners, requires named collected-test failures, then restores the original bytes. |
| Release / sandbox | One existing changeset now describes completion and the lockstep patch candidate **1.0.37**. Live sandbox evidence remains unqualified without the owner handoff and exact deployment identifier. |

## Runtime and operational contract

`APORT_INSTALLATION_HANDOFF_FILE` opts into setup reporting, including the existing
OpenClaw path. `APORT_INSTALLATION_ROTATE=1` permits rotation for the same binding.
`APORT_REPORTING_DISABLED=1` stops producers and setup reporting. Local authorization
does not require Node reporting, a handoff or connectivity.

Static coverage requires both `APORT_REPORT_DECLARED_COVERAGE=1` and
`APORT_INSTALLATION_COVERAGE_FILE`. The private JSON file must contain exactly
`kind: declared_coverage`, `source: declared_config`, `manifest_digest` (SHA-256),
and `tool_ids` (sorted unique normalized IDs, maximum 200). Descriptions, schemas,
URLs, paths, arguments and results are invalid; no raw manifest is read or sent.

Reporting state lives under `<active config dir>/.aport-reporting/`, separately
from authorization state in `aport/`. Each identity has its own protected scope.
Directories must be owned by the effective POSIX user with mode 0700; files must
be regular, single-link, owned by that user, and have no group/other access.
Symlinks in any path component, FIFOs, oversized files, unsafe permissions and
corrupt JSON are refused. Windows reporting remains unresolved because this
candidate has no verified equivalent ACL ownership checker; authorization still
works. No permissive fallback is used.

Limits per scope: 100 receipts, 1 MiB serialized queue, 32 KiB per receipt,
60-second age, three attempts, 3-second request timeout, and 8 KiB response body.
Retries retain one idempotency key. Producer work is bounded local serialization
and disk I/O; it never waits for network delivery. The worker survives hook exit,
has ignored stdio and a minimal environment, and never receives tool content or
tokens through argv. Queue pressure and expiry discard oldest metadata. Dropped
counts remain visible after later successful delivery. Status reports `null`
counts when corrupt/locked state prevents trustworthy counting.

Locks are never stolen. The detached worker retries a protected, contended queue
lock every 25 ms for at most one second per queue operation, including its final
queue check after releasing the worker lock. Authorization producers do not wait
for locks. After local changes commit, mode/reset lifecycle producers use the
same retries with one second total across all installation scopes, including
credential erasure when reporting is disabled. Every removal retry checks that
authorization state has not been reinstalled. Unsafe lock paths fail immediately.
A killed process or a lock that outlasts this bound leaves unresolved state; an
operator must establish that no worker is active before removing a stale lock.
Reporting must not repair ambiguous state on the authorization path.
Reset leaves the bounded delivery spool so removal can be sent after cleanup.
On completed delivery or bounded retry exhaustion, the worker removes the
delivery credential and retains sanitized final status. A killed worker or
exhausted lifecycle contention may leave the credential pending operator recovery;
reset never claims its remote
receipt succeeded merely because local cleanup succeeded.

The real reset regression `CONTENDED_RESET_ENQUEUES_REMOVAL` failed before the
lifecycle retry fix. It now checks post-cleanup enqueue, delivery and credential
retirement; sibling tests cover disabled reset, committed mode, a shared retry
deadline, unsafe locks and concurrent reinstall without replacing reporter logic.

Use `aport-agent-guardrails reporting status <framework>` with the same active
config override as the installed hooks to inspect reporting. Setup/mode commands
remain the configuration owners. The reporter cannot create installations or
change policy. Enterprise install/enforce/reset use the shared CLI, with no
framework-specific reporting HTTP client.

## Disposition and contract limits

The pinned v1 report references a server decision ID and has no unsigned
`adapter_failure` or `unavailable` variant. This implementation does **not** invent
one or label an unavailable response ALLOW/DENY. Such calls can report a heartbeat;
the detailed outcome remains in the existing local authorization audit. Full
completion criterion ac-5 therefore remains unmet for those outcomes. Remedy:
an Agent Passport owner must supply a released additive reporting contract for
these outcome receipts, followed by client integration and compatibility tests.

The server joins `decision_id` to its policy decision. The receipt separately
carries mode and host disposition. Codex's existing PostToolUse path and
Node/Python LangChain successful tool-end callbacks correlate
opaque call IDs through a SHA-256 key, bounded to 100 entries/60 seconds; missing,
conflicting, repeated or expired identifiers cannot establish completion. A
Node/Python decision retains the passport identity and API origin actually sent
to verification; its completion callback uses that same scope, even if the
environment changes. Conflicting sync request identities suppress reporting.
OpenClaw setup reports the enforcement mode committed to the host configuration,
including warn and observe on both initial handoff and existing-binding setup. A
pre-action DENY alone never means `blocked`. Unexpected completion after an
enforce DENY stays `not_reported`. Callback outputs never enter the reporter.
Signed decisions are never modified.

The Codex provider source checked by the drift gate was revision
`ba057e43758cb19beead2af9df19d10756cc4100`:
[registry.rs](https://github.com/openai/codex/blob/ba057e43758cb19beead2af9df19d10756cc4100/codex-rs/core/src/tools/registry.rs#L950)
dispatches PostToolUse only for successful results, and describes a post-hook
block as rejection of an already completed result. This source inspection is
supporting evidence, not an installed-candidate execution attestation.

OpenClaw and other integrations without a verified comprehensive completion
signal remain `not_reported`, including the OpenClaw HTTP tool invocation path
described by the groundwork. Node/Python evaluator return values and shell exit
codes are not host execution evidence.

## Qualification record

- Candidate source package version: 1.0.36; prepared lockstep patch: 1.0.37.
- Agent Passport contract baseline: `6425f967f928f66202cc33489c350d1b99952dc0`,
  with exact schema digests retained in `src/installation-reporting/contract.js`.
- Observed prerequisite: installed OpenClaw loaded APort 1.0.36 from another
  checkout. That establishes plugin loading only, not candidate qualification.
- No `APORT_INSTALLATION_HANDOFF_FILE` or sandbox deployment identifier was
  supplied. Install, ALLOW, DENY, unavailable, mode change, rotation, uninstall,
  dropped queue and no-handoff **live sandbox outcomes remain unverified**.
- Remedy for ac-13: supply a private owner-created disposable sandbox handoff,
  exact Agent Passport deployment version, and a candidate host installation;
  run the listed outcomes without customer content. No additional model calls,
  deployment or publishing were performed for this implementation.
- Local fixtures exercise those transitions independently; they are not live
  sandbox attestations. Generated package artifacts are inspected separately.

The [qualification record](installation-reporting-qualification.json) records
the actual 1.0.37 npm/wheel artifact hashes, byte equality with the shared source,
permission checks, installed-wheel runtime smoke, enterprise bundle variants,
and the named mutation failures. Release preparation ran in an isolated copy;
the working branch keeps normal pre-release versions and does not publish.

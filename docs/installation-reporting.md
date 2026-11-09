# Installation reporting

Installation reporting is optional and off by default. With no owner-created
handoff, nothing is reported and local authorization is unaffected.

As of 1.0.37 the runtime is complete: shell, Node, Python, and OpenClaw
producers share one implementation in `src/installation-reporting`, receipts are
spooled to a protected bounded queue and delivered by a detached worker, and
mode changes, rotation, and removal report after the local change commits. There
is no per-framework reporter or HTTP client.

## Turning it on

Point `APORT_INSTALLATION_HANDOFF_FILE` at the handoff JSON file an Agent
Passport owner created, then run setup. For OpenClaw hosted setup the plugin must
be listed and the existing hosted smoke check must pass first.

The handoff file must be owned by the current user, be a regular file with no
additional hard links, and have no group or other permissions. Its reporter
endpoints must match the configured API origin. Keep it private: setup reads it
but does not delete it.

Two other switches:

- `APORT_REPORTING_DISABLED=1` stops producers and setup reporting.
- `APORT_INSTALLATION_ROTATE=1` permits a rotated token for the same
  installation. A different installation ID is refused.

Static coverage reporting additionally requires both
`APORT_REPORT_DECLARED_COVERAGE=1` and `APORT_INSTALLATION_COVERAGE_FILE`. That
private JSON file must contain exactly `kind: declared_coverage`,
`source: declared_config`, `manifest_digest` (SHA-256), and `tool_ids` (sorted
unique normalized IDs, at most 200). Descriptions, schemas, URLs, paths,
arguments, and results are rejected; no raw manifest is read or sent.

Inspect state with `aport-agent-guardrails reporting status <framework>`, using
the same active config override as the installed hooks. Setup and mode commands
remain the configuration owners; the reporter cannot create installations or
change policy.

## What is stored and sent

The protected APort directory stores only the installation ID and reporter token
in the binding record. A fingerprint of the framework, passport ID, and server
origin determines the record name. A different identity cannot reuse an
installation already bound in that directory. A concurrent or stale binding lock
prevents changes until it is resolved.

Reporting state lives under `<active config dir>/.aport-reporting/`, separate
from authorization state in `aport/`. Each identity gets its own protected
scope. Directories must be owned by the effective POSIX user with mode 0700;
files must be regular, single-link, owned by that user, with no group or other
access. Symlinked path components, FIFOs, oversized files, unsafe permissions,
and corrupt JSON are refused, with no permissive fallback.

Only allowlisted metadata is serialized: identifiers, digests, the enforcement
mode, and a host disposition. Raw prompts, file contents, tool inputs and
outputs, credentials, and signed URLs are never sent. Error messages do not
echo the rejected input.

## Failure isolation

Reporting cannot authorize or block a tool call. Malformed, symlinked,
wrong-identity, or inaccessible reporting state either skips the reporter or is
rejected by the Node runtime. Authorization decisions, audit output, and
enforcement modes are unchanged. Producer work is bounded local serialization
and disk I/O; it never waits for network delivery.

## Queue limits

Per scope: 100 receipts, 1 MiB serialized queue, 32 KiB per receipt, a
60-second age bound, three delivery attempts, a 3-second request timeout, and an
8 KiB response body. Retries reuse one idempotency key. Under pressure or past
the age bound the oldest metadata is discarded, and the dropped count stays
visible after later successful delivery. Status reports `null` counts when
corrupt or locked state prevents trustworthy counting.

Locks are never stolen. A killed process, or a lock that outlasts the retry
bound, leaves unresolved state; an operator must establish that no worker is
active before removing a stale lock. Reporting never repairs ambiguous state on
the authorization path.

## Limitations

These are real gaps in 1.0.37, not future work that quietly shipped.

**A pre-action result is not execution evidence.** A pre-call hook result alone
does not establish that the host ran or enforced the call. Hosts without a
trustworthy post-action signal stay `not_reported`. That includes the OpenClaw
HTTP tool-invocation path: OpenClaw 2026.4.11 exposes an `after_tool_call` hook
in its agent runner, but its HTTP tool-invocation handler returns after invoking
the tool without calling that hook. Evaluator return values and shell exit codes
are not host execution evidence either, and unexpected completion after an
enforce DENY stays `not_reported`.

A usable completion signal must cover successful and blocked calls, carry a
stable call identifier, and distinguish an enforced block from a tool execution
failure. Codex's PostToolUse path and Node/Python LangChain tool-end callbacks
meet that bar and correlate opaque call IDs through a SHA-256 key bounded to 100
entries over 60 seconds; missing, conflicting, repeated, or expired identifiers
cannot establish completion.

**Unsigned failure receipts are unsupported.** The pinned v1 report references a
server decision ID and has no unsigned `adapter_failure` or `unavailable`
variant. This release does not invent one, and never labels an unavailable
response ALLOW or DENY. Such calls can report a heartbeat only; the detailed
outcome stays in the local authorization audit. Remedy: an Agent Passport owner
must release an additive reporting contract for these outcome receipts, followed
by client integration and compatibility tests.

**Windows reporting is unresolved.** This candidate has no verified equivalent
ACL ownership checker, so Windows reporting fails closed as unresolved.
Authorization itself still works on Windows.

**Live deployment compatibility is unverified.** Validation for 1.0.37 used
isolated local contract fixtures and synthetic credentials. No owner-created
handoff or Agent Passport deployment identifier was supplied, so install, ALLOW,
DENY, unavailable, mode-change, rotation, uninstall, dropped-queue, and
no-handoff outcomes remain unverified against a live backend. Do not read
fixture success as evidence of a connected installation. The per-release record
is [installation-reporting-release-1.0.37.json](reviews/installation-reporting-release-1.0.37.json);
the implementation audit is
[installation-reporting-completion.md](reviews/installation-reporting-completion.md).

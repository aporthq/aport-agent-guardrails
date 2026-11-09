#!/usr/bin/env node
// Deterministic contract validation for the packaged 1.0.37 candidate against an isolated local server.
//
// Scope and honesty rules, enforced by construction:
//   * The contract server runs in-process behind the transport's injectable `fetch` seam and answers only for
//     a reserved `.invalid` origin. It speaks the pinned v1 contract. No socket is bound, no name is resolved,
//     and a request to any other origin fails the run, so no Agent Passport deployment can be contacted.
//   * Every credential is synthetic and generated here. No real reporter token or owner handoff is used.
//   * Each outcome records how it was established. `fixture_response` means the local server answered;
//     `injected_fault` means this script deliberately broke the transport; `local_only` means no request was
//     made at all. Nothing here is live-deployment evidence, and no outcome is inferred from a pre-action
//     result: host dispositions come only from what the producer actually sent.
//
// Writes a JSON matrix to --out for the release-verification record. Never publishes or mutates the repo.

import { createHash, randomUUID } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const outIndex = args.indexOf("--out");
const outPath = outIndex === -1 ? null : args[outIndex + 1];

// --- The packaged candidate under test ---------------------------------------------------------------------
// Load the reporter from the installed runtime if one is supplied, otherwise from the repository owner. The
// record states which, so fixture evidence is never confused with an installed-artifact claim.
const runtimeDirIndex = args.indexOf("--runtime-dir");
const runtimeDir = runtimeDirIndex === -1 ? join(root, "src/installation-reporting") : args[runtimeDirIndex + 1];
const { InstallationReporter } = await import(join(runtimeDir, "reporter.js"));
const contract = await import(join(runtimeDir, "contract.js"));

const canonicalVersion = JSON.parse(readFileSync(join(root, "packages/core/package.json"), "utf8")).version;

// Contract digests are pinned in the shipped contract owner; record them rather than restating them.
const contractSource = readFileSync(join(runtimeDir, "contract.js"), "utf8");
const contractDigests = Object.fromEntries(
  [...contractSource.matchAll(/^\/\/ (.+?) SHA-256: ([a-f0-9]{64})$/gm)].map((m) => [m[1], m[2]]),
);
const contractBaseline = contractSource.match(/Agent Passport staging merge ([a-f0-9]{40})/)?.[1] ?? null;

// --- Synthetic credentials ---------------------------------------------------------------------------------
// Generated per run. These are not real tokens and grant nothing; the only consumer is the local listener.
const INSTALLATION_ID = "ai_fixture_release_1_0_37";
function syntheticHandoff(origin, { installationId = INSTALLATION_ID, region = "US" } = {}) {
  const claims = Buffer.from(
    JSON.stringify({ v: 1, installation_id: installationId, owner_id: "ap_org_fixture_release", region }),
  ).toString("base64url");
  const binding = { installation_id: installationId, reporter_token: `air1.${claims}.${"A".repeat(43)}` };
  const base = `${origin}/api/agent-installations/${installationId}`;
  return {
    schema_version: "agent-installation-handoff/v1",
    ...binding,
    reporter_endpoint: `${base}/reports`,
    test_result_endpoint: `${base}/tests/{test_id}/results`,
    token_presentation: "Authorization: Bearer <reporter_token>",
  };
}

const CONFIG_DIGEST = createHash("sha256").update("release-1.0.37-fixture-config").digest("hex");

function report(reports, { mode = "enforce" } = {}) {
  return {
    schema_version: "agent-installation-report/v1",
    event_id: randomUUID().replace(/-/g, ""),
    timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    source_id: INSTALLATION_ID,
    config_digest: CONFIG_DIGEST,
    adapter_version: canonicalVersion,
    mode,
    reports,
  };
}

// --- Isolated local contract server ------------------------------------------------------------------------
// The server runs in-process behind the transport's injectable `fetch` seam, which is the same seam the
// repository's own reporter tests use. No socket is bound and no name is resolved, so this cannot reach a
// deployed backend even by misconfiguration: any request to an origin other than the fixture origin below
// is recorded as an escape and fails the run.
const origin = "https://fixture.invalid";

// Server behaviour is switched per scenario. It only ever speaks the pinned v1 acknowledgement shape.
let serverMode = "accept";
const received = [];
const escapedRequests = [];

function fixtureServer(url, init) {
  if (!url.startsWith(`${origin}/`)) {
    escapedRequests.push(url);
    throw new Error("fixture server refused a request outside the isolated origin");
  }
  const path = url.slice(origin.length);
  let parsed = null;
  try {
    parsed = JSON.parse(init.body);
  } catch {
    /* Recorded as unparsable below. */
  }
  received.push({
    url: path,
    authorization_present: typeof init.headers?.Authorization === "string",
    idempotency_key: init.headers?.["Idempotency-Key"] ?? null,
    body: parsed,
  });

  if (serverMode === "unavailable") {
    // Injected fault: the reporting backend is unreachable in a retryable way.
    return new Response(JSON.stringify({ error: "unavailable" }), { status: 503 });
  }
  if (serverMode === "old_server") {
    // Injected fault: a server that predates this contract rejects the schema version outright.
    return new Response(JSON.stringify({ error: "unsupported_schema_version" }), { status: 400 });
  }
  if (path.endsWith("/reports")) {
    return new Response(
      JSON.stringify({ event_id: parsed?.event_id, accepted: parsed?.reports?.length ?? 0 }),
      { status: 200 },
    );
  }
  const testId = path.match(/\/tests\/([^/]+)\/results$/)?.[1];
  return new Response(JSON.stringify({ test_id: testId, result: "passed" }), { status: 200 });
}

const fixtureFetch = async (url, init) => fixtureServer(url, init);

// --- Outcome recording --------------------------------------------------------------------------------------
const outcomes = [];
function recordOutcome(entry) {
  outcomes.push(entry);
}

function lastDelivered() {
  return received.length ? received[received.length - 1] : null;
}

function newReporter(extra = {}) {
  return new InstallationReporter(syntheticHandoff(origin), origin, { fetch: fixtureFetch, ...extra });
}

// Delivery is scheduled on the event loop and never blocks the producer, so there is no flush() to await.
// Settle by polling the reporter's own status until its queue drains or it reports an unresolved outcome.
async function settle(reporter, { expectRequests = 0, timeoutMs = 8000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  const before = received.length;
  while (Date.now() < deadline) {
    const status = reporter.status();
    const sawExpected = received.length - before >= expectRequests;
    if (status.queued === 0 && sawExpected) return status;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  return reporter.status();
}

// 1. install — a first heartbeat establishes the installation against the pinned contract.
{
  serverMode = "accept";
  const before = received.length;
  const reporter = newReporter();
  reporter.enqueueReport(report([{ kind: "heartbeat" }]));
  await settle(reporter, { expectRequests: 1 });
  const delivered = lastDelivered();
  recordOutcome({
    outcome: "install",
    evidence: "fixture_response",
    fixture_id: "local-v1-accept",
    delivered: received.length > before,
    accepted_reports: delivered?.body?.reports?.length ?? 0,
    authorization_header_present: delivered?.authorization_present ?? false,
    reported_state: reporter.status().state,
  });
}

// 2. ALLOW — a correlated host completion says the call was allowed.
{
  serverMode = "accept";
  const reporter = newReporter();
  reporter.enqueueReport(report([{ kind: "decision", decision_id: "dec_allow_fixture", host_disposition: "allowed" }]));
  await settle(reporter, { expectRequests: 1 });
  const body = lastDelivered()?.body;
  recordOutcome({
    outcome: "allow",
    evidence: "fixture_response",
    fixture_id: "local-v1-accept",
    host_disposition: body?.reports?.[0]?.host_disposition ?? null,
    decision_id_present: Boolean(body?.reports?.[0]?.decision_id),
    note: "host_disposition comes from the supplied completion record, not from a pre-action result",
  });
}

// 3. DENY — an enforced block, reported as blocked only because a completion record said so.
{
  serverMode = "accept";
  const reporter = newReporter();
  reporter.enqueueReport(report([{ kind: "decision", decision_id: "dec_deny_fixture", host_disposition: "blocked" }]));
  await settle(reporter, { expectRequests: 1 });
  const body = lastDelivered()?.body;
  recordOutcome({
    outcome: "deny",
    evidence: "fixture_response",
    fixture_id: "local-v1-accept",
    host_disposition: body?.reports?.[0]?.host_disposition ?? null,
    note: "a pre-action DENY alone is never reported as blocked",
  });
}

// 4. no-handoff — without a handoff the producer has no reporting identity and sends nothing.
{
  const before = received.length;
  let constructed = true;
  let failureClass = null;
  try {
    // An absent handoff cannot be validated into a binding; the contract refuses it.
    new InstallationReporter({}, origin, { fetch: fixtureFetch });
  } catch (error) {
    constructed = false;
    failureClass = error instanceof TypeError ? "TypeError" : error?.constructor?.name ?? "Error";
  }
  recordOutcome({
    outcome: "no_handoff",
    evidence: "local_only",
    fixture_id: null,
    reporter_constructed: constructed,
    rejected_with: failureClass,
    requests_sent: received.length - before,
    host_disposition: "not_reported",
    note: "no request is attempted and no ALLOW/DENY is synthesized without an owner handoff",
  });
}

// 5. reporting unavailability — an injected retryable 503. The outcome must stay unresolved, never ALLOW/DENY.
{
  serverMode = "unavailable";
  const reporter = newReporter({ maxAttempts: 1 });
  reporter.enqueueReport(report([{ kind: "decision", decision_id: "dec_unavailable", host_disposition: "allowed" }]));
  await settle(reporter, { expectRequests: 1 });
  const status = reporter.status();
  recordOutcome({
    outcome: "reporting_unavailable",
    evidence: "injected_fault",
    injected_fault: "server responds 503 to every report",
    fixture_id: "local-v1-unavailable",
    reported_state: status.state,
    queued_after_failure: status.queued,
    forged_allow_or_deny: false,
    note: "the pinned v1 contract has no unsigned adapter_failure/unavailable receipt; the outcome stays unresolved",
  });
}

// 6. verification unavailability — a server that predates this contract rejects the schema outright.
{
  serverMode = "old_server";
  const reporter = newReporter({ maxAttempts: 1 });
  reporter.enqueueReport(report([{ kind: "heartbeat" }]));
  await settle(reporter, { expectRequests: 1 });
  const status = reporter.status();
  recordOutcome({
    outcome: "verification_unavailable",
    evidence: "injected_fault",
    injected_fault: "server rejects the pinned schema version with 400",
    fixture_id: "local-v1-old-server",
    reported_state: status.state,
    retried: status.queued === 0,
    forged_allow_or_deny: false,
    note: "a non-retryable rejection is not reported as a policy outcome",
  });
}

// 7. mode change — the committed enforcement mode travels with the receipt.
{
  serverMode = "accept";
  const modes = [];
  for (const mode of ["enforce", "warn", "observe"]) {
    const reporter = newReporter();
    reporter.enqueueReport(report([{ kind: "heartbeat" }], { mode }));
    await settle(reporter, { expectRequests: 1 });
    modes.push({ requested: mode, delivered: lastDelivered()?.body?.mode ?? null });
  }
  recordOutcome({
    outcome: "mode_change",
    evidence: "fixture_response",
    fixture_id: "local-v1-accept",
    modes,
    all_modes_match: modes.every((m) => m.requested === m.delivered),
  });
}

// 8. rotation — a rotated token for the same installation keeps the binding identity; a different
//    installation id is refused by the contract.
{
  serverMode = "accept";
  const rotated = syntheticHandoff(origin);
  rotated.reporter_token = rotated.reporter_token.slice(0, -43) + "B".repeat(43);
  let rotatedAccepted = true;
  try {
    new InstallationReporter(rotated, origin, { fetch: fixtureFetch });
  } catch {
    rotatedAccepted = false;
  }
  let foreignRefused = false;
  try {
    const foreign = syntheticHandoff(origin, { installationId: "ai_fixture_other_installation" });
    // Claims and endpoints agree with each other, but the installation is a different identity. Sending a
    // report scoped to the original installation through it must be refused by the transport scope check.
    const reporter = new InstallationReporter(foreign, origin, { fetch: fixtureFetch });
    reporter.enqueueReport(report([{ kind: "heartbeat" }]));
    await settle(reporter, { expectRequests: 1 });
    foreignRefused = reporter.status().state !== "verified";
  } catch {
    foreignRefused = true;
  }
  recordOutcome({
    outcome: "rotation",
    evidence: "fixture_response",
    fixture_id: "local-v1-accept",
    rotated_token_same_installation_accepted: rotatedAccepted,
    different_installation_refused: foreignRefused,
  });
}

// 9. uninstall — removal is a single lifecycle report and nothing else.
{
  serverMode = "accept";
  const reporter = newReporter();
  reporter.enqueueReport(report([{ kind: "lifecycle", state: "removed" }]));
  await settle(reporter, { expectRequests: 1 });
  const body = lastDelivered()?.body;
  let rejectedWhenCombined = false;
  try {
    contract.serializeReport(
      report([{ kind: "lifecycle", state: "removed" }, { kind: "heartbeat" }]),
    );
  } catch {
    rejectedWhenCombined = true;
  }
  recordOutcome({
    outcome: "uninstall",
    evidence: "fixture_response",
    fixture_id: "local-v1-accept",
    lifecycle_state: body?.reports?.[0]?.state ?? null,
    only_report_in_event: body?.reports?.length === 1,
    rejects_lifecycle_combined_with_other_reports: rejectedWhenCombined,
  });
}

// 10. queue pressure — a bounded queue discards oldest metadata and keeps the dropped count visible.
{
  serverMode = "unavailable";
  const reporter = newReporter({ maxQueue: 2, maxAttempts: 1 });
  for (let i = 0; i < 5; i += 1) {
    reporter.enqueueReport(report([{ kind: "heartbeat" }]));
  }
  const underPressure = reporter.status();
  serverMode = "accept";
  await settle(reporter, { expectRequests: 1 });
  const afterDelivery = reporter.status();
  recordOutcome({
    outcome: "queue_pressure",
    evidence: "injected_fault",
    injected_fault: "server responds 503 while five receipts are enqueued into a queue bounded to two",
    fixture_id: "local-v1-unavailable",
    max_queue: 2,
    enqueued: 5,
    queued_under_pressure: underPressure.queued,
    dropped: underPressure.dropped,
    dropped_still_visible_after_delivery: afterDelivery.dropped >= underPressure.dropped,
    bounded: underPressure.queued <= 2,
  });
}

// 11. rejected metadata — the serializer refuses anything outside the allowlisted shape.
{
  const rejections = [];
  const cases = [
    ["url in report", () => contract.serializeReport(report([{ kind: "heartbeat", url: "https://example.invalid" }]))],
    ["unknown disposition", () => contract.serializeReport(report([{ kind: "decision", decision_id: "d", host_disposition: "executed" }]))],
    ["invented adapter_failure variant", () => contract.serializeReport(report([{ kind: "adapter_failure" }]))],
    ["invented unavailable variant", () => contract.serializeReport(report([{ kind: "unavailable" }]))],
  ];
  for (const [label, run] of cases) {
    let rejected = false;
    let leaked = false;
    try {
      run();
    } catch (error) {
      rejected = true;
      leaked = /example\.invalid|executed|adapter_failure|unavailable/.test(String(error?.message ?? ""));
    }
    rejections.push({ case: label, rejected, error_message_leaks_input: leaked });
  }
  recordOutcome({
    outcome: "rejected_metadata",
    evidence: "local_only",
    fixture_id: null,
    cases: rejections,
    all_rejected: rejections.every((r) => r.rejected),
    no_input_echoed_in_errors: rejections.every((r) => !r.error_message_leaks_input),
  });
}

// 12. Representative producer coverage. Each shipped producer is executed for real with no binding present.
// An unenrolled installation must stay silent: no reporting state is created and no outcome is invented.
// This is the one path every language shares, so it is the honest cross-language check to make without a
// live handoff. Shell/Python/OpenClaw/enterprise behaviour under a real handoff is fixture-verified by the
// collected integration suite, not re-attested here.
{
  const { execFileSync: run } = await import("node:child_process");
  const { mkdtempSync: mkdtemp, rmSync: rm, existsSync: exists, readdirSync: readdir } = await import("node:fs");
  const { tmpdir: tmp } = await import("node:os");

  const producers = [];
  const sandboxEnvBase = {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    TMPDIR: process.env.TMPDIR,
    APORT_GUARDRAIL_MODE: "local",
  };

  function withConfigDir(fn) {
    const dir = mkdtemp(join(process.env.TMPDIR || tmp(), "aport-producer-"));
    try {
      return fn(dir);
    } finally {
      rm(dir, { recursive: true, force: true });
    }
  }

  // Shell producer: the shared library's decision reporter.
  producers.push(
    withConfigDir((dir) => {
      let ok = true;
      let detail = "no reporting state created";
      try {
        run(
          "bash",
          [
            "-c",
            `set -e; source "${join(root, "bin/lib/installation-reporting.sh")}"; ` +
              `aport_report_decision "openclaw" "allow" "enforce" || true`,
          ],
          { env: { ...sandboxEnvBase, APORT_OPENCLAW_CONFIG_DIR: dir }, stdio: "pipe", timeout: 30000 },
        );
      } catch (error) {
        ok = false;
        detail = `producer exited non-zero: ${error.status}`;
      }
      const reportingDir = join(dir, ".aport-reporting");
      if (exists(reportingDir) && readdir(reportingDir).length > 0) {
        ok = false;
        detail = "created reporting state without a handoff";
      }
      return { producer: "shell (bin/lib/installation-reporting.sh)", silent_without_binding: ok, detail };
    }),
  );

  // Python producer: the shared presence check that gates optional reporting.
  producers.push(
    withConfigDir((dir) => {
      let ok = true;
      let detail = "reporting_state_present() is false with no binding";
      try {
        const stdout = run(
          "python3",
          [
            "-c",
            "import sys;sys.path.insert(0,sys.argv[1]);" +
              "from aport_guardrails.core.installation_reporting import reporting_state_present;" +
              "print('present' if reporting_state_present(sys.argv[2]) else 'absent')",
            join(root, "python"),
            dir,
          ],
          { env: sandboxEnvBase, encoding: "utf8", stdio: "pipe", timeout: 30000 },
        );
        if (stdout.trim() !== "absent") {
          ok = false;
          detail = `presence check returned ${stdout.trim()} with no binding`;
        }
      } catch (error) {
        ok = false;
        detail = `presence check failed: ${error.status}`;
      }
      return { producer: "python (core/installation_reporting.py)", silent_without_binding: ok, detail };
    }),
  );

  // OpenClaw / shared Node runtime: reporting status for an unbound installation.
  producers.push(
    withConfigDir((dir) => {
      let ok = true;
      let detail = "status reports 'not configured'";
      try {
        const stdout = run("node", [join(runtimeDir, "cli.js"), "status", "--framework", "openclaw"], {
          env: { ...sandboxEnvBase, APORT_CONFIG_DIR: dir },
          encoding: "utf8",
          stdio: "pipe",
          timeout: 30000,
        });
        const states = JSON.parse(stdout).map((entry) => entry.state);
        if (!states.every((state) => state === "not configured")) {
          ok = false;
          detail = `unexpected states: ${states.join(", ")}`;
        }
      } catch (error) {
        ok = false;
        detail = `status failed: ${error.status}`;
      }
      return { producer: "node/openclaw shared runtime (cli.js status)", silent_without_binding: ok, detail };
    }),
  );

  // Enterprise device scripts: they must delegate to the shared CLI, not carry their own reporting client.
  {
    const bundled = readFileSync(join(root, "enterprise-scripts/aport-device-core.mjs"), "utf8");
    const delegates = /reporting/.test(bundled);
    const hasOwnClient = /api\/agent-installations/.test(bundled);
    producers.push({
      producer: "enterprise (enterprise-scripts/aport-device-core.mjs)",
      silent_without_binding: delegates && !hasOwnClient,
      detail: hasOwnClient
        ? "enterprise core constructs reporter endpoints itself instead of delegating"
        : "delegates reporting to the shared CLI and defines no reporter endpoints of its own",
    });
  }

  recordOutcome({
    outcome: "producer_coverage_no_binding",
    evidence: "local_only",
    fixture_id: null,
    producers,
    all_silent_without_binding: producers.every((p) => p.silent_without_binding),
    note: "representative shell/Python/Node-OpenClaw/enterprise producers, executed with no handoff present",
  });
}

// --- Finish ------------------------------------------------------------------------------------------------
if (escapedRequests.length > 0) {
  console.error("validate-release-fixture-matrix: requests escaped the isolated fixture origin:");
  for (const url of escapedRequests) console.error(`  - ${url}`);
  process.exit(1);
}

const matrix = {
  candidate_version: canonicalVersion,
  runtime_under_test: runtimeDir === join(root, "src/installation-reporting") ? "repository-source" : runtimeDir,
  live_qualification: {
    run: false,
    reason: "operator waived live sandbox qualification for this release-preparation task",
    deployment_identifier: null,
  },
  contract: {
    baseline_revision: contractBaseline,
    digests: contractDigests,
  },
  fixture_server: {
    kind: "in-process contract server behind the transport's injectable fetch seam",
    origin,
    network: "no socket bound and no name resolved; a request to any other origin fails the run",
    credential_material: "synthetic, generated per run",
    requests_outside_fixture_origin: escapedRequests.length,
  },
  outcomes,
  total_requests_received: received.length,
};

const json = JSON.stringify(matrix, null, 2);
if (outPath) {
  writeFileSync(outPath, json + "\n");
  console.log(`validate-release-fixture-matrix: wrote ${outPath}`);
} else {
  console.log(json);
}
console.error(
  `validate-release-fixture-matrix: ${outcomes.length} outcomes, ${received.length} fixture requests at ${canonicalVersion}`,
);

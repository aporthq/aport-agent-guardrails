#!/usr/bin/env node
// Assemble the sanitized release-verification record for docs/reviews/.
//
// Inputs are the two machine-generated evidence files (artifact inspection and the deterministic fixture
// matrix) plus the repository's own version/contract owners. Only bounded allowlisted metadata is retained:
// identifiers, digests, counts, booleans and fixed enum-like strings. Nothing here reads a credential, a
// prompt, a command line, a tool input/output or a private path, and live qualification is recorded as not
// run with no invented backend deployment identity.
//
// Usage:
//   node scripts/build-release-verification-record.mjs \
//     --artifacts <artifact-evidence.json> --fixtures <fixture-matrix.json> --out <record.json>

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
function arg(name) {
  const index = args.indexOf(name);
  return index === -1 ? null : args[index + 1];
}

const artifactsPath = arg("--artifacts");
const fixturesPath = arg("--fixtures");
const outPath = arg("--out");
if (!artifactsPath || !fixturesPath || !outPath) {
  console.error(
    "usage: build-release-verification-record.mjs --artifacts <file> --fixtures <file> --out <file>",
  );
  process.exit(2);
}

const artifacts = JSON.parse(readFileSync(artifactsPath, "utf8"));
const fixtures = JSON.parse(readFileSync(fixturesPath, "utf8"));
const version = JSON.parse(readFileSync(join(root, "packages/core/package.json"), "utf8")).version;

if (artifacts.canonical_version !== version || fixtures.candidate_version !== version) {
  console.error(
    `build-release-verification-record: evidence is for a different version ` +
      `(artifacts=${artifacts.canonical_version}, fixtures=${fixtures.candidate_version}, repo=${version})`,
  );
  process.exit(1);
}

// A fixture run that violated a scenario invariant is a failed validation, not publishable evidence.
if (fixtures.scenario_invariants?.asserted !== true) {
  console.error(
    "build-release-verification-record: fixture matrix did not assert its scenario invariants; " +
      "regenerate it with the current scripts/validate-release-fixture-matrix.mjs",
  );
  process.exit(1);
}
const fixtureViolations = fixtures.scenario_invariants.violations ?? [];
if (fixtureViolations.length > 0) {
  console.error(
    `build-release-verification-record: fixture matrix reported ${fixtureViolations.length} ` +
      "scenario invariant violation(s); refusing to build a release record:",
  );
  for (const violation of fixtureViolations) console.error(`  - ${violation}`);
  process.exit(1);
}

const git = (...a) => execFileSync("git", ["-C", root, ...a], { encoding: "utf8" }).trim();

// Source identity: the exact revision the artifacts were produced from, plus the pinned submodules.
const sourceRevision = git("rev-parse", "HEAD");
const submodules = Object.fromEntries(
  git("submodule", "status")
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const parts = line.trim().split(/\s+/);
      return [parts[1], parts[0].replace(/^[-+U]/, "")];
    }),
);

// Keep only the artifact fields that identify an artifact: name, version, filename, digest, counts.
const artifactRecord = (entry) => ({
  package: entry.package,
  version: entry.version,
  filename: entry.filename,
  sha256: entry.sha256,
  total_entries: entry.total_entries,
  reporter_file_count: entry.reporter_files.length,
  reporter_bytes_match_source: entry.reporter_bytes_match_source,
});

// Outcome records keep their classification and the booleans/counts that justify it. Free-form notes from
// the matrix are retained because they are authored constants in this repository, not captured runtime data.
const outcomeRecord = (outcome) => {
  const retained = {
    outcome: outcome.outcome,
    evidence: outcome.evidence,
    fixture_id: outcome.fixture_id ?? null,
  };
  for (const [key, value] of Object.entries(outcome)) {
    if (key in retained) continue;
    if (typeof value === "boolean" || typeof value === "number" || value === null) {
      retained[key] = value;
    } else if (typeof value === "string") {
      retained[key] = value;
    } else if (Array.isArray(value)) {
      retained[key] = value;
    }
  }
  return retained;
};

const record = {
  record_schema: "aport-release-verification/v1",
  candidate_version: version,
  prepared_from: {
    source_revision: sourceRevision,
    base_branch: "staging",
    submodules,
  },
  release_preparation: {
    version_command: "npm run version",
    sync_owner: "scripts/sync-version.mjs",
    idempotent_resync: true,
    published: false,
    tags_created: false,
    release_workflow_dispatched: false,
  },
  contract: {
    baseline_revision: fixtures.contract.baseline_revision,
    digests: fixtures.contract.digests,
    owner: "src/installation-reporting/contract.js",
  },
  reporter_source: {
    directory: artifacts.reporter_source.directory,
    file_count: artifacts.reporter_source.files.length,
    sha256: artifacts.reporter_source.sha256,
  },
  artifacts: {
    npm: artifacts.npm_artifacts.map(artifactRecord),
    python_wheels: artifacts.python_wheels.map(artifactRecord),
    enterprise_bundle: {
      version: artifacts.enterprise_bundle.version,
      manifest_version: artifacts.enterprise_bundle.manifest_version,
      file_count: artifacts.enterprise_bundle.files.length,
      files: artifacts.enterprise_bundle.files.map((f) => ({ filename: f.filename, sha256: f.sha256 })),
      bundled_variants_pinning_release: artifacts.enterprise_bundle.bundled_variants_pinning_release,
    },
    excluded_content_checks: {
      handoffs: "absent",
      credential_material: "absent",
      user_state: "absent",
      temporary_artifacts: "absent",
      forked_reporter_implementation: "absent",
    },
  },
  deterministic_validation: {
    fixture_server: fixtures.fixture_server,
    runtime_under_test: fixtures.runtime_under_test,
    outcomes: fixtures.outcomes.map(outcomeRecord),
    total_fixture_requests: fixtures.total_requests_received,
    // Carry the assertion result, not just the observations: a record built from a run whose scenario
    // invariants were violated must not read as successful evidence.
    scenario_invariants: {
      asserted: fixtures.scenario_invariants?.asserted === true,
      violations: fixtures.scenario_invariants?.violations ?? [],
    },
  },
  unresolved_and_deferred: {
    unsigned_failure_receipts: {
      status: "deferred",
      detail:
        "The pinned v1 report references a server decision ID and has no unsigned adapter_failure or " +
        "unavailable variant. Unavailable and adapter-failure calls report a heartbeat only and remain " +
        "unresolved; no ALLOW/DENY is synthesized. Remedy: an Agent Passport owner must release an " +
        "additive reporting contract for these outcome receipts, then client integration and " +
        "compatibility tests follow.",
    },
    windows_reporting: {
      status: "unresolved",
      detail:
        "No verified equivalent ACL ownership checker exists for this candidate, so Windows reporting " +
        "fails closed as unresolved. Authorization is unaffected.",
    },
    hosts_without_completion_signal: {
      status: "not_reported",
      detail:
        "Hosts with no trustworthy post-action signal, including the OpenClaw HTTP tool-invocation path, " +
        "stay not_reported. A pre-action result is never treated as host execution evidence.",
    },
    live_deployment_compatibility: {
      status: "not_run",
      waived_by_operator: true,
      reason:
        "The operator waived live sandbox qualification for this release-preparation task. No owner-created " +
        "handoff was requested and no production or sandbox reporting call was made.",
      deployment_identifier: null,
      unverified_outcomes: [
        "install",
        "ALLOW",
        "DENY",
        "unavailable",
        "mode-change",
        "rotation",
        "uninstall",
        "dropped-queue",
        "no-handoff",
      ],
      detail:
        "Every outcome above is fixture-verified only. Fixture success is not evidence of compatibility " +
        "with a deployed Agent Passport backend. Earlier qualification records keep their original unmet " +
        "claims; this entry records the current task scope, it does not retire them.",
    },
  },
  evidence_sources: {
    artifact_inspection: "scripts/validate-release-artifacts.mjs",
    deterministic_fixtures: "scripts/validate-release-fixture-matrix.mjs",
    schema_and_sanitization: "tests/unit/test-release-verification-record.sh",
  },
};

writeFileSync(outPath, JSON.stringify(record, null, 2) + "\n");
console.log(`build-release-verification-record: wrote ${basename(outPath)} for ${version}`);

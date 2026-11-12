#!/usr/bin/env node
// Schema and sanitization validator for a published release-verification record.
//
// The record lives in Git, so it must contain only bounded allowlisted metadata. This validator enforces
// three things: the required identity is present, every retained value is shaped like metadata rather than
// captured runtime content, and fixture evidence is never presented as a live run.
//
// Usage: node scripts/check-release-verification-record.mjs <record.json>

import { readFileSync } from "node:fs";

const path = process.argv[2];
if (!path) {
  console.error("usage: check-release-verification-record.mjs <record.json>");
  process.exit(2);
}

let record;
try {
  record = JSON.parse(readFileSync(path, "utf8"));
} catch (error) {
  console.error(`record is not readable JSON: ${error.message}`);
  process.exit(1);
}

const problems = [];
const fail = (message) => problems.push(message);

// --- Required identity -------------------------------------------------------------------------------------
if (record.record_schema !== "aport-release-verification/v1") {
  fail(`unexpected record_schema: ${JSON.stringify(record.record_schema)}`);
}
if (!/^\d+\.\d+\.\d+$/.test(record.candidate_version ?? "")) {
  fail("candidate_version must be a release version");
}
if (!/^[0-9a-f]{40}$/.test(record.prepared_from?.source_revision ?? "")) {
  fail("prepared_from.source_revision must be a full git revision");
}
for (const [name, revision] of Object.entries(record.prepared_from?.submodules ?? {})) {
  if (!/^[0-9a-f]{40}$/.test(revision)) fail(`submodule ${name} is not pinned to a full revision`);
}

// Artifacts must be identifiable: name, version, filename and digest.
const artifactGroups = [
  ["npm", record.artifacts?.npm],
  ["python_wheels", record.artifacts?.python_wheels],
];
for (const [group, list] of artifactGroups) {
  if (!Array.isArray(list) || list.length === 0) {
    fail(`artifacts.${group} must list the inspected artifacts`);
    continue;
  }
  for (const entry of list) {
    const label = entry?.filename ?? "(unnamed)";
    if (!entry?.package) fail(`artifacts.${group}: ${label} has no package name`);
    if (entry?.version !== record.candidate_version) {
      fail(`artifacts.${group}: ${label} is ${entry?.version}, expected ${record.candidate_version}`);
    }
    if (!/^[0-9a-f]{64}$/.test(entry?.sha256 ?? "")) {
      fail(`artifacts.${group}: ${label} has no sha256 artifact digest`);
    }
    if (entry?.reporter_bytes_match_source !== true) {
      fail(`artifacts.${group}: ${label} does not record matching reporter bytes`);
    }
  }
}

const enterprise = record.artifacts?.enterprise_bundle;
if (!enterprise || !Array.isArray(enterprise.files) || enterprise.files.length === 0) {
  fail("artifacts.enterprise_bundle must list the bundled files");
} else {
  for (const file of enterprise.files) {
    if (!/^[0-9a-f]{64}$/.test(file?.sha256 ?? "")) {
      fail(`enterprise bundle file ${file?.filename ?? "(unnamed)"} has no sha256`);
    }
  }
}

// Contract identity: a pinned baseline plus the schema digests the client validates against.
if (!/^[0-9a-f]{40}$/.test(record.contract?.baseline_revision ?? "")) {
  fail("contract.baseline_revision must be a full revision");
}
const digests = record.contract?.digests ?? {};
if (Object.keys(digests).length === 0) fail("contract.digests must record the pinned schema digests");
for (const [name, digest] of Object.entries(digests)) {
  if (!/^[0-9a-f]{64}$/.test(digest)) fail(`contract digest ${name} is not a sha256`);
}

// --- Fixture and outcome identity --------------------------------------------------------------------------
const EVIDENCE_CLASSES = new Set(["fixture_response", "injected_fault", "local_only"]);
const outcomes = record.deterministic_validation?.outcomes;
if (!Array.isArray(outcomes) || outcomes.length === 0) {
  fail("deterministic_validation.outcomes must record the validated outcomes");
} else {
  for (const outcome of outcomes) {
    const label = outcome?.outcome ?? "(unnamed)";
    if (!label || typeof label !== "string") fail("an outcome has no name");
    if (!EVIDENCE_CLASSES.has(outcome?.evidence)) {
      // This is also the gate that rejects a fixture outcome relabelled as a live run.
      fail(
        `outcome ${label} has evidence ${JSON.stringify(outcome?.evidence)}; ` +
          `expected one of ${[...EVIDENCE_CLASSES].join(", ")}`,
      );
    }
    if (outcome?.evidence === "fixture_response" && !outcome?.fixture_id) {
      fail(`outcome ${label} is fixture evidence but names no fixture_id`);
    }
    if (outcome?.evidence === "injected_fault" && !outcome?.injected_fault) {
      fail(`outcome ${label} is an injected fault but does not label the fault`);
    }
  }
}

// The fixture run must have asserted its scenario invariants, with none violated. Recorded observations alone
// are diagnostics; without this the record could publish a run that produced the wrong results.
const invariants = record.deterministic_validation?.scenario_invariants;
if (invariants?.asserted !== true) {
  fail("deterministic_validation.scenario_invariants.asserted must be true");
}
if (!Array.isArray(invariants?.violations)) {
  fail("deterministic_validation.scenario_invariants.violations must be a list");
} else if (invariants.violations.length > 0) {
  fail(
    `deterministic_validation.scenario_invariants reports ${invariants.violations.length} violation(s); ` +
      "a violated fixture run is not successful evidence",
  );
}

// --- Live qualification must stay honest -------------------------------------------------------------------
const live = record.unresolved_and_deferred?.live_deployment_compatibility;
if (!live) {
  fail("unresolved_and_deferred.live_deployment_compatibility is required");
} else {
  if (live.status !== "not_run") {
    fail(`live_deployment_compatibility.status is ${JSON.stringify(live.status)}; fixtures cannot establish a live run`);
  }
  if (live.deployment_identifier !== null) {
    fail("live_deployment_compatibility.deployment_identifier must be null when no live run happened");
  }
  if (typeof live.waived_by_operator !== "boolean") {
    fail("live_deployment_compatibility.waived_by_operator must state whether a waiver was recorded");
  }
  if (!Array.isArray(live.unverified_outcomes) || live.unverified_outcomes.length === 0) {
    fail("live_deployment_compatibility must list the outcomes that remain unverified");
  }
}
for (const key of ["unsigned_failure_receipts", "windows_reporting", "hosts_without_completion_signal"]) {
  const entry = record.unresolved_and_deferred?.[key];
  if (!entry?.status || !entry?.detail) fail(`unresolved_and_deferred.${key} must record a status and detail`);
}

// --- Sanitization ------------------------------------------------------------------------------------------
// Keys that indicate captured runtime content rather than metadata.
const FORBIDDEN_KEYS = [
  /^(api_?key|apikey|token|reporter_token|secret|password|passwd|credential|credentials|authorization|bearer)$/i,
  /^(prompt|prompts|system_prompt|user_prompt|message|messages|completion)$/i,
  /^(command|commands|argv|cmd|script|shell)$/i,
  /^(tool_input|tool_output|tool_result|tool_args|arguments|stdin|stdout|stderr|raw|body|payload|response_body)$/i,
  /^(passport|passport_id|agent_id|owner_id|handoff|handoff_file|env|environ)$/i,
];

// Value shapes that must never appear anywhere in the record.
const FORBIDDEN_VALUES = [
  { label: "reporter token", re: /\bair1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{20,}/ },
  { label: "APort API key", re: /\bap_(?:live|test)_[A-Za-z0-9_]{12,}/ },
  { label: "bearer header", re: /\bBearer\s+\S+/i },
  { label: "private key block", re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/ },
  { label: "home directory path", re: /(^|[\s"'=:(])(?:\/Users\/|\/home\/|\/root\/|C:\\Users\\)[^\s"')]+/ },
  { label: "shell invocation", re: /\b(?:curl|wget|ssh|scp|npm publish|twine upload|git push)\b/ },
  { label: "shell redirection or pipeline", re: /\S\s*(?:\|\||&&|\|)\s*\S|\s>\s*\/\S/ },
];

// Authored constants in this repository are allowed to describe behaviour in prose. Only these keys may hold
// explanatory text; everything else must be an identifier, digest, count, boolean or fixed string. Being a
// prose key buys a longer length bound and nothing else: every forbidden value shape is scanned everywhere,
// because the record builder copies outcome strings verbatim, so an exemption here would let real diagnostics
// reach a file committed under docs/reviews/.
const PROSE_KEYS = new Set(["detail", "reason", "note", "network", "credential_material", "kind"]);

// The only literal placeholders prose may contain. These are the documented token-presentation strings from
// the pinned contract, not credentials: the angle brackets are part of the literal. Anything else that matches
// a forbidden shape is rejected even inside prose.
const ALLOWED_PLACEHOLDERS = [
  "Authorization: Bearer <reporter_token>",
  "Bearer <reporter_token>",
];

function withoutAllowedPlaceholders(value) {
  let text = value;
  for (const placeholder of ALLOWED_PLACEHOLDERS) {
    text = text.split(placeholder).join("");
  }
  return text;
}

function walk(value, pathParts) {
  const where = pathParts.join(".") || "(root)";
  if (value === null || typeof value === "boolean" || typeof value === "number") return;

  if (typeof value === "string") {
    const key = pathParts[pathParts.length - 1] ?? "";
    const isProse = PROSE_KEYS.has(String(key).replace(/\[\d+\]$/, ""));
    // Strip only the documented literal placeholders, then scan prose exactly like every other field.
    const scanned = withoutAllowedPlaceholders(value);
    for (const { label, re } of FORBIDDEN_VALUES) {
      if (re.test(scanned)) fail(`${where} contains a ${label}`);
    }
    const limit = isProse ? 2048 : 512;
    if (value.length > limit) fail(`${where} holds an unbounded string (${value.length} chars)`);
    return;
  }

  if (Array.isArray(value)) {
    if (value.length > 256) fail(`${where} holds an unbounded array (${value.length} entries)`);
    value.forEach((entry, index) => walk(entry, [...pathParts, `[${index}]`]));
    return;
  }

  if (typeof value === "object") {
    for (const [key, entry] of Object.entries(value)) {
      for (const pattern of FORBIDDEN_KEYS) {
        if (pattern.test(key)) fail(`${where}.${key} is a forbidden field for a published record`);
      }
      walk(entry, [...pathParts, key]);
    }
    return;
  }

  fail(`${where} has an unsupported value type ${typeof value}`);
}

walk(record, []);

if (problems.length > 0) {
  console.error(`check-release-verification-record: ${problems.length} problem(s) in ${path}`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log(
  `check-release-verification-record: ${path} is a clean ${record.candidate_version} record ` +
    `(${outcomes.length} outcomes, live qualification not run)`,
);

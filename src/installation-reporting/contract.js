'use strict';

// Agent Passport staging merge 6425f967f928f66202cc33489c350d1b99952dc0.
// handoff schema SHA-256: 8698089f04abf76a797a9a2c45308798600de22637ecce6efcee36ae1759c815
// server contract.ts SHA-256: 6f9c8cc5848e05950728a4a08dc37795ff9affc192540ade70d2418372a40e23
// server api.ts SHA-256: eed0448380d43eb56d02717159ce69543453a9be6b5432da9a7e135014668491
// OpenAPI SHA-256: 775903af487a8f80eeaf27b216c237fefb7232742a591ddebbd4e8c16a041976
const INSTALLATION_ID = /^ai_[A-Za-z0-9_-]{1,100}$/;
const SHORT_ID = /^[A-Za-z0-9_-]{8,128}$/;
const DECISION_ID = /^[A-Za-z0-9_-]{1,128}$/;
const DIGEST = /^[a-f0-9]{64}$/;
const VERSION = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$/;
const TOOL_ID = /^[a-z0-9][a-z0-9._-]{0,127}$/;
const DISPOSITIONS = new Set(['allowed', 'blocked', 'continued_after_warning', 'continued_after_observation', 'not_reported']);
const MODES = new Set(['enforce', 'warn', 'observe']);

// Error messages deliberately do not include rejected input.
function invalid() { throw new TypeError('Invalid installation reporting metadata'); }
function object(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) invalid();
  const actual = Reflect.ownKeys(value);
  if (actual.length !== keys.length || actual.some(k => typeof k !== 'string' || !keys.includes(k))) invalid();
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || !('value' in descriptor)) invalid();
  }
}
function string(value, pattern) {
  if (typeof value !== 'string' || value.match(pattern)?.[0] !== value) invalid();
  return value;
}
function timestamp(value) {
  string(value, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/);
  if (!Number.isFinite(Date.parse(value))) invalid();
  return value;
}
function disposition(value) { if (!DISPOSITIONS.has(value)) invalid(); return value; }
function array(value, min, max) {
  if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype || value.length < min || value.length > max ||
      Reflect.ownKeys(value).length !== value.length + 1 ||
      Array.from({ length: value.length }, (_, i) => Object.getOwnPropertyDescriptor(value, String(i)))
        .some(descriptor => !descriptor || !('value' in descriptor))) invalid();
}

function validateHandoff(value, configuredOrigin) {
  object(value, ['schema_version', 'installation_id', 'reporter_endpoint', 'test_result_endpoint', 'token_presentation', 'reporter_token']);
  if (value.schema_version !== 'agent-installation-handoff/v1' || value.token_presentation !== 'Authorization: Bearer <reporter_token>') invalid();
  const id = string(value.installation_id, INSTALLATION_ID);
  let origin;
  if (typeof configuredOrigin !== 'string') invalid();
  try { origin = new URL(configuredOrigin); } catch { invalid(); }
  if (origin.protocol !== 'https:' || origin.username || origin.password || origin.pathname !== '/' || origin.search || origin.hash || origin.origin !== configuredOrigin) invalid();
  const base = `${origin.origin}/api/agent-installations/${id}`;
  if (value.reporter_endpoint !== `${base}/reports` || value.test_result_endpoint !== `${base}/tests/{test_id}/results`) invalid();
  const token = string(value.reporter_token, /^air1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{43}$/);
  if (token.length > 1024) invalid();
  let claims;
  try { claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8')); } catch { invalid(); }
  if (!claims || claims.v !== 1 || claims.installation_id !== id ||
      typeof claims.owner_id !== 'string' || claims.owner_id.match(/^ap_(?:user|org)_[A-Za-z0-9_-]{1,120}$/)?.[0] !== claims.owner_id ||
      !['US', 'EU', 'CA'].includes(claims.region)) invalid();
  return { installation_id: id, reporter_token: token };
}

function serializeReport(value) {
  object(value, ['schema_version', 'event_id', 'timestamp', 'source_id', 'config_digest', 'adapter_version', 'mode', 'reports']);
  if (value.schema_version !== 'agent-installation-report/v1') invalid();
  string(value.event_id, SHORT_ID); timestamp(value.timestamp); string(value.source_id, INSTALLATION_ID);
  string(value.config_digest, DIGEST); string(value.adapter_version, VERSION);
  if (!MODES.has(value.mode)) invalid();
  array(value.reports, 1, 20);
  let hasCoverage = false;
  const reports = value.reports.map(item => {
    if (!item || typeof item !== 'object') invalid();
    const kind = Object.getOwnPropertyDescriptor(item, 'kind');
    if (!kind || !('value' in kind)) invalid();
    if (kind.value === 'heartbeat') { object(item, ['kind']); return { kind: 'heartbeat' }; }
    // Additive v1 variants in the pinned Agent Passport contract.
    if (kind.value === 'declared_coverage') {
      object(item, ['kind', 'source', 'manifest_digest', 'tool_ids']);
      if (hasCoverage || item.source !== 'declared_config') invalid();
      hasCoverage = true;
      string(item.manifest_digest, DIGEST);
      array(item.tool_ids, 0, 200);
      const toolIds = item.tool_ids.map(id => string(id, TOOL_ID));
      if (toolIds.some((id, i) => i > 0 && id <= toolIds[i - 1])) invalid();
      return { kind: 'declared_coverage', source: 'declared_config', manifest_digest: item.manifest_digest, tool_ids: toolIds };
    }
    if (kind.value === 'lifecycle') {
      object(item, ['kind', 'state']);
      if (value.reports.length !== 1 || item.state !== 'removed') invalid();
      return { kind: 'lifecycle', state: 'removed' };
    }
    object(item, ['kind', 'decision_id', 'host_disposition']);
    if (item.kind !== 'decision') invalid();
    return { kind: 'decision', decision_id: string(item.decision_id, DECISION_ID), host_disposition: disposition(item.host_disposition) };
  });
  return JSON.stringify({ schema_version: value.schema_version, event_id: value.event_id, timestamp: value.timestamp,
    source_id: value.source_id, config_digest: value.config_digest, adapter_version: value.adapter_version, mode: value.mode, reports });
}

function serializeTestResult(value) {
  object(value, ['schema_version', 'event_id', 'timestamp', 'source_id', 'challenge', 'decision_id', 'host_disposition', 'config_digest']);
  if (value.schema_version !== 'agent-installation-test-result/v1') invalid();
  return JSON.stringify({ schema_version: value.schema_version, event_id: string(value.event_id, SHORT_ID), timestamp: timestamp(value.timestamp),
    source_id: string(value.source_id, INSTALLATION_ID), challenge: string(value.challenge, /^[a-f0-9-]{72}$/),
    decision_id: string(value.decision_id, DECISION_ID), host_disposition: disposition(value.host_disposition), config_digest: string(value.config_digest, DIGEST) });
}
module.exports = { validateHandoff, serializeReport, serializeTestResult };

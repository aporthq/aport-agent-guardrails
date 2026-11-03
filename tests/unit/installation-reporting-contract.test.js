'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateHandoff, serializeReport, serializeTestResult } = require('../../src/installation-reporting/contract');

const id = 'ai_example';
const origin = 'https://sandbox.aport.io';
const claims = Buffer.from(JSON.stringify({ v: 1, owner_id: 'ap_user_example', region: 'US', installation_id: id })).toString('base64url');
const token = `air1.${claims}.${'A'.repeat(43)}`;
const handoff = { schema_version: 'agent-installation-handoff/v1', installation_id: id,
  reporter_endpoint: `${origin}/api/agent-installations/${id}/reports`,
  test_result_endpoint: `${origin}/api/agent-installations/${id}/tests/{test_id}/results`,
  token_presentation: 'Authorization: Bearer <reporter_token>', reporter_token: token };
const report = { schema_version: 'agent-installation-report/v1', event_id: 'event_123', timestamp: '2026-11-03T12:00:00Z', source_id: id,
  config_digest: 'a'.repeat(64), adapter_version: '1.0.36', mode: 'warn',
  reports: [{ kind: 'heartbeat' }, { kind: 'decision', decision_id: 'decision_1', host_disposition: 'continued_after_warning' }] };
const result = { schema_version: 'agent-installation-test-result/v1', event_id: 'event_123', timestamp: report.timestamp,
  source_id: id, challenge: 'a'.repeat(72), decision_id: 'decision_1', host_disposition: 'blocked', config_digest: report.config_digest };

test('handoff validates scoped endpoints and retains only credential and installation', () => {
  assert.deepEqual(validateHandoff(handoff, origin), { installation_id: id, reporter_token: token });
  for (const bad of [
    { ...handoff, reporter_endpoint: 'https://evil.example/reports' },
    { ...handoff, test_result_endpoint: `${origin}/other` },
    { ...handoff, installation_id: 'ai_other' },
    { ...handoff, reporter_token: 'secret' },
    { ...handoff, extra: 'secret' }
  ]) assert.throws(() => validateHandoff(bad, origin), /Invalid installation reporting metadata/);
  assert.throws(() => validateHandoff(handoff, `${origin}/path`));
});

test('report and test result serialize only pinned contract fields', () => {
  assert.deepEqual(JSON.parse(serializeReport(report)), report);
  assert.deepEqual(JSON.parse(serializeTestResult(result)), result);
  for (const field of ['prompt', 'command', 'arguments', 'path', 'username', 'environment', 'api_key', 'config']) {
    assert.throws(() => serializeReport({ ...report, [field]: 'secret' }), /Invalid installation reporting metadata/);
    assert.throws(() => serializeReport({ ...report, reports: [{ kind: 'heartbeat', [field]: 'secret' }] }));
    assert.throws(() => serializeTestResult({ ...result, [field]: 'secret' }));
  }
});

test('invalid metadata, sparse batches and accessors are rejected locally', () => {
  assert.throws(() => serializeReport({ ...report, reports: Array(1) }));
  const inheritedBatch = [ { kind: 'heartbeat' } ];
  Object.setPrototypeOf(inheritedBatch, { map: () => [{ prompt: 'secret' }] });
  assert.throws(() => serializeReport({ ...report, reports: inheritedBatch }));
  assert.throws(() => serializeReport({ ...report, reports: [{ kind: 'decision', decision_id: 'a', host_disposition: 'denied' }] }));
  assert.throws(() => serializeReport({ ...report, config_digest: '/sensitive/path' }));
  assert.throws(() => serializeReport({ ...report, adapter_version: '1.0.36\n' }));
  assert.throws(() => serializeReport({ ...report, timestamp: '2026-11-03T12:00:00Z\n' }));
  assert.throws(() => serializeReport({ ...report, reports: [{ get kind() { throw Error('getter invoked'); } }] }), /Invalid installation reporting metadata/);
  assert.throws(() => serializeTestResult({ ...result, challenge: 'secret' }));
});

test('declared coverage accepts only sorted unique normalized IDs and a digest', () => {
  const coverage = { kind: 'declared_coverage', source: 'declared_config', manifest_digest: 'b'.repeat(64), tool_ids: ['alpha', 'mcp.tool-1', 'z_2'] };
  const value = { ...report, reports: [{ kind: 'heartbeat' }, coverage] };
  assert.deepEqual(JSON.parse(serializeReport(value)), value);
  assert.deepEqual(JSON.parse(serializeReport({ ...report, reports: [{ ...coverage, tool_ids: [] }] })).reports[0].tool_ids, []);
  for (const invalidIds of [ ['z', 'a'], ['a', 'a'], ['A'], ['a/url'], ['a\n'], Array(1), Array(201).fill('a') ]) {
    assert.throws(() => serializeReport({ ...report, reports: [{ ...coverage, tool_ids: invalidIds }] }), /Invalid installation reporting metadata/);
  }
  for (const invalidCoverage of [
    { ...coverage, source: 'observed' }, { ...coverage, manifest_digest: 'invalid' },
    { ...coverage, description: 'private text' }, { ...coverage, tool_ids: ['x'.repeat(129)] }
  ]) assert.throws(() => serializeReport({ ...report, reports: [invalidCoverage] }));
  assert.throws(() => serializeReport({ ...report, reports: [coverage, coverage] }));
  const accessorIds = ['safe'];
  Object.defineProperty(accessorIds, '0', { get() { throw Error('getter invoked'); } });
  assert.throws(() => serializeReport({ ...report, reports: [{ ...coverage, tool_ids: accessorIds }] }), /Invalid installation reporting metadata/);
});

test('removal is the only event in its batch', () => {
  const removal = { kind: 'lifecycle', state: 'removed' };
  assert.deepEqual(JSON.parse(serializeReport({ ...report, reports: [removal] })).reports, [removal]);
  for (const invalidReports of [
    [removal, { kind: 'heartbeat' }], [{ ...removal, state: 'suspended' }], [{ ...removal, path: '/private' }]
  ]) assert.throws(() => serializeReport({ ...report, reports: invalidReports }), /Invalid installation reporting metadata/);
});

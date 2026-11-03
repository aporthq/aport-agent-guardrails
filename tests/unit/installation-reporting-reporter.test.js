'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { InstallationReporter } = require('../../src/installation-reporting/reporter');
const origin = 'https://sandbox.aport.io';
const id = 'ai_example';
const envelope = Buffer.from(JSON.stringify({ v: 1, owner_id: 'ap_user_example', region: 'US', installation_id: id })).toString('base64url');
const handoff = { schema_version: 'agent-installation-handoff/v1', installation_id: id,
  reporter_endpoint: `${origin}/api/agent-installations/${id}/reports`, test_result_endpoint: `${origin}/api/agent-installations/${id}/tests/{test_id}/results`,
  token_presentation: 'Authorization: Bearer <reporter_token>', reporter_token: `air1.${envelope}.${'A'.repeat(43)}` };
const report = { schema_version: 'agent-installation-report/v1', event_id: 'event_123', timestamp: '2026-11-03T12:00:00Z', source_id: id,
  config_digest: 'a'.repeat(64), adapter_version: '1.0.36', mode: 'enforce', reports: [{ kind: 'heartbeat' }] };
const result = { schema_version: 'agent-installation-test-result/v1', event_id: 'event_234', timestamp: report.timestamp, source_id: id,
  challenge: 'a'.repeat(72), decision_id: 'decision_1', host_disposition: 'blocked', config_digest: report.config_digest };
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
function accepted(url, init) {
  const body = JSON.parse(init.body);
  const payload = url.endsWith('/reports') ? { event_id: body.event_id, accepted: body.reports.length } : { test_id: url.split('/').at(-2), result: 'passed' };
  return new Response(JSON.stringify(payload), { status: 200 });
}
async function until(predicate) {
  for (let i = 0; i < 300; i++) { if (predicate()) return; await wait(10); }
  assert.fail('reporter did not finish');
}

test('queues validated receipts and only sends to scoped reporter endpoints', async () => {
  const calls = [];
  const sender = new InstallationReporter(handoff, origin, { fetch: async (url, init) => { calls.push({ url, init }); return accepted(url, init); } });
  sender.enqueueReport(report);
  sender.enqueueTestResult('ait_example', result);
  assert.equal(calls.length, 0, 'network must not run in enqueue');
  await until(() => calls.length === 2 && sender.status().state === 'connected');
  assert.deepEqual(calls.map(call => call.url), [`${origin}/api/agent-installations/${id}/reports`, `${origin}/api/agent-installations/${id}/tests/ait_example/results`]);
  for (const call of calls) {
    assert.equal(call.init.method, 'POST');
    assert.equal(call.init.redirect, 'error');
    assert.equal(call.init.headers.Authorization, `Bearer ${handoff.reporter_token}`);
    assert.match(call.init.headers['Idempotency-Key'], /^[A-Za-z0-9_-]{8,128}$/);
  }
  assert.throws(() => sender.enqueueReport({ ...report, source_id: 'ai_other' }));
  assert.throws(() => sender.enqueueTestResult('../outside', result));
  assert.equal(sender.enqueue, undefined, 'raw request bodies and paths cannot bypass the serializer');
  assert.equal(sender.token, undefined, 'reporter credential is not exposed as a public property');
});

test('queue pressure drops oldest waiting metadata without sending synchronously', async () => {
  const events = [];
  const sender = new InstallationReporter(handoff, origin, { maxQueue: 2, fetch: async (url, init) => { events.push(JSON.parse(init.body).event_id); return accepted(url, init); } });
  for (const event_id of ['event_001', 'event_002', 'event_003']) sender.enqueueReport({ ...report, event_id });
  assert.deepEqual(sender.status(), { state: 'unresolved', queued: 2, dropped: 1 });
  assert.deepEqual(events, []);
  await until(() => events.length === 2);
  assert.deepEqual(events, ['event_002', 'event_003']);
});

test('old-server errors are reporting-only and leave a visible unresolved count', async () => {
  const sender = new InstallationReporter(handoff, origin, { fetch: async () => ({ status: 400 }) });
  assert.doesNotThrow(() => sender.enqueueReport(report));
  await until(() => sender.status().dropped === 1);
  assert.deepEqual(sender.status(), { state: 'unresolved', queued: 0, dropped: 1 });
});

test('unavailable reporting retries with the same idempotency key', async () => {
  const keys = [];
  const sender = new InstallationReporter(handoff, origin, { maxAttempts: 2, fetch: async (_url, init) => { keys.push(init.headers['Idempotency-Key']); throw new Error('unavailable'); } });
  sender.enqueueReport(report);
  await until(() => keys.length === 2 && sender.status().dropped === 1);
  assert.equal(keys[0], keys[1]);
  assert.equal(sender.status().state, 'unresolved');
});

test('a stalled reporting request expires without blocking enqueue', async () => {
  let signal;
  const sender = new InstallationReporter(handoff, origin, { timeoutMs: 10, maxAttempts: 1, fetch: (_url, init) => { signal = init.signal; return new Promise(() => {}); } });
  assert.doesNotThrow(() => sender.enqueueReport(report));
  await until(() => sender.status().dropped === 1);
  assert.equal(signal.aborted, true);
  assert.equal(sender.status().state, 'unresolved');
});

test('retry pressure discards the oldest in-flight receipt before newer queued receipts', async () => {
  const events = [];
  let rejectFirst;
  const sender = new InstallationReporter(handoff, origin, { maxQueue: 2, fetch: (url, init) => {
    events.push(JSON.parse(init.body).event_id);
    if (events.length === 1) return new Promise((_, reject) => { rejectFirst = reject; });
    return Promise.resolve(accepted(url, init));
  } });
  sender.enqueueReport({ ...report, event_id: 'event_001' });
  await until(() => Boolean(rejectFirst));
  sender.enqueueReport({ ...report, event_id: 'event_002' });
  sender.enqueueReport({ ...report, event_id: 'event_003' });
  rejectFirst(new Error('unavailable'));
  await until(() => events.length === 3);
  assert.deepEqual(events, ['event_001', 'event_002', 'event_003']);
  assert.equal(sender.status().dropped, 1);
});

test('a successful HTTP status without a matching receipt does not claim connection', async () => {
  for (const payload of ['not json', JSON.stringify({ event_id: 'wrong', accepted: 1 }), 'x'.repeat(8193)]) {
    const sender = new InstallationReporter(handoff, origin, { maxAttempts: 1, fetch: async () => new Response(payload, { status: 200 }) });
    sender.enqueueReport(report);
    await until(() => sender.status().dropped === 1);
    assert.equal(sender.status().state, 'unresolved');
  }
});

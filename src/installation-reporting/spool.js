'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const { noSymlinkComponents, readProtected, supportedFramework } = require('./binding');
const { serializeReport, validateHandoff } = require('./contract');
const { handoffFor, deliver } = require('./transport');

const LIMITS = Object.freeze({ count: 100, bytes: 1048576, receiptBytes: 32768, ageMs: 60000, attempts: 3, timeoutMs: 3000, lockWaitMs: 1000 });
const fail = () => { throw Error('Reporting state unresolved'); };
function directory(dir, create = false) {
  if (create) {
    noSymlinkComponents(path.dirname(dir));
    try { fs.mkdirSync(dir, { mode: 0o700 }); } catch (e) { if (e.code !== 'EEXIST') throw e; }
  }
  noSymlinkComponents(dir);
  const stat = fs.lstatSync(dir);
  if (!stat.isDirectory() || (stat.mode & 0o077) || typeof process.getuid !== 'function' || stat.uid !== process.getuid()) fail();
  return stat;
}
function atomic(dir, name, value, maxBytes) {
  directory(dir);
  const target = path.join(dir, name);
  try { readProtected(target, maxBytes); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  const data = JSON.stringify(value);
  if (Buffer.byteLength(data) > maxBytes) fail();
  const tmp = path.join(dir, `.${randomUUID()}.tmp`);
  let fd;
  try {
    fd = fs.openSync(tmp, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
    fs.writeFileSync(fd, data); fs.fsyncSync(fd); fs.closeSync(fd); fd = undefined;
    fs.renameSync(tmp, target);
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
    try { fs.unlinkSync(tmp); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  }
}
function locked(dir, fn) {
  const before = directory(dir);
  const lock = path.join(dir, 'queue.lock');
  try { fs.mkdirSync(lock, { mode: 0o700 }); }
  catch (e) {
    if (e.code !== 'EEXIST') throw e;
    // A competing holder may release between mkdir and validation. Retry that
    // race too; every attempt still validates before acquiring its own lock.
    try { directory(lock); }
    catch (validation) { if (validation.code !== 'ENOENT') throw validation; }
    throw Object.assign(Error('Reporting queue busy'), { code: 'APORT_REPORTING_QUEUE_BUSY' });
  }
  try {
    const after = directory(dir);
    if (before.ino !== after.ino || before.dev !== after.dev) fail();
    return fn();
  } finally { fs.rmdirSync(lock); }
}
// Authorization producers remain nonblocking. Workers and committed lifecycle
// changes may wait for a current holder; neither removes nor steals its lock.
// Lifecycle callers share one deadline across all installation scopes.
async function retryQueueLock(operation, deadline = Date.now() + LIMITS.lockWaitMs) {
  for (;;) {
    try { return operation(); }
    catch (e) {
      if (e.code !== 'APORT_REPORTING_QUEUE_BUSY' || Date.now() >= deadline) throw e;
      await new Promise(resolve => setTimeout(resolve, Math.min(25, deadline - Date.now())));
    }
  }
}
function authority(dir) {
  directory(path.dirname(dir));
  directory(dir);
  const value = JSON.parse(readProtected(path.join(dir, 'authority.json'), 4096));
  if (Object.keys(value).sort().join(',') !== 'binding,framework,origin' ||
      !supportedFramework(value.framework)) fail();
  validateHandoff(handoffFor(value.binding, value.origin), value.origin);
  return value;
}
function state(dir, id) {
  let q;
  try { q = JSON.parse(readProtected(path.join(dir, 'queue.json'), LIMITS.bytes)); }
  catch (e) { if (e.code !== 'ENOENT') throw e; return { state: 'unverified', dropped: 0, items: [], mode: 'enforce' }; }
  if (Object.keys(q).sort().join(',') !== 'dropped,items,mode,state' || !['enforce', 'warn', 'observe'].includes(q.mode) || !Number.isSafeInteger(q.dropped) || q.dropped < 0 ||
      !['unverified', 'connected', 'unresolved'].includes(q.state) || !Array.isArray(q.items) || q.items.length > LIMITS.count) fail();
  for (const item of q.items) {
    if (Object.keys(item).sort().join(',') !== 'attempts,created,key,receipt' ||
        !Number.isSafeInteger(item.created) || item.created > Date.now() + 1000 || item.created < 0 ||
        !Number.isInteger(item.attempts) || item.attempts < 0 || item.attempts > LIMITS.attempts ||
        typeof item.key !== 'string' || !/^[a-f0-9-]{36}$/.test(item.key) || item.receipt.source_id !== id ||
        Buffer.byteLength(serializeReport(item.receipt)) > LIMITS.receiptBytes) fail();
  }
  return q;
}
function discard(q) { q.items.shift(); q.dropped = Math.min(Number.MAX_SAFE_INTEGER, q.dropped + 1); q.state = 'unresolved'; }
function expire(q) {
  while (q.items.length && (Date.now() - q.items[0].created >= LIMITS.ageMs || q.items[0].attempts >= LIMITS.attempts)) discard(q);
}
function provision(dir, value) {
  directory(path.dirname(dir), true); directory(dir, true);
  validateHandoff(handoffFor(value.binding, value.origin), value.origin);
  locked(dir, () => {
    try {
      const previous = authority(dir);
      if (previous.origin !== value.origin || previous.framework !== value.framework || previous.binding.installation_id !== value.binding.installation_id) fail();
    } catch (e) { if (e.code !== 'ENOENT') throw e; }
    atomic(dir, 'authority.json', value, 4096);
    for (const name of ['retiring.json', 'final-status.json']) {
      try { readProtected(path.join(dir, name), 1024); fs.unlinkSync(path.join(dir, name)); }
      catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
  });
}
function enqueue(dir, receipt, { launch = true } = {}) {
  // Serialize before touching disk; callers cannot smuggle additional fields.
  const serialized = serializeReport(receipt);
  if (Buffer.byteLength(serialized) > LIMITS.receiptBytes) fail();
  locked(dir, () => {
    const a = authority(dir);
    if (receipt.source_id !== a.binding.installation_id) fail();
    const q = state(dir, a.binding.installation_id);
    expire(q);
    q.mode = receipt.mode;
    if (q.items.length >= LIMITS.count) discard(q);
    q.items.push({ key: randomUUID(), created: Date.now(), attempts: 0, receipt: JSON.parse(serialized) });
    while (Buffer.byteLength(JSON.stringify(q)) > LIMITS.bytes) discard(q);
    atomic(dir, 'queue.json', q, LIMITS.bytes);
    if (receipt.reports.length === 1 && receipt.reports[0].kind === 'lifecycle') {
      atomic(dir, 'retiring.json', { created: Date.now() }, 1024);
    }
  });
  if (launch) startWorker(dir);
}
function readStatus(dir) {
  directory(path.dirname(dir)); directory(dir);
  try {
    const final = JSON.parse(readProtected(path.join(dir, 'final-status.json'), 1024));
    if (Object.keys(final).sort().join(',') !== 'dropped,queued,state' || final.queued !== 0 ||
        !['connected', 'unresolved'].includes(final.state) || !Number.isSafeInteger(final.dropped) || final.dropped < 0) fail();
    return final;
  } catch (e) { if (e.code !== 'ENOENT') throw e; }
  const a = authority(dir);
  return locked(dir, () => {
    const q = state(dir, a.binding.installation_id);
    expire(q); atomic(dir, 'queue.json', q, LIMITS.bytes);
    let stale = false;
    try { const s = directory(path.join(dir, 'worker.lock')); stale = Date.now() - s.mtimeMs > LIMITS.ageMs + LIMITS.timeoutMs; }
    catch (e) { if (e.code !== 'ENOENT') stale = true; }
    return { state: stale || q.dropped ? 'unresolved' : q.state, queued: q.items.length, dropped: q.dropped };
  });
}
function status(dir) {
  try { return readStatus(dir); }
  catch { return { state: 'unresolved', queued: null, dropped: null }; }
}
function workerStatus(dir) { return retryQueueLock(() => readStatus(dir)); }
function startWorker(dir) {
  directory(dir);
  const lock = path.join(dir, 'worker.lock');
  try { fs.mkdirSync(lock, { mode: 0o700 }); } catch (e) { if (e.code === 'EEXIST') return; throw e; }
  try {
    // Only a protected spool locator crosses argv. No inherited prompts, tool
    // data, verification credentials, NODE_OPTIONS, or TLS overrides.
    const child = spawn(process.execPath, [path.join(__dirname, 'worker.js'), dir], {
      detached: true, stdio: 'ignore', env: { PATH: process.env.PATH || '' }
    });
    child.once('error', () => { try { fs.rmdirSync(lock); } catch { /* unresolved */ } });
    child.unref();
  } catch { fs.rmdirSync(lock); fail(); }
}
async function drain(dir, options = {}) {
  const deadline = Date.now() + LIMITS.ageMs;
  while (Date.now() < deadline) {
    const a = authority(dir);
    const item = await retryQueueLock(() => locked(dir, () => {
      const q = state(dir, a.binding.installation_id); expire(q);
      const next = q.items[0];
      if (next) next.attempts++;
      atomic(dir, 'queue.json', q, LIMITS.bytes);
      return next;
    }));
    if (!item) { await retryQueueLock(() => retire(dir)); return; }
    const result = await deliver(a.binding, a.origin, item.receipt, undefined, item.key, { ...options, timeoutMs: LIMITS.timeoutMs });
    await retryQueueLock(() => locked(dir, () => {
      const q = state(dir, a.binding.installation_id);
      // Pressure may discard an in-flight oldest receipt. Never remove its successor.
      if (q.items[0]?.key === item.key) {
        if (result.accepted) { q.items.shift(); q.state = q.dropped ? 'unresolved' : 'connected'; }
        else if (!result.retry || item.attempts >= LIMITS.attempts) discard(q);
        else q.state = 'unresolved';
      }
      atomic(dir, 'queue.json', q, LIMITS.bytes);
    }));
    if (result.retry) await new Promise(resolve => setTimeout(resolve, 1000 * item.attempts));
  }
  await retryQueueLock(() => retire(dir));
}
function retire(dir) {
  locked(dir, () => {
    let marker;
    try { marker = JSON.parse(readProtected(path.join(dir, 'retiring.json'), 1024)); }
    catch (e) { if (e.code === 'ENOENT') return; throw e; }
    if (Object.keys(marker).join(',') !== 'created' || !Number.isSafeInteger(marker.created) || marker.created > Date.now()) fail();
    const a = authority(dir), q = state(dir, a.binding.installation_id);
    expire(q);
    atomic(dir, 'queue.json', q, LIMITS.bytes);
    if (q.items.length) return;
    // Successful removal or exhausted bounded retries: retain only a sanitized
    // terminal status, and erase the delivery copy of the reporting credential.
    atomic(dir, 'final-status.json', { state: q.dropped ? 'unresolved' : q.state, queued: 0, dropped: q.dropped }, 1024);
    readProtected(path.join(dir, 'authority.json'), 4096);
    fs.unlinkSync(path.join(dir, 'authority.json'));
  });
}
function forgetCredential(dir) {
  locked(dir, () => {
    const a = authority(dir), q = state(dir, a.binding.installation_id);
    while (q.items.length) discard(q);
    q.state = 'unresolved';
    atomic(dir, 'queue.json', q, LIMITS.bytes);
    atomic(dir, 'final-status.json', { state: 'unresolved', queued: 0, dropped: q.dropped }, 1024);
    readProtected(path.join(dir, 'authority.json'), 4096);
    fs.unlinkSync(path.join(dir, 'authority.json'));
  });
}
// Correlate only host-provided opaque call IDs (already hashed at the adapter
// boundary). The server decision ID remains the policy/disposition join key.
function correlation(dir, key, value) {
  if (typeof key !== 'string' || !/^[a-f0-9]{64}$/.test(key)) fail();
  return locked(dir, () => {
    let entries = [];
    try { entries = JSON.parse(readProtected(path.join(dir, 'pending.json'), 65536)); }
    catch (e) { if (e.code !== 'ENOENT') throw e; }
    if (!Array.isArray(entries) || entries.length > 100) fail();
    for (const e of entries) {
      if (Object.keys(e).sort().join(',') !== 'allow,ambiguous,created,decision_id,key,mode' || typeof e.ambiguous !== 'boolean' ||
          !/^[a-f0-9]{64}$/.test(e.key) || typeof e.allow !== 'boolean' ||
          !Number.isSafeInteger(e.created) || e.created > Date.now() + 1000 ||
          !['enforce', 'warn', 'observe'].includes(e.mode) || typeof e.decision_id !== 'string' ||
          !/^[A-Za-z0-9_-]{1,128}$/.test(e.decision_id)) fail();
    }
    entries = entries.filter(e => Date.now() - e.created < LIMITS.ageMs);
    const found = entries.find(e => e.key === key);
    entries = entries.filter(e => e.key !== key);
    if (found) {
      // Keep a tombstone for the entire correlation window. Neither a duplicate
      // pre-call nor a repeated callback may revive an earlier association.
      entries.push({ ...found, ambiguous: true });
    } else if (value) {
      const e = { key, created: Date.now(), ambiguous: false, ...value };
      if (typeof e.allow !== 'boolean' || !['enforce', 'warn', 'observe'].includes(e.mode) ||
          typeof e.decision_id !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(e.decision_id)) fail();
      entries.push(e);
      if (entries.length > 100) entries.shift();
    }
    atomic(dir, 'pending.json', entries, 65536);
    return found && !found.ambiguous && !value ? found : undefined;
  });
}
function currentMode(dir) { return state(dir, authority(dir).binding.installation_id).mode; }
module.exports = { LIMITS, directory, provision, enqueue, status, workerStatus, startWorker, drain, authority, correlation, currentMode, forgetCredential, retryQueueLock };

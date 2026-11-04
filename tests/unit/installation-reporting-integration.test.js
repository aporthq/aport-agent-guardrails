'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync, spawn } = require('node:child_process');
const { createHash } = require('node:crypto');
const runtime = require('../../src/installation-reporting/runtime');
const spool = require('../../src/installation-reporting/spool');
const { bindHandoff } = require('../../src/installation-reporting/binding');
const root = path.resolve(__dirname, '../..');
const hash = value => createHash('sha256').update(value).digest('hex');

function fixture(t, framework = 'codex', activeWorker = false) {
  const base = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'aport-report-')));
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));
  const configDir = path.join(base, 'config'); fs.mkdirSync(configDir); fs.mkdirSync(path.join(configDir, 'aport'), { mode: 0o700 });
  const options = { configDir, framework, passportId: 'ap_fixture', apiUrl: 'https://127.0.0.1:1', authMode: 'api', mode: 'enforce' };
  const id = 'ai_fixture';
  const claims = Buffer.from(JSON.stringify({ v: 1, owner_id: 'ap_user_fixture', region: 'US', installation_id: id })).toString('base64url');
  const binding = { installation_id: id, reporter_token: `air1.${claims}.${'A'.repeat(43)}` };
  const handoff = { schema_version: 'agent-installation-handoff/v1', ...binding,
    reporter_endpoint: `${options.apiUrl}/api/agent-installations/${id}/reports`,
    test_result_endpoint: `${options.apiUrl}/api/agent-installations/${id}/tests/{test_id}/results`, token_presentation: 'Authorization: Bearer <reporter_token>' };
  const handoffFile = path.join(base, 'handoff.json'); fs.writeFileSync(handoffFile, JSON.stringify(handoff), { mode: 0o600 });
  const loc = runtime.location(options);
  bindHandoff({ ...loc, framework, passportId: options.passportId, handoffFile });
  spool.provision(loc.dir, { binding, framework, origin: loc.origin });
  if (!activeWorker) fs.mkdirSync(path.join(loc.dir, 'worker.lock'), { mode: 0o700 }); // Pause delivery, not serialization.
  const env = { ...process.env, APORT_CONFIG_DIR: configDir, APORT_HOOK_FRAMEWORK: framework,
    APORT_GUARDRAIL_MODE: 'api', APORT_AGENT_ID: 'ap_fixture', APORT_API_URL: options.apiUrl,
    APORT_ENFORCEMENT_MODE: 'enforce', APORT_REPORTING_DISABLED: '0' };
  const queue = () => JSON.parse(fs.readFileSync(path.join(loc.dir, 'queue.json'), 'utf8'));
  return { base, options, loc, binding, handoff, handoffFile, env, queue };
}
function cli(f, command, value) {
  return spawnSync(process.execPath, [path.join(root, 'src/installation-reporting/cli.js'), command],
    { env: f.env, encoding: 'utf8', input: value === undefined ? '' : JSON.stringify(value), timeout: 5000 });
}
function workerExit(t, f, extraArgs = []) {
  const worker = spawn(process.execPath, [...extraArgs, path.join(root, 'src/installation-reporting/worker.js'), f.loc.dir],
    { env: { PATH: process.env.PATH }, stdio: 'ignore' });
  t.after(() => { if (worker.exitCode === null) worker.kill(); });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { worker.kill(); reject(Error('Worker did not finish')); }, 15000);
    worker.once('error', e => { clearTimeout(timer); reject(e); });
    worker.once('exit', code => { clearTimeout(timer); resolve(code); });
  });
}
function managementWithLock(t, f, args, lock) {
  const marker = path.join(f.base, 'lock-attempts');
  const preload = path.join(f.base, 'observe-lock.cjs');
  // Observe actual acquisition attempts without replacing the lock or reporter.
  fs.writeFileSync(preload, `
    const fs = require('node:fs'), mkdir = fs.mkdirSync;
    fs.mkdirSync = function(target, ...args) {
      if (target === ${JSON.stringify(lock)}) fs.appendFileSync(${JSON.stringify(marker)}, 'x');
      return mkdir.call(this, target, ...args);
    };
  `);
  fs.writeFileSync(path.join(f.options.configDir, 'openclaw.json'), JSON.stringify({ plugins: { entries: { 'openclaw-aport': {
    config: { mode: 'api', agentId: f.options.passportId, apiUrl: f.options.apiUrl }
  } } } }));
  const child = spawn('bash', [path.join(root, 'bin/agent-guardrails'), ...args], {
    env: { ...f.env, HOME: f.base, APORT_OPENCLAW_CONFIG_DIR: f.options.configDir, NODE_OPTIONS: `--require=${preload}` },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.on('data', chunk => { output += chunk; });
  t.after(() => { if (child.exitCode === null) child.kill(); });
  const exited = new Promise((resolve, reject) => {
    const timer = setTimeout(() => { child.kill(); reject(Error('Management command did not finish')); }, 10000);
    child.once('error', e => { clearTimeout(timer); reject(e); });
    child.once('exit', code => { clearTimeout(timer); resolve({ code, output }); });
  });
  return { exited, marker, async contended() {
    const deadline = Date.now() + 5000;
    while (!fs.existsSync(marker)) {
      assert.ok(child.exitCode === null && Date.now() < deadline, `Management command never attempted queue lock: ${output}`);
      await new Promise(resolve => setTimeout(resolve, 10));
    }
  } };
}
test('real reset retries producer contention and retires its removal credential', async t => {
  const f = fixture(t, 'openclaw'); runtime.report(f.options, 'before_reset');
  const lock = path.join(f.loc.dir, 'queue.lock'); fs.mkdirSync(lock, { mode: 0o700 });
  const inode = fs.statSync(lock).ino;
  const command = managementWithLock(t, f, ['reset', 'openclaw', '--yes'], lock);
  await command.contended();
  assert.ok(!fs.existsSync(path.join(f.options.configDir, 'aport')), 'RESET_COMMITS_BEFORE_REPORTING_RETRY');
  await new Promise(resolve => setTimeout(resolve, 75));
  assert.equal(fs.statSync(lock).ino, inode, 'LIFECYCLE_DOES_NOT_STEAL_QUEUE_LOCK');
  fs.rmdirSync(lock);
  const result = await command.exited; assert.equal(result.code, 0, result.output);
  assert.deepEqual(f.queue().items.at(-1).receipt.reports, [{ kind: 'lifecycle', state: 'removed' }], 'CONTENDED_RESET_ENQUEUES_REMOVAL');
  assert.ok(fs.existsSync(path.join(f.loc.dir, 'retiring.json')), 'CONTENDED_RESET_MARKS_RETIREMENT');
  const delivered = [];
  await spool.drain(f.loc.dir, { fetch: async (_url, init) => {
    const receipt = JSON.parse(init.body); delivered.push(...receipt.reports);
    return new Response(JSON.stringify({ event_id: receipt.event_id, accepted: receipt.reports.length }));
  } });
  assert.deepEqual(delivered.at(-1), { kind: 'lifecycle', state: 'removed' }, 'CONTENDED_RESET_DELIVERS_REMOVAL');
  assert.ok(!fs.existsSync(path.join(f.loc.dir, 'authority.json')), 'CONTENDED_RESET_RETIRES_CREDENTIAL');
});
test('real disabled reset retries contention before erasing its delivery credential', async t => {
  const f = fixture(t, 'openclaw'); runtime.report(f.options, 'before_disabled_reset');
  f.env.APORT_REPORTING_DISABLED = '1';
  const lock = path.join(f.loc.dir, 'queue.lock'); fs.mkdirSync(lock, { mode: 0o700 });
  const command = managementWithLock(t, f, ['reset', 'openclaw', '--yes'], lock);
  await command.contended();
  assert.ok(!fs.existsSync(path.join(f.options.configDir, 'aport')));
  await new Promise(resolve => setTimeout(resolve, 75)); fs.rmdirSync(lock);
  const result = await command.exited; assert.equal(result.code, 0, result.output);
  assert.ok(!fs.existsSync(path.join(f.loc.dir, 'authority.json')), 'CONTENDED_DISABLED_RESET_ERASES_CREDENTIAL');
  assert.deepEqual(spool.status(f.loc.dir), { state: 'unresolved', queued: 0, dropped: 1 });
  assert.ok(!fs.existsSync(path.join(f.loc.dir, 'retiring.json')), 'DISABLED_RESET_DOES_NOT_REPORT');
});
test('real mode change retries contention after committing the selected mode', async t => {
  const f = fixture(t, 'openclaw'); runtime.report(f.options, 'before_mode');
  const lock = path.join(f.loc.dir, 'queue.lock'); fs.mkdirSync(lock, { mode: 0o700 });
  const command = managementWithLock(t, f, ['mode', 'openclaw', '--enforcement=observe'], lock);
  await command.contended();
  assert.match(fs.readFileSync(path.join(f.options.configDir, 'aport/guardrail-mode.env'), 'utf8'), /observe/, 'MODE_COMMITS_BEFORE_REPORTING_RETRY');
  await new Promise(resolve => setTimeout(resolve, 75)); fs.rmdirSync(lock);
  const result = await command.exited; assert.equal(result.code, 0, result.output);
  const receipt = f.queue().items.at(-1).receipt;
  assert.equal(receipt.mode, 'observe', 'CONTENDED_MODE_REPORTS_COMMITTED_MODE');
  assert.deepEqual(receipt.reports, [{ kind: 'heartbeat' }]);
});
test('real reset shares one contention deadline across scopes without rolling back cleanup', async t => {
  const f = fixture(t, 'openclaw'); runtime.report(f.options, 'before_persistent_lock');
  const dirs = [f.loc.dir];
  for (let i = 0; i < 3; i++) {
    const dir = runtime.location({ ...f.options, passportId: `ap_old_${i}` }).dir;
    spool.provision(dir, spool.authority(f.loc.dir)); dirs.push(dir);
  }
  const locks = dirs.map(dir => {
    const lock = path.join(dir, 'queue.lock'); fs.mkdirSync(lock, { mode: 0o700 });
    return { lock, inode: fs.statSync(lock).ino };
  });
  const start = Date.now();
  const command = managementWithLock(t, f, ['reset', 'openclaw', '--yes'], locks[0].lock);
  const result = await command.exited; assert.equal(result.code, 0, result.output);
  assert.ok(Date.now() - start < 3000, 'LIFECYCLE_ONE_BOUNDED_DEADLINE');
  assert.ok(!fs.existsSync(path.join(f.options.configDir, 'aport')), 'CONTENTION_NEVER_ROLLS_BACK_RESET');
  for (const { lock, inode } of locks) assert.equal(fs.statSync(lock).ino, inode, 'LIFECYCLE_PRESERVES_PERSISTENT_LOCK');
  assert.deepEqual(spool.status(f.loc.dir), { state: 'unresolved', queued: null, dropped: null });
  assert.ok(fs.existsSync(path.join(f.loc.dir, 'authority.json')), 'PERSISTENT_CONTENTION_REQUIRES_RECOVERY');
  assert.ok(!fs.existsSync(path.join(f.loc.dir, 'retiring.json')));
});
test('real reset rejects unsafe locks immediately without retrying or altering them', async t => {
  for (const kind of ['symlink', 'permissions']) await t.test(kind, async t => {
    const f = fixture(t, 'openclaw'); runtime.report(f.options, 'before_unsafe_lock');
    const lock = path.join(f.loc.dir, 'queue.lock');
    if (kind === 'symlink') {
      const target = path.join(f.base, 'lock-target'); fs.mkdirSync(target, { mode: 0o700 }); fs.symlinkSync(target, lock);
    } else {
      fs.mkdirSync(lock, { mode: 0o700 }); fs.chmodSync(lock, 0o755);
    }
    const before = fs.lstatSync(lock);
    const command = managementWithLock(t, f, ['reset', 'openclaw', '--yes'], lock);
    const result = await command.exited; assert.equal(result.code, 0, result.output);
    assert.equal(fs.readFileSync(command.marker, 'utf8'), 'x', 'UNSAFE_LIFECYCLE_LOCK_NOT_RETRIED');
    const after = fs.lstatSync(lock);
    assert.equal(after.ino, before.ino); assert.equal(after.mode, before.mode);
    assert.ok(!fs.existsSync(path.join(f.options.configDir, 'aport')));
    assert.equal(f.queue().items.length, 1);
    assert.deepEqual(spool.status(f.loc.dir), { state: 'unresolved', queued: null, dropped: null });
  });
});
test('real reset preserves a reinstall that appears during lifecycle contention', async t => {
  for (const disabled of ['0', '1']) await t.test(`reporting disabled=${disabled}`, async t => {
    const f = fixture(t, 'openclaw'); runtime.report(f.options, 'before_reinstall');
    f.env.APORT_REPORTING_DISABLED = disabled;
    const lock = path.join(f.loc.dir, 'queue.lock'); fs.mkdirSync(lock, { mode: 0o700 });
    const command = managementWithLock(t, f, ['reset', 'openclaw', '--yes'], lock);
    await command.contended();
    const installed = path.join(f.options.configDir, 'aport');
    assert.ok(!fs.existsSync(installed)); fs.mkdirSync(installed, { mode: 0o700 });
    fs.writeFileSync(path.join(installed, 'new-install'), 'preserve');
    fs.rmdirSync(lock);
    const result = await command.exited; assert.equal(result.code, 0, result.output);
    assert.equal(fs.readFileSync(path.join(installed, 'new-install'), 'utf8'), 'preserve');
    assert.ok(fs.existsSync(path.join(f.loc.dir, 'authority.json')), 'REINSTALL_PRESERVES_CREDENTIAL');
    assert.equal(f.queue().items.length, 1, 'REINSTALL_SUPPRESSES_STALE_REMOVAL');
    assert.ok(!fs.existsSync(path.join(f.loc.dir, 'retiring.json')));
  });
});
test('real worker retries a competing queue lock and retires an uninstall receipt', async t => {
  const f = fixture(t);
  fs.rmSync(path.join(f.options.configDir, 'aport'), { recursive: true });
  assert.equal(cli(f, 'removed').status, 0);
  const lock = path.join(f.loc.dir, 'queue.lock'); fs.mkdirSync(lock, { mode: 0o700 });
  const inode = fs.statSync(lock).ino;
  const exited = workerExit(t, f);
  await new Promise(resolve => setTimeout(resolve, 250));
  assert.equal(fs.statSync(lock).ino, inode, 'WORKER_DOES_NOT_STEAL_QUEUE_LOCK');
  fs.rmdirSync(lock);
  assert.equal(await exited, 0, 'WORKER_RECOVERS_TRANSIENT_CONTENTION');
  assert.deepEqual(spool.status(f.loc.dir), { state: 'unresolved', queued: 0, dropped: 1 });
  assert.ok(!fs.existsSync(path.join(f.loc.dir, 'authority.json')), 'CONTENDED_UNINSTALL_RETIRES_CREDENTIAL');
});
test('worker contention retries stay bounded and preserve a persistent lock', async t => {
  const f = fixture(t);
  cli(f, 'decision', { decision_id: 'persistent_lock' });
  const lock = path.join(f.loc.dir, 'queue.lock'); fs.mkdirSync(lock, { mode: 0o700 });
  const inode = fs.statSync(lock).ino, start = Date.now();
  assert.equal(await workerExit(t, f), 1);
  assert.ok(Date.now() - start < 5000, 'WORKER_LOCK_RETRY_BOUNDED');
  assert.equal(fs.statSync(lock).ino, inode);
  assert.equal(f.queue().items.length, 1);
  assert.ok(fs.existsSync(path.join(f.loc.dir, 'authority.json')));
});
test('worker refuses an unsafe queue lock without treating it as contention', async t => {
  const f = fixture(t); cli(f, 'decision', { decision_id: 'unsafe_lock' });
  const target = path.join(f.base, 'lock-target'); fs.mkdirSync(target, { mode: 0o700 });
  const lock = path.join(f.loc.dir, 'queue.lock'); fs.symlinkSync(target, lock);
  assert.equal(await workerExit(t, f), 1);
  assert.ok(fs.lstatSync(lock).isSymbolicLink(), 'UNSAFE_QUEUE_LOCK_NOT_REMOVED');
  assert.equal(f.queue().items[0].attempts, 0, 'UNSAFE_QUEUE_LOCK_NOT_RETRIED');
  assert.deepEqual(spool.status(f.loc.dir), { state: 'unresolved', queued: null, dropped: null });
});
test('worker recovers when a competing lock disappears before validation', async t => {
  const f = fixture(t); cli(f, 'decision', { decision_id: 'released_lock' });
  const preload = path.join(f.base, 'released-lock.cjs');
  fs.writeFileSync(preload, `
    const fs = require('node:fs'), path = require('node:path');
    const mkdir = fs.mkdirSync; let first = true;
    fs.mkdirSync = function(target, ...args) {
      if (first && path.basename(target) === 'queue.lock') {
        first = false; throw Object.assign(Error('Competing lock already released'), {code:'EEXIST'});
      }
      return mkdir.call(this, target, ...args);
    };
    global.fetch = async (_url, init) => { const b = JSON.parse(init.body); return new Response(JSON.stringify({event_id:b.event_id,accepted:b.reports.length})); };
  `);
  assert.equal(await workerExit(t, f, ['--require', preload]), 0, 'RELEASED_QUEUE_LOCK_IS_RETRIED');
  assert.deepEqual(spool.status(f.loc.dir), { state:'connected', queued:0, dropped:0 });
});
test('worker retries acknowledgment contention without redelivering the receipt', async t => {
  const f = fixture(t); cli(f, 'decision', { decision_id: 'ack_lock' });
  let delivered = 0;
  await spool.drain(f.loc.dir, { fetch: async (_url, init) => {
    delivered++;
    const lock = path.join(f.loc.dir, 'queue.lock'); fs.mkdirSync(lock, { mode: 0o700 });
    setTimeout(() => fs.rmdirSync(lock), 100);
    const body = JSON.parse(init.body);
    return new Response(JSON.stringify({ event_id: body.event_id, accepted: body.reports.length }));
  } });
  assert.equal(delivered, 1, 'CONTENDED_ACK_IS_NOT_REDELIVERED');
  assert.deepEqual(spool.status(f.loc.dir), { state: 'connected', queued: 0, dropped: 0 });
});
test('real worker final check recovers a receipt queued during worker exit contention', async t => {
  const f = fixture(t); cli(f, 'decision', { decision_id: 'first' });
  const next = f.queue().items[0].receipt;
  next.event_id = 'event_during_exit'; next.reports[0].decision_id = 'during_exit';
  const preload = path.join(f.base, 'exit-contention.cjs');
  fs.writeFileSync(preload, `
    const fs = require('node:fs'), path = require('node:path');
    const spool = require(${JSON.stringify(path.join(root, 'src/installation-reporting/spool.js'))});
    global.fetch = async (_url, init) => { const b = JSON.parse(init.body); return new Response(JSON.stringify({event_id:b.event_id, accepted:b.reports.length})); };
    const original = fs.rmdirSync;
    fs.rmdirSync = function(target, ...args) {
      const result = original.call(this, target, ...args);
      if (path.basename(target) === 'worker.lock') {
        const dir = path.dirname(target), lock = path.join(dir, 'queue.lock');
        spool.enqueue(dir, ${JSON.stringify(next)}, {launch:false});
        fs.mkdirSync(lock, {mode:0o700});
        setTimeout(() => original(lock), 150);
      }
      return result;
    };
  `);
  assert.equal(await workerExit(t, f, ['--require', preload]), 0);
  for (let i = 0; i < 100 && f.queue().items.length; i++) await new Promise(resolve => setTimeout(resolve, 100));
  assert.equal(f.queue().items.length, 0, 'WORKER_EXIT_RECHECK_DOES_NOT_STRAND_RECEIPT');
  assert.equal(spool.status(f.loc.dir).dropped, 1);
});
test('real metadata CLI rejects prohibited fields and preserves pre-action disposition', t => {
  const f = fixture(t);
  assert.equal(cli(f, 'pre', { decision_id: 'decision_allow', allow: true, call_key: hash('call') }).status, 0);
  assert.deepEqual(f.queue().items[0].receipt.reports, [{ kind: 'decision', decision_id: 'decision_allow', host_disposition: 'not_reported' }], 'PREACTION_NOT_EXECUTION');
  const before = f.queue().items.length;
  for (const field of ['prompt', 'command', 'path', 'url', 'arguments', 'results', 'token']) {
    assert.equal(cli(f, 'decision', { decision_id: 'valid', [field]: 'secret' }).status, 1, 'CLI_REDACTION');
  }
  assert.equal(f.queue().items.length, before);
  assert.equal(cli(f, 'decision', { decision_id: 'https://secret/token' }).status, 0);
  assert.equal(f.queue().items.length, before, 'SERIALIZER_REJECTS_URL');
  assert.equal(cli(f, 'post', { call_key: hash('call') }).status, 0);
  assert.equal(f.queue().items.at(-1).receipt.reports[0].host_disposition, 'allowed', 'POST_CALLBACK_DISPOSITION');
  assert.equal(f.queue().items.at(-1).receipt.reports[0].decision_id, 'decision_allow');
  assert.equal(cli(f, 'post', { call_key: hash('call') }).status, 0);
  assert.equal(f.queue().items.length, 2, 'CALLBACK_CONSUMED_ONCE');
});
test('existing groundwork binding starts durable reporting without a new handoff', t => {
  const f = fixture(t);
  fs.rmSync(path.dirname(f.loc.dir), { recursive: true });
  assert.equal(cli(f, 'decision', { decision_id: 'upgraded_binding' }).status, 0);
  assert.equal(f.queue().items[0].receipt.reports[0].decision_id, 'upgraded_binding', 'EXISTING_BINDING_UPGRADE');
  assert.ok(fs.existsSync(path.join(f.loc.dir, 'authority.json')));
});
test('warning and observation callbacks retain signed decision ID and configured mode', t => {
  const f = fixture(t);
  for (const mode of ['enforce', 'warn', 'observe']) {
    f.env.APORT_ENFORCEMENT_MODE = mode;
    cli(f, 'pre', { decision_id: `deny_${mode}`, allow: false, call_key: hash(mode) });
    cli(f, 'post', { call_key: hash(mode) });
    const receipt = f.queue().items.at(-1).receipt;
    assert.equal(receipt.mode, mode);
    assert.equal(receipt.reports[0].host_disposition, mode === 'warn' ? 'continued_after_warning' : mode === 'observe' ? 'continued_after_observation' : 'not_reported');
  }
});
test('conflicting pre-action correlation cannot attribute completion to an earlier decision', t => {
  const f = fixture(t);
  const key = hash('reused-host-call');
  cli(f, 'pre', { decision_id: 'earlier_allow', allow: true, call_key: key });
  cli(f, 'pre', { decision_id: 'later_deny', allow: false, call_key: key });
  cli(f, 'post', { call_key: key });
  assert.equal(f.queue().items.length, 2, 'AMBIGUOUS_CALL_HAS_NO_DISPOSITION');
  assert.ok(f.queue().items.every(item => item.receipt.reports[0].host_disposition === 'not_reported'));
});
test('disk spool bounds, expiry, old server and retries are visible without secrets', async t => {
  const f = fixture(t);
  for (let i = 0; i < 102; i++) assert.equal(runtime.report(f.options, `decision_${i}`), true);
  assert.deepEqual(spool.status(f.loc.dir), { state: 'unresolved', queued: 100, dropped: 2 });
  assert.equal(f.queue().items[0].receipt.reports[0].decision_id, 'decision_2', 'DISCARD_OLDEST');
  await spool.drain(f.loc.dir, { fetch: async () => new Response('', { status: 404 }) });
  assert.deepEqual(spool.status(f.loc.dir), { state: 'unresolved', queued: 0, dropped: 102 });
  runtime.report(f.options, 'expired');
  const q = f.queue(); q.items[0].created -= 60001;
  fs.writeFileSync(path.join(f.loc.dir, 'queue.json'), JSON.stringify(q));
  assert.equal(spool.status(f.loc.dir).dropped, 103);
  runtime.report(f.options, 'retry');
  const keys = [];
  await spool.drain(f.loc.dir, { fetch: async (_url, init) => { keys.push(init.headers['Idempotency-Key']); throw Error('private network detail'); } });
  assert.equal(keys.length, 3); assert.equal(new Set(keys).size, 1, 'RETRY_STABLE_KEY');
  assert.equal(spool.status(f.loc.dir).dropped, 104);
  assert.ok(!JSON.stringify(spool.status(f.loc.dir)).includes('air1.'));
});
test('revoked expired and wrong-installation credentials affect reporting only', async t => {
  for (const [label, status] of [['revoked', 401], ['expired', 401], ['wrong-installation', 403]]) {
    const f = fixture(t);
    assert.equal(runtime.report(f.options, `decision_${label}`), true);
    const calls = [];
    await spool.drain(f.loc.dir, { fetch: async (url, init) => {
      calls.push(url);
      assert.equal(init.headers.Authorization, `Bearer ${f.binding.reporter_token}`);
      assert.ok(!url.includes('/verify/') && !url.includes('/passports'));
      return new Response('', { status });
    } });
    assert.equal(calls.length, 1);
    assert.deepEqual(spool.status(f.loc.dir), { state: 'unresolved', queued: 0, dropped: 1 });
    assert.equal(runtime.report(f.options, 'authorization_still_independent'), true);
  }
});
test('protected spool rejects symlinks, hardlinks, permissions, oversized and corrupt state through CLI', t => {
  for (const kind of ['symlink', 'hardlink', 'permissions', 'oversized', 'corrupt']) {
    const f = fixture(t); runtime.report(f.options, 'before');
    const file = path.join(f.loc.dir, 'queue.json'), victim = path.join(f.base, 'victim');
    fs.writeFileSync(victim, 'preserve', { mode: 0o600 });
    if (kind === 'symlink') { fs.unlinkSync(file); fs.symlinkSync(victim, file); }
    if (kind === 'hardlink') fs.linkSync(file, path.join(f.base, 'linked'));
    if (kind === 'permissions') fs.chmodSync(file, 0o644);
    if (kind === 'oversized') fs.writeFileSync(file, 'x'.repeat(spool.LIMITS.bytes + 1));
    if (kind === 'corrupt') fs.writeFileSync(file, '{');
    const before = fs.readFileSync(file);
    assert.equal(cli(f, 'decision', { decision_id: 'after' }).status, 0);
    assert.deepEqual(fs.readFileSync(file), before, `PROTECTED_SPOOL_${kind}`);
    assert.equal(spool.status(f.loc.dir).state, 'unresolved', `PROTECTED_STATUS_${kind}`);
    assert.equal(fs.readFileSync(victim, 'utf8'), 'preserve');
  }
});
test('setup, rotation and committed removal use the shared protocol', t => {
  const f = fixture(t);
  f.env.APORT_INSTALLATION_HANDOFF_FILE = f.handoffFile;
  assert.equal(cli(f, 'setup').status, 0);
  assert.equal(f.queue().items[0].receipt.reports[0].kind, 'heartbeat');
  const installedCount = f.queue().items.length;
  assert.equal(cli(f, 'removed').status, 0);
  assert.equal(f.queue().items.length, installedCount, 'REMOVAL_REQUIRES_LOCAL_CLEANUP');
  const rotated = { ...f.handoff, reporter_token: f.handoff.reporter_token.slice(0, -43) + 'B'.repeat(43) };
  fs.writeFileSync(f.handoffFile, JSON.stringify(rotated));
  assert.equal(cli(f, 'setup').status, 1);
  f.env.APORT_INSTALLATION_ROTATE = '1'; assert.equal(cli(f, 'setup').status, 0);
  const claims = JSON.parse(Buffer.from(rotated.reporter_token.split('.')[1], 'base64url'));
  claims.region = 'EU';
  fs.writeFileSync(f.handoffFile, JSON.stringify({ ...rotated, reporter_token: `air1.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.${'C'.repeat(43)}` }));
  assert.equal(cli(f, 'setup').status, 1, 'ROTATION_SCOPE_CANNOT_WIDEN');
  fs.rmSync(path.join(f.options.configDir, 'aport'), { recursive: true });
  assert.equal(cli(f, 'removed').status, 0);
  assert.deepEqual(f.queue().items.at(-1).receipt.reports, [{ kind: 'lifecycle', state: 'removed' }]);
});
test('explicit coverage consent rejects raw manifests at the shared setup entry', t => {
  const f = fixture(t), file = path.join(f.base, 'coverage.json');
  f.env.APORT_INSTALLATION_HANDOFF_FILE = f.handoffFile; f.env.APORT_INSTALLATION_COVERAGE_FILE = file;
  const coverage = { kind: 'declared_coverage', source: 'declared_config', manifest_digest: 'a'.repeat(64), tool_ids: ['exec', 'mcp.search'] };
  fs.writeFileSync(file, JSON.stringify(coverage), { mode: 0o600 });
  assert.equal(cli(f, 'setup').status, 1);
  f.env.APORT_REPORT_DECLARED_COVERAGE = '1'; assert.equal(cli(f, 'setup').status, 0);
  for (const field of ['description', 'schema', 'url', 'path', 'arguments', 'results']) {
    fs.writeFileSync(file, JSON.stringify({ ...coverage, [field]: 'secret' }));
    assert.equal(cli(f, 'setup').status, 1, 'COVERAGE_REDACTION');
  }
});
test('local, disabled and absent handoff never create reporting state', t => {
  const f = fixture(t);
  assert.equal(runtime.report({ ...f.options, authMode: 'local' }, 'decision'), false);
  assert.equal(runtime.report({ ...f.options, passportId: 'ap_other' }, 'decision'), false);
  f.env.APORT_REPORTING_DISABLED = '1'; assert.equal(cli(f, 'decision', { decision_id: 'decision' }).status, 0);
  assert.ok(!fs.existsSync(path.join(f.loc.dir, 'queue.json')));
});
test('disabled reporting cannot retain a delivery credential after reset', t => {
  const f = fixture(t);
  runtime.report(f.options, 'waiting');
  fs.rmSync(path.join(f.options.configDir, 'aport'), { recursive: true });
  f.env.APORT_REPORTING_DISABLED = '1';
  assert.equal(cli(f, 'removed').status, 0);
  assert.ok(!fs.existsSync(path.join(f.loc.dir, 'authority.json')), 'DISABLED_RESET_CLEARS_CREDENTIAL');
  assert.deepEqual(spool.status(f.loc.dir), { state: 'unresolved', queued: 0, dropped: 1 });
});
test('detached worker drains after the short-lived producer exits', async t => {
  const f = fixture(t, 'codex', true);
  assert.equal(cli(f, 'decision', { decision_id: 'detached' }).status, 0);
  for (let i = 0; i < 140; i++) {
    if (spool.status(f.loc.dir).dropped === 1) break;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.equal(spool.status(f.loc.dir).dropped, 1, 'DETACHED_WORKER_SURVIVES_PRODUCER');
});

test('real shell harness preserves authorization bytes and correlates Codex completion', t => {
  const f = fixture(t);
  const preload = path.join(f.base, 'fetch.cjs');
  fs.writeFileSync(preload, `global.fetch = async () => ({ok:true, json:async()=>({decision_id:'shell_decision',allow:process.env.FIXTURE_ALLOW==='1',reasons:[{code:'oap.denied',message:'fixture'}]})});`);
  f.env.NODE_OPTIONS = `--require=${preload}`;
  f.env.APORT_CODEX_CONFIG_DIR = f.options.configDir;
  const payload = { hook_event_name: 'PreToolUse', tool_name: 'exec_command', tool_call_id: 'shell_call', tool_input: { cmd: 'echo PRIVATE_TOOL_CONTENT', yield_time_ms: 1000 } };
  const run = (enabled, input = payload) => spawnSync('bash', [path.join(root, 'bin/aport-codex-hook.sh')],
    { env: { ...f.env, APORT_REPORTING_DISABLED: enabled ? '0' : '1' }, encoding: 'utf8', input: JSON.stringify(input), timeout: 15000 });
  for (const allowed of ['1', '0']) {
    f.env.FIXTURE_ALLOW = allowed;
    const disabled = run(false), enabled = run(true);
    assert.equal(enabled.status, disabled.status, 'SHELL_EXIT_COMPATIBILITY');
    assert.equal(enabled.stdout, disabled.stdout, 'SHELL_STDOUT_COMPATIBILITY');
    assert.equal(enabled.stderr, disabled.stderr, 'SHELL_STDERR_COMPATIBILITY');
    assert.equal(f.queue().items.at(-1).receipt.reports[0].host_disposition, 'not_reported', 'SHELL_PRE_NOT_EXECUTION');
    assert.ok(!JSON.stringify(f.queue()).includes('PRIVATE_TOOL_CONTENT'), 'SHELL_REDACTION');
  }
  run(true, { hook_event_name: 'PostToolUse', tool_name: 'exec_command', tool_call_id: 'shell_call', tool_response: 'PRIVATE_RESULT' });
  assert.ok(!JSON.stringify(f.queue()).includes('PRIVATE_RESULT'));
});
test('real Node and Python evaluators delegate metadata without altering decisions', async t => {
  const f = fixture(t, 'langchain');
  const config = path.join(f.options.configDir, 'config.yaml');
  fs.writeFileSync(config, `mode: api\nagent_id: ap_fixture\napi_url: ${f.options.apiUrl}\n`);
  const nodeResult = spawnSync(process.execPath, ['-e', `
    const { Evaluator } = require('./packages/core/dist/core/evaluator.js');
    global.fetch = async () => ({ok:true,text:async()=>JSON.stringify({decision:{allow:false,decision_id:'node_deny',reasons:[]}})});
    new Evaluator(process.argv[1]).verify({}, {}, {tool:'exec',command:'PRIVATE_NODE_INPUT'}).then(d=>process.stdout.write(JSON.stringify(d)));
  `, config], { cwd: root, env: f.env, encoding: 'utf8', timeout: 5000 });
  assert.equal(nodeResult.status, 0, nodeResult.stderr);
  assert.equal(nodeResult.stdout, '{"allow":false,"reasons":[]}', 'NODE_AUTHORIZATION_COMPATIBILITY');
  assert.equal(f.queue().items.at(-1).receipt.reports[0].decision_id, 'node_deny', 'NODE_SHARED_REPORTER');
  const py = spawnSync('python3', ['-c', `
import json, sys
from unittest.mock import patch
from aport_guardrails.core.evaluator import Evaluator
with patch('aport_guardrails.core.evaluator._call_api_sync', return_value={'allow': True, 'decision_id': 'python_allow', 'reasons': []}):
    result = Evaluator(sys.argv[1]).verify_sync({}, {}, {'tool': 'exec', 'command': 'PRIVATE_PYTHON_INPUT'})
    assert result == {'allow': True, 'decision_id': 'python_allow', 'reasons': []}
`, config], { cwd: root, env: { ...f.env, PYTHONPATH: path.join(root, 'python') }, encoding: 'utf8', timeout: 5000 });
  assert.equal(py.status, 0, py.stderr);
  assert.equal(f.queue().items.at(-1).receipt.reports[0].decision_id, 'python_allow', 'PYTHON_SHARED_REPORTER');
  assert.ok(!JSON.stringify(f.queue()).includes('PRIVATE_'), 'ADAPTER_REDACTION');
});
test('Node and Python sync and async reporting retain the evaluated passport through completion', async t => {
  for (const language of ['node', 'python']) for (const method of ['sync', 'async']) for (const source of ['supplied', 'file']) for (const inherited of ['ap_reporting', '']) {
    await t.test(`${language} ${method} ${source} inherited=${inherited || 'absent'}`, async t => {
      const f = fixture(t, 'langchain'), config = path.join(f.options.configDir, 'config.yaml');
      const passportFile = path.join(f.options.configDir, 'passport.json');
      fs.writeFileSync(passportFile, JSON.stringify({agent_id:'ap_fixture'}), {mode:0o600});
      fs.writeFileSync(config, `mode: api\napi_url: ${f.options.apiUrl}\nenforcement_mode: warn\n${source === 'file' ? `passport_path: ${passportFile}\n` : ''}`);
      const otherOptions = { ...f.options, passportId: 'ap_reporting' }, otherLoc = runtime.location(otherOptions);
      const claims = Buffer.from(JSON.stringify({ v: 1, owner_id: 'ap_user_fixture', region: 'US', installation_id: 'ai_other' })).toString('base64url');
      const otherBinding = { installation_id: 'ai_other', reporter_token: `air1.${claims}.${'A'.repeat(43)}` };
      const handoff = { ...f.handoff, ...otherBinding,
        reporter_endpoint: `${f.options.apiUrl}/api/agent-installations/ai_other/reports`,
        test_result_endpoint: `${f.options.apiUrl}/api/agent-installations/ai_other/tests/{test_id}/results` };
      const handoffFile = path.join(f.base, 'other-handoff.json'); fs.writeFileSync(handoffFile, JSON.stringify(handoff), { mode: 0o600 });
      bindHandoff({ ...otherLoc, framework: 'langchain', passportId: 'ap_reporting', handoffFile });
      spool.provision(otherLoc.dir, { binding: otherBinding, framework: 'langchain', origin: otherLoc.origin });
      fs.mkdirSync(path.join(otherLoc.dir, 'worker.lock'), { mode: 0o700 });
      const env = { ...f.env, HOME: f.base, APORT_AGENT_ID: inherited, OPENCLAW_PASSPORT_FILE: '' };
      let result;
      if (language === 'node') {
        const preload = path.join(f.base, 'api.cjs');
        fs.writeFileSync(preload, `
          global.fetch = async (_url, init) => {
            const body = JSON.parse(init.body);
            require('node:assert/strict').equal(${source === 'file' ? 'body.passport.agent_id' : 'body.context.agent_id'}, 'ap_fixture', 'NODE_EVALUATED_ID');
            const d = {decision:{allow:false,decision_id:'evaluated_node',reasons:[]}};
            return {ok:true,text:async()=>JSON.stringify(d),json:async()=>d};
          };
        `);
        result = spawnSync(process.execPath, ['-e', `
          const assert = require('node:assert/strict'), { Evaluator } = require('./packages/core/dist/core/evaluator.js');
          (async()=>{
            const e = new Evaluator(process.argv[1]);
            const d = ${method === 'sync' ? 'e.verifySync' : 'await e.verify'}(${source === 'file' ? '{}' : "{agent_id:'ap_fixture'}"}, {}, {tool:'exec'});
            assert.equal(d.decision_id, 'evaluated_node');
            assert.equal(JSON.stringify(d), '{"allow":false,"reasons":[]}');
            process.env.APORT_AGENT_ID = 'ap_reporting';
            e.trackToolCall('effective_identity', d);
            e.completeToolCall('effective_identity');
            e.completeToolCall('effective_identity');
            e.trackToolCall('ambiguous_identity', d);
            e.trackToolCall('ambiguous_identity', {allow:true});
            e.completeToolCall('ambiguous_identity');
          })().catch(e=>{console.error(e);process.exitCode=1;});
        `, config], { cwd: root, env: { ...env, NODE_OPTIONS: `--require=${preload}` }, encoding: 'utf8', timeout: 10000 });
      } else {
        result = spawnSync('python3', ['-c', `
import asyncio, json, os, sys
from unittest.mock import patch
from aport_guardrails.core.evaluator import Evaluator
def verify(*args, **kwargs):
    assert ${source === 'file' ? "kwargs['passport']['agent_id']" : "kwargs['agent_id']"} == 'ap_fixture', 'PYTHON_EVALUATED_ID'
    return {'allow':False,'decision_id':'evaluated_python','reasons':[]}
async def main():
    e = Evaluator(sys.argv[1])
    with patch('aport_guardrails.core.evaluator._call_api_sync', side_effect=verify):
        d = ${method === 'sync' ? 'e.verify_sync' : 'await e.verify'}(${source === 'file' ? '{}' : "{'agent_id':'ap_fixture'}"}, {}, {'tool':'exec'})
    assert json.dumps(d) == json.dumps({'allow':False,'decision_id':'evaluated_python','reasons':[]})
    os.environ['APORT_AGENT_ID'] = 'ap_reporting'
    e.track_tool_call('effective_identity', d)
    e.complete_tool_call('effective_identity')
    e.complete_tool_call('effective_identity')
    e.track_tool_call('ambiguous_identity', d)
    e.track_tool_call('ambiguous_identity', {'allow': True})
    e.complete_tool_call('ambiguous_identity')
asyncio.run(main())
`, config], { cwd: root, env: { ...env, PYTHONPATH: path.join(root, 'python') }, encoding: 'utf8', timeout: 10000 });
      }
      assert.equal(result.status, 0, result.stderr);
      assert.ok(!fs.existsSync(path.join(otherLoc.dir, 'queue.json')), 'UNEVALUATED_INSTALLATION_UNTOUCHED');
      assert.equal(f.queue().items.length, 2, 'EVALUATED_INSTALLATION_PRE_AND_POST');
      const reports = f.queue().items.map(item => item.receipt.reports[0]);
      assert.deepEqual(reports.map(r => r.host_disposition), ['not_reported', 'continued_after_warning']);
      assert.equal(reports[0].decision_id, reports[1].decision_id, 'EVALUATED_SCOPE_CORRELATION');
    });
  }
});
test('Node sync reporting refuses conflicting request passport selectors', t => {
  const f = fixture(t, 'langchain'), config = path.join(f.options.configDir, 'config.yaml');
  const passport = path.join(f.options.configDir, 'passport.json');
  fs.writeFileSync(passport, JSON.stringify({agent_id:'ap_other'}), {mode:0o600});
  fs.writeFileSync(config, `mode: api\napi_url: ${f.options.apiUrl}\npassport_path: ${passport}\n`);
  const preload = path.join(f.base, 'conflicting-api.cjs');
  fs.writeFileSync(preload, `global.fetch = async (_url, init) => {
    const body = JSON.parse(init.body), assert = require('node:assert/strict');
    assert.equal(body.context.agent_id, 'ap_fixture'); assert.equal(body.passport.agent_id, 'ap_other');
    return {json:async()=>({decision:{allow:true,decision_id:'ambiguous_request',reasons:[]}})};
  };`);
  const result = spawnSync(process.execPath, ['-e', `
    const {Evaluator} = require('./packages/core/dist/core/evaluator.js');
    const e = new Evaluator(process.argv[1]), d = e.verifySync({agent_id:'ap_fixture'}, {}, {tool:'exec'});
    require('node:assert/strict').equal(d.decision_id, 'ambiguous_request');
    e.trackToolCall('ambiguous_request', d); e.completeToolCall('ambiguous_request');
  `, config], {cwd:root, env:{...f.env, NODE_OPTIONS:`--require=${preload}`}, encoding:'utf8', timeout:10000});
  assert.equal(result.status, 0, result.stderr);
  assert.ok(!fs.existsSync(path.join(f.loc.dir, 'queue.json')), 'CONFLICTING_REQUEST_HAS_NO_REPORTING_IDENTITY');
});
test('real OpenClaw plugin keeps all pre-action results not_reported', async t => {
  const f = fixture(t, 'openclaw');
  const saved = process.env.APORT_OPENCLAW_CONFIG_DIR;
  process.env.APORT_OPENCLAW_CONFIG_DIR = f.options.configDir;
  t.after(() => { if (saved === undefined) delete process.env.APORT_OPENCLAW_CONFIG_DIR; else process.env.APORT_OPENCLAW_CONFIG_DIR = saved; });
  const { default: plugin, canonicalize } = await import('../../extensions/openclaw-aport/index.js');
  let callback;
  plugin.register({ pluginConfig: { mode: 'api', agentId: 'ap_fixture', apiUrl: f.options.apiUrl }, logger: {},
    on(name, handler) { if (name === 'before_tool_call') callback = handler; } });
  const savedFetch = global.fetch; t.after(() => { global.fetch = savedFetch; });
  for (const allow of [true, false]) {
    const decision = { allow, decision_id: allow ? 'openclaw_allow' : 'openclaw_deny', reasons: [] };
    decision.content_hash = `sha256:${hash(canonicalize(decision))}`;
    global.fetch = async () => ({ ok: true, json: async () => ({ decision }) });
    const response = await callback({ toolName: 'exec', params: { command: 'echo PRIVATE_OPENCLAW' } });
    assert.equal(response.block === true, !allow);
    assert.equal(f.queue().items.at(-1).receipt.reports[0].host_disposition, 'not_reported', 'OPENCLAW_NO_COMPLETION_INFERENCE');
  }
  global.fetch = async () => { throw Error('unavailable'); };
  assert.equal((await callback({ toolName: 'exec', params: { command: 'echo ok' } })).block, true);
  assert.deepEqual(f.queue().items.at(-1).receipt.reports, [{ kind: 'heartbeat' }], 'UNAVAILABLE_NEVER_INVENTS_DECISION');
  assert.ok(!JSON.stringify(f.queue()).includes('PRIVATE_OPENCLAW'));
});
test('real mode and reset scripts report only after local commits and retire credentials', async t => {
  const f = fixture(t, 'openclaw');
  f.env.APORT_OPENCLAW_CONFIG_DIR = f.options.configDir;
  fs.writeFileSync(path.join(f.options.configDir, 'openclaw.json'), JSON.stringify({ plugins: { entries: { 'openclaw-aport': { enabled: true, config: { mode: 'api', agentId: 'ap_fixture', apiUrl: f.options.apiUrl } } } } }));
  const mode = spawnSync('bash', [path.join(root, 'bin/agent-guardrails'), 'mode', 'openclaw', '--enforcement=warn'], { env: f.env, encoding: 'utf8', timeout: 10000 });
  assert.equal(mode.status, 0, mode.stderr);
  assert.equal(f.queue().items.at(-1).receipt.mode, 'warn', 'MODE_AFTER_COMMIT');
  assert.match(fs.readFileSync(path.join(f.options.configDir, 'aport/guardrail-mode.env'), 'utf8'), /warn/);
  const reset = spawnSync('bash', [path.join(root, 'bin/agent-guardrails'), 'reset', 'openclaw', '--yes'], { env: f.env, encoding: 'utf8', timeout: 10000 });
  assert.equal(reset.status, 0, reset.stderr);
  assert.ok(!fs.existsSync(path.join(f.options.configDir, 'aport')));
  assert.deepEqual(f.queue().items.at(-1).receipt.reports, [{ kind: 'lifecycle', state: 'removed' }], 'RESET_AFTER_COMMIT');
  await spool.drain(f.loc.dir, { fetch: async (_url, init) => {
    const body = JSON.parse(init.body);
    return new Response(JSON.stringify({ event_id: body.event_id, accepted: body.reports.length }));
  } });
  assert.equal(spool.status(f.loc.dir).state, 'connected');
  assert.ok(!fs.existsSync(path.join(f.loc.dir, 'authority.json')), 'RESET_ERASES_DELIVERY_CREDENTIAL');
});
test('enterprise uninstall delegates to real reset and survives reporting rejection', t => {
  const f = fixture(t, 'claude-code');
  const bin = path.join(f.base, 'bin'); fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, 'npx'), `#!/bin/bash\nshift 2\nexec bash '${path.join(root, 'bin/agent-guardrails')}' "$@"\n`, { mode: 0o700 });
  const stateDir = path.join(f.base, 'device-state'); fs.mkdirSync(stateDir);
  fs.writeFileSync(path.join(stateDir, 'state.env'), 'fixture');
  const result = spawnSync(process.execPath, [path.join(root, 'enterprise-scripts/aport-device-core.mjs'), 'uninstall'],
    { env: { ...f.env, PATH: `${bin}:${process.env.PATH}`, APORT_FRAMEWORK: 'claude-code', APORT_TARGET_USER: 'fixture', APORT_TARGET_HOME: f.base,
      APORT_SKIP_USER_SWITCH: '1', APORT_STATE_DIR: stateDir, APORT_CLAUDE_CODE_CONFIG_DIR: f.options.configDir }, encoding: 'utf8', timeout: 15000 });
  assert.equal(result.status, 0, result.stderr);
  assert.ok(!fs.existsSync(stateDir), 'ENTERPRISE_CLEANUP_COMMITTED');
  assert.ok(fs.existsSync(path.join(f.loc.dir, 'queue.json')), result.stdout + result.stderr);
  assert.deepEqual(f.queue().items.at(-1).receipt.reports, [{ kind: 'lifecycle', state: 'removed' }], 'ENTERPRISE_SHARED_PROTOCOL');
});
test('native Python setup reuses the shared handoff and reports after setup', t => {
  const f = fixture(t, 'langchain');
  const config = path.join(f.options.configDir, 'config.yaml');
  fs.writeFileSync(config, `mode: api\nagent_id: ap_fixture\napi_url: ${f.options.apiUrl}\n`);
  const result = spawnSync('python3', ['-c', "from aport_guardrails.core.cli_common import run_setup; run_setup('langchain', ci=True)"],
    { cwd: root, env: { ...f.env, PYTHONPATH: path.join(root, 'python'), APORT_LANGCHAIN_CONFIG_DIR: f.options.configDir,
      APORT_INSTALLATION_HANDOFF_FILE: f.handoffFile }, encoding: 'utf8', timeout: 15000 });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.queue().items[0].receipt.reports[0].kind, 'heartbeat', 'PYTHON_SETUP_SHARED_PROTOCOL');
  assert.ok(fs.existsSync(path.join(f.options.configDir, 'aport/runtime/src/installation-reporting/worker.js')));
});
test('Node and Python LangChain tool-end callbacks report continuation without tool output', t => {
  const f = fixture(t, 'langchain'), config = path.join(f.options.configDir, 'config.yaml');
  fs.writeFileSync(config, `mode: api\nagent_id: ap_fixture\napi_url: ${f.options.apiUrl}\nenforcement_mode: warn\n`);
  const nodeResult = spawnSync(process.execPath, ['-e', `
    const { APortGuardrailCallback } = require('./packages/langchain/dist/middleware.js');
    global.fetch = async () => ({ok:true,text:async()=>JSON.stringify({decision:{allow:false,decision_id:'node_callback',reasons:[]}})});
    const callback = new APortGuardrailCallback({configPath:process.argv[1]});
    (async()=>{await callback.handleToolStart({name:'exec'},'PRIVATE_INPUT','node_run');
      await callback.handleToolEnd('PRIVATE_RESULT','node_run');})();
  `, config], { cwd: root, env: f.env, encoding: 'utf8', timeout: 10000 });
  assert.equal(nodeResult.status, 0, nodeResult.stderr);
  assert.equal(f.queue().items.at(-1).receipt.reports[0].host_disposition, 'continued_after_warning', 'NODE_TOOL_END_CALLBACK');
  const py = spawnSync('python3', ['-c', `
import asyncio, sys
from unittest.mock import patch
from aport_guardrails_langchain.middleware import APortCallback
async def main():
    callback = APortCallback(sys.argv[1])
    with patch('aport_guardrails.core.evaluator._call_api_sync', return_value={'allow': False, 'decision_id': 'python_callback', 'reasons': []}):
        await callback.on_tool_start({'name':'exec'}, 'PRIVATE_INPUT', run_id='python_run')
        await callback.on_tool_end('PRIVATE_RESULT', run_id='python_run')
asyncio.run(main())
`, config], { cwd: root, env: { ...f.env, PYTHONPATH: `${root}/python:${root}/python/langchain_adapter` }, encoding: 'utf8', timeout: 10000 });
  assert.equal(py.status, 0, py.stderr);
  assert.equal(f.queue().items.at(-1).receipt.reports[0].host_disposition, 'continued_after_warning', 'PYTHON_TOOL_END_CALLBACK');
  assert.equal(f.queue().items.at(-1).receipt.reports[0].decision_id, 'python_callback');
  assert.ok(!JSON.stringify(f.queue()).includes('PRIVATE_'));
});
test('enterprise user switching preserves reporting consent without putting credentials in argv', t => {
  const f = fixture(t, 'claude-code'), bin = path.join(f.base, 'bin'); fs.mkdirSync(bin);
  const recorded = path.join(f.base, 'sudo-args');
  fs.writeFileSync(path.join(bin, 'sudo'), `#!/bin/bash\nprintf '%s\\n' "$@" > '${recorded}'\nexit 0\n`, { mode: 0o700 });
  const preload = path.join(f.base, 'root-fixture.cjs'); fs.writeFileSync(preload, 'process.getuid = () => 0;');
  const stateDir = path.join(f.base, 'state'); fs.mkdirSync(stateDir);
  const result = spawnSync(process.execPath, [path.join(root, 'enterprise-scripts/aport-device-core.mjs'), 'uninstall'], {
    env: { ...f.env, PATH: `${bin}:${process.env.PATH}`, NODE_OPTIONS: `--require=${preload}`, APORT_FRAMEWORK: 'claude-code',
      APORT_TARGET_USER: 'fixture', APORT_TARGET_HOME: f.base, APORT_SKIP_USER_SWITCH: '0', APORT_STATE_DIR: stateDir,
      APORT_INSTALLATION_HANDOFF_FILE: f.handoffFile, APORT_REPORTING_DISABLED: '1', APORT_API_KEY: 'verification_secret' },
    encoding: 'utf8', timeout: 10000 });
  assert.equal(result.status, 0, result.stderr);
  const args = fs.readFileSync(recorded, 'utf8');
  assert.match(args, /--preserve-env=APORT_INSTALLATION_HANDOFF_FILE,APORT_REPORTING_DISABLED/, 'ENTERPRISE_CONSENT_SURVIVES_USER_SWITCH');
  assert.ok(!args.includes('verification_secret') && !args.includes('air1.'));
});

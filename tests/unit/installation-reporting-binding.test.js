'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { spawn, spawnSync, execFileSync } = require('node:child_process');
const os = require('node:os');
const path = require('node:path');
const { bindHandoff, bindingStatus } = require('../../src/installation-reporting/binding');

const origin = 'https://sandbox.aport.io';
const id = 'ai_example';
function handoff(installationId, secret = 'A') {
  const claims = Buffer.from(JSON.stringify({ v: 1, owner_id: 'ap_user_example', region: 'US', installation_id: installationId })).toString('base64url');
  return { schema_version: 'agent-installation-handoff/v1', installation_id: installationId,
    reporter_endpoint: `${origin}/api/agent-installations/${installationId}/reports`,
    test_result_endpoint: `${origin}/api/agent-installations/${installationId}/tests/{test_id}/results`,
    token_presentation: 'Authorization: Bearer <reporter_token>', reporter_token: `air1.${claims}.${secret.repeat(43)}` };
}
function fixture(t) {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'aport-binding-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const stateDir = path.join(root, 'aport'); fs.mkdirSync(stateDir, { mode: 0o700 });
  const handoffFile = path.join(root, 'handoff.json');
  const write = data => fs.writeFileSync(handoffFile, JSON.stringify(data), { mode: 0o600 });
  write(handoff(id));
  return { root, stateDir, handoffFile, write, args: { stateDir, framework: 'openclaw', passportId: 'ap_example', origin, handoffFile } };
}

test('stores only the installation and scoped token with protected permissions', t => {
  const f = fixture(t);
  assert.equal(bindingStatus(f.args), 'not configured');
  assert.equal(bindHandoff(f.args), 'bound');
  assert.equal(bindingStatus(f.args), 'unverified');
  assert.equal(bindingStatus({ ...f.args, passportId: 'ap_other' }), 'not configured');
  const files = fs.readdirSync(f.stateDir);
  assert.equal(files.length, 1);
  const file = path.join(f.stateDir, files[0]);
  assert.equal(fs.statSync(file).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), { installation_id: id, reporter_token: handoff(id).reporter_token });
  assert.equal(bindHandoff(f.args), 'reused');
  f.write(handoff(id, 'B'));
  assert.throws(() => bindHandoff(f.args), /could not be bound safely/);
  assert.equal(bindHandoff({ ...f.args, allowRotation: true }), 'rotated');
  assert.equal(JSON.parse(fs.readFileSync(file, 'utf8')).reporter_token, handoff(id, 'B').reporter_token);
});

test('changed identities cannot reuse an installation and existing identities cannot silently rebind', t => {
  const f = fixture(t);
  bindHandoff(f.args);
  assert.throws(() => bindHandoff({ ...f.args, passportId: 'ap_other' }), /could not be bound safely/);
  f.write(handoff('ai_other'));
  assert.throws(() => bindHandoff(f.args), /could not be bound safely/);
  assert.equal(bindHandoff({ ...f.args, passportId: 'ap_other' }), 'bound');
});

test('unsafe paths, permissive or corrupt handoffs, and linked state fail closed', t => {
  const f = fixture(t);
  fs.chmodSync(f.handoffFile, 0o644);
  assert.throws(() => bindHandoff(f.args));
  fs.chmodSync(f.handoffFile, 0o600);
  const link = path.join(f.root, 'link'); fs.symlinkSync(f.handoffFile, link);
  assert.throws(() => bindHandoff({ ...f.args, handoffFile: link }));
  const handoffHardlink = path.join(f.root, 'handoff-hardlink'); fs.linkSync(f.handoffFile, handoffHardlink);
  assert.throws(() => bindHandoff(f.args));
  fs.unlinkSync(handoffHardlink);
  const stateLink = path.join(f.root, 'state-link'); fs.symlinkSync(f.stateDir, stateLink);
  assert.throws(() => bindHandoff({ ...f.args, stateDir: stateLink }));
  f.write({ ...handoff(id), extra: 'sensitive' });
  assert.throws(() => bindHandoff(f.args));
  fs.writeFileSync(f.handoffFile, 'x'.repeat(8193), { mode: 0o600 });
  assert.throws(() => bindHandoff(f.args));
  f.write(handoff(id));
  bindHandoff(f.args);
  const stateFile = path.join(f.stateDir, fs.readdirSync(f.stateDir)[0]);
  const second = path.join(f.root, 'hardlink'); fs.linkSync(stateFile, second);
  assert.throws(() => bindHandoff(f.args));
  assert.equal(bindingStatus(f.args), 'unresolved');
});

test('an existing binding lock fails closed and is never removed', t => {
  const f = fixture(t);
  const lock = path.join(f.stateDir, '.installation-binding.lock');
  fs.mkdirSync(lock, { mode: 0o700 });
  assert.throws(() => bindHandoff(f.args), /could not be bound safely/);
  assert.equal(bindingStatus(f.args), 'unresolved');
  assert.equal(fs.statSync(lock).isDirectory(), true);
  assert.deepEqual(fs.readdirSync(f.stateDir), ['.installation-binding.lock']);
});

test('a replaced state directory is rejected before a binding is written', t => {
  const f = fixture(t);
  const originalMkdir = fs.mkdirSync;
  try {
    fs.mkdirSync = (target, options) => {
      if (target === path.join(f.stateDir, '.installation-binding.lock')) {
        fs.renameSync(f.stateDir, `${f.stateDir}-old`);
        originalMkdir(f.stateDir, { mode: 0o700 });
      }
      return originalMkdir(target, options);
    };
    assert.throws(() => bindHandoff(f.args), /could not be bound safely/);
    assert.deepEqual(fs.readdirSync(f.stateDir), []);
  } finally { fs.mkdirSync = originalMkdir; }
});

test('concurrent identities cannot bind the same installation in one state directory', async t => {
  const f = fixture(t);
  const modulePath = require.resolve('../../src/installation-reporting/binding');
  const code = `const {bindHandoff}=require(process.argv[1]); try { bindHandoff({stateDir:process.argv[2],framework:'openclaw',passportId:process.argv[3],origin:process.argv[4],handoffFile:process.argv[5]}); process.exit(0); } catch { process.exit(1); }`;
  const run = passport => new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['-e', code, modulePath, f.stateDir, passport, origin, f.handoffFile], { stdio: 'ignore' });
    child.once('error', reject);
    child.once('exit', resolve);
  });
  const outcomes = await Promise.all([run('ap_one'), run('ap_two')]);
  assert.deepEqual(outcomes.sort(), [0, 1]);
  assert.equal(fs.readdirSync(f.stateDir).filter(name => name.endsWith('.json')).length, 1);
});

test('non-regular handoff and state files are rejected without blocking setup', t => {
  const f = fixture(t);
  const fifo = path.join(f.root, 'handoff-fifo');
  execFileSync('mkfifo', [fifo]);
  const modulePath = require.resolve('../../src/installation-reporting/binding');
  const code = `const {bindHandoff}=require(process.argv[1]); try { bindHandoff({stateDir:process.argv[2],framework:'openclaw',passportId:'ap_example',origin:process.argv[3],handoffFile:process.argv[4]}); process.exit(1); } catch { process.exit(0); }`;
  const run = handoffFile => spawnSync(process.execPath, ['-e', code, modulePath, f.stateDir, origin, handoffFile], { stdio: 'ignore', timeout: 2000 });
  const handoffResult = run(fifo);
  assert.equal(handoffResult.status, 0, 'FIFO handoff must be rejected promptly');
  const stateFifo = path.join(f.stateDir, `installation-v1-${'a'.repeat(64)}.json`);
  execFileSync('mkfifo', [stateFifo]);
  const stateResult = run(f.handoffFile);
  assert.equal(stateResult.status, 0, 'FIFO state must be rejected promptly');
});

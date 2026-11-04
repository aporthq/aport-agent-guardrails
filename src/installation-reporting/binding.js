'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createHash, randomUUID } = require('node:crypto');
const { validateHandoff } = require('./contract');
const { O_RDONLY, O_WRONLY, O_CREAT, O_EXCL, O_NOFOLLOW, O_NONBLOCK } = fs.constants;

function invalid() { throw new Error('Installation handoff could not be bound safely'); }
function noSymlinkComponents(target) {
  let current = path.resolve(target);
  for (;;) {
    const stat = fs.lstatSync(current);
    if (stat.isSymbolicLink()) invalid();
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
}
function readProtected(file, maxBytes) {
  const fd = fs.openSync(file, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
  try {
    const stat = fs.fstatSync(fd);
    if (!stat.isFile() || stat.nlink !== 1 || stat.size > maxBytes || (stat.mode & 0o077) !== 0 ||
        (typeof process.getuid === 'function' && stat.uid !== process.getuid())) invalid();
    const buffer = Buffer.alloc(maxBytes + 1);
    let used = 0, count;
    while (used < buffer.length && (count = fs.readSync(fd, buffer, used, buffer.length - used, null)) > 0) used += count;
    if (used > maxBytes) invalid();
    return buffer.subarray(0, used).toString('utf8');
  } finally { fs.closeSync(fd); }
}
function readRecord(file) {
  const record = JSON.parse(readProtected(file, 4096));
  if (!record || Array.isArray(record) || Object.keys(record).sort().join(',') !== 'installation_id,reporter_token' ||
      typeof record.installation_id !== 'string' || record.installation_id.match(/^ai_[A-Za-z0-9_-]{1,100}$/)?.[0] !== record.installation_id ||
      typeof record.reporter_token !== 'string' || record.reporter_token.length > 1024) invalid();
  return record;
}
function supportedFramework(framework) {
  return ['openclaw', 'claude-code', 'cursor', 'codex', 'gemini-cli', 'goose', 'langchain', 'crewai', 'deerflow', 'n8n', 'generic'].includes(framework);
}
function identityName(framework, passportId, origin) {
  // Keep this compatibility check aligned with is_aport_hosted_agent_id in
  // bin/lib/guardrail-mode.sh, which also accepts legacy hosted IDs.
  if (!supportedFramework(framework) || typeof passportId !== 'string' || passportId.match(/^(?:ap|apt|agt_inst|agt_tmpl)_[A-Za-z0-9_-]+$/)?.[0] !== passportId || typeof origin !== 'string') invalid();
  const url = new URL(origin);
  if (url.protocol !== 'https:' || url.origin !== origin || url.username || url.password || url.pathname !== '/' || url.search || url.hash) invalid();
  const identity = createHash('sha256').update(JSON.stringify(['installation-binding/v1', framework, passportId, origin])).digest('hex');
  return `installation-v1-${identity}.json`;
}
function bindHandoff({ stateDir, framework, passportId, origin, handoffFile, allowRotation = false }) {
  try {
    const basename = identityName(framework, passportId, origin);
    if (typeof stateDir !== 'string' || typeof handoffFile !== 'string') invalid();
    noSymlinkComponents(stateDir);
    noSymlinkComponents(path.dirname(handoffFile));
    const dirStat = fs.lstatSync(stateDir);
    if (!dirStat.isDirectory() || (typeof process.getuid === 'function' && dirStat.uid !== process.getuid())) invalid();
    const handoff = JSON.parse(readProtected(handoffFile, 8192));
    const binding = validateHandoff(handoff, origin);
    const dirFd = fs.openSync(stateDir, O_RDONLY | O_NOFOLLOW);
    try {
      const openedDir = fs.fstatSync(dirFd);
      if (!openedDir.isDirectory() || openedDir.dev !== dirStat.dev || openedDir.ino !== dirStat.ino) invalid();
      if ((openedDir.mode & 0o077) !== 0) fs.fchmodSync(dirFd, 0o700);
    } finally { fs.closeSync(dirFd); }
    // Serialize the identity scan and update so concurrent setups cannot bind
    // one installation to two identities. An existing lock fails closed.
    const lock = path.join(stateDir, '.installation-binding.lock');
    fs.mkdirSync(lock, { mode: 0o700 });
    try {
      const lockedDir = fs.lstatSync(stateDir);
      if (!lockedDir.isDirectory() || lockedDir.isSymbolicLink() || lockedDir.dev !== dirStat.dev || lockedDir.ino !== dirStat.ino) invalid();
      const entries = fs.readdirSync(stateDir).filter(name => /^installation-v1-[a-f0-9]{64}\.json$/.test(name));
      if (entries.length > 512) invalid();
      let existing;
      for (const name of entries) {
        const record = readRecord(path.join(stateDir, name));
        if (name === basename) existing = record;
        else if (record.installation_id === binding.installation_id) invalid();
      }
      if (existing && existing.installation_id !== binding.installation_id) invalid();
      if (existing && existing.reporter_token === binding.reporter_token) return 'reused';
      if (existing && allowRotation !== true) invalid();
      if (existing) {
        const previous = JSON.parse(Buffer.from(existing.reporter_token.split('.')[1], 'base64url').toString('utf8'));
        const next = JSON.parse(Buffer.from(binding.reporter_token.split('.')[1], 'base64url').toString('utf8'));
        if (previous.owner_id !== next.owner_id || previous.region !== next.region || previous.v !== next.v) invalid();
      }
      const target = path.join(stateDir, basename);
      const tmp = path.join(stateDir, `.installation-${randomUUID()}.tmp`);
      let fd;
      try {
        fd = fs.openSync(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600);
        fs.writeFileSync(fd, JSON.stringify(binding) + '\n');
        fs.fsyncSync(fd);
        fs.closeSync(fd); fd = undefined;
        fs.renameSync(tmp, target);
      } finally {
        if (fd !== undefined) fs.closeSync(fd);
        try { fs.unlinkSync(tmp); } catch (error) { if (error.code !== 'ENOENT') throw error; }
      }
      return existing ? 'rotated' : 'bound';
    } finally { fs.rmdirSync(lock); }
  } catch { invalid(); }
}
function bindingStatus({ stateDir, framework, passportId, origin }) {
  try {
    const basename = identityName(framework, passportId, origin);
    if (typeof stateDir !== 'string') invalid();
    noSymlinkComponents(path.dirname(stateDir));
    try { fs.lstatSync(stateDir); } catch (error) { if (error.code === 'ENOENT') return 'not configured'; throw error; }
    noSymlinkComponents(stateDir);
    const dir = fs.lstatSync(stateDir);
    if (!dir.isDirectory() || (typeof process.getuid === 'function' && dir.uid !== process.getuid())) invalid();
    try { fs.lstatSync(path.join(stateDir, '.installation-binding.lock')); return 'unresolved'; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    const file = path.join(stateDir, basename);
    try { fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return 'not configured'; throw error; }
    if ((dir.mode & 0o077) !== 0) invalid();
    const record = readRecord(file);
    const base = `${origin}/api/agent-installations/${record.installation_id}`;
    validateHandoff({ schema_version: 'agent-installation-handoff/v1', installation_id: record.installation_id,
      reporter_endpoint: `${base}/reports`, test_result_endpoint: `${base}/tests/{test_id}/results`,
      token_presentation: 'Authorization: Bearer <reporter_token>', reporter_token: record.reporter_token }, origin);
    return 'unverified';
  } catch { return 'unresolved'; }
}
function loadBinding(options) {
  if (bindingStatus(options) !== 'unverified') invalid();
  return readRecord(path.join(options.stateDir, identityName(options.framework, options.passportId, options.origin)));
}
module.exports = { bindHandoff, bindingStatus, loadBinding, identityName, noSymlinkComponents, readProtected, supportedFramework };

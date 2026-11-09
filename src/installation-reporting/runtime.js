'use strict';

const path = require('node:path');
const fs = require('node:fs');
const { createHash, randomUUID } = require('node:crypto');
const { bindHandoff, bindingStatus, loadBinding, identityName, readProtected } = require('./binding');
const spool = require('./spool');
const VERSION = '1.0.37'; // Updated by the normal lockstep release script.
const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

function location(options) {
  const origin = new URL(options.apiUrl).origin;
  const name = identityName(options.framework, options.passportId, origin).replace(/\.json$/, '');
  return { origin, dir: path.join(options.configDir, '.aport-reporting', name),
    stateDir: path.join(options.configDir, 'aport') };
}
function envelope(a, mode, reports, authMode = 'api') {
  return { schema_version: 'agent-installation-report/v1', event_id: randomUUID(), timestamp: new Date().toISOString(),
    source_id: a.binding.installation_id, config_digest: digest(['installation-config/v1', a.framework, a.origin, a.binding.installation_id, mode, authMode]),
    adapter_version: VERSION, mode, reports };
}
function enabled(options) { return options.authMode === 'api' && process.env.APORT_REPORTING_DISABLED !== '1'; }
function setup(options, handoffFile, { allowRotation = false, coverage } = {}) {
  if (!enabled(options)) return { state: 'not configured', queued: 0, dropped: 0 };
  const loc = location(options);
  const bindingOptions = { ...loc, framework: options.framework, passportId: options.passportId };
  const result = handoffFile ? bindHandoff({ ...bindingOptions, handoffFile, allowRotation }) : 'reused';
  const binding = loadBinding(bindingOptions);
  spool.provision(loc.dir, { binding, framework: options.framework, origin: loc.origin });
  const a = spool.authority(loc.dir);
  const reports = [{ kind: 'heartbeat' }];
  // Consent is explicit and the caller supplies the small contract object,
  // never a manifest from which arbitrary descriptions/schemas are extracted.
  if (coverage !== undefined) {
    if (process.env.APORT_REPORT_DECLARED_COVERAGE !== '1') throw Error('Coverage consent required');
    reports.push(coverage);
  }
  spool.enqueue(loc.dir, envelope(a, options.mode || 'enforce', reports));
  return { ...spool.status(loc.dir), binding: result };
}
function setupFromEnvironment(options = fromEnvironment()) {
  if (!enabled(options)) return { state: 'not configured', queued: 0, dropped: 0 };
  let coverage;
  if (process.env.APORT_INSTALLATION_COVERAGE_FILE) {
    if (process.env.APORT_REPORT_DECLARED_COVERAGE !== '1') throw Error('Coverage consent required');
    const file = process.env.APORT_INSTALLATION_COVERAGE_FILE;
    require('./binding').noSymlinkComponents(path.dirname(file));
    coverage = JSON.parse(readProtected(file, 32768));
  }
  return setup(options, process.env.APORT_INSTALLATION_HANDOFF_FILE,
    { allowRotation: process.env.APORT_INSTALLATION_ROTATE === '1', coverage });
}
function report(options, decisionId, disposition = 'not_reported') {
  try {
    if (!enabled(options)) return false;
    const loc = location(options);
    // A binding is checked again on each producer call; a changed passport or
    // revoked local binding cannot reuse the previous installation's spool.
    const binding = loadBinding({ ...loc, framework: options.framework, passportId: options.passportId });
    let a;
    try { a = spool.authority(loc.dir); }
    catch (e) {
      if (e.code !== 'ENOENT') throw e;
      try { fs.lstatSync(loc.dir); return false; }
      catch (missing) { if (missing.code !== 'ENOENT') throw missing; }
      // Upgrade an already-consented groundwork binding without requiring a
      // second handoff. Existing incomplete/retired scopes are not repaired here.
      spool.provision(loc.dir, { binding, framework: options.framework, origin: loc.origin });
      a = spool.authority(loc.dir);
    }
    if (binding.installation_id !== a.binding.installation_id || binding.reporter_token !== a.binding.reporter_token) return false;
    const reports = decisionId ? [{ kind: 'decision', decision_id: decisionId, host_disposition: disposition }] : [{ kind: 'heartbeat' }];
    spool.enqueue(loc.dir, envelope(a, options.mode || 'enforce', reports));
    return true;
  } catch { return false; }
}
function connectionStatus(options) {
  if (!enabled(options)) return { state: 'not configured', queued: 0, dropped: 0 };
  try {
    const loc = location(options), { dir } = loc;
    try { fs.lstatSync(dir); } catch (e) {
      if (e.code === 'ENOENT') return { state: bindingStatus({ ...loc, framework: options.framework, passportId: options.passportId }), queued: 0, dropped: 0 };
      throw e;
    }
    return spool.status(dir);
  } catch { return { state: 'unresolved', queued: null, dropped: null }; }
}
async function lifecycle(configDir, framework, mode, removed = false, selector, authMode = 'api') {
  const disabled = process.env.APORT_REPORTING_DISABLED === '1';
  if (disabled && !removed) return;
  function removalBlocked() {
    if (!removed) return false;
    // Public CLI callers cannot announce removal while authorization state is
    // still installed or preserved for another hook. Broken links also count.
    try { fs.lstatSync(path.join(configDir, 'aport')); return true; }
    catch (e) { if (e.code !== 'ENOENT') throw e; return false; }
  }
  // This lives outside aport/ so committed reset can still report removal.
  const root = path.join(configDir, '.aport-reporting');
  try {
    spool.directory(root);
    const entries = fs.readdirSync(root);
    if (entries.length > 512) return;
    const deadline = Date.now() + spool.LIMITS.lockWaitMs;
    for (const entry of entries) {
      if (!/^installation-v1-[a-f0-9]{64}$/.test(entry)) continue;
      if (!removed && entry !== selector) continue;
      try {
        await spool.retryQueueLock(() => {
          // A reinstall during a contention wait must preserve its authority.
          if (removalBlocked()) return;
          const dir = path.join(root, entry), a = spool.authority(dir);
          if (a.framework !== framework) return;
          if (disabled) { spool.forgetCredential(dir); return; }
          const effectiveMode = mode || spool.currentMode(dir);
          spool.enqueue(dir, envelope(a, effectiveMode, removed ? [{ kind: 'lifecycle', state: 'removed' }] : [{ kind: 'heartbeat' }], authMode));
        }, deadline);
      } catch { /* Failure cannot roll back a committed local change. */ }
    }
  } catch { /* No binding or unsafe state. */ }
}
function statuses(configDir) {
  try {
    const root = path.join(configDir, '.aport-reporting');
    try { fs.lstatSync(root); } catch (e) { if (e.code === 'ENOENT') return [{ state: 'not configured', queued: 0, dropped: 0 }]; throw e; }
    spool.directory(root);
    const entries = fs.readdirSync(root);
    if (entries.length > 512) throw Error('Unresolved');
    return entries.filter(entry => /^installation-v1-[a-f0-9]{64}$/.test(entry)).map(entry => spool.status(path.join(root, entry)));
  } catch { return [{ state: 'unresolved', queued: null, dropped: null }]; }
}
function fromEnvironment(env = process.env) {
  return { configDir: env.APORT_CONFIG_DIR, framework: env.APORT_HOOK_FRAMEWORK,
    passportId: env.APORT_AGENT_ID, apiUrl: env.APORT_API_URL || 'https://api.aport.io',
    authMode: env.APORT_GUARDRAIL_MODE, mode: env.APORT_ENFORCEMENT_MODE || 'enforce' };
}
function preAction(options, metadata) {
  if (!report(options, metadata.decision_id)) return false;
  remember(options, metadata);
  return true;
}
function remember(options, metadata) {
  try {
    if (!enabled(options)) return false;
    if (metadata.call_key && metadata.decision_id) spool.correlation(location(options).dir, metadata.call_key,
      { decision_id: metadata.decision_id, allow: metadata.allow, mode: options.mode || 'enforce' });
  } catch { /* Missing/ambiguous correlation keeps not_reported. */ }
  return true;
}
function postAction(options, callKey) {
  try {
    if (!enabled(options) || !['codex', 'langchain'].includes(options.framework)) return false;
    const pending = spool.correlation(location(options).dir, callKey);
    if (!pending) return false;
    const disposition = pending.allow ? 'allowed' : pending.mode === 'warn' ? 'continued_after_warning'
      : pending.mode === 'observe' ? 'continued_after_observation' : 'not_reported';
    // An unexpected post-call after enforce DENY does not prove an enforced block.
    return report({ ...options, mode: pending.mode }, pending.decision_id, disposition);
  } catch { return false; }
}
module.exports = { setup, setupFromEnvironment, report, preAction, remember, postAction, connectionStatus, statuses, lifecycle, fromEnvironment, location };

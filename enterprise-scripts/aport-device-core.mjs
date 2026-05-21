#!/usr/bin/env node
/**
 * Cross-platform APort device installer core (macOS, Linux, Windows).
 * Used by aport-device-deploy/enforce/uninstall (.sh / .ps1) and release bundles.
 *
 * Commands: install | enforce | uninstall
 * Configuration: environment variables (see enterprise-scripts/README.md).
 */

import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const COMMAND = process.env.APORT_DEVICE_COMMAND || process.argv[2] || 'install';

function log(msg) {
  console.log(`[aport-device] ${msg}`);
}

function die(msg) {
  log(`ERROR: ${msg}`);
  process.exit(1);
}

function requireCmd(name) {
  let ok = false;
  if (isWin()) {
    ok = spawnSync('where', [name], { stdio: 'ignore', shell: true }).status === 0;
  } else {
    // Use bash: POSIX `command` is a shell builtin (spawnSync('command', …) fails on Linux CI).
    ok =
      spawnSync('bash', ['-c', `command -v ${JSON.stringify(name)}`], {
        stdio: 'ignore',
      }).status === 0;
    if (!ok) {
      ok = spawnSync('which', [name], { stdio: 'ignore' }).status === 0;
    }
  }
  if (!ok) die(`${name} is required`);
}

function isWin() {
  return process.platform === 'win32';
}

function isTruthy(v) {
  return /^(1|true|yes|y|on)$/i.test(String(v || '').trim());
}

/** Prevent command/path injection via APORT_TARGET_USER and passport IDs. */
function assertSafeUsername(user) {
  if (!/^[a-zA-Z0-9._-]+$/.test(user)) {
    die('APORT_TARGET_USER must contain only letters, numbers, dot, underscore, and hyphen');
  }
}

function assertSafePassportId(id, label) {
  if (!/^(ap|apt)_[a-zA-Z0-9_-]+$/.test(id)) {
    die(`${label} must be a valid APort passport id (ap_... or apt_...)`);
  }
}

function env(name, fallback = '') {
  return (process.env[name] ?? fallback).toString();
}

function loadConfig() {
  const framework = env('APORT_FRAMEWORK', 'claude-code').toLowerCase();
  const cfg = {
    npxPackage: env('APORT_NPX_PACKAGE', '@aporthq/aport-agent-guardrails'),
    packageVersion: env('APORT_PACKAGE_VERSION', ''),
    framework,
    platformId: env('APORT_PLATFORM_ID', `${framework}-enterprise`),
    apiUrl: env('APORT_API_URL', 'https://api.aport.io').replace(/\/$/, ''),
    apiKey: env('APORT_API_KEY', ''),
    templateId: env('APORT_TEMPLATE_ID', ''),
    targetUser: env('APORT_TARGET_USER', ''),
    targetHome: env('APORT_TARGET_HOME', ''),
    deviceId: env('APORT_DEVICE_ID', ''),
    stateDir: env('APORT_STATE_DIR', ''),
    stateFile: env('APORT_STATE_FILE', ''),
    skipUserSwitch: isTruthy(env('APORT_SKIP_USER_SWITCH', '')),
    disableDeviceInfo: isTruthy(env('DISABLE_DEVICE_INFO', '')),
  };

  if (cfg.packageVersion) {
    cfg.npxPackage = `@aporthq/aport-agent-guardrails@${cfg.packageVersion}`;
  }

  if (!cfg.stateDir) {
    cfg.stateDir = defaultStateDir(cfg.framework);
  }
  if (!cfg.stateFile) {
    cfg.stateFile = path.join(cfg.stateDir, 'state.env');
  }

  return cfg;
}

function defaultStateDir(framework) {
  if (process.platform === 'darwin') {
    return path.join('/Library/Application Support/APort', framework);
  }
  if (process.platform === 'win32') {
    const base = process.env.ProgramData || 'C:\\ProgramData';
    return path.join(base, 'APort', framework);
  }
  return path.join('/var/lib/aport', framework);
}

function validateFramework(framework) {
  const ok = new Set([
    'claude-code',
    'cursor',
    'openclaw',
    'langchain',
    'crewai',
    'deerflow',
    'n8n',
  ]);
  if (!ok.has(framework)) die(`Unsupported APORT_FRAMEWORK: ${framework}`);
}

function validateDeployConfig(cfg) {
  validateFramework(cfg.framework);
  if (!cfg.apiKey) die('Set APORT_API_KEY to an APort issue-scoped API key');
  if (!cfg.templateId) die('Set APORT_TEMPLATE_ID to the template passport ID');
  if (!/^apk_[a-zA-Z0-9_-]+$/.test(cfg.apiKey)) {
    die('APORT_API_KEY must be an APort API key (apk_...)');
  }
  assertSafePassportId(cfg.templateId, 'APORT_TEMPLATE_ID');
}

function jsonGet(obj, dotted) {
  let v = obj;
  for (const key of dotted.split('.')) {
    v = v?.[key];
  }
  return v === undefined || v === null ? '' : String(v);
}

function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, {
    encoding: 'utf8',
    shell: isWin(),
    ...options,
  });
  return result;
}

function curl(args) {
  const result = run('curl', args, { stdio: ['ignore', 'pipe', 'pipe'] });
  if (result.status !== 0) {
    const err = (result.stderr || result.stdout || '').trim();
    throw new Error(err || `curl exited ${result.status}`);
  }
  return result.stdout;
}

function targetUser(cfg) {
  if (cfg.targetUser) {
    assertSafeUsername(cfg.targetUser);
    return cfg.targetUser;
  }

  if (process.platform === 'win32') {
    const u = process.env.USERNAME || os.userInfo().username;
    if (!u || u.toLowerCase() === 'system') {
      die('Set APORT_TARGET_USER to the Windows account that runs the agent framework');
    }
    return u;
  }

  if (process.platform === 'darwin') {
    const stat = run('stat', ['-f', '%Su', '/dev/console']);
    const u = (stat.stdout || '').trim();
    if (u && u !== 'root') return u;
  }

  if (process.platform === 'linux') {
    const seat = run('loginctl', ['list-sessions', '--no-legend']);
    if (seat.status === 0 && seat.stdout) {
      const line = seat.stdout.split('\n').find((l) => l.includes('seat0') || l.includes('tty'));
      if (line) {
        const user = line.trim().split(/\s+/)[2];
        if (user && user !== 'root') return user;
      }
    }
    const who = run('who');
    if (who.status === 0 && who.stdout) {
      const u = who.stdout.trim().split(/\s+/)[0];
      if (u && u !== 'root') return u;
    }
  }

  const u = process.env.SUDO_USER || process.env.USER || os.userInfo().username;
  if (!u || u === 'root') {
    die('Set APORT_TARGET_USER to the account that runs the agent framework');
  }
  assertSafeUsername(u);
  return u;
}

function homeForUser(cfg, user) {
  assertSafeUsername(user);
  if (cfg.targetHome) return path.resolve(cfg.targetHome);

  if (process.platform === 'win32') {
    const profile = process.env.USERPROFILE;
    if (user.toLowerCase() === (process.env.USERNAME || '').toLowerCase() && profile) {
      return profile;
    }
    const drive = process.env.SystemDrive || 'C:';
    return path.join(drive, 'Users', user);
  }

  try {
    const passwd = fs.readFileSync('/etc/passwd', 'utf8');
    for (const line of passwd.split('\n')) {
      const parts = line.split(':');
      if (parts[0] === user && parts[5]) return parts[5];
    }
  } catch {
    /* ignore */
  }

  if (process.platform === 'darwin' && user.match(/^[a-zA-Z0-9._-]+$/)) {
    const dscl = run('dscl', ['.', '-read', `/Users/${user}`, 'NFSHomeDirectory']);
    if (dscl.status === 0) {
      const m = (dscl.stdout || '').match(/NFSHomeDirectory:\s*(.+)/);
      if (m) return m[1].trim();
    }
  }

  return path.join('/home', user);
}

function deviceId(cfg) {
  if (cfg.deviceId) return cfg.deviceId;

  if (process.platform === 'darwin') {
    const ioreg = run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
    if (ioreg.status === 0) {
      const m = (ioreg.stdout || '').match(/"IOPlatformSerialNumber"\s*=\s*"([^"]+)"/);
      if (m) return m[1];
    }
  }

  if (process.platform === 'linux') {
    for (const p of ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
      try {
        const id = fs.readFileSync(p, 'utf8').trim();
        if (id) return id;
      } catch {
        /* ignore */
      }
    }
  }

  if (process.platform === 'win32') {
    const ps = run('powershell', [
      '-NoProfile',
      '-Command',
      '(Get-CimInstance Win32_BIOS).SerialNumber',
    ]);
    const serial = (ps.stdout || '').trim();
    if (serial) return serial;
  }

  return os.hostname();
}

function deviceIdSource(cfg) {
  if (cfg.deviceId) return 'env';
  const id = deviceId(cfg);
  if (id === os.hostname()) return 'hostname';
  if (process.platform === 'darwin') return 'serial';
  if (process.platform === 'linux') return 'machine-id';
  if (process.platform === 'win32') return 'serial';
  return 'hostname';
}

function collectDeviceInfo(cfg, user) {
  if (cfg.disableDeviceInfo) return '';

  const info = {
    collected_at: new Date().toISOString(),
    collection_source: 'enterprise_script',
    framework: cfg.framework,
    platform_id: cfg.platformId,
    device_id: deviceId(cfg),
    device_id_source: deviceIdSource(cfg),
    hostname: os.hostname(),
    username: user,
    os: {
      name: os.type(),
      version: os.release(),
      arch: os.arch(),
      platform: process.platform,
    },
    runtime: {
      node_version: process.version,
      shell: process.env.SHELL || process.env.ComSpec || '',
    },
  };

  if (process.platform === 'darwin') {
    const sw = run('sw_vers', ['-productVersion']);
    if (sw.status === 0) info.os.version = (sw.stdout || '').trim();
  }

  return JSON.stringify(info);
}

function deriveTenantRef(cfg, user) {
  const id = deviceId(cfg);
  const payload = `${id}:${user}:${cfg.framework}:${cfg.templateId}`;
  const hash = crypto.createHash('sha256').update(payload).digest('hex').slice(0, 32);
  return `${cfg.framework}-${hash}`;
}

function frameworkConfigDir(home, framework) {
  switch (framework) {
    case 'claude-code':
      return path.join(home, '.claude');
    case 'cursor':
      return path.join(home, '.cursor');
    case 'openclaw':
      return path.join(home, '.openclaw');
    case 'langchain':
    case 'crewai':
    case 'deerflow':
      return path.join(home, '.aport', framework);
    case 'n8n':
      return path.join(home, '.n8n');
    default:
      return path.join(home, '.aport', framework);
  }
}

function parseState(content) {
  const out = {};
  for (const line of content.split('\n')) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (!m) continue;
    try {
      out[m[1]] = JSON.parse(m[2]);
    } catch {
      out[m[1]] = m[2].replace(/^'|'$/g, '');
    }
  }
  return out;
}

function loadState(cfg) {
  try {
    return parseState(fs.readFileSync(cfg.stateFile, 'utf8'));
  } catch {
    return {};
  }
}

function persistState(cfg, agentId, runtimeApiKey, tenantRef) {
  fs.mkdirSync(cfg.stateDir, { recursive: true, mode: 0o700 });
  const body = [
    `APORT_AGENT_ID=${JSON.stringify(agentId)}`,
    `APORT_RUNTIME_API_KEY=${JSON.stringify(runtimeApiKey)}`,
    `APORT_API_URL=${JSON.stringify(cfg.apiUrl)}`,
    `APORT_TEMPLATE_ID=${JSON.stringify(cfg.templateId)}`,
    `APORT_FRAMEWORK=${JSON.stringify(cfg.framework)}`,
    `APORT_PLATFORM_ID=${JSON.stringify(cfg.platformId)}`,
    `APORT_TENANT_REF=${JSON.stringify(tenantRef)}`,
  ].join('\n');
  fs.writeFileSync(cfg.stateFile, `${body}\n`, { mode: 0o600 });
}

function findExistingInstance(cfg, tenantRef) {
  const url = `${cfg.apiUrl}/api/check-instance?${new URLSearchParams({
    template_id: cfg.templateId,
    platform_id: cfg.platformId,
    tenant_ref: tenantRef,
  })}`;
  let response;
  try {
    response = curl(['-fsS', url]);
  } catch {
    die(
      'Could not verify whether this device already has a passport instance. Aborting to avoid duplicate issuance.'
    );
  }
  const data = JSON.parse(response);
  const exists = jsonGet(data, 'exists');
  const instanceId = jsonGet(data, 'instance_id') || jsonGet(data, 'data.instance_id');
  if (exists === 'true' && instanceId) return instanceId;
  if (exists === 'false') return '';
  die('Unexpected check-instance response. Aborting to avoid duplicate issuance.');
}

function createInstance(cfg, tenantRef, user, deviceInfoJson) {
  const body = {
    platform_id: cfg.platformId,
    tenant_ref: tenantRef,
    controller_id: env('APORT_CONTROLLER_ID', tenantRef),
    controller_type: env('APORT_CONTROLLER_TYPE', 'org'),
    agent_data: {
      name: env('APORT_AGENT_NAME', `${cfg.framework} on ${user}`),
      role: 'developer_assistant',
      description: `${cfg.framework} protected by APort device deployment`,
      framework: [cfg.framework],
    },
    overrides: { status: 'active' },
  };
  if (deviceInfoJson) body.device_info = JSON.parse(deviceInfoJson);

  const response = curl([
    '-fsS',
    '-X',
    'POST',
    `${cfg.apiUrl}/api/passports/${cfg.templateId}/instances`,
    '-H',
    'Content-Type: application/json',
    '-H',
    `Authorization: Bearer ${cfg.apiKey}`,
    '-d',
    JSON.stringify(body),
  ]);
  const data = JSON.parse(response);
  const agentId = jsonGet(data, 'instance_id') || jsonGet(data, 'data.instance_id');
  if (!agentId) die('Instance create response did not include instance_id');
  return agentId;
}

function createRuntimeSetupKey(cfg, agentId) {
  const response = curl([
    '-fsS',
    '-X',
    'POST',
    `${cfg.apiUrl}/api/passports/${agentId}/setup-key`,
    '-H',
    'Content-Type: application/json',
    '-H',
    `Authorization: Bearer ${cfg.apiKey}`,
    '-d',
    JSON.stringify({ name: `${cfg.framework} device runtime key for ${agentId}` }),
  ]);
  const data = JSON.parse(response);
  const key = jsonGet(data, 'key') || jsonGet(data, 'data.key');
  if (!key) die('Setup key response did not include a plaintext key');
  return key;
}

function isRoot() {
  try {
    return process.getuid() === 0;
  } catch {
    return false;
  }
}

function npxInstall(cfg, user, home, agentId, runtimeApiKey) {
  const args = [
    '--yes',
    cfg.npxPackage,
    cfg.framework,
    agentId,
    '--mode=api',
    `--api-url=${cfg.apiUrl}`,
    '--non-interactive',
  ];
  const envVars = {
    ...process.env,
    HOME: home,
    APORT_NONINTERACTIVE: '1',
    CI: '1',
    APORT_API_KEY: runtimeApiKey,
    APORT_AGENT_ID: agentId,
    APORT_API_URL: cfg.apiUrl,
  };

  if (!cfg.skipUserSwitch && isRoot() && !isWin()) {
    const result = spawnSync('sudo', ['-u', user, '-H', 'npx', ...args], {
      stdio: 'inherit',
      env: { ...envVars, HOME: home, USER: user, LOGNAME: user },
    });
    if (result.status !== 0) process.exit(result.status ?? 1);
    return;
  }

  const result = spawnSync('npx', args, { stdio: 'inherit', env: envVars, shell: false });
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function writeRuntimeConfig(cfg, user, home, agentId, runtimeApiKey) {
  const configDir = frameworkConfigDir(home, cfg.framework);
  const aportDir = path.join(configDir, 'aport');
  fs.mkdirSync(aportDir, { recursive: true });
  const modeFile = path.join(aportDir, 'guardrail-mode.env');
  const content = [
    'APORT_GUARDRAIL_MODE=api',
    `APORT_API_URL=${cfg.apiUrl}`,
    `APORT_AGENT_ID=${agentId}`,
    `APORT_API_KEY=${runtimeApiKey}`,
  ].join('\n');
  fs.writeFileSync(modeFile, `${content}\n`, { mode: 0o600 });

  if (isRoot() && !isWin()) {
    spawnSync('chown', ['-R', user, aportDir], { stdio: 'ignore' });
  }
}

function hookPresent(home, framework) {
  if (framework === 'claude-code') {
    try {
      const settings = fs.readFileSync(path.join(home, '.claude', 'settings.json'), 'utf8');
      return settings.includes('aport-claude-code-hook.sh');
    } catch {
      return false;
    }
  }
  if (framework === 'cursor') {
    try {
      const hooks = fs.readFileSync(path.join(home, '.cursor', 'hooks.json'), 'utf8');
      return hooks.includes('aport-cursor-hook.sh');
    } catch {
      return false;
    }
  }
  return fs.existsSync(path.join(frameworkConfigDir(home, framework), 'aport', 'guardrail-mode.env'));
}

function installAction(cfg) {
  requireCmd('curl');
  requireCmd('node');
  requireCmd('npx');

  const user = targetUser(cfg);
  const home = homeForUser(cfg, user);
  if (!home) die(`Could not resolve home directory for ${user}`);

  const tenantRef = deriveTenantRef(cfg, user);
  const deviceInfoJson = collectDeviceInfo(cfg, user);

  let state = loadState(cfg);
  let agentId = state.APORT_AGENT_ID || '';
  let runtimeApiKey = state.APORT_RUNTIME_API_KEY || '';

  if (!agentId) {
    agentId = findExistingInstance(cfg, tenantRef);
    if (agentId) {
      log(`Reusing existing passport instance ${agentId}`);
    } else {
      log(`Creating passport instance for ${cfg.framework} tenant_ref=${tenantRef}`);
      agentId = createInstance(cfg, tenantRef, user, deviceInfoJson);
    }
  } else {
    log(`Using persisted passport instance ${agentId}`);
  }
  assertSafePassportId(agentId, 'instance_id');

  if (!runtimeApiKey) {
    log(`Minting read-scoped runtime key for ${agentId}`);
    runtimeApiKey = createRuntimeSetupKey(cfg, agentId);
  }

  persistState(cfg, agentId, runtimeApiKey, tenantRef);
  npxInstall(cfg, user, home, agentId, runtimeApiKey);
  writeRuntimeConfig(cfg, user, home, agentId, runtimeApiKey);
  log(`Install complete for ${cfg.framework} (${agentId})`);
}

function enforceAction(cfg) {
  validateDeployConfig(cfg);
  const user = targetUser(cfg);
  const home = homeForUser(cfg, user);
  if (!home) die(`Could not resolve home directory for ${user}`);

  const state = fs.existsSync(cfg.stateFile) ? loadState(cfg) : {};
  const needsInstall =
    !state.APORT_AGENT_ID ||
    !state.APORT_RUNTIME_API_KEY ||
    !hookPresent(home, cfg.framework);

  if (needsInstall) {
    if (!fs.existsSync(cfg.stateFile)) log('State file missing');
    else if (!hookPresent(home, cfg.framework)) log('Framework guardrail configuration missing');
    return installAction(cfg);
  }

  writeRuntimeConfig(cfg, user, home, state.APORT_AGENT_ID, state.APORT_RUNTIME_API_KEY);
  log(`Enforcement check passed for ${cfg.framework} (${state.APORT_AGENT_ID})`);
}

function uninstallAction(cfg) {
  validateFramework(cfg.framework);
  requireCmd('npx');

  const user = targetUser(cfg);
  const home = homeForUser(cfg, user);
  if (!home) die(`Could not resolve home directory for ${user}`);

  const args = ['--yes', cfg.npxPackage, 'reset', cfg.framework, '--yes'];
  const envVars = { ...process.env, HOME: home, APORT_NONINTERACTIVE: '1', CI: '1' };

  if (!cfg.skipUserSwitch && isRoot() && !isWin()) {
    const result = spawnSync('sudo', ['-u', user, '-H', 'npx', ...args], {
      stdio: 'inherit',
      env: { ...envVars, HOME: home, USER: user, LOGNAME: user },
    });
    if (result.status !== 0) process.exit(result.status ?? 1);
  } else {
    const result = spawnSync('npx', args, { stdio: 'inherit', env: envVars, shell: false });
    if (result.status !== 0) process.exit(result.status ?? 1);
  }

  try {
    fs.rmSync(cfg.stateDir, { recursive: true, force: true });
  } catch {
    /* ignore */
  }
  log(`Uninstall complete for ${cfg.framework}`);
}

function main() {
  const cfg = loadConfig();

  switch (COMMAND) {
    case 'install':
      validateDeployConfig(cfg);
      installAction(cfg);
      break;
    case 'enforce':
      enforceAction(cfg);
      break;
    case 'uninstall':
      uninstallAction(cfg);
      break;
    default:
      die(`Unknown command: ${COMMAND}. Use install, enforce, or uninstall.`);
  }
}

main();

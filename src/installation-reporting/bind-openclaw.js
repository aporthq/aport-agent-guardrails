'use strict';
const { setupFromEnvironment } = require('./runtime');
try {
  const status = setupFromEnvironment({ configDir: process.env.APORT_CONFIG_DIR, framework: 'openclaw',
    passportId: process.env.APORT_INSTALLATION_PASSPORT_ID, apiUrl: process.env.APORT_INSTALLATION_API_URL,
    authMode: 'api', mode: process.env.APORT_ENFORCEMENT_MODE || 'enforce' });
  if (status.state === 'not configured') process.stdout.write('Reporting connection: not configured.\n');
  else process.stdout.write(`Installation handoff stored; reporting connection is unverified. Queued: ${status.queued}; dropped: ${status.dropped}.\n`);
} catch {
  process.stderr.write('Installation handoff binding could not be confirmed; reporting remains unverified.\n');
  process.exitCode = 1;
}

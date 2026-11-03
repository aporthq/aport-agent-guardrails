'use strict';
const { bindHandoff } = require('./binding');
try {
  const { APORT_INSTALLATION_HANDOFF_FILE: handoffFile, APORT_CONFIG_DIR: configDir, APORT_INSTALLATION_PASSPORT_ID: passportId, APORT_INSTALLATION_API_URL: apiUrl } = process.env;
  const origin = new URL(apiUrl).origin;
  bindHandoff({ stateDir: require('node:path').join(configDir, 'aport'), framework: 'openclaw', passportId, origin, handoffFile,
    allowRotation: process.env.APORT_INSTALLATION_ROTATE === '1' });
  process.stdout.write('Installation handoff stored; reporting connection is unverified.\n');
} catch {
  process.stderr.write('Installation handoff binding could not be confirmed; reporting remains unverified.\n');
  process.exitCode = 1;
}

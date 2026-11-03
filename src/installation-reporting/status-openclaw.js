'use strict';
const { bindingStatus } = require('./binding');
try {
  const { APORT_CONFIG_DIR: configDir, APORT_INSTALLATION_PASSPORT_ID: passportId, APORT_INSTALLATION_API_URL: apiUrl } = process.env;
  const origin = new URL(apiUrl).origin;
  const state = bindingStatus({ stateDir: require('node:path').join(configDir, 'aport'), framework: 'openclaw', passportId, origin });
  process.stdout.write(`Reporting connection: ${state}.\n`);
} catch {
  process.stdout.write('Reporting connection: unresolved.\n');
}

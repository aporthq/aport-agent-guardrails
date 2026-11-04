'use strict';
const { connectionStatus } = require('./runtime');
const status = connectionStatus({ configDir: process.env.APORT_CONFIG_DIR, framework: 'openclaw',
  passportId: process.env.APORT_INSTALLATION_PASSPORT_ID, apiUrl: process.env.APORT_INSTALLATION_API_URL, authMode: 'api' });
process.stdout.write(`Reporting connection: ${status.state}. Queued: ${status.queued}; dropped: ${status.dropped}.\n`);

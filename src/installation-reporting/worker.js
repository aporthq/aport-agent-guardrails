'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { directory, drain, workerStatus, startWorker } = require('./spool');
const dir = process.argv[2];
(async () => {
  directory(dir); directory(path.join(dir, 'worker.lock'));
  try { await drain(dir); }
  finally {
    fs.rmdirSync(path.join(dir, 'worker.lock'));
    // Close the enqueue-versus-exit race: a producer may have observed our
    // lock after the final empty read. Release first, then check for new work.
    if ((await workerStatus(dir)).queued > 0) startWorker(dir);
  }
})().catch(() => { process.exitCode = 1; });

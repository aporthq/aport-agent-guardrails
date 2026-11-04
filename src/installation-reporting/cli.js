'use strict';
const runtime = require('./runtime');
const options = runtime.fromEnvironment();
async function main() {
  switch (process.argv[2]) {
    case 'setup': {
      const status = runtime.setupFromEnvironment(options);
      process.stdout.write(JSON.stringify(status) + '\n');
      break;
    }
    case 'decision':
    case 'remember':
    case 'pre':
    case 'post': {
      let input = '';
      for await (const chunk of process.stdin) { input += chunk; if (Buffer.byteLength(input) > 2048) throw Error('Too large'); }
      const metadata = JSON.parse(input);
      if (process.argv[2] === 'post') {
        if (Object.keys(metadata).join(',') !== 'call_key') throw Error('Invalid metadata');
        runtime.postAction(options, metadata.call_key);
        break;
      }
      if (Object.keys(metadata).sort().join(',') !== (['pre', 'remember'].includes(process.argv[2]) ? 'allow,call_key,decision_id' : 'decision_id') ||
          (metadata.decision_id !== null && typeof metadata.decision_id !== 'string')) throw Error('Invalid metadata');
      if (process.argv[2] === 'remember') runtime.remember(options, metadata);
      else if (process.argv[2] === 'pre') runtime.preAction(options, metadata);
      else runtime.report(options, metadata.decision_id);
      break;
    }
    case 'status': process.stdout.write(JSON.stringify(runtime.statuses(options.configDir)) + '\n'); break;
    case 'mode': runtime.lifecycle(options.configDir, options.framework, options.mode, false,
      require('node:path').basename(runtime.location(options).dir), process.env.APORT_INSTALLATION_AUTH_MODE || options.authMode); break;
    case 'removed': runtime.lifecycle(options.configDir, options.framework, undefined, true); break;
    default: throw Error('Unknown reporting operation');
  }
}
main().catch(() => { process.stderr.write('Reporting connection unresolved.\n'); process.exitCode = 1; });

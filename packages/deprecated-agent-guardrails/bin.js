#!/usr/bin/env node

// Deprecation wrapper bin for @aporthq/agent-guardrails → @aporthq/aport-agent-guardrails

console.warn('\n⚠️  DEPRECATION WARNING\n');
console.warn('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.warn('Package @aporthq/agent-guardrails has been RENAMED to:');
console.warn('  @aporthq/aport-agent-guardrails');
console.warn('');
console.warn('Please update your usage:');
console.warn('  npx @aporthq/aport-agent-guardrails');
console.warn('');
console.warn('This wrapper will be removed in a future version.');
console.warn('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

// Forward to the new package's bin
const { spawn } = require('child_process');
const path = require('path');

// Find the new package's bin directory
const newPackageBin = path.join(
  require.resolve('@aporthq/aport-agent-guardrails/package.json'),
  '..',
  'bin',
  'agent-guardrails'
);

// Forward all arguments to the new package
const child = spawn(newPackageBin, process.argv.slice(2), {
  stdio: 'inherit',
  shell: false
});

child.on('exit', (code) => {
  process.exit(code);
});

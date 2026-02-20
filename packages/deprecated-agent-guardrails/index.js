#!/usr/bin/env node

// Deprecation wrapper for @aporthq/agent-guardrails → @aporthq/aport-agent-guardrails

console.warn('\n⚠️  DEPRECATION WARNING\n');
console.warn('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.warn('Package @aporthq/agent-guardrails has been RENAMED to:');
console.warn('  @aporthq/aport-agent-guardrails');
console.warn('');
console.warn('Please update your dependencies:');
console.warn('  npm install @aporthq/aport-agent-guardrails');
console.warn('');
console.warn('This wrapper will be removed in a future version.');
console.warn('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

// Re-export everything from the new package
module.exports = require('@aporthq/aport-agent-guardrails');

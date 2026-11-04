// Deliberately mutate the production owners, exercise collected adapter tests,
// and restore byte-for-byte even when an assertion or process fails.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const mutations = [
  { name: 'serializer', file: 'src/installation-reporting/contract.js',
    from: 'decision_id: string(item.decision_id, DECISION_ID)', to: 'decision_id: item.decision_id',
    pattern: 'real metadata CLI', assertion: 'SERIALIZER_REJECTS_URL' },
  { name: 'redaction', file: 'src/installation-reporting/cli.js',
    from: "Object.keys(metadata).sort().join(',') !== (['pre', 'remember'].includes(process.argv[2]) ? 'allow,call_key,decision_id' : 'decision_id')",
    to: 'false', pattern: 'real metadata CLI', assertion: 'CLI_REDACTION' },
  { name: 'spool-permissions', file: 'src/installation-reporting/binding.js',
    from: '(stat.mode & 0o077) !== 0', to: 'false', pattern: 'protected spool', assertion: 'PROTECTED_SPOOL_permissions' },
  { name: 'disposition', file: 'src/installation-reporting/runtime.js',
    from: "disposition = 'not_reported'", to: "disposition = 'allowed'",
    pattern: 'real shell harness', assertion: 'SHELL_PRE_NOT_EXECUTION' },
];
const results = [];
for (const mutation of mutations) {
  const file = path.join(root, mutation.file), original = fs.readFileSync(file, 'utf8');
  if (!original.includes(mutation.from)) throw Error(`Mutation target missing: ${mutation.name}`);
  try {
    fs.writeFileSync(file, original.replace(mutation.from, mutation.to));
    const result = spawnSync(process.execPath, ['--test', `--test-name-pattern=${mutation.pattern}`, 'tests/unit/installation-reporting-integration.test.js'],
      { cwd: root, encoding: 'utf8', timeout: 60000 });
    const output = result.stdout + result.stderr;
    if (result.status === 0 || !output.includes(mutation.assertion)) throw Error(`Mutation escaped named assertion: ${mutation.name}\n${output}`);
    results.push({ mutation: mutation.name, owner: mutation.file, assertion: mutation.assertion, exit: result.status, restored: true });
  } finally { fs.writeFileSync(file, original); }
}
process.stdout.write(JSON.stringify(results, null, 2) + '\n');

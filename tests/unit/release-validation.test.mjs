import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const version = JSON.parse(readFileSync(join(root, 'packages/core/package.json'))).version;
const recordName = `installation-reporting-release-${version}.json`;
const historical = JSON.parse(readFileSync(join(root, 'docs/reviews', recordName)));
const json = (path, value) => writeFileSync(path, JSON.stringify(value, null, 2) + '\n');
function scratch(t) {
  const dir = mkdtempSync(join(process.env.TMPDIR || tmpdir(), 'aport-release-regression-'));
  t.after(() => rmSync(dir, {recursive:true, force:true}));
  return dir;
}
function run(script, args = [], options = {}) {
  return spawnSync(process.execPath, [join(root, script), ...args], {encoding:'utf8', timeout:60000, ...options});
}
function success(result) {
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr || result.stdout);
}
// Synthetic builder inputs, not new artifact inspection evidence. Seed the
// accepted shape from an actual record so rejection tests cannot pass on a
// broken positive control. Only the gate under test is changed per case.
function inputs() {
  const artifact = ({reporter_file_count, ...entry}) => ({...entry, reporter_files:Array(reporter_file_count).fill('fixture.js')});
  return {
    artifacts: {
      canonical_version:version,
      reporter_source:{...historical.reporter_source, files:Object.keys(historical.reporter_source.sha256)},
      npm_artifacts:historical.artifacts.npm.map(artifact),
      python_wheels:historical.artifacts.python_wheels.map(artifact),
      enterprise_bundle:historical.artifacts.enterprise_bundle,
      problems:[],
    },
    fixtures: {
      candidate_version:version, contract:historical.contract,
      ...historical.deterministic_validation,
      total_requests_received:historical.deterministic_validation.total_fixture_requests,
    },
  };
}
function build(dir, evidence) {
  const artifacts = join(dir, 'artifacts.json'), fixtures = join(dir, 'fixtures.json'), out = join(dir, 'record.json');
  json(artifacts, evidence.artifacts); json(fixtures, evidence.fixtures);
  return {result:run('scripts/build-release-verification-record.mjs', ['--artifacts', artifacts, '--fixtures', fixtures, '--out', out]), out};
}

test('builder accepts a successful inspection and its output passes the record validator', t => {
  const {result, out} = build(scratch(t), inputs());
  success(result);
  success(run('scripts/check-release-verification-record.mjs', [out]));
});
for (const [name, value] of [['failure', ['credential-material inspection failed']], ['missing', undefined], ['null', null], ['object', {}], ['empty-string', '']]) {
  test(`builder refuses ${name} artifact inspection result without writing a clean record`, t => {
    const evidence = inputs();
    evidence.artifacts.problems = value;
    const {result, out} = build(scratch(t), evidence);
    assert.equal(result.error, undefined);
    assert.equal(result.status, 1, 'failed inspection was converted to release evidence');
    assert.match(result.stderr, /artifact inspection/);
    assert.equal(existsSync(out), false);
  });
}
for (const value of [undefined, null, {}, '']) {
  test(`builder requires an explicit fixture violation list (${JSON.stringify(value)})`, t => {
    const evidence = inputs();
    evidence.fixtures.scenario_invariants = {asserted:true, violations:value};
    const {result, out} = build(scratch(t), evidence);
    assert.equal(result.error, undefined);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /scenario invariant/);
    assert.equal(existsSync(out), false);
  });
}

test('matrix observes rejection and zero requests, and fails with installation scope checks removed', t => {
  const dir = scratch(t), clean = join(dir, 'clean.json');
  success(run('scripts/validate-release-fixture-matrix.mjs', ['--out', clean]));
  const matrix = JSON.parse(readFileSync(clean)), rotation = matrix.outcomes.find(o => o.outcome === 'rotation');
  assert.equal(rotation.different_installation_enqueue_rejected, true);
  assert.equal(rotation.different_installation_requests_sent, 0);
  assert.equal(rotation.rotated_token_same_installation_accepted, true);
  const mutant = join(dir, 'reporter');
  cpSync(join(root, 'src/installation-reporting'), mutant, {recursive:true});
  const edits = [
    ['reporter.js', "if (value.source_id !== this.#installationId) throw new TypeError('Invalid installation reporting scope');", ''],
    ['transport.js', 'value.source_id !== binding.installation_id || ', ''],
  ];
  for (const [file, before, after] of edits) {
    const path = join(mutant, file), source = readFileSync(path, 'utf8');
    assert.ok(source.includes(before), `scope mutation did not reach ${file}`);
    writeFileSync(path, source.replaceAll(before, after));
  }
  const failed = join(dir, 'failed.json');
  const result = run('scripts/validate-release-fixture-matrix.mjs', ['--runtime-dir', mutant, '--out', failed]);
  assert.equal(result.error, undefined);
  assert.equal(result.status, 1, 'scope bypass received successful release evidence');
  const broken = JSON.parse(readFileSync(failed));
  assert.ok(broken.scenario_invariants.violations.some(v => v.startsWith('rotation.different_installation_enqueue_rejected')));
  assert.equal(broken.outcomes.find(o => o.outcome === 'rotation').different_installation_requests_sent, 1);
  assert.equal(broken.fixture_server.requests_outside_fixture_origin, 0);
});

test('collected record test selects the next release without changing historical evidence', t => {
  const dir = scratch(t), repo = join(dir, 'repo');
  for (const file of ['scripts/check-release-verification-record.mjs', 'tests/unit/test-release-verification-record.sh']) {
    mkdirSync(dirname(join(repo, file)), {recursive:true});
    cpSync(join(root, file), join(repo, file));
  }
  mkdirSync(join(repo, 'packages/core'), {recursive:true});
  mkdirSync(join(repo, 'docs/reviews'), {recursive:true});
  const next = version.replace(/\d+$/, n => Number(n) + 1);
  json(join(repo, 'packages/core/package.json'), {version:next});
  const oldFile = join(repo, 'docs/reviews', recordName);
  json(oldFile, historical);
  const oldBytes = readFileSync(oldFile, 'utf8'), record = structuredClone(historical);
  record.candidate_version = next;
  for (const entry of [...record.artifacts.npm, ...record.artifacts.python_wheels]) entry.version = next;
  record.artifacts.enterprise_bundle.version = next;
  record.artifacts.enterprise_bundle.manifest_version = next;
  const current = join(repo, 'docs/reviews', `installation-reporting-release-${next}.json`);
  json(current, record);
  const options = {cwd:repo, encoding:'utf8', timeout:60000, env:{...process.env, GIT_CEILING_DIRECTORIES:dir, APORT_TEST_DIR:join(dir, 'outputs')}};
  success(spawnSync('bash', [join(repo, 'tests/unit/test-release-verification-record.sh')], options));
  assert.equal(readFileSync(oldFile, 'utf8'), oldBytes);
  rmSync(current);
  const missing = spawnSync('bash', [join(repo, 'tests/unit/test-release-verification-record.sh')], options);
  assert.equal(missing.status, 1, 'missing current evidence must not fall back to historical evidence');
  assert.ok(missing.stderr.includes(`installation-reporting-release-${next}.json`));
});

function matrixSnapshot(dir) {
  for (const file of ['scripts/validate-release-fixture-matrix.mjs', 'bin/lib/installation-reporting.sh', 'bin/lib/hook-runtime.sh', 'packages/core/package.json']) {
    mkdirSync(dirname(join(dir, file)), {recursive:true});
    cpSync(join(root, file), join(dir, file));
  }
  for (const tree of ['src', 'python', 'enterprise-scripts']) symlinkSync(join(root, tree), join(dir, tree), 'dir');
}
function snapshotMatrix(dir) {
  const out = join(dir, 'matrix.json');
  const result = spawnSync(process.execPath, [join(dir, 'scripts/validate-release-fixture-matrix.mjs'), '--out', out], {encoding:'utf8', timeout:60000});
  assert.equal(result.error, undefined);
  return {result, matrix:JSON.parse(readFileSync(out))};
}

test('shell no-binding fixture reaches its gate and rejects a removed binding guard', t => {
  const dir = scratch(t);
  matrixSnapshot(dir);
  const clean = snapshotMatrix(dir);
  success(clean.result);
  const shell = clean.matrix.outcomes.find(o => o.outcome === 'producer_coverage_no_binding').producers.find(p => p.producer.startsWith('shell'));
  assert.equal(shell.reporting_invocations_without_binding, 0);
  assert.equal(shell.reporting_invocations_with_marker, 1, 'enabled shell positive control never reached reporting');
  assert.equal(shell.positive_control_metadata_valid, true);
  const file = join(dir, 'bin/lib/installation-reporting.sh');
  const source = readFileSync(file, 'utf8');
  const guard = '[ -d "${APORT_CONFIG_DIR:-}/.aport-reporting" ] || compgen -G "${APORT_CONFIG_DIR:-}/aport/installation-v1-*.json" > /dev/null || return 0';
  assert.ok(source.includes(guard), 'shell mutation did not reach the missing-binding gate');
  writeFileSync(file, source.replace(guard, ':'));
  const broken = snapshotMatrix(dir);
  assert.equal(broken.result.status, 1, 'removed shell binding guard received successful release evidence');
  const observation = broken.matrix.outcomes.find(o => o.outcome === 'producer_coverage_no_binding');
  assert.equal(observation.producers.find(p => p.producer.startsWith('shell')).reporting_invocations_without_binding, 1);
  assert.ok(broken.matrix.scenario_invariants.violations.some(v => v.startsWith('producer_coverage_no_binding.')));
});

test('queue-pressure evidence observes the outage and recovery rather than only selecting a fault mode', t => {
  const dir = scratch(t);
  matrixSnapshot(dir);
  const clean = snapshotMatrix(dir);
  success(clean.result);
  const queue = clean.matrix.outcomes.find(o => o.outcome === 'queue_pressure');
  assert.equal(queue.unavailable_responses, 1);
  assert.equal(queue.accepted_after_recovery, 2);
  assert.equal(queue.retry_preserved_identity, true);
  assert.equal(queue.queued_after_delivery, 0);
  assert.equal(queue.dropped, 3);
  const script = join(dir, 'scripts/validate-release-fixture-matrix.mjs');
  const source = readFileSync(script, 'utf8');
  const fault = 'return new Response(JSON.stringify({ error: "unavailable" }), { status: 503 });';
  assert.ok(source.includes(fault), 'outage mutation did not reach the fixture response');
  writeFileSync(script, source.replace(fault, 'return new Response(JSON.stringify({ event_id: parsed?.event_id, accepted: parsed?.reports?.length ?? 0 }), { status: 200 });'));
  const broken = snapshotMatrix(dir);
  assert.equal(broken.result.status, 1, 'unobserved outage received successful release evidence');
  assert.equal(broken.matrix.outcomes.find(o => o.outcome === 'queue_pressure').unavailable_responses, 0);
  assert.ok(broken.matrix.scenario_invariants.violations.some(v => v.startsWith('queue_pressure.')));
});

test('missing delivery cannot reuse a previous scenario receipt as successful evidence', t => {
  const dir = scratch(t);
  matrixSnapshot(dir);
  const script = join(dir, 'scripts/validate-release-fixture-matrix.mjs');
  const source = readFileSync(script, 'utf8');
  const enqueue = 'reporter.enqueueReport(report([{ kind: "heartbeat" }], { mode }));';
  assert.ok(source.includes(enqueue), 'mutation did not reach the mode-change producer');
  writeFileSync(script, source.replace(enqueue, `if (mode !== "enforce") ${enqueue}`));
  const broken = snapshotMatrix(dir);
  assert.equal(broken.result.status, 1, 'missing delivery reused the previous receipt as evidence');
  assert.ok(broken.matrix.scenario_invariants.violations.some(v => v.startsWith('delivery_settle:')));
});

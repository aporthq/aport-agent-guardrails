#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
pin = 'aporthq/policy-verify-action/integrity@d1ccc3aa355c449018ee1adef5a59b3b79c92fb2'
# These static analysis tools read source, rather than executing repository code.
read_only = {'shellcheck.yml'}
seen = 0
for file in (root / '.github/workflows').glob('*.yml'):
    if file.name in read_only:
        continue
    workflow = yaml.load(file.read_text(), Loader=yaml.BaseLoader)
    for name, job in workflow['jobs'].items():
        steps = job.get('steps', [])
        indexes = [i for i, step in enumerate(steps) if step.get('uses', '').startswith('actions/checkout@')]
        if not indexes:
            continue
        seen += 1
        i = indexes[0]
        checkout, identity, gate = steps[i:i + 3]
        label = f'{file.name}:{name}'
        assert checkout.get('with', {}).get('fetch-depth') == '0', f'{label}: full history required'
        assert identity.get('run') == 'echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"', f'{label}: identify actual checkout'
        assert identity.get('id') == 'integrity-revision', label
        assert gate.get('uses') == pin, f'{label}: trusted scan must precede repository execution'
        assert gate.get('with') == {'head': '${{ steps.integrity-revision.outputs.sha }}'}, label
        assert 'continue-on-error' not in gate and 'continue-on-error' not in job, f'{label}: no integrity bypass'
        assert gate.get('if') == checkout.get('if'), f'{label}: matching execution condition'
        ids = [step['id'] for step in steps if 'id' in step]
        assert len(ids) == len(set(ids)), f'{label}: duplicate step ID'
        if file.name == 'release.yml' and name in {'validate', 'ensure-release-tag'}:
            assert checkout['with']['persist-credentials'] == 'true', f'{label}: preserve authenticated Git operations'
            recovery = next(i for i, step in enumerate(steps) if step.get('name') == 'Checkout existing release tag for recovery')
            assert steps[recovery + 1].get('id') == 'recovered-integrity-revision', f'{label}: identify recovered ref'
            assert steps[recovery + 2].get('uses') == pin, f'{label}: rescan after changing source'
            assert steps[recovery + 2].get('with') == {'head': '${{ steps.recovered-integrity-revision.outputs.sha }}'}, label
        else:
            assert checkout['with']['persist-credentials'] == 'false', f'{label}: no persisted checkout token'
assert seen == 15, f'Expected 15 checkout jobs, reached {seen}'
monitor = yaml.load((root / '.github/workflows/repository-integrity.yml').read_text(), Loader=yaml.BaseLoader)
assert monitor['on']['push'] == {'branches': ['**'], 'tags': ['**']}
assert all(event in monitor['on'] for event in ['pull_request', 'merge_group', 'schedule', 'workflow_dispatch'])
assert monitor['jobs']['integrity']['if'] == 'github.event.deleted != true'
print(f'PASS: {seen} execution jobs scan exact Git objects before candidate code; release recovery rescans its target')
PY

#!/bin/bash
# Execute the workflow's shell, not a model of its bootstrap. All downloads,
# extraction and scanner execution are inert; SHA-256 verification is real.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml

root = Path(sys.argv.pop())
workflow = yaml.load((root / '.github/workflows/secrets-scan.yml').read_text(), Loader=yaml.BaseLoader)
tools = {'gitleaks': 'Gitleaks', 'trufflehog': 'TruffleHog'}
archive_content = 'inert test archive\n'
pins = {
    'gitleaks': ('gitleaks/gitleaks', '8.18.2', 'linux_x64',
                '6298c9235dfc9278c14b28afd9b7fa4e6f4a289cb1974bd27949fc1e9122bdee'),
    'trufflehog': ('trufflesecurity/trufflehog', '3.63.5', 'linux_amd64',
                  '7ff2575d3d185b5d0a035e91b5215588f72ae2dc7c0d2e6badf2f2d09a65ef74'),
}


def step(tool, name):
    return next(s for s in workflow['jobs'][tool]['steps'] if s.get('name') == name)


# A single inert executable stands in for curl/wget, tar and the extracted tools.
# Even the vulnerable baseline cannot download code or move a file into /usr/local.
fake = '#!' + sys.executable + '\n' + r'''
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
name = Path(sys.argv[0]).name
mode = os.environ['TEST_MODE']
tool = os.environ['TEST_TOOL']

def log(kind, **fields):
    with open(os.environ['TEST_LOG'], 'a') as stream:
        stream.write(json.dumps(dict(kind=kind, cwd=os.getcwd(), **fields)) + '\n')

if name in ('curl', 'wget'):
    url = next(a for a in args if a.startswith('https://'))
    option = next((a for a in ('--output', '-o', '-O') if a in args), None)
    target = Path(args[args.index(option) + 1] if option else url.rsplit('/', 1)[1])
    if name == 'wget' and not option:
        # Reproduce wget's collision behavior without downloading an archive.
        while target.exists():
            target = Path(str(target) + '.1')
    content = os.environ['TEST_ARCHIVE_CONTENT']
    if mode == 'checksum-failure':
        content += 'corrupt'
    target.write_text(content)
    log('download', target=str(target.absolute()), explicit=bool(option), url=url)
    sys.exit(22 if mode == 'download-failure' else 0)
elif name == 'tar':
    archive = Path(args[args.index('-xzf') + 1])
    directory = Path(args[args.index('-C') + 1]) if '-C' in args else Path.cwd()
    log('extract', archive=str(archive.absolute()), directory=str(directory.absolute()),
        args=args, content=archive.read_text())
    if mode == 'extract-failure':
        sys.exit(2)
    target = directory / tool
    if mode == 'symlink-binary':
        target.symlink_to(os.environ['TEST_FAKE'])
    else:
        target.write_text(Path(os.environ['TEST_FAKE']).read_text())
        target.chmod(0o755)
elif name in ('gitleaks', 'trufflehog'):
    log('execute', binary=sys.argv[0], args=args)
    if args in (['version'], ['--version']):
        sys.exit(0)
    if name == 'gitleaks':
        report = Path(args[args.index('--report-path') + 1])
        if mode == 'symlink-report':
            report.symlink_to(os.environ['TEST_SENTINEL'])
        else:
            report.write_text(json.dumps([dict(Description='inert fixture', File='fixture.txt', StartLine=1)]))
    else:
        if mode == 'symlink-report':
            report = Path('trufflehog-report.json')
            report.unlink()
            report.symlink_to(os.environ['TEST_SENTINEL'])
        print(json.dumps(dict(DetectorName='inert fixture')))
    sys.exit(1)  # Findings remain report-only, not bootstrap failures.
else:
    log('unexpected', name=name, args=args)
    sys.exit(99)
'''


class Fixture:
    def __init__(self, tool, mode='success'):
        self.temp = tempfile.TemporaryDirectory(prefix='secrets bootstrap ')
        self.root = Path(self.temp.name).resolve()
        self.checkout = self.root / 'candidate checkout'
        self.runner = self.root / 'runner temp'
        self.bin = self.root / 'bin'
        for directory in (self.checkout, self.runner, self.bin):
            directory.mkdir()
        self.log = self.root / 'events.jsonl'
        self.output = self.root / 'output'
        self.sentinel = self.root / 'untouched'
        self.sentinel.write_text('outside report target\n')
        self.tool = tool
        self.install = step(tool, 'Install ' + tools[tool])
        self.fake = self.bin / 'fake.py'
        self.fake.write_text(fake)
        self.fake.chmod(0o755)
        for name in ('curl', 'wget', 'tar', 'sudo', 'mv', 'gitleaks', 'trufflehog'):
            (self.bin / name).symlink_to(self.fake)
        # No ambient PATH: a typo or mutation cannot fall back to a real downloader.
        for name in ('bash', 'mktemp', 'sha256sum', 'rm', 'jq', 'head'):
            executable = shutil.which(name)
            assert executable, f'TEST_PREREQUISITE: {name}'
            (self.bin / name).symlink_to(executable)
        self.env = dict(self.install.get('env', {}), PATH=str(self.bin), HOME=str(self.root),
                        RUNNER_TEMP=str(self.runner), GITHUB_WORKSPACE=str(self.checkout),
                        GITHUB_OUTPUT=str(self.output), TEST_TOOL=tool, TEST_MODE=mode,
                        TEST_LOG=str(self.log), TEST_FAKE=str(self.fake),
                        TEST_SENTINEL=str(self.sentinel), TEST_ARCHIVE_CONTENT=archive_content)
        # Only the expected digest changes for inert bytes. Test the production pin separately.
        self.env['SCANNER_SHA256'] = hashlib.sha256(archive_content.encode()).hexdigest()

    def run(self, block, extra=None):
        return subprocess.run([str(self.bin / 'bash'), '--noprofile', '--norc', '-e', '-o', 'pipefail', '-c', block],
                              cwd=self.checkout, env=dict(self.env, **(extra or {})),
                              text=True, capture_output=True, timeout=15)

    def events(self, kind):
        entries = self.log.read_text().splitlines() if self.log.exists() else []
        return [entry for entry in map(json.loads, entries) if entry['kind'] == kind]

    def binary(self):
        return dict(line.split('=', 1) for line in self.output.read_text().splitlines())['binary']

    def close(self):
        self.temp.cleanup()


class BootstrapTests(unittest.TestCase):
    def fixture(self, tool, mode='success'):
        fixture = Fixture(tool, mode)
        self.addCleanup(fixture.close)
        return fixture

    def install(self, fixture):
        result = fixture.run(fixture.install['run'])
        self.assertEqual(result.returncode, 0, 'BOOTSTRAP_SUCCESS: ' + result.stderr)
        return fixture.binary()

    def test_candidate_collision_and_fresh_install(self):
        for tool in tools:
            for symlink in (False, True):
                with self.subTest(tool=tool, symlink=symlink):
                    f = self.fixture(tool)
                    _, version, platform, _ = pins[tool]
                    names = (f'{tool}_{version}_{platform}.tar.gz', 'trufflehog.tar.gz', 'scanner.tar.gz', tool)
                    for name in names:
                        target = f.checkout / name
                        if symlink:
                            target.symlink_to(f.sentinel)
                        else:
                            target.write_text('candidate collision\n')
                    result = f.run(f.install['run'])
                    downloads = f.events('download')
                    self.assertEqual(len(downloads), 1, 'DOWNLOAD_REACHED')
                    self.assertTrue(downloads[0]['explicit'], 'EXPLICIT_DOWNLOAD_TARGET')
                    archive = Path(downloads[0]['target'])
                    self.assertTrue(archive.is_relative_to(f.runner), 'INSTALL_OUTSIDE_CHECKOUT')
                    self.assertEqual(result.returncode, 0, 'COLLISION_SAFE_BOOTSTRAP: ' + result.stderr)
                    binary = Path(f.binary())
                    self.assertTrue(binary.is_absolute() and binary.is_relative_to(f.runner), 'ABSOLUTE_RUNNER_EXECUTABLE')
                    self.assertFalse(binary.is_symlink(), 'NO_CANDIDATE_EXECUTABLE_SYMLINK')
                    extracts = f.events('extract')
                    self.assertEqual(len(extracts), 1, 'EXTRACTION_REACHED')
                    self.assertEqual(extracts[0]['archive'], str(archive), 'EXTRACT_DOWNLOADED_ARCHIVE')
                    self.assertEqual(extracts[0]['directory'], str(binary.parent), 'EXTRACT_OUTSIDE_CHECKOUT')
                    self.assertEqual(extracts[0]['content'], archive_content, 'NOT_CANDIDATE_ARCHIVE')
                    self.assertEqual(extracts[0]['args'][-1], tool, 'EXTRACT_ONLY_SCANNER')
                    self.assertEqual(f.events('execute'), [dict(kind='execute', cwd=str(binary.parent),
                                     binary=str(binary), args=['version' if tool == 'gitleaks' else '--version'])],
                                     'ONLY_VERIFIED_ABSOLUTE_EXECUTABLE')
                    second = self.install(f)
                    self.assertNotEqual(str(binary), second, 'FRESH_INSTALL_DIRECTORY')
                    for name in names:
                        self.assertEqual((f.checkout / name).read_text(),
                                         'outside report target\n' if symlink else 'candidate collision\n',
                                         'CANDIDATE_FILES_UNTOUCHED')
                    self.assertEqual(f.sentinel.read_text(), 'outside report target\n', 'SYMLINK_TARGET_UNTOUCHED')
                    self.assertFalse(f.events('unexpected'), 'NO_PRIVILEGED_INSTALL')

    def test_failures_stop_before_execution(self):
        for tool in tools:
            for mode in ('checksum-failure', 'download-failure', 'extract-failure', 'symlink-binary'):
                with self.subTest(tool=tool, mode=mode):
                    f = self.fixture(tool, mode)
                    result = f.run(f.install['run'])
                    self.assertEqual(len(f.events('download')), 1, 'FAILURE_PATH_REACHED')
                    self.assertNotEqual(result.returncode, 0, 'BOOTSTRAP_FAILURE_PROPAGATES')
                    if mode in ('checksum-failure', 'download-failure'):
                        self.assertFalse(f.events('extract'), 'CHECKSUM_FAILURE_NO_EXTRACTION')
                    else:
                        self.assertEqual(len(f.events('extract')), 1, 'EXTRACTION_FAILURE_REACHED')
                    self.assertFalse(f.events('execute'), 'BOOTSTRAP_FAILURE_NO_EXECUTION')
                    self.assertFalse(f.output.exists() and f.output.read_text(), 'FAILED_BINARY_NOT_EXPORTED')

    def test_reports_unlink_candidate_symlinks_and_preserve_findings(self):
        for tool in tools:
            with self.subTest(tool=tool):
                f = self.fixture(tool)
                binary = self.install(f)
                report = f.checkout / f'{tool}-report.json'
                report.symlink_to(f.sentinel)
                scan = step(tool, 'Run ' + tools[tool])
                self.assertEqual(scan['env'], {'SCANNER_BIN': '${{ steps.scanner.outputs.binary }}'})
                result = f.run(scan['run'], dict(SCANNER_BIN=binary))
                self.assertEqual(result.returncode, 0, 'FINDINGS_REMAIN_REPORT_ONLY: ' + result.stderr)
                self.assertTrue(report.is_file() and not report.is_symlink(), 'FRESH_REGULAR_REPORT')
                self.assertEqual(f.sentinel.read_text(), 'outside report target\n', 'REPORT_SYMLINK_TARGET_UNTOUCHED')
                executions = f.events('execute')
                self.assertEqual(len(executions), 2, 'SCANNER_RUN_REACHED')
                self.assertEqual(executions[-1]['binary'], binary, 'SCAN_ABSOLUTE_VERIFIED_EXECUTABLE')
                expected = (['detect', '--source', '.', '--report-path', 'gitleaks-report.json',
                             '--report-format', 'json', '--verbose'] if tool == 'gitleaks'
                            else ['filesystem', '.', '--json', '--only-verified'])
                self.assertEqual(executions[-1]['args'], expected, 'SCAN_ARGUMENTS_PRESERVED')
                check = step(tool, 'Check for secrets' if tool == 'gitleaks' else 'Check for verified secrets')
                checked = f.run(check['run'])
                self.assertEqual(checked.returncode, 0, 'REPORT_CHECK_PRESERVED: ' + checked.stderr)
                if tool == 'gitleaks':
                    self.assertIn('secrets_found=true', f.output.read_text(), 'PR_COMMENT_SIGNAL_PRESERVED')
                else:
                    self.assertIn('Verified secrets may have been detected', checked.stdout)

    def test_nonregular_reports_fail(self):
        for tool in tools:
            for mode in ('directory-report', 'symlink-report'):
                with self.subTest(tool=tool, mode=mode):
                    f = self.fixture(tool, mode)
                    binary = self.install(f)
                    if mode == 'directory-report':
                        (f.checkout / f'{tool}-report.json').mkdir()
                    result = f.run(step(tool, 'Run ' + tools[tool])['run'], dict(SCANNER_BIN=binary))
                    self.assertNotEqual(result.returncode, 0, 'NONREGULAR_REPORT_REJECTED')
                    self.assertEqual(len(f.events('execute')), 1 if mode == 'directory-report' else 2,
                                     'REPORT_FAILURE_PATH_REACHED')
                    self.assertEqual(f.sentinel.read_text(), 'outside report target\n')

    def test_pins_and_reporting_contract(self):
        self.assertEqual(set(workflow['jobs']), set(tools), 'PRESERVE_TWO_SCANNER_JOBS')
        for tool, title in tools.items():
            with self.subTest(tool=tool):
                repository, version, platform, checksum = pins[tool]
                install = step(tool, 'Install ' + title)
                self.assertEqual(install['env'], dict(SCANNER_NAME=tool,
                    SCANNER_URL=f'https://github.com/{repository}/releases/download/v{version}/{tool}_{version}_{platform}.tar.gz',
                    SCANNER_SHA256=checksum, SCANNER_VERSION_ARG='version' if tool == 'gitleaks' else '--version'),
                    'OFFICIAL_PINNED_RELEASE')
                self.assertEqual(install['id'], 'scanner')
                scan = step(tool, 'Run ' + title)
                self.assertEqual(scan['id'], 'scan')
                self.assertNotIn('continue-on-error', workflow['jobs'][tool], 'INTEGRITY_FAILURE_NOT_MASKED')
                self.assertNotIn('continue-on-error', install, 'BOOTSTRAP_FAILURE_NOT_MASKED')
                upload = step(tool, 'Upload ' + title + ' report')
                self.assertEqual(upload['if'], "always() && steps.scan.outcome == 'success'", 'NO_UPLOAD_OF_CANDIDATE_REPORT')
                self.assertEqual(upload['uses'], 'actions/upload-artifact@v4')
                self.assertEqual(upload['with'], dict(name=f'{tool}-report', path=f'{tool}-report.json',
                                                     **{'retention-days': '30'}), 'UPLOAD_CONTRACT_PRESERVED')


unittest.main(verbosity=2)
PY

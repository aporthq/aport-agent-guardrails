#!/usr/bin/env node
/**
 * Integration test: run agent-guardrails --framework=openclaw in temp dir and assert config files exist.
 * Non-interactive: uses OPENCLAW_HOME and piped input. Run with: node tests/frameworks/openclaw/setup.test.mjs
 * Exit 0 on success, 1 on failure.
 */

import { spawn } from 'child_process';
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..', '..');
const DISPATCHER = join(REPO_ROOT, 'bin', 'agent-guardrails');
const AGENT_ID = process.env.APORT_TEST_OPENCLAW_AGENT_ID || 'ap_8955f5450cd542fe8f67bbbf07c3e103';

function run() {
  const testDir = mkdtempSync(join(tmpdir(), 'aport-openclaw-setup-'));
  const configDir = join(testDir, '.openclaw');
  const fakeBin = join(testDir, 'bin');
  mkdirSync(configDir, { recursive: true });
  mkdirSync(fakeBin, { recursive: true });
  const fakeOpenClaw = join(fakeBin, 'openclaw');
  writeFileSync(fakeOpenClaw, `#!/bin/bash
set -e
case "$*" in
  "plugins list --json")
    printf '{"plugins":[{"id":"openclaw-aport","version":"test"}]}'
    ;;
  "plugins list")
    printf 'openclaw-aport test\\n'
    ;;
  plugins\\ install*)
    exit 0
    ;;
  "gateway restart" | "gateway probe" | "gateway start")
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
`);
  chmodSync(fakeOpenClaw, 0o755);

  return new Promise((resolve, reject) => {
    const child = spawn(DISPATCHER, ['--framework=openclaw', AGENT_ID], {
      cwd: REPO_ROOT,
      env: { ...process.env, OPENCLAW_HOME: configDir, PATH: `${fakeBin}:${process.env.PATH || ''}` },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    // Send newlines for any prompts
    child.stdin.write('\n\n\n\n');
    child.stdin.end();
    let stderr = '';
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('close', (code) => {
      const configYaml = join(configDir, 'config.yaml');
      if (!existsSync(configYaml)) {
        reject(new Error(`Expected config file: ${configYaml}`));
        return;
      }
      const content = readFileSync(configYaml, 'utf8');
      if (!content.includes('agentId:')) {
        reject(new Error('config.yaml should contain agentId'));
        return;
      }
      resolve();
    });
    child.on('error', reject);
  });
}

run()
  .then(() => { console.log('OK setup.test.mjs'); process.exit(0); })
  .catch((err) => { console.error('FAIL', err.message); process.exit(1); });

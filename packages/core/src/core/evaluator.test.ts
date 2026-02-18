/**
 * Tests for Evaluator: fail-closed by default when no config; legacy allow via fail_open_when_missing_config.
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { Evaluator } from './evaluator.js';

describe('Evaluator', () => {
  let tmpDir: string;
  let envFailOpen: string | undefined;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aport-eval-test-'));
    envFailOpen = process.env.APORT_FAIL_OPEN_WHEN_MISSING_CONFIG;
  });

  afterEach(() => {
    if (envFailOpen !== undefined) process.env.APORT_FAIL_OPEN_WHEN_MISSING_CONFIG = envFailOpen;
    else delete process.env.APORT_FAIL_OPEN_WHEN_MISSING_CONFIG;
    try {
      fs.rmSync(tmpDir, { recursive: true });
    } catch {
      // ignore
    }
  });

  it('verify() returns allow: false when no config (fail-closed by default)', async () => {
    delete process.env.APORT_FAIL_OPEN_WHEN_MISSING_CONFIG;
    const configPath = path.join(tmpDir, 'config.yaml');
    fs.writeFileSync(configPath, 'mode: local\nframework: langchain\n', 'utf8');
    const origHome = process.env.HOME;
    process.env.HOME = tmpDir; // so default passport paths point under tmpDir and do not exist
    try {
      const evaluator = new Evaluator(configPath, 'langchain');
      const decision = await evaluator.verify(
        {},
        { capability: 'system.command.execute.v1' },
        { tool: 'exec.run', input: '{"command":"ls"}' }
      );
      expect(decision.allow).toBe(false);
      expect(decision.reasons?.[0]?.code).toBe('oap.misconfigured');
    } finally {
      process.env.HOME = origHome;
    }
  });

  it('verifySync() returns allow: false when no config (fail-closed by default)', () => {
    delete process.env.APORT_FAIL_OPEN_WHEN_MISSING_CONFIG;
    const configPath = path.join(tmpDir, 'config.yaml');
    fs.writeFileSync(configPath, 'mode: local\nframework: langchain\n', 'utf8');
    const origHome = process.env.HOME;
    process.env.HOME = tmpDir;
    try {
      const evaluator = new Evaluator(configPath, 'langchain');
      const decision = evaluator.verifySync(
        {},
        { capability: 'system.command.execute.v1' },
        { tool: 'exec.run', input: '{"command":"ls"}' }
      );
      expect(decision.allow).toBe(false);
      expect(decision.reasons?.[0]?.code).toBe('oap.misconfigured');
    } finally {
      process.env.HOME = origHome;
    }
  });

  it('verify() returns allow: true when no config and APORT_FAIL_OPEN_WHEN_MISSING_CONFIG=1', async () => {
    const origHome = process.env.HOME;
    process.env.HOME = tmpDir; // so findConfigPath finds no config
    process.env.APORT_FAIL_OPEN_WHEN_MISSING_CONFIG = '1';
    try {
      const evaluator = new Evaluator(null, 'langchain');
      const decision = await evaluator.verify(
        {},
        { capability: 'system.command.execute.v1' },
        { tool: 'exec.run', input: '{"command":"ls"}' }
      );
      expect(decision.allow).toBe(true);
    } finally {
      if (origHome !== undefined) process.env.HOME = origHome;
      else delete process.env.HOME;
    }
  });

  it('verifySync() returns allow: true when no config and fail_open in config', () => {
    const origHome = process.env.HOME;
    process.env.HOME = tmpDir; // so default passport/script paths are empty
    try {
      const configPath = path.join(tmpDir, 'config.yaml');
      fs.writeFileSync(configPath, 'fail_open_when_missing_config: true\n', 'utf8');
      const evaluator = new Evaluator(configPath, 'langchain');
      const decision = evaluator.verifySync(
        {},
        { capability: 'system.command.execute.v1' },
        { tool: 'exec.run', input: '{"command":"ls"}' }
      );
      expect(decision.allow).toBe(true);
    } finally {
      if (origHome !== undefined) process.env.HOME = origHome;
      else delete process.env.HOME;
    }
  });

  it('uses config from explicit path when provided (no passport/script still denies unless fail_open)', async () => {
    const origHome = process.env.HOME;
    process.env.HOME = tmpDir; // so default passport/script paths are empty
    try {
      const configPath = path.join(tmpDir, 'config.yaml');
      fs.writeFileSync(configPath, 'mode: local\nframework: langchain\nfail_open_when_missing_config: true\n', 'utf8');
      const evaluator = new Evaluator(configPath, 'langchain');
      const decision = await evaluator.verify(
        {},
        { capability: 'system.command.execute.v1' },
        { tool: 'run_command', input: '{}' }
      );
      expect(decision.allow).toBe(true);
    } finally {
      if (origHome !== undefined) process.env.HOME = origHome;
      else delete process.env.HOME;
    }
  });
});

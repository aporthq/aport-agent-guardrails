/**
 * Tests for config: loadConfig, writeConfig, findConfigPath.
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { loadConfig, writeConfig, findConfigPath } from './config.js';

describe('config', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aport-config-test-'));
  });

  afterEach(() => {
    try {
      fs.rmSync(tmpDir, { recursive: true });
    } catch {
      // ignore
    }
  });

  describe('loadConfig', () => {
    it('returns empty object for non-existent path', () => {
      expect(loadConfig(path.join(tmpDir, 'missing.yaml'))).toEqual({});
    });

    it('loads YAML config', () => {
      const yamlPath = path.join(tmpDir, 'config.yaml');
      fs.writeFileSync(yamlPath, 'mode: api\nagent_id: ap_1234567890abcdef1234567890abcdef', 'utf8');
      expect(loadConfig(yamlPath)).toMatchObject({ mode: 'api', agent_id: 'ap_1234567890abcdef1234567890abcdef' });
    });

    it('loads JSON config', () => {
      const jsonPath = path.join(tmpDir, 'config.json');
      fs.writeFileSync(jsonPath, JSON.stringify({ mode: 'local', framework: 'langchain' }), 'utf8');
      expect(loadConfig(jsonPath)).toEqual({ mode: 'local', framework: 'langchain' });
    });
  });

  describe('writeConfig', () => {
    it('writes YAML file and creates parent dirs', () => {
      const outPath = path.join(tmpDir, 'sub', 'config.yaml');
      writeConfig(outPath, { mode: 'api', agent_id: 'ap_abc' });
      expect(fs.existsSync(outPath)).toBe(true);
      const loaded = loadConfig(outPath);
      expect(loaded).toMatchObject({ mode: 'api', agent_id: 'ap_abc' });
    });
  });

  describe('findConfigPath', () => {
    it('returns null when no config exists', () => {
      const cwd = process.cwd();
      const origHome = process.env.HOME;
      process.env.HOME = tmpDir; // so ~/.aport is not found
      process.chdir(tmpDir);
      try {
        expect(findConfigPath('langchain')).toBeNull();
      } finally {
        process.chdir(cwd);
        if (origHome !== undefined) process.env.HOME = origHome;
        else delete process.env.HOME;
      }
    });

    it('returns path when .aport/config.yaml exists in cwd', () => {
      const aportDir = path.join(tmpDir, '.aport');
      fs.mkdirSync(aportDir, { recursive: true });
      const configPath = path.join(aportDir, 'config.yaml');
      fs.writeFileSync(configPath, 'mode: local\n', 'utf8');
      const cwd = process.cwd();
      process.chdir(tmpDir);
      try {
        const found = findConfigPath('langchain');
        expect(found).not.toBeNull();
        expect(fs.existsSync(found!)).toBe(true);
        expect(loadConfig(found!)).toMatchObject({ mode: 'local' });
      } finally {
        process.chdir(cwd);
      }
    });
  });
});

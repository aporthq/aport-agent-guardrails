/**
 * Tests for passport: loadPassport, validatePassport.
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { loadPassport, validatePassport } from './passport.js';

describe('passport', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aport-passport-test-'));
  });

  afterEach(() => {
    try {
      fs.rmSync(tmpDir, { recursive: true });
    } catch {
      // ignore
    }
  });

  describe('loadPassport', () => {
    it('returns { agent_id } when path looks like agent_id (ap_ + 32 hex)', () => {
      const result = loadPassport('ap_fa2f6d53bb5b4c98b9af0124285b6e0f');
      expect(result).toEqual({ agent_id: 'ap_fa2f6d53bb5b4c98b9af0124285b6e0f' });
    });

    it('returns empty object for non-existent file', () => {
      expect(loadPassport(path.join(tmpDir, 'missing.json'))).toEqual({});
    });

    it('loads JSON file and sets agent_id from passport_id when missing', () => {
      const passportPath = path.join(tmpDir, 'passport.json');
      fs.writeFileSync(
        passportPath,
        JSON.stringify({ passport_id: 'ap_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', owner_id: 'user1' }),
        'utf8'
      );
      const result = loadPassport(passportPath);
      expect(result).toMatchObject({ agent_id: 'ap_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', owner_id: 'user1' });
    });
  });

  describe('validatePassport', () => {
    it('returns valid: true for non-empty object', () => {
      expect(validatePassport({ agent_id: 'ap_abc' })).toEqual({ valid: true });
    });

    it('returns valid: false for non-object', () => {
      expect(validatePassport(null as any)).toEqual({ valid: false, errors: ['Passport must be an object'] });
    });
  });
});

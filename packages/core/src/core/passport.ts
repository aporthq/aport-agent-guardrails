/**
 * Passport loading (OAP v1.0). Shared across all frameworks.
 * Aligns with Python evaluator passport resolution.
 */

import fs from 'node:fs';
import path from 'node:path';
import { expandUser } from './pathUtils.js';

export interface Passport {
  agent_id?: string;
  passport_id?: string;
  owner_id?: string;
  [key: string]: unknown;
}

export interface ValidationResult {
  valid: boolean;
  errors?: string[];
}

const AGENT_ID_REGEX = /^ap_[a-f0-9]{32}$/;

/**
 * Load passport: if pathOrAgentId looks like agent_id (ap_ + 32 hex), return { agent_id }.
 * Otherwise read JSON file and return parsed passport (with agent_id from passport_id if needed).
 */
export function loadPassport(pathOrAgentId: string): Passport {
  const trimmed = (pathOrAgentId ?? '').trim();
  if (AGENT_ID_REGEX.test(trimmed)) {
    return { agent_id: trimmed };
  }
  const resolved = path.resolve(expandUser(trimmed));
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    return {};
  }
  try {
    const raw = fs.readFileSync(resolved, 'utf8');
    const data = JSON.parse(raw) as Record<string, unknown>;
    if (!data.agent_id && data.passport_id) {
      data.agent_id = data.passport_id;
    }
    return data as Passport;
  } catch {
    return {};
  }
}

export function validatePassport(passport: Passport): ValidationResult {
  // Minimal check; full OAP v1.0 schema validation can be added later.
  if (!passport || typeof passport !== 'object') {
    return { valid: false, errors: ['Passport must be an object'] };
  }
  return { valid: true };
}

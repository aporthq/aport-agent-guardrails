/**
 * Shared path helpers. Single source for expandUser used by config, passport, evaluator.
 */

import path from 'node:path';

/**
 * Expand leading ~ to HOME/USERPROFILE. Used for config and passport paths.
 */
export function expandUser(p: string): string {
  const home = process.env.HOME ?? process.env.USERPROFILE ?? '';
  if (p.startsWith('~/') || p.startsWith('~\\')) return path.join(home, p.slice(2));
  if (p === '~') return home || p;
  return p;
}

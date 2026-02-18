/**
 * Default passport path per framework. Single source: default-passport-paths.json.
 * Aligns with bin/lib/config.sh get_config_dir() + /aport/passport.json.
 */

import path from 'node:path';
import { readFileSync } from 'node:fs';

declare const __dirname: string;

const paths: Record<string, string> = JSON.parse(
  readFileSync(path.join(__dirname, 'default-passport-paths.json'), 'utf8')
);

export function getDefaultPassportPaths(): Record<string, string> {
  return { ...paths };
}

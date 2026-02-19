/**
 * Config management: read/write framework config files.
 * Aligns with python/aport_guardrails/core/config.py and bin/lib/config.sh.
 */

import fs from 'node:fs';
import path from 'node:path';
import yaml from 'js-yaml';
import { expandUser } from './pathUtils.js';

export interface Config {
  passport_path?: string;
  agent_id?: string;
  mode?: 'api' | 'local';
  api_url?: string;
  api_key?: string;
  framework?: string;
  guardrail_script?: string;
  /** When true, missing passport/guardrail script returns allow (legacy). Default false = fail-closed. */
  fail_open_when_missing_config?: boolean;
  [key: string]: unknown;
}

export function loadConfig(configPath: string): Config {
  const resolved = path.resolve(expandUser(configPath));
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    return {};
  }
  try {
    const raw = fs.readFileSync(resolved, 'utf8');
    if (resolved.endsWith('.json')) {
      return JSON.parse(raw) as Config;
    }
    return (yaml.load(raw) as Config) ?? {};
  } catch {
    return {};
  }
}

export function writeConfig(configPath: string, config: Config): void {
  const resolved = path.resolve(expandUser(configPath));
  const dir = path.dirname(resolved);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  const ext = path.extname(resolved);
  const out = ext === '.json' ? JSON.stringify(config, null, 2) : yaml.dump(config, { lineWidth: -1 });
  fs.writeFileSync(resolved, out, 'utf8');
}

/**
 * First existing config path: .aport/config.yaml, then ~/.aport/<framework>/config.yaml, then ~/.aport/config.yaml.
 */
export function findConfigPath(framework: string = 'langchain'): string | null {
  const cwd = process.cwd();
  const home = process.env.HOME ?? '';
  const candidates = [
    path.join(cwd, '.aport', 'config.yaml'),
    path.join(cwd, '.aport', 'config.yml'),
    path.join(home, '.aport', framework, 'config.yaml'),
    path.join(home, '.aport', 'config.yaml'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c) && fs.statSync(c).isFile()) {
      return c;
    }
  }
  return null;
}

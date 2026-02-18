/**
 * Shared evaluator: verify tool execution against passport + policy.
 * Mirrors python/aport_guardrails/core/evaluator.py (API + local bash script).
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import type { Config } from './config.js';
import { loadConfig, findConfigPath } from './config.js';
import { loadPassport, type Passport } from './passport.js';
import { expandUser } from './pathUtils.js';
import { toolToPackId } from './toolPackMapping.js';
import { getDefaultPassportPaths } from './defaultPassportPaths.js';

export type { Passport } from './passport.js';
export { toolToPackId } from './toolPackMapping.js';

export interface PolicyPack {
  capability?: string;
  id?: string;
  requires_capabilities?: unknown;
  [key: string]: unknown;
}

export interface ToolContext {
  tool?: string;
  input?: string;
  params?: Record<string, unknown>;
  [key: string]: unknown;
}

export interface Decision {
  allow: boolean;
  reasons?: Array<{ code?: string; message?: string }>;
}

export interface VerifyRequest {
  passport: Passport;
  policy: PolicyPack;
  context: ToolContext;
}

export interface VerifyResponse {
  allow: boolean;
  reasons?: Array<{ message?: string }>;
}

const MISCONFIGURED_DENY: Decision = {
  allow: false,
  reasons: [
    {
      code: 'oap.misconfigured',
      message:
        'Passport or guardrail script not found; deny by default. Set fail_open_when_missing_config in config or APORT_FAIL_OPEN_WHEN_MISSING_CONFIG=1 for legacy allow.',
    },
  ],
};

function getFailOpenWhenMissingConfig(config: Config): boolean {
  const v = config.fail_open_when_missing_config ?? process.env.APORT_FAIL_OPEN_WHEN_MISSING_CONFIG;
  return v === true || v === '1' || v === 'true';
}

function resolvePassportPath(config: Config): string | null {
  let p = (config.passport_path ?? process.env.OPENCLAW_PASSPORT_FILE) as string | undefined;
  if (p) {
    const resolved = path.resolve(expandUser(p));
    if (fs.existsSync(resolved)) return resolved;
    return resolved;
  }
  const defaultPaths = getDefaultPassportPaths();
  const framework = config.framework as string | undefined;
  if (framework && defaultPaths[framework]) {
    const candidate = path.resolve(expandUser(defaultPaths[framework]));
    if (fs.existsSync(candidate)) return candidate;
  }
  for (const v of Object.values(defaultPaths)) {
    const candidate = path.resolve(expandUser(v));
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

function getGuardrailScriptPath(config: Config): string | null {
  const script = (config.guardrail_script ?? process.env.APORT_GUARDRAIL_SCRIPT) as string | undefined;
  let resolved: string | null = null;
  if (script && fs.existsSync(script)) {
    resolved = path.resolve(script);
  } else {
    const defaultPath = path.join(expandUser('~/.openclaw'), '.skills', 'aport-guardrail.sh');
    if (fs.existsSync(defaultPath)) resolved = defaultPath;
  }
  if (!resolved) return null;
  // Resolve symlinks so we execute the actual file, not a PATH-hijacked or swapped symlink (Issue 18).
  try {
    return fs.realpathSync(resolved);
  } catch {
    return resolved;
  }
}

function runGuardrailSync(
  guardrailScript: string,
  passportPath: string,
  toolName: string,
  context: Record<string, unknown>
): Decision {
  const dataDir = path.dirname(passportPath);
  // Per-invocation decision file to avoid race when multiple tool calls run concurrently (Issue 1).
  const decisionPath = path.join(dataDir, `decision-${process.pid}-${Date.now()}.json`);
  const env = {
    ...process.env,
    OPENCLAW_PASSPORT_FILE: passportPath,
    OPENCLAW_DECISION_FILE: decisionPath,
  };
  const contextJson = JSON.stringify(context);
  try {
    const result = spawnSync(guardrailScript, [toolName, contextJson], {
      env,
      cwd: dataDir,
      encoding: 'utf8',
      timeout: 30_000,
    });
    if (fs.existsSync(decisionPath)) {
      try {
        const data = JSON.parse(fs.readFileSync(decisionPath, 'utf8'));
        return {
          allow: Boolean(data.allow),
          reasons: data.reasons ?? [{ message: 'Policy evaluation failed' }],
        };
      } catch {
        /* malformed decision; fall through to deny with script exit reason */
      }
    }
    return {
      allow: false,
      reasons: [{ code: 'oap.evaluator_error', message: `Script exit ${result.status ?? 'unknown'}` }],
    };
  } finally {
    try {
      if (fs.existsSync(decisionPath)) fs.unlinkSync(decisionPath);
    } catch {
      /* best-effort cleanup */
    }
  }
}

const IN_BODY_PACK_ID = 'IN_BODY';

function isFullPolicyPack(p: PolicyPack | undefined): boolean {
  if (!p || typeof p !== 'object') return false;
  return Boolean(p.id && p.requires_capabilities !== undefined);
}

async function callApi(
  apiUrl: string,
  packId: string,
  context: Record<string, unknown>,
  options: {
    agentId?: string;
    passport?: Passport;
    policyPack?: PolicyPack;
    apiKey?: string;
  }
): Promise<Decision> {
  const base = apiUrl.replace(/\/$/, '');
  const pathId = isFullPolicyPack(options.policyPack) ? IN_BODY_PACK_ID : packId;
  const url = `${base}/api/verify/policy/${pathId}`;
  const bodyContext = { ...context };
  if (options.agentId) (bodyContext as Record<string, unknown>).agent_id = options.agentId;
  (bodyContext as Record<string, unknown>).policy_id =
    pathId !== IN_BODY_PACK_ID ? pathId : (options.policyPack?.id ?? '');
  const body: Record<string, unknown> = { context: bodyContext };
  if (options.passport) body.passport = options.passport;
  if (options.policyPack && isFullPolicyPack(options.policyPack)) body.policy = options.policyPack;
  if (!options.agentId && !options.passport) {
    return { allow: false, reasons: [{ code: 'oap.api_error', message: 'Either agent_id or passport required' }] };
  }
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (options.apiKey) headers.Authorization = `Bearer ${options.apiKey}`;
  try {
    const res = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    const raw = await res.text();
    if (!res.ok) {
      return {
        allow: false,
        reasons: [
          {
            code: 'oap.api_error',
            message: `API ${res.status} ${res.statusText}${raw ? `: ${raw.slice(0, 200)}` : ''}`,
          },
        ],
      };
    }
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      return {
        allow: false,
        reasons: [{ code: 'oap.api_error', message: 'Invalid JSON response from API' }],
      };
    }
    const decision = (data.decision as Record<string, unknown>) ?? data;
    return {
      allow: Boolean((decision as Record<string, unknown>).allow),
      reasons: (decision.reasons as Decision['reasons']) ?? [{ message: 'API response' }],
    };
  } catch (e) {
    return {
      allow: false,
      reasons: [{ code: 'oap.api_error', message: String(e) }],
    };
  }
}

export class Evaluator {
  private configPath: string | null;
  private framework: string;
  private cachedConfig: Config | null = null;

  constructor(configPath?: string | null, framework: string = 'langchain') {
    this.configPath = configPath ?? null;
    this.framework = framework;
  }

  private loadConfig(): Config {
    if (this.cachedConfig) return this.cachedConfig;
    if (this.configPath && fs.existsSync(this.configPath)) {
      this.cachedConfig = loadConfig(this.configPath);
      return this.cachedConfig;
    }
    const found = findConfigPath(this.framework);
    if (found) {
      this.cachedConfig = loadConfig(found);
      return this.cachedConfig;
    }
    this.cachedConfig = {};
    return this.cachedConfig;
  }

  async verify(
    passport: Passport,
    policy: PolicyPack,
    context: ToolContext
  ): Promise<Decision> {
    const config = this.loadConfig();
    const mode = (config.mode ?? 'local') as string;
    const toolName = (context.tool ?? 'unknown') as string;
    const packId = toolToPackId(toolName);
    const ctx = { ...context };

    if (mode === 'api') {
      const apiUrl = (config.api_url ?? process.env.APORT_API_URL ?? 'https://api.aport.io') as string;
      const apiKey = (config.api_key ?? process.env.APORT_API_KEY) as string | undefined;
      const agentId = (config.agent_id ?? passport.agent_id) as string | undefined;
      const passportPath = resolvePassportPath(config);
      let passportBody: Passport | undefined;
      if (passportPath && fs.existsSync(passportPath)) {
        try {
          const raw = fs.readFileSync(passportPath, 'utf8');
          passportBody = JSON.parse(raw) as Passport;
          if (!passportBody.agent_id && passportBody.passport_id) passportBody.agent_id = passportBody.passport_id;
        } catch {
          /* invalid or unreadable passport file; proceed without body */
          passportBody = undefined;
        }
      }
      if (agentId) {
        return callApi(apiUrl, packId, ctx, { agentId, policyPack: isFullPolicyPack(policy) ? policy : undefined, apiKey });
      }
      if (passportBody) {
        return callApi(apiUrl, packId, ctx, {
          passport: passportBody,
          policyPack: isFullPolicyPack(policy) ? policy : undefined,
          apiKey,
        });
      }
    }

    const passportPath = resolvePassportPath(config);
    const guardrailScript = getGuardrailScriptPath(config);
    if (!passportPath || !guardrailScript) {
      if (getFailOpenWhenMissingConfig(config)) return { allow: true };
      return MISCONFIGURED_DENY;
    }
    return runGuardrailSync(guardrailScript, passportPath, toolName, ctx);
  }

  /**
   * Synchronous verify for sync callers (e.g. CrewAI before_tool_call).
   * In API mode this uses a sync bridge: writes request to temp files, spawns `node -e` to run
   * async fetch(), writes response to temp file, then reads it. Temp files are unlinked in finally.
   */
  verifySync(passport: Passport, policy: PolicyPack, context: ToolContext): Decision {
    const config = this.loadConfig();
    const mode = (config.mode ?? 'local') as string;
    const toolName = (context.tool ?? 'unknown') as string;
    const packId = toolToPackId(toolName);
    const ctx = { ...context };

    if (mode === 'api') {
      const apiUrl = (config.api_url ?? process.env.APORT_API_URL ?? 'https://api.aport.io') as string;
      const apiKey = (config.api_key ?? process.env.APORT_API_KEY) as string | undefined;
      const agentId = (config.agent_id ?? passport.agent_id) as string | undefined;
      const passportPath = resolvePassportPath(config);
      let passportBody: Passport | undefined;
      if (passportPath && fs.existsSync(passportPath)) {
        try {
          const raw = fs.readFileSync(passportPath, 'utf8');
          passportBody = JSON.parse(raw) as Passport;
          if (!passportBody.agent_id && passportBody.passport_id) passportBody.agent_id = passportBody.passport_id;
        } catch {
          /* invalid or unreadable passport file; proceed without body */
          passportBody = undefined;
        }
      }
      if (agentId || passportBody) {
        const pathId = isFullPolicyPack(policy) ? IN_BODY_PACK_ID : packId;
        const body: Record<string, unknown> = {
          context: {
            ...ctx,
            agent_id: agentId,
            policy_id: pathId !== IN_BODY_PACK_ID ? pathId : (policy?.id ?? ''),
          },
        };
        if (passportBody) body.passport = passportBody;
        if (isFullPolicyPack(policy)) body.policy = policy;
        const url = `${apiUrl.replace(/\/$/, '')}/api/verify/policy/${pathId}`;
        const headers: Record<string, string> = { 'Content-Type': 'application/json' };
        if (apiKey) headers.Authorization = `Bearer ${apiKey}`;
        const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aport-sync-'));
        const tmpIn = path.join(tmpDir, `req-${crypto.randomUUID()}.json`);
        const tmpOut = path.join(tmpDir, `res-${crypto.randomUUID()}.json`);
        const fileOpts = { encoding: 'utf8' as const, mode: 0o600 };
        try {
          fs.writeFileSync(tmpIn, JSON.stringify({ url, headers, body }), fileOpts);
          const script = `
(async () => {
  const { url, headers, body } = JSON.parse(require('fs').readFileSync(process.env.APORT_IN, 'utf8'));
  try {
    const res = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    const data = await res.json();
    require('fs').writeFileSync(process.env.APORT_OUT, JSON.stringify(data), 'utf8');
  } catch (e) {
    require('fs').writeFileSync(process.env.APORT_OUT, JSON.stringify({ error: String(e) }), 'utf8');
  }
})();
`;
          const result = spawnSync(process.execPath, ['-e', script], {
            env: { ...process.env, APORT_IN: tmpIn, APORT_OUT: tmpOut },
            timeout: 15_000,
            encoding: 'utf8',
          });
          if (result.status !== 0 || !fs.existsSync(tmpOut)) {
            return { allow: false, reasons: [{ code: 'oap.api_error', message: 'Sync API call failed' }] };
          }
          const data = JSON.parse(fs.readFileSync(tmpOut, 'utf8')) as Record<string, unknown>;
          if (data.error) {
            return { allow: false, reasons: [{ code: 'oap.api_error', message: String(data.error) }] };
          }
          const decision = (data.decision as Record<string, unknown>) ?? data;
          return {
            allow: Boolean((decision as Record<string, unknown>).allow),
            reasons: (decision.reasons as Decision['reasons']) ?? [{ message: 'API response' }],
          };
        } catch (e) {
          return { allow: false, reasons: [{ code: 'oap.api_error', message: String(e) }] };
        } finally {
          try {
            if (fs.existsSync(tmpIn)) fs.unlinkSync(tmpIn);
          } catch {
            /* best-effort */
          }
          try {
            if (fs.existsSync(tmpOut)) fs.unlinkSync(tmpOut);
          } catch {
            /* best-effort */
          }
          try {
            if (fs.existsSync(tmpDir)) fs.rmdirSync(tmpDir);
          } catch {
            /* best-effort */
          }
        }
      }
    }

    const passportPath = resolvePassportPath(config);
    const guardrailScript = getGuardrailScriptPath(config);
    if (!passportPath || !guardrailScript) {
      if (getFailOpenWhenMissingConfig(config)) return { allow: true };
      return MISCONFIGURED_DENY;
    }
    return runGuardrailSync(guardrailScript, passportPath, toolName, ctx);
  }
}

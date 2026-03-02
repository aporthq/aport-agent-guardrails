/**
 * Local audit logger for policy decisions.
 * Writes one-line entries matching the bash guardrail audit.log format.
 * Best-effort: never throws.
 */

import fs from 'node:fs';
import path from 'node:path';

export interface AuditEntry {
  tool: string;
  decision_id?: string;
  allow: boolean;
  policy_id: string;
  code?: string;
  message?: string;
  agent_id?: string;
  context_summary?: string;
}

function sanitize(s: string, maxLen: number = 120): string {
  return s.replace(/[\r\n]+/g, ' ').replace(/"/g, '\\"').slice(0, maxLen);
}

function formatEntry(entry: AuditEntry): string {
  const now = new Date();
  const ts = now.toISOString().replace('T', ' ').replace(/\.\d+Z$/, '');
  const code = entry.code || (entry.allow ? 'oap.allowed' : 'oap.denied');
  // Match bash format: [ts] tool=X decision_id=D allow=T policy=P code=C agent_id=A context="..."
  let line = `[${ts}] tool=${entry.tool}`;
  if (entry.decision_id) line += ` decision_id=${entry.decision_id}`;
  line += ` allow=${entry.allow} policy=${entry.policy_id} code=${code}`;
  if (entry.agent_id) line += ` agent_id=${entry.agent_id}`;
  if (entry.context_summary) line += ` context="${sanitize(entry.context_summary)}"`;
  return line;
}

function ensureDir(filePath: string): void {
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

/**
 * Log a policy decision to a local audit log file.
 * Deny entries are written synchronously (blocking).
 * Allow entries are written asynchronously (non-blocking).
 */
export function logDecision(auditLogPath: string, entry: AuditEntry): void {
  try {
    const line = formatEntry(entry) + '\n';
    ensureDir(auditLogPath);

    if (!entry.allow) {
      // Deny: sync write (blocking) — matches bash guardrail behavior
      fs.appendFileSync(auditLogPath, line, 'utf8');
    } else {
      // Allow: async write (non-blocking)
      fs.appendFile(auditLogPath, line, 'utf8', () => {
        /* best-effort, ignore errors */
      });
    }
  } catch {
    /* best-effort: never throw */
  }
}

/**
 * Resolve the audit log file path from config.
 * - string path: use as-is
 * - true: default path relative to config dir or ~/.aport/<framework>/audit.log
 * - false/undefined: no audit logging
 *
 * Env var APORT_AUDIT_LOG overrides config: "1"/"true" = default path, other string = explicit path.
 */
export function resolveAuditLogPath(
  auditLogConfig: string | boolean | undefined,
  configPath: string | null,
  framework: string,
): string | null {
  // Env var takes precedence
  const envVal = process.env.APORT_AUDIT_LOG;
  if (envVal !== undefined) {
    if (envVal === '0' || envVal === 'false' || envVal === '') return null;
    if (envVal === '1' || envVal === 'true') {
      return defaultAuditLogPath(configPath, framework);
    }
    return envVal;
  }

  if (auditLogConfig === false || auditLogConfig === undefined) return null;
  if (auditLogConfig === true) {
    return defaultAuditLogPath(configPath, framework);
  }
  if (typeof auditLogConfig === 'string') return auditLogConfig;
  return null;
}

function defaultAuditLogPath(configPath: string | null, framework: string): string {
  // If we have a config path, put audit.log next to it
  if (configPath) {
    return path.join(path.dirname(configPath), 'audit.log');
  }
  // Check for local .aport/ dir
  const localDir = path.join(process.cwd(), '.aport');
  if (fs.existsSync(localDir)) {
    return path.join(localDir, 'audit.log');
  }
  // Fallback: ~/.aport/<framework>/audit.log
  const home = process.env.HOME ?? '';
  return path.join(home, '.aport', framework, 'audit.log');
}

/**
 * Extract a short context summary from tool context for audit log entries.
 */
export function extractContextSummary(context: Record<string, unknown>): string | undefined {
  const command = context.command ?? context.cmd ?? context.full_command;
  if (typeof command === 'string' && command) return command;

  const filePath = context.file_path ?? context.path ?? context.file;
  if (typeof filePath === 'string' && filePath) return filePath;

  const recipient = context.recipient ?? context.to;
  if (typeof recipient === 'string' && recipient) return recipient;

  const url = context.url;
  if (typeof url === 'string' && url) return url;

  const input = context.input;
  if (typeof input === 'string' && input) return input;

  return undefined;
}

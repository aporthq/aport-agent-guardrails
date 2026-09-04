import { appendFile, appendFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

export function logAuditEntry(auditLogPath, entry) {
  try {
    const ts = new Date().toISOString().replace("T", " ").replace(/\.\d+Z$/, "");
    const code = entry.code || (entry.allow ? "oap.allowed" : "oap.denied");
    let line = `[${ts}] tool=${entry.tool}`;
    if (entry.decisionId) line += ` decision_id=${entry.decisionId}`;
    line += ` allow=${entry.allow} policy=${entry.policy} code=${code}`;
    if (entry.agentId) line += ` agent_id=${entry.agentId}`;
    if (entry.context) {
      const sanitized = String(entry.context)
        .replace(/[\r\n]+/g, " ")
        .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
        .replace(/apk_[A-Za-z0-9_-]+/g, "[REDACTED_APORT_KEY]")
        .replace(/github_pat_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
        .replace(/gh[pousr]_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
        .replace(/AKIA[0-9A-Z]{16}/g, "[REDACTED_AWS_KEY]")
        .replace(/(Authorization:?\s*Bearer|Bearer)\s+[A-Za-z0-9._~+/-]+=*/gi, "$1 [REDACTED]")
        .replace(/(password|passwd|pwd|token|secret|api[_-]?key)=\S+/gi, "$1=[REDACTED]")
        .replace(/"/g, '\\"')
        .slice(0, 120);
      line += ` context="${sanitized}"`;
    }
    line += "\n";

    const dir = dirname(auditLogPath);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

    if (entry.allow) {
      appendFile(auditLogPath, line, "utf8", () => {});
    } else {
      appendFileSync(auditLogPath, line, "utf8");
    }
  } catch {
    // Best-effort only.
  }
}

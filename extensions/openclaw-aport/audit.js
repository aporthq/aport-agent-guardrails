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

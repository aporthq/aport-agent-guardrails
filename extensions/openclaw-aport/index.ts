/**
 * APort OpenClaw Plugin
 *
 * Registers before_tool_call hook for deterministic policy enforcement.
 * Calls APort guardrail (local or API) before every tool execution.
 */

import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { spawn } from "child_process";
import { createHash, randomUUID } from "crypto";
import { readFile, mkdir, appendFile } from "fs/promises";
import { appendFileSync, mkdirSync, existsSync } from "fs";
import { join, dirname } from "path";
import { homedir } from "os";

// Re-export utility functions for testing
export { mapToolToPolicy, canonicalize, verifyDecisionIntegrity };

interface APortPluginConfig {
  mode?: "local" | "api";
  agentId?: string;
  passportFile?: string;
  guardrailScript?: string;
  apiUrl?: string;
  apiKey?: string;
  failClosed?: boolean;
  allowUnmappedTools?: boolean;
  alwaysVerifyEachToolCall?: boolean;
  mapExecToPolicy?: boolean;
}

const plugin = {
  id: "openclaw-aport",
  name: "APort Guardrails",
  description:
    "Deterministic pre-action authorization via APort policy enforcement. Registers before_tool_call to block disallowed tools.",
  configSchema: {
    type: "object",
    additionalProperties: false,
    properties: {
      mode: {
        type: "string",
        enum: ["local", "api"],
        default: "local",
        description: "local = guardrail script, api = APort API",
      },
      passportFile: {
        type: "string",
        default: "~/.openclaw/passport.json",
        description: "Path to passport JSON",
      },
      guardrailScript: {
        type: "string",
        default: "~/.openclaw/.skills/aport-guardrail-bash.sh",
        description: "Path to guardrail script (local mode)",
      },
      apiUrl: {
        type: "string",
        description: "APort API base URL (api mode)",
      },
      apiKey: {
        type: "string",
        description: "API key (prefer APORT_API_KEY env var)",
      },
      failClosed: {
        type: "boolean",
        default: true,
        description: "Block tool on guardrail error when true",
      },
      allowUnmappedTools: {
        type: "boolean",
        default: false,
        description:
          "If true, allow tools with no policy mapping (custom skills, ClawHub, etc.). If false (default, RECOMMENDED), block unmapped tools for security. All core OpenClaw tools are mapped; only set to true if you use custom/ClawHub skills.",
      },
      agentId: {
        type: "string",
        description:
          "Optional: hosted passport from aport.io (API fetches passport)",
      },
      alwaysVerifyEachToolCall: {
        type: "boolean",
        default: true,
        description: "Run fresh APort verify for each tool call",
      },
      mapExecToPolicy: {
        type: "boolean",
        default: true,
        description: "Map exec tool to system.command.execute policy",
      },
    },
  },

  register(api: OpenClawPluginApi) {
    // Get plugin config
    const config = (api.pluginConfig || {}) as APortPluginConfig;
    const mode = config.mode || "local";
    const agentId = config.agentId || null;
    const passportFile = expandPath(
      config.passportFile || "~/.openclaw/aport/passport.json",
    );
    const guardrailScript = expandPath(
      config.guardrailScript || "~/.openclaw/.skills/aport-guardrail-bash.sh",
    );
    const apiUrl =
      config.apiUrl || process.env.APORT_API_URL || "https://api.aport.io";
    const apiKey = process.env.APORT_API_KEY || config.apiKey;

    const failClosed = config.failClosed !== false;
    const allowUnmappedTools = config.allowUnmappedTools === true; // Default false for security
    const mapExecToPolicy = config.mapExecToPolicy !== false;

    const log = (msg: string) => api.logger?.info?.(msg);
    const warn = (msg: string) => api.logger?.warn?.(msg);
    const err = (msg: string) => api.logger?.error?.(msg);

    log(
      `[APort] Loaded: mode=${mode}, ${agentId ? `agentId=${agentId}` : `passportFile=${passportFile}`}, unmapped=${allowUnmappedTools ? "allow" : "block"}, mapExec=${mapExecToPolicy}`,
    );

    /**
     * before_tool_call hook - Runs before EVERY tool execution
     */
    api.on("before_tool_call", async (event: any, _ctx: any) => {
      const { toolName, params } = event;

      try {
        // Map OpenClaw tool names to APort policy names
        const policyName =
          toolName === "exec" && !mapExecToPolicy
            ? null
            : mapToolToPolicy(toolName);

        if (!policyName) {
          if (allowUnmappedTools) {
            log(`[APort] ALLOW: ${toolName} - (unmapped, no policy)`);
            return {};
          }
          log(
            `[APort] BLOCKED: ${toolName} - no policy mapping (allowUnmappedTools=false)`,
          );
          return {
            block: true,
            blockReason: `🛡️ APort: Tool "${toolName}" has no policy mapping. Unmapped tools are blocked (allowUnmappedTools: false). Set allowUnmappedTools: true in config to allow custom skills and ClawHub tools.`,
          };
        }

        log(`[APort] Checking tool: ${toolName} → policy: ${policyName}`);

        // Normalize context
        let effectivePolicyName = policyName;
        let effectiveToolName = toolName;
        let context =
          policyName === "system.command.execute.v1"
            ? normalizeExecContext(params, event)
            : params;


        // Allow exec with no command
        if (effectivePolicyName === "system.command.execute.v1") {
          const cmdStr =
            typeof context.command === "string" ? context.command.trim() : "";
          if (!cmdStr) {
            log(`[APort] ALLOW: exec - (empty command, skip)`);
            return {};
          }
        }

        // Verify via API or script
        const scriptToolName = effectivePolicyName.replace(/\.v\d+$/, "");
        let decision: any;
        if (mode === "api") {
          decision = await verifyViaAPI(effectivePolicyName, context, {
            apiUrl,
            apiKey,
            passportFile: agentId ? null : passportFile,
            agentId,
          });
          // Audit log for API mode (local mode is logged by the bash script via OPENCLAW_AUDIT_LOG)
          const configDir = dirname(passportFile);
          const auditLogPath = join(configDir, "audit.log");
          const ctxSummary = typeof context.command === "string" ? context.command
            : typeof context.file_path === "string" ? context.file_path
            : typeof context.recipient === "string" ? context.recipient
            : undefined;
          logAuditEntry(auditLogPath, {
            tool: effectiveToolName,
            allow: Boolean(decision.allow),
            policy: effectivePolicyName,
            code: decision.reasons?.[0]?.code,
            agentId: agentId || undefined,
            context: ctxSummary,
          });
        } else {
          decision = await verifyViaScript(scriptToolName, context, {
            guardrailScript,
            passportFile,
          });
        }

        // Verify decision integrity (prevent tampering)
        if (!verifyDecisionIntegrity(decision)) {
          err(
            `[APort] Decision integrity check failed for ${effectiveToolName} - content_hash mismatch`,
          );
          return {
            block: true,
            blockReason:
              "🛡️ APort: Decision integrity verification failed (content_hash mismatch). Possible tampering detected.",
          };
        }

        // Check decision
        if (!decision.allow) {
          const { reasons, primaryMessage } = formatReasons(decision);
          const message = primaryMessage || "Policy denied";
          log(`[APort] BLOCKED: ${effectiveToolName} - ${message}`);

          const reasonLines = reasons
            .map((r: any) => `  • ${r.code || "oap.unknown"}: ${r.message || ""}`)
            .join("\n");

          const blockReason = [
            "🛡️ APort Policy Denied",
            "",
            `Policy: ${effectivePolicyName}`,
            "",
            "Reasons (OAP codes):",
            reasonLines || `  • ${message}`,
            "",
            agentId
              ? `To allow this action, update limits at aport.io (hosted passport: ${agentId})`
              : `To allow this action, update limits in your passport: ${passportFile}`,
          ].join("\n");

          return {
            block: true,
            blockReason,
            reasons,
          };
        }

        log(`[APort] ALLOW: ${effectiveToolName}`);
        return {
          reasons: decision.reasons?.length ? decision.reasons : undefined,
        };
      } catch (error: any) {
        err(`[APort] Error evaluating policy: ${error.message}`);

        if (failClosed) {
          return {
            block: true,
            blockReason: `🛡️ APort Policy Error (fail-closed)\n\nError: ${error.message}\n\nCheck configuration at plugins.entries.openclaw-aport.config`,
          };
        } else {
          warn(`[APort] Allowing tool despite error (failClosed=false)`);
          return {};
        }
      }
    });

    log(`[APort] Registered hooks: before_tool_call`);
  },
};

export default plugin;

// Helper functions

function formatReasons(decision: any) {
  const reasons = decision.reasons || [];
  const primaryMessage = reasons[0]?.message || decision.reason || "";
  return { reasons, primaryMessage };
}

function normalizeExecContext(params: any, event: any) {
  const src =
    event && typeof event === "object" ? { ...event, ...params } : params || {};
  if (typeof src !== "object") return { command: "" };

  const raw =
    src.command ??
    src.cmd ??
    (src.arguments &&
      typeof src.arguments === "object" &&
      src.arguments.command) ??
    (src.input && typeof src.input === "object" && src.input.command) ??
    (typeof src.input === "string" && src.input.trim().length > 0
      ? src.input
      : null) ??
    (src.args && typeof src.args === "object" && src.args.command) ??
    (src.invocation &&
      typeof src.invocation === "object" &&
      src.invocation.command) ??
    (src.payload && typeof src.payload === "object" && src.payload.command) ??
    (Array.isArray(src.args) && src.args.length > 0
      ? src.args.join(" ")
      : src.args?.[0]);

  const full = typeof raw === "string" ? raw : raw != null ? String(raw) : "";

  const out = { ...params, command: full, full_command: full };
  if (params && params.workdir !== undefined && out.cwd === undefined)
    out.cwd = params.workdir;
  return out;
}

function mapToolToPolicy(toolName: string): string | null {
  const tool = toolName.toLowerCase();

  // Git/Code operations
  if (tool.match(/git\.(create_pr|merge|push|commit)/))
    return "code.repository.merge.v1";
  if (tool.startsWith("git.")) return "code.repository.merge.v1";

  // System commands / exec
  if (tool === "exec") return "system.command.execute.v1";
  if (tool.match(/exec\.(run|shell)/)) return "system.command.execute.v1";
  if (tool.startsWith("exec.")) return "system.command.execute.v1";
  if (tool.startsWith("system.command.")) return "system.command.execute.v1";
  if (tool === "bash" || tool === "shell" || tool === "command")
    return "system.command.execute.v1";

  // Messaging
  if (tool.startsWith("message.")) return "messaging.message.send.v1";
  if (tool.startsWith("messaging.")) return "messaging.message.send.v1";
  if (tool.match(/sms|whatsapp|slack|email/))
    return "messaging.message.send.v1";

  // File operations
  if (tool === "read") return "data.file.read.v1";
  if (tool.startsWith("file.read")) return "data.file.read.v1";
  if (tool.startsWith("data.file.read")) return "data.file.read.v1";
  if (tool === "write") return "data.file.write.v1";
  if (tool === "edit") return "data.file.write.v1";
  if (tool.startsWith("file.write")) return "data.file.write.v1";
  if (tool.startsWith("file.edit")) return "data.file.write.v1";
  if (tool.startsWith("data.file.write")) return "data.file.write.v1";

  // Web operations
  if (tool === "web_fetch" || tool === "webfetch") return "web.fetch.v1";
  if (tool === "web_search" || tool === "websearch") return "web.fetch.v1";
  if (tool.startsWith("web.fetch")) return "web.fetch.v1";
  if (tool.startsWith("web.search")) return "web.fetch.v1";
  if (tool === "browser") return "web.browser.v1";
  if (tool.startsWith("web.browser")) return "web.browser.v1";
  if (tool.startsWith("browser.")) return "web.browser.v1";

  // MCP tools
  if (tool.startsWith("mcp.")) return "mcp.tool.execute.v1";

  // Agent sessions and spawning
  if (tool.match(/agent\.session|session\.create/))
    return "agent.session.create.v1";
  if (tool === "sessions_spawn" || tool === "sessions_send")
    return "agent.session.create.v1";
  if (tool.startsWith("session.") || tool.startsWith("sessions."))
    return "agent.session.create.v1";

  // Scheduled tasks (cron)
  if (tool === "cron" || tool.startsWith("cron."))
    return "agent.session.create.v1";

  // Gateway operations (high risk - treat as command execution)
  if (tool === "gateway" || tool.startsWith("gateway."))
    return "system.command.execute.v1";

  // Process operations
  if (tool === "process" || tool.startsWith("process."))
    return "system.command.execute.v1";

  // Tool registration
  if (tool.match(/agent\.tool|tool\.register/)) return "agent.tool.register.v1";

  // Financial operations
  if (tool.match(/payment\.refund|refund/)) return "finance.payment.refund.v1";
  if (tool.match(/payment\.charge|charge/)) return "finance.payment.charge.v1";
  if (tool.startsWith("finance.")) return "finance.payment.refund.v1";

  // Data operations
  if (tool.match(/database\.(write|insert|update|delete)/))
    return "data.export.create.v1";
  if (tool.match(/data\.export|export/)) return "data.export.create.v1";

  return null;
}

function canonicalize(obj: any): string {
  if (obj === null || typeof obj !== "object") return JSON.stringify(obj);
  if (Array.isArray(obj)) return "[" + obj.map(canonicalize).join(",") + "]";
  const keys = Object.keys(obj).sort();
  const parts = keys.map((k) => JSON.stringify(k) + ":" + canonicalize(obj[k]));
  return "{" + parts.join(",") + "}";
}

function verifyDecisionIntegrity(decision: any): boolean {
  if (!decision || !decision.content_hash) return true;
  const { content_hash, ...rest } = decision;
  const canonical = canonicalize(rest);
  const computed =
    "sha256:" + createHash("sha256").update(canonical, "utf8").digest("hex");
  return computed === content_hash;
}

async function verifyViaScript(
  toolName: string,
  params: any,
  { guardrailScript, passportFile }: any,
): Promise<any> {
  const contextJson = JSON.stringify(params);
  const configDir = dirname(passportFile);
  const decisionsDir = join(configDir, "decisions");
  await mkdir(decisionsDir, { recursive: true });
  const decisionFile = join(decisionsDir, `${randomUUID()}.json`);

  return new Promise((resolve, reject) => {
    const proc = spawn(guardrailScript, [toolName, contextJson], {
      env: {
        ...process.env,
        OPENCLAW_PASSPORT_FILE: passportFile,
        OPENCLAW_DECISION_FILE: decisionFile,
        OPENCLAW_AUDIT_LOG: join(configDir, "audit.log"),
      },
    });

    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (data) => (stdout += data));
    proc.stderr.on("data", (data) => (stderr += data));

    proc.on("close", async (code) => {
      try {
        const decisionData = await readFile(decisionFile, "utf8");
        const decision = JSON.parse(decisionData);
        resolve(decision);
      } catch (err) {
        if (code === 0) {
          resolve({ allow: true });
        } else {
          resolve({
            allow: false,
            reasons: [
              { message: stderr || `Tool ${toolName} denied (exit ${code})` },
            ],
          });
        }
      }
    });

    proc.on("error", (error) => {
      reject(new Error(`Failed to run guardrail script: ${error.message}`));
    });
  });
}

function ensureIdempotencyKey(context: any) {
  if (context && context.idempotency_key) return context;
  const ts = Date.now().toString(36);
  const r = Math.random().toString(36).slice(2, 10);
  const key = `idem_${ts}_${r}`.slice(0, 64);
  return { ...context, idempotency_key: key };
}

async function verifyViaAPI(
  policyName: string,
  params: any,
  { apiUrl, apiKey, passportFile, agentId }: any,
): Promise<any> {
  try {
    const context = ensureIdempotencyKey(params);

    const url = `${apiUrl}/api/verify/policy/${policyName}`;
    const headers: any = {
      "Content-Type": "application/json",
    };
    if (apiKey) {
      headers["Authorization"] = `Bearer ${apiKey}`;
    }

    let body;
    if (agentId) {
      body = JSON.stringify({
        context: { agent_id: agentId, ...context },
      });
    } else {
      const passportData = await readFile(passportFile, "utf8");
      const passport = JSON.parse(passportData);
      body = JSON.stringify({
        passport,
        context,
      });
    }

    const response = await fetch(url, {
      method: "POST",
      headers,
      body,
    });

    if (!response.ok) {
      throw new Error(
        `API request failed: ${response.status} ${response.statusText}`,
      );
    }

    const data = (await response.json()) as { decision?: any };
    return data.decision || data;
  } catch (error: any) {
    throw new Error(`API verification failed: ${error.message}`);
  }
}

function expandPath(path: string): string {
  if (path.startsWith("~/")) {
    return join(homedir(), path.slice(2));
  }
  return path;
}

/**
 * Write one-line audit entry matching bash guardrail format.
 * Deny: sync (blocking). Allow: async (non-blocking). Best-effort: never throws.
 */
function logAuditEntry(
  auditLogPath: string,
  entry: { tool: string; allow: boolean; policy: string; code?: string; agentId?: string; context?: string },
): void {
  try {
    const ts = new Date().toISOString().replace("T", " ").replace(/\.\d+Z$/, "");
    const code = entry.code || (entry.allow ? "oap.allowed" : "oap.denied");
    let line = `[${ts}] tool=${entry.tool} allow=${entry.allow} policy=${entry.policy} code=${code}`;
    if (entry.agentId) line += ` agent_id=${entry.agentId}`;
    if (entry.context) {
      const sanitized = entry.context.replace(/[\r\n]+/g, " ").replace(/"/g, '\\"').slice(0, 120);
      line += ` context="${sanitized}"`;
    }
    line += "\n";
    const dir = dirname(auditLogPath);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    if (!entry.allow) {
      appendFileSync(auditLogPath, line, "utf8");
    } else {
      appendFile(auditLogPath, line, "utf8").catch(() => {});
    }
  } catch {
    /* best-effort */
  }
}

#!/usr/bin/env node
/**
 * APort OpenClaw Plugin
 *
 * Deterministic pre-action authorization via before_tool_call.
 * Uses a built-in JS local evaluator for offline mode and direct API calls for hosted mode.
 */

import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { homedir } from "node:os";
import { logAuditEntry } from "./audit.js";
import { canonicalize, formatReasons, verifyDecisionIntegrity } from "./decision.js";
import { evaluateLocalDecision } from "./local-evaluator.js";
import { mapToolToPolicy, normalizePolicyContext } from "./tool-mapping.js";
import { verifyViaApi } from "./api-client.js";

export { canonicalize, mapToolToPolicy, verifyDecisionIntegrity };

export default definePluginEntry({
  id: "openclaw-aport",
  name: "APort Guardrails",
  description:
    "Deterministic pre-action authorization via APort policy enforcement. Registers before_tool_call to block disallowed tools.",

  register(api) {
    const config = api.pluginConfig || {};
    const envAgentId = typeof process.env.APORT_AGENT_ID === "string" && process.env.APORT_AGENT_ID
      ? process.env.APORT_AGENT_ID
      : null;
    const mode = config.mode === "api" || (!config.mode && envAgentId) ? "api" : "local";
    const agentId = typeof config.agentId === "string" && config.agentId ? config.agentId : envAgentId;
    const passportFile = expandPath(config.passportFile || "~/.openclaw/aport/passport.json");
    const apiUrl = config.apiUrl || process.env.APORT_API_URL || "https://api.aport.io";
    const apiKey = config.apiKey || process.env.APORT_API_KEY || undefined;
    const failClosed = config.failClosed !== false;
    const allowUnmappedTools = config.allowUnmappedTools === true;
    const mapExecToPolicy = config.mapExecToPolicy !== false;
    const enforcement = normalizeEnforcementMode(
      config.enforcementMode ||
        config.enforcement ||
        process.env.APORT_ENFORCEMENT_MODE ||
        process.env.APORT_ENFORCEMENT ||
        process.env.APORT_GUARDRAIL_ENFORCEMENT,
    );

    const log = (msg) => api.logger?.info?.(msg);
    const warn = (msg) => api.logger?.warn?.(msg);
    const err = (msg) => api.logger?.error?.(msg);

    log(
      `[APort] Loaded: mode=${mode}, ${agentId ? `agentId=${agentId}` : `passportFile=${passportFile}`}, unmapped=${allowUnmappedTools ? "allow" : "block"}, mapExec=${mapExecToPolicy}`,
    );

    api.on("before_tool_call", async (event, hookContext = {}) => {
      const { toolName, params } = event;

      try {
        const policyName =
          toolName === "exec" && !mapExecToPolicy ? null : mapToolToPolicy(toolName, params);

        if (!policyName) {
          if (allowUnmappedTools) {
            log(`[APort] ALLOW: ${toolName} - (unmapped, no policy)`);
            return {};
          }
          const notice = formatGuardrailNotice({
            outcome: enforcement === "warn" ? "warn" : "deny",
            policy: "hook.tool.map",
            code: "oap.unknown_tool",
            message: `No policy mapping for ${toolName}`,
            agentId,
            passportFile,
          });
          log(`[APort] ${enforcement === "warn" ? "WARN" : "BLOCKED"}: ${toolName} - no policy mapping`);
          if (enforcement === "warn") return {};
          return {
            block: true,
            blockReason: notice,
          };
        }

        let effectivePolicyName = policyName;
        let effectiveToolName = toolName;
        let context = normalizePolicyContext(policyName, toolName, params, event);

        const delegated = parseGuardrailInvocation(
          effectivePolicyName === "system.command.execute.v1" ? context.command : null,
        );
        if (delegated) {
          const innerPolicy = mapToolToPolicy(delegated.innerToolName, delegated.innerContext);
          if (innerPolicy) {
            effectivePolicyName = innerPolicy;
            effectiveToolName = delegated.innerToolName;
            context = normalizePolicyContext(
              innerPolicy,
              delegated.innerToolName,
              delegated.innerContext,
              { params: delegated.innerContext },
            );
          }
        }

        if (effectivePolicyName === "system.command.execute.v1") {
          const command = typeof context.command === "string" ? context.command.trim() : "";
          if (!command) {
            log("[APort] ALLOW: exec - (empty command, skip)");
            return {};
          }
        }

        const requestContext = ensureIdempotencyKey(context, event, hookContext);
        const auditLogPath = join(dirname(passportFile), "audit.log");
        const decision =
          mode === "api"
            ? await verifyViaApi({
                apiUrl,
                apiKey,
                policyName: effectivePolicyName,
                context: requestContext,
                passport: agentId ? null : JSON.parse(await readFile(passportFile, "utf8")),
                agentId,
                signal: hookContext?.abortSignal,
              })
            : evaluateLocalDecision({
                policyName: effectivePolicyName,
                toolName: effectiveToolName,
                context: requestContext,
                passportFile,
              });

        if (!verifyDecisionIntegrity(decision)) {
          const notice = formatGuardrailNotice({
            outcome: enforcement === "warn" ? "warn" : "deny",
            policy: effectivePolicyName,
            code: "oap.decision_integrity_failed",
            message: "Decision integrity verification failed.",
            agentId,
            passportFile,
          });
          err(`[APort] Decision integrity check failed for ${effectiveToolName} - content_hash mismatch`);
          if (enforcement === "warn") {
            warn(`[APort] WARN: decision integrity failed; report-only mode allowed the tool. ${notice}`);
            return {};
          }
          return {
            block: true,
            blockReason: notice,
          };
        }

        logAuditEntry(auditLogPath, {
          tool: effectiveToolName,
          decisionId: decision.decision_id,
          allow: Boolean(decision.allow),
          policy: effectivePolicyName,
          code: decision.reasons?.[0]?.code,
          agentId: agentId || decision.agent_id || undefined,
          context: extractContextSummary(requestContext),
        });

        if (!decision.allow) {
          const { reasons, primaryMessage } = formatReasons(decision);
          const primaryReason = reasons[0] || {};
          const message = primaryMessage || "Policy denied.";
          const notice = formatGuardrailNotice({
            outcome: enforcement === "warn" ? "warn" : "deny",
            policy: effectivePolicyName,
            code: primaryReason.code || "oap.denied",
            message,
            agentId,
            passportFile,
          });
          log(`[APort] ${enforcement === "warn" ? "WARN" : "BLOCKED"}: ${effectiveToolName} - ${sanitizeDisplayText(message)}`);

          if (enforcement === "warn") {
            return {};
          }

          return {
            block: true,
            blockReason: notice,
          };
        }

        log(`[APort] ALLOW: ${effectiveToolName}`);
        return {};
      } catch (error) {
        err(`[APort] Error evaluating policy: ${sanitizeDisplayText(error.message)}`);
        if (failClosed && enforcement !== "warn") {
          return {
            block: true,
            blockReason: formatGuardrailNotice({
              outcome: "deny",
              policy: "hook.runtime",
              code: "oap.policy_error",
              message: error.message,
              agentId,
              passportFile,
            }),
          };
        }
        warn(
          enforcement === "warn"
            ? `[APort] WARN: policy evaluation failed; report-only mode allowed the tool. ${policyReference({ agentId, passportFile })}`
            : "[APort] Allowing tool despite policy evaluation error because failClosed is disabled.",
        );
        return {};
      }
    });

    log("[APort] Registered hooks: before_tool_call");
  },
});

function ensureIdempotencyKey(context, event = {}, hookContext = {}) {
  if (context && context.idempotency_key) return context;
  const stableSeed = [
    event?.toolCallId,
    event?.tool_call_id,
    event?.id,
    event?.callId,
    event?.call_id,
    hookContext?.toolCallId,
    hookContext?.tool_call_id,
    hookContext?.toolInvocationId,
    hookContext?.tool_invocation_id,
  ]
    .filter((value) => typeof value === "string" && value.trim())
    .join(":");
  if (stableSeed) {
    const digest = createHash("sha256").update(stableSeed).digest("hex").slice(0, 40);
    return {
      ...context,
      idempotency_key: `openclaw_${digest}`.slice(0, 64),
    };
  }
  const ts = Date.now().toString(36);
  const rand = Math.random().toString(36).slice(2, 10);
  return {
    ...context,
    idempotency_key: `idem_${ts}_${rand}`.slice(0, 64),
  };
}

function expandPath(value) {
  if (value.startsWith("~/")) return join(homedir(), value.slice(2));
  return value;
}

function extractContextSummary(context) {
  if (typeof context?.command === "string" && context.command) return sanitizeDisplayText(context.command);
  if (typeof context?.file_path === "string" && context.file_path) return sanitizeDisplayText(context.file_path);
  if (typeof context?.recipient === "string" && context.recipient) return sanitizeDisplayText(context.recipient);
  if (typeof context?.url === "string" && context.url) return sanitizeDisplayText(context.url);
  return undefined;
}

function parseGuardrailInvocation(command) {
  if (typeof command !== "string" || !command.includes("aport-guardrail")) return null;
  const trimmed = command.trim();
  const argv = splitSimpleShellWords(trimmed);
  if (!argv || argv.length !== 3) return null;
  const commandName = basename(argv[0]);
  if (!TRUSTED_GUARDRAIL_BINARIES.has(commandName)) return null;
  try {
    return {
      innerToolName: argv[1],
      innerContext: argv[2].trim() ? JSON.parse(argv[2]) : {},
    };
  } catch {
    return null;
  }
}

const TRUSTED_GUARDRAIL_BINARIES = new Set([
  "aport-guardrail.sh",
  "aport-guardrail-bash.sh",
  "aport-guardrail-api.sh",
  "aport-guardrail-v2.sh",
]);

function splitSimpleShellWords(input) {
  const words = [];
  let current = "";
  let quote = "";

  for (const ch of input) {
    if (quote) {
      if (ch === quote) {
        quote = "";
      } else {
        current += ch;
      }
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      continue;
    }
    if (/\s/.test(ch)) {
      if (current) {
        words.push(current);
        current = "";
      }
      continue;
    }
    current += ch;
  }

  if (quote) return null;
  if (current) words.push(current);
  return words;
}

function normalizeEnforcementMode(value) {
  const normalized = String(value || "enforce").toLowerCase().replace(/_/g, "-");
  if (["warn", "report-only", "audit-only", "observe", "observation"].includes(normalized)) return "warn";
  return "enforce";
}

function sanitizeDisplayText(value) {
  return String(value ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
    .replace(/(?:apk|aprt)_[A-Za-z0-9_-]+/g, "[REDACTED_APORT_KEY]")
    .replace(/github_pat_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
    .replace(/gh[pousr]_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
    .replace(/AKIA[0-9A-Z]{16}/g, "[REDACTED_AWS_KEY]")
    .replace(/(Authorization:?\s*Bearer|Bearer)\s+[A-Za-z0-9._~+/-]+=*/gi, "$1 [REDACTED]")
    .replace(/(password|passwd|pwd|token|secret|api[_-]?key)=\S+/gi, "$1=[REDACTED]")
    .slice(0, 320);
}

function policyReference({ agentId, passportFile }) {
  const appUrl = String(process.env.APORT_APP_URL || "https://aport.io").replace(/\/$/, "");
  if (agentId) return `${appUrl}/passports?details=${encodeURIComponent(agentId)}`;
  if (passportFile) return passportFile;
  return `${appUrl}/quickstart`;
}

function formatGuardrailNotice({ outcome, policy, code, message, agentId, passportFile }) {
  const prefix =
    outcome === "warn"
      ? "APort warning: policy would have denied this tool call."
      : "APort denied this tool call.";
  const detail = sanitizeDisplayText(message || "");
  const safeCode = sanitizeDisplayText(code || "oap.denied");
  const safePolicy = sanitizeDisplayText(policy || "hook.runtime");
  const reference = sanitizeDisplayText(policyReference({ agentId, passportFile }));
  const parts = [`${prefix} Policy: ${safePolicy}. Reason: ${safeCode}.`];
  if (detail && detail !== safeCode) parts.push(`Detail: ${detail}.`);
  parts.push(`Review: ${reference}`);
  return parts.join(" ");
}

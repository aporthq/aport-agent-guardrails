#!/usr/bin/env node
/**
 * APort OpenClaw Plugin
 *
 * Deterministic pre-action authorization via before_tool_call.
 * Uses a built-in JS local evaluator for offline mode and direct API calls for hosted mode.
 */

import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
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
    const allowUnmappedTools = config.allowUnmappedTools !== false;
    const mapExecToPolicy = config.mapExecToPolicy !== false;

    const log = (msg) => api.logger?.info?.(msg);
    const warn = (msg) => api.logger?.warn?.(msg);
    const err = (msg) => api.logger?.error?.(msg);

    log(
      `[APort] Loaded: mode=${mode}, ${agentId ? `agentId=${agentId}` : `passportFile=${passportFile}`}, unmapped=${allowUnmappedTools ? "allow" : "block"}, mapExec=${mapExecToPolicy}`,
    );

    api.on("before_tool_call", async (event) => {
      const { toolName, params } = event;

      try {
        const policyName =
          toolName === "exec" && !mapExecToPolicy ? null : mapToolToPolicy(toolName, params);

        if (!policyName) {
          if (allowUnmappedTools) {
            log(`[APort] ALLOW: ${toolName} - (unmapped, no policy)`);
            return {};
          }
          log(`[APort] BLOCKED: ${toolName} - no policy mapping (allowUnmappedTools=false)`);
          return {
            block: true,
            blockReason: `🛡️ APort: Tool "${toolName}" has no policy mapping. Unmapped tools are blocked (allowUnmappedTools: false). Set allowUnmappedTools: true in config to allow unmapped custom skills and ClawHub tools.`,
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

        const requestContext = ensureIdempotencyKey(context);
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
              })
            : evaluateLocalDecision({
                policyName: effectivePolicyName,
                context: requestContext,
                passportFile,
              });

        if (!verifyDecisionIntegrity(decision)) {
          err(`[APort] Decision integrity check failed for ${effectiveToolName} - content_hash mismatch`);
          return {
            block: true,
            blockReason:
              "🛡️ APort: Decision integrity verification failed (content_hash mismatch). Possible tampering detected.",
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
          const message = primaryMessage || "Policy denied";
          log(`[APort] BLOCKED: ${effectiveToolName} - ${message}`);

          const reasonLines = reasons
            .map((reason) => `  • ${reason.code || "oap.unknown"}: ${reason.message || ""}`)
            .join("\n");

          return {
            block: true,
            blockReason: [
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
            ].join("\n"),
          };
        }

        log(`[APort] ALLOW: ${effectiveToolName}`);
        return {};
      } catch (error) {
        err(`[APort] Error evaluating policy: ${error.message}`);
        if (failClosed) {
          return {
            block: true,
            blockReason: `🛡️ APort Policy Error (fail-closed)\n\nError: ${error.message}\n\nCheck configuration at plugins.entries.openclaw-aport.config`,
          };
        }
        warn("[APort] Allowing tool despite error (failClosed=false)");
        return {};
      }
    });

    log("[APort] Registered hooks: before_tool_call");
  },
});

function ensureIdempotencyKey(context) {
  if (context && context.idempotency_key) return context;
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
  if (typeof context?.command === "string" && context.command) return context.command;
  if (typeof context?.file_path === "string" && context.file_path) return context.file_path;
  if (typeof context?.recipient === "string" && context.recipient) return context.recipient;
  if (typeof context?.url === "string" && context.url) return context.url;
  return undefined;
}

function parseGuardrailInvocation(command) {
  if (typeof command !== "string" || !command.includes("aport-guardrail")) return null;
  const match = command.match(/aport-guardrail[^\s]*\s+(\S+)\s+['"]([\s\S]*)['"]\s*$/);
  if (!match) return null;
  try {
    return {
      innerToolName: match[1],
      innerContext: match[2].trim() ? JSON.parse(match[2]) : {},
    };
  } catch {
    return null;
  }
}

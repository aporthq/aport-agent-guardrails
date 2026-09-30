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
import { normalizeEnforcementMode, shouldAllowDeniedDecision } from "./enforcement.js";
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
      `[APort] Loaded: mode=${mode}, enforcement=${enforcement}, ${agentId ? `agentId=${agentId}` : `passportFile=${passportFile}`}, unmapped=${allowUnmappedTools ? "allow" : "block"}, mapExec=${mapExecToPolicy}`,
    );

    api.on("before_tool_call", async (event, hookContext = {}) => {
      const { toolName, params } = event;

      try {
        const policyName =
          toolName === "exec" && !mapExecToPolicy ? null : mapToolToPolicy(toolName, params);

        if (!policyName) {
          if (toolName === "exec" && !mapExecToPolicy) {
            log("[APort] ALLOW: exec - (exec policy mapping disabled)");
            return {};
          }
          if (allowUnmappedTools) {
            log(`[APort] ALLOW: ${toolName} - (unmapped, no policy)`);
            return {};
          }
          const notice = formatGuardrailNotice({
            outcome: failureOutcomeForEnforcement(enforcement),
            policy: "hook.tool.map",
            code: "oap.unknown_tool",
            message: `No policy mapping for ${toolName}`,
            agentId,
            passportFile,
          });
          const shouldAllowFailure = shouldAllowAdapterOrRuntimeFailure(enforcement, failClosed);
          log(`[APort] ${shouldAllowFailure ? "ALLOW" : "BLOCKED"}: ${toolName} - no policy mapping`);
          if (shouldAllowFailure) {
            warn(`[APort] ${failureAllowMessage(enforcement, "Allowing unmapped tool because failClosed is disabled.")} ${notice}`);
            return {};
          }
          return {
            block: true,
            blockReason: notice,
          };
        }

        let effectivePolicyName = policyName;
        let effectiveToolName = toolName;
        let context = normalizePolicyContext(
          policyName,
          toolName,
          params,
          buildPolicyContextHints(policyName, event, hookContext),
        );

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
              buildPolicyContextHints(innerPolicy, { params: delegated.innerContext }, hookContext),
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

        const sessionAdapterError =
          effectivePolicyName === "agent.session.create.v1" ? sessionContextAdapterError(context) : null;
        if (sessionAdapterError) {
          const notice = formatGuardrailNotice({
            outcome: failureOutcomeForEnforcement(enforcement),
            policy: effectivePolicyName,
            code: sessionAdapterError.code,
            message: sessionAdapterError.message,
            agentId,
            passportFile,
          });
          const shouldAllowFailure = shouldAllowAdapterOrRuntimeFailure(enforcement, failClosed);
          log(`[APort] ${shouldAllowFailure ? "ALLOW" : "BLOCKED"}: ${effectiveToolName} - ${sessionAdapterError.summary}`);
          if (shouldAllowFailure) {
            warn(`[APort] ${failureAllowMessage(enforcement, sessionAdapterError.failOpenMessage)} ${notice}`);
            return {};
          }
          return {
            block: true,
            blockReason: notice,
          };
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
                runtime: buildRuntimeMetadata(enforcement),
              })
            : evaluateLocalDecision({
                policyName: effectivePolicyName,
                toolName: effectiveToolName,
                context: requestContext,
                passportFile,
              });

        if (!verifyDecisionIntegrity(decision)) {
          const notice = formatGuardrailNotice({
            outcome: failureOutcomeForEnforcement(enforcement),
            policy: effectivePolicyName,
            code: "oap.decision_integrity_failed",
            message: "Decision integrity verification failed.",
            agentId,
            passportFile,
          });
          err(`[APort] Decision integrity check failed for ${effectiveToolName} - content_hash mismatch`);
          if (shouldAllowAdapterOrRuntimeFailure(enforcement, failClosed)) {
            warn(
              `[APort] ${failureAllowMessage(enforcement, "Allowing tool despite decision integrity failure because failClosed is disabled.")} ${notice}`,
            );
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
            outcome: policyOutcomeForEnforcement(enforcement, decision),
            policy: effectivePolicyName,
            code: primaryReason.code || "oap.denied",
            message,
            agentId,
            passportFile,
          });
          const policyAllows = shouldAllowPolicyDecision(enforcement, decision);
          log(`[APort] ${policyAllows ? enforcement.toUpperCase() : "BLOCKED"}: ${effectiveToolName} - ${sanitizeDisplayText(message)}`);

          if (policyAllows) {
            warn(`[APort] ${notice}`);
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
        const notice = formatGuardrailNotice({
          outcome: failureOutcomeForEnforcement(enforcement),
          policy: "hook.runtime",
          code: "oap.policy_error",
          message: error.message,
          agentId,
          passportFile,
        });
        if (!shouldAllowAdapterOrRuntimeFailure(enforcement, failClosed)) {
          return {
            block: true,
            blockReason: notice,
          };
        }
        warn(
          `[APort] ${failureAllowMessage(enforcement, "Allowing tool despite policy evaluation error because failClosed is disabled.")} ${notice}`,
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

function buildPolicyContextHints(policyName, event = {}, hookContext = {}) {
  if (policyName !== "agent.session.create.v1") return event;
  return {
    ...(event && typeof event === "object" ? event : {}),
    ...(hookContext && typeof hookContext === "object" ? hookContext : {}),
    user_id: resolveSessionUserId(event),
  };
}

function resolveSessionUserId(event = {}) {
  const configUserId =
    event && typeof event === "object"
      ? event.user_id ?? event.userId ?? event.owner_id ?? event.ownerId
      : "";
  return firstNonEmptyString(
    configUserId,
    process.env.APORT_USER_ID,
    process.env.APORT_TARGET_USER,
    process.env.APORT_OWNER_EMAIL,
    process.env.APORT_EMAIL,
    process.env.APORT_AGENT_ID,
    process.env.USER,
    process.env.LOGNAME,
  );
}

function firstNonEmptyString(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
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
  let hadToken = false;
  let escaped = false;

  for (const ch of input) {
    if (escaped) {
      current += ch;
      hadToken = true;
      escaped = false;
      continue;
    }
    if (quote) {
      if (quote === '"' && ch === "\\") {
        escaped = true;
        hadToken = true;
        continue;
      }
      if (ch === quote) {
        quote = "";
      } else {
        current += ch;
        hadToken = true;
      }
      continue;
    }
    if (ch === "\\") {
      escaped = true;
      hadToken = true;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      hadToken = true;
      continue;
    }
    if (/[;&|<>`$]/.test(ch)) return null;
    if (/\s/.test(ch)) {
      if (hadToken) {
        words.push(current);
        current = "";
        hadToken = false;
      }
      continue;
    }
    current += ch;
    hadToken = true;
  }

  if (quote || escaped) return null;
  if (hadToken) words.push(current);
  return words;
}

function buildRuntimeMetadata(enforcement) {
  return {
    enforcement_mode: enforcement === "observe" ? "observe" : enforcement === "warn" ? "warn" : "enforce",
    enforced_by: "@aporthq/openclaw-aport",
    harness: "openclaw",
  };
}

function sessionContextAdapterError(context) {
  if (context?.invalid_session_duration === true) {
    return {
      code: "oap.invalid_session_duration",
      message: "Session duration is malformed or outside the supported 60-86400 second range.",
      summary: "invalid session duration",
      failOpenMessage: "Allowing tool despite invalid session duration because failClosed is disabled.",
    };
  }
  if (context?.invalid_session_type === true) {
    return {
      code: "oap.invalid_session_type",
      message: "Session type is malformed or outside the supported interactive, batch, webhook, scheduled, or ephemeral values.",
      summary: "invalid session type",
      failOpenMessage: "Allowing tool despite invalid session type because failClosed is disabled.",
    };
  }
  if (context?.invalid_session_count === true) {
    return {
      code: "oap.invalid_session_count",
      message: "Active session count is malformed; expected a non-negative integer from trusted host metadata.",
      summary: "invalid active session count",
      failOpenMessage: "Allowing tool despite invalid active session count because failClosed is disabled.",
    };
  }
  return null;
}

function shouldAllowPolicyDecision(enforcement, decision) {
  return shouldAllowDeniedDecision(enforcement, decision);
}

function shouldAllowAdapterOrRuntimeFailure(enforcement, failClosed) {
  return enforcement === "observe" || !failClosed;
}

function policyOutcomeForEnforcement(enforcement, decision) {
  if (!shouldAllowDeniedDecision(enforcement, decision)) return "deny";
  return enforcement === "observe" ? "observe" : "warn";
}

function failureOutcomeForEnforcement(enforcement) {
  return enforcement === "observe" ? "observe" : "deny";
}

function failureAllowMessage(enforcement, failOpenMessage) {
  if (enforcement === "observe") {
    return "Observe mode allowed an action that APort did not authorize.";
  }
  return failOpenMessage;
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
    outcome === "observe"
      ? "APort observation: observe mode allowed a tool call that APort did not authorize."
      : outcome === "warn"
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

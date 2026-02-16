#!/usr/bin/env node
/**
 * APort OpenClaw Plugin
 *
 * Registers before_tool_call hook for deterministic policy enforcement.
 * Calls APort guardrail (local or API) before every tool execution.
 * Returns { block?, blockReason?, params?, reasons?, reasonSummary? }. On allow, reasons from APort are propagated for UX.
 *
 * Installation:
 *   openclaw plugins install /path/to/aport-agent-guardrails/extensions/openclaw-aport
 *
 * Configuration (in config.yaml):
 *   plugins:
 *     entries:
 *       openclaw-aport:
 *         enabled: true
 *         config:
 *           mode: local        # "local" | "api"
 *           passportFile: ~/.openclaw/passport.json   # Omit when using agentId (hosted)
 *           agentId: ap_...     # Optional: hosted passport from aport.io (API fetches passport)
 *           guardrailScript: ~/.openclaw/.skills/aport-guardrail-bash.sh
 *           apiUrl: https://api.aport.io  # For API mode
 *           # apiKey optional: set APORT_API_KEY env var if your API requires it
 *           failClosed: true               # Block on error
 *
 * Decisions (local mode): Written to <config_dir>/decisions/<timestamp>-<id>.json and left for
 * audit. The guardrail script also appends a one-line summary to <config_dir>/audit.log. Decisions
 * follow OAP v1.0 schema (see agent-passport spec/oap/decision-schema.json). Local mode uses
 * unsigned/local-unsigned; API mode can return signed decisions (chained audit in agent-passport).
 */

import { spawn } from "child_process";
import { createHash } from "crypto";
import { readFile, mkdir } from "fs/promises";
import { join, dirname } from "path";
import { homedir } from "os";

export default function (api) {
  const id = "openclaw-aport";
  const name = "APort Guardrails";

  // Plugin config from plugins.entries.openclaw-aport.config (OpenClaw passes api.pluginConfig)
  const config = api.pluginConfig || {};
  const mode = config.mode || "local";
  const agentId = config.agentId || null;
  const passportFile = expandPath(
    config.passportFile || "~/.openclaw/passport.json",
  );
  const guardrailScript = expandPath(
    config.guardrailScript || "~/.openclaw/.skills/aport-guardrail-bash.sh",
  );
  const apiUrl =
    config.apiUrl || process.env.APORT_API_URL || "https://api.aport.io";
  const apiKey = config.apiKey || process.env.APORT_API_KEY;
  const failClosed = config.failClosed !== false; // Default true
  const allowUnmappedTools = config.allowUnmappedTools !== false; // Default true = allow unmapped (custom skills, ClawHub); set false for strict
  // When true (default), every before_tool_call runs a fresh APort verify; we never reuse a previous decision (passport/limits may have changed).
  const alwaysVerifyEachToolCall = config.alwaysVerifyEachToolCall !== false;
  // When true (default), exec is mapped to system.command.execute.v1 and checked against passport allowed_commands.
  // When false, exec is not mapped (unmapped tools allowed by default) so OpenClaw can run any command — no guardrail for exec (use only if you rely on other controls).
  const mapExecToPolicy = config.mapExecToPolicy !== false;

  const log = (msg) => api.logger?.info?.(msg);
  const warn = (msg) => api.logger?.warn?.(msg);
  const err = (msg) => api.logger?.error?.(msg);

  /**
   * One-line summary for ALLOW/BLOCKED logs — tool + context hint. No I/O, no heavy work.
   * Keeps logs scannable and screenshot-friendly (e.g. "system.command.execute - mkdir test").
   */
  function decisionLogSummary(effectiveToolName, policyName, context) {
    if (policyName === "system.command.execute.v1" && context?.command) {
      const cmd = String(context.command).replace(/\s+/g, " ").trim();
      return cmd.length > 52 ? cmd.slice(0, 52) + "…" : cmd;
    }
    if (policyName === "messaging.message.send.v1") {
      const to = context?.recipient ?? context?.to ?? "";
      return to ? `send → ${String(to).slice(0, 32)}` : "send";
    }
    if (policyName?.startsWith("code.repository.")) return "repo";
    if (policyName?.startsWith("mcp.")) return "mcp tool";
    return policyName?.replace(/\.v\d+$/, "") ?? effectiveToolName;
  }

  /** Format decision.reasons (OAP code + message) for logs and UX; used for both allow and deny. */
  function formatReasons(decision) {
    const reasons = decision.reasons || [];
    const primaryMessage = reasons[0]?.message || decision.reason || "";
    const codes = reasons.map((r) => r.code).filter(Boolean);
    const codeList = codes.length ? codes.join(", ") : "";
    const lines =
      reasons.length > 0
        ? reasons
            .map((r) => `  • ${r.code || "oap.unknown"}: ${r.message || ""}`)
            .join("\n")
        : primaryMessage
          ? `  • ${primaryMessage}`
          : "";
    return { reasons, codeList, lines, primaryMessage };
  }

  /**
   * Detect if exec is actually invoking our guardrail script (e.g. agent/skill runs
   * "aport-guardrail.sh messaging.message.send '{}'" or "aport-guardrail.sh system.command.execute '{\"command\":\"mkdir ...\"}'").
   * If so, return { innerToolName, innerContext } so we evaluate the inner tool's policy, not exec as a shell command.
   * @param {string} command - params.command from exec
   * @returns {{ innerToolName: string, innerContext: object } | null}
   */
  function parseGuardrailInvocation(command) {
    if (typeof command !== "string" || !command.includes("aport-guardrail"))
      return null;
    const match = command.match(
      /aport-guardrail[^\s]*\s+(\S+)\s+['"]([\s\S]*)['"]\s*$/,
    );
    if (!match) return null;
    const innerToolName = match[1];
    let innerContext = {};
    try {
      const jsonStr = match[2].trim();
      if (jsonStr) innerContext = JSON.parse(jsonStr);
    } catch (_) {
      return null;
    }
    return { innerToolName, innerContext };
  }

  /** Collect all string values from a nested object (like openclaw-shield). */
  function collectStrings(value) {
    const out = [];
    if (typeof value === "string") {
      out.push(value);
    } else if (Array.isArray(value)) {
      for (const v of value) out.push(...collectStrings(v));
    } else if (value && typeof value === "object") {
      for (const v of Object.values(value)) out.push(...collectStrings(v));
    }
    return out;
  }

  /**
   * Normalize context for exec / system.command.execute so the actual shell command
   * is always in context.command. OpenClaw uses one tool "exec" for all commands (cp, mkdir, etc.);
   * the policy checks the command string against allowed_commands, so we must pass the real command.
   * Per https://docs.openclaw.ai/tools/exec the tool takes "command" (required). Gateway may
   * pass it as params.command, event.input, or nested; we also fall back to first long string in params/event.
   * @param {object} params - event.params from before_tool_call
   * @param {object} [event] - full event in case gateway puts command on event.input/event.arguments
   */
  function normalizeExecContext(params, event) {
    const src =
      event && typeof event === "object"
        ? { ...event, ...params }
        : params || {};
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
    let full = typeof raw === "string" ? raw : raw != null ? String(raw) : "";
    if (!full) {
      const strings = collectStrings(src);
      const likeCommand = (s) =>
        typeof s === "string" && s.length > 2 && s.trim().length > 0;
      const withSpace = strings.filter(
        (s) => likeCommand(s) && s.includes(" "),
      );
      const candidate = withSpace[0] ?? strings.find(likeCommand);
      if (candidate) full = candidate.trim();
    }
    const out = { ...params, command: full, full_command: full };
    if (params && params.workdir !== undefined && out.cwd === undefined)
      out.cwd = params.workdir;
    return out;
  }

  log(
    `[${name}] Loaded: mode=${mode}, ${agentId ? `agentId=${agentId}` : `passportFile=${passportFile}`}, unmapped=${allowUnmappedTools ? "allow" : "block"}, alwaysVerify=${alwaysVerifyEachToolCall}, mapExec=${mapExecToPolicy}`,
  );

  /**
   * before_tool_call hook - Runs before EVERY tool execution.
   * We never reuse a previous decision: each call triggers a fresh APort verify (passport/limits may have changed).
   *
   * @param {object} event - { toolName, params, ... }
   * @param {object} ctx - OpenClaw context
   * @returns {Promise<object>} - { block?, blockReason?, params?, reasons? (OAP), reasonSummary? }
   */
  api.on("before_tool_call", async (event, ctx) => {
    const { toolName, params } = event;

    try {
      // Map OpenClaw tool names to APort policy names. If mapExecToPolicy is false, exec is unmapped (never blocked).
      const policyName =
        toolName === "exec" && !mapExecToPolicy
          ? null
          : mapToolToPolicy(toolName);

      if (!policyName) {
        // No policy mapping: allow by default so custom skills / ClawHub / built-in tools work; block only if allowUnmappedTools is false (strict)
        if (allowUnmappedTools) {
          log(`[${name}] ALLOW: ${toolName} - (unmapped, no policy)`);
          return {};
        }
        log(
          `[${name}] BLOCKED: ${toolName} - no policy mapping (allowUnmappedTools=false)`,
        );
        return {
          block: true,
          blockReason: `🛡️ APort: Tool "${toolName}" has no policy mapping. Unmapped tools are blocked (allowUnmappedTools: false). Set allowUnmappedTools: true in config to allow custom skills and ClawHub tools.`,
        };
      }

      log(`[${name}] Checking tool: ${toolName} → policy: ${policyName}`);

      // For exec: the "command" may be (1) a real shell command (mkdir, npm, etc.) or
      // (2) an invocation of our guardrail script (e.g. aport-guardrail.sh messaging.message.send '{}').
      // In case (2) we evaluate the inner tool's policy, not exec as a shell command.
      let effectivePolicyName = policyName;
      let effectiveToolName = toolName;
      let context =
        policyName === "system.command.execute.v1"
          ? normalizeExecContext(params, event)
          : params;

      if (policyName === "system.command.execute.v1" && context.command) {
        const guardrailInvocation = parseGuardrailInvocation(context.command);
        if (guardrailInvocation) {
          const { innerToolName, innerContext } = guardrailInvocation;
          const innerPolicy = mapToolToPolicy(innerToolName);
          if (innerPolicy) {
            effectivePolicyName = innerPolicy;
            effectiveToolName = innerToolName;
            context =
              innerPolicy === "system.command.execute.v1"
                ? normalizeExecContext(innerContext, { params: innerContext })
                : innerContext;
            log(
              `[${name}] exec delegates to inner tool: ${innerToolName} → policy: ${innerPolicy}`,
            );
          }
        }
        const cmd = context.command || "";
        log(
          `[${name}] exec params.command → effective policy=${effectivePolicyName} context.command=${cmd ? `"${cmd.slice(0, 60)}${cmd.length > 60 ? "…" : ""}"` : "(n/a)"}`,
        );
      }

      // Allow exec with no command (probe/placeholder) without calling guardrail so we don't block pre-checks.
      if (effectivePolicyName === "system.command.execute.v1") {
        const cmdStr =
          typeof context.command === "string" ? context.command.trim() : "";
        if (!cmdStr) {
          log(`[${name}] ALLOW: exec - (empty command, skip)`);
          return {};
        }
      }

      // Every call runs a fresh verify — no cache. Each invocation gets a unique decision file path; we never reuse a previous decision.
      // Local mode: guardrail script maps tool names via case "exec.run|exec.*|system.*" etc. Raw "exec" does not match, so pass policy-derived name (e.g. system.command.execute) so the script recognizes it.
      const scriptToolName = effectivePolicyName.replace(/\.v\d+$/, "");
      let decision;
      if (mode === "api") {
        decision = await verifyViaAPI(effectivePolicyName, context, {
          apiUrl,
          apiKey,
          passportFile: agentId ? null : passportFile,
          agentId,
        });
      } else {
        decision = await verifyViaScript(scriptToolName, context, {
          guardrailScript,
          passportFile,
        });
      }

      // Tamper check is non-core: run after we return so it never blocks the tool call
      if (!decision.allow && decision.content_hash) {
        const decisionId = decision.decision_id;
        setImmediate(() => {
          if (!verifyDecisionIntegrity(decision)) {
            warn(
              `[${name}] Decision ${decisionId} may be tampered (content_hash mismatch)`,
            );
          }
        });
      }

      if (!decision.allow) {
        const {
          reasons,
          codeList,
          lines: reasonLines,
          primaryMessage,
        } = formatReasons(decision);
        const message = primaryMessage || "Policy denied";
        log(
          `[${name}] BLOCKED: ${effectiveToolName} - ${message}${codeList ? ` (${codeList})` : ""}`,
        );
        const isCommandNotAllowed =
          effectivePolicyName === "system.command.execute.v1" &&
          reasons.some((r) => r.code === "oap.command_not_allowed");
        if (isCommandNotAllowed) {
          if (agentId) {
            warn(
              `[${name}] Hosted passport (agent_id: ${agentId}). Add allowed_commands at aport.io or use "*" to allow all (blocked patterns still apply).`,
            );
          } else {
            try {
              const passportData = await readFile(passportFile, "utf8");
              const passport = JSON.parse(passportData);
              const allowed =
                passport?.limits?.["system.command.execute"]?.allowed_commands;
              warn(
                `[${name}] Passport allowed_commands: ${JSON.stringify(allowed)} — add "*" or the command (e.g. ls) to fix. File: ${passportFile}`,
              );
            } catch (_) {
              warn(
                `[${name}] Could not read passport for diagnostic: ${passportFile}`,
              );
            }
          }
        }
        const hint = isCommandNotAllowed
          ? "\nFor shell commands (cp, mkdir, npm, etc.), add them to limits.allowed_commands in your passport."
          : "";
        const passportHint = agentId
          ? `To allow this action, update limits at aport.io (hosted passport: ${agentId})`
          : `To allow this action, update limits in your passport: ${passportFile}`;
        const blockReason = [
          "🛡️ APort Policy Denied",
          "",
          `Policy: ${effectivePolicyName}`,
          "",
          "Reasons (OAP codes):",
          reasonLines || `  • ${message}`,
          "",
          passportHint,
          hint,
        ].join("\n");
        return {
          block: true,
          blockReason,
          reasons,
        };
      }

      const {
        reasons,
        codeList,
        lines: reasonLines,
        primaryMessage,
      } = formatReasons(decision);
      const reasonSummary =
        reasonLines || primaryMessage
          ? ["APort allowed", reasonLines || primaryMessage]
              .filter(Boolean)
              .join("\n")
          : undefined;
      const allowSummary = decisionLogSummary(
        effectiveToolName,
        effectivePolicyName,
        context,
      );
      log(`[${name}] ALLOW: ${effectiveToolName} - ${allowSummary}`);
      return {
        reasons: decision.reasons?.length ? decision.reasons : undefined,
        reasonSummary: reasonSummary || undefined,
      };
    } catch (error) {
      err(`[${name}] Error evaluating policy: ${error.message}`);

      if (failClosed) {
        // Fail closed - block on error
        return {
          block: true,
          blockReason: `🛡️ APort Policy Error (fail-closed)\n\nError: ${error.message}\n\nCheck configuration at plugins.entries.openclaw-aport.config`,
        };
      } else {
        // Fail open - allow on error (not recommended)
        warn(`[${name}] Allowing tool despite error (failClosed=false)`);
        return {};
      }
    }
  });

  /**
   * after_tool_call hook - Runs after successful tool execution
   * Optional: For audit logging
   */
  api.on("after_tool_call", async (event, ctx) => {
    const { toolName, params, result } = event;
    log(`[${name}] Tool completed: ${toolName}`);
    // Could log to audit trail here
  });

  log(`[${name}] Registered hooks: before_tool_call, after_tool_call`);
}

/**
 * Map OpenClaw tool names to APort policy names.
 * Exported for tests; used by before_tool_call to decide if we run guardrail and for API mode.
 */
export function mapToolToPolicy(toolName) {
  // Normalize tool name
  const tool = toolName.toLowerCase();

  // Git/Code operations
  if (tool.match(/git\.(create_pr|merge|push|commit)/))
    return "code.repository.merge.v1";
  if (tool.startsWith("git.")) return "code.repository.merge.v1";

  // System commands / exec (include bare "exec" - OpenClaw may send this for run-command tools)
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

  // MCP tools
  if (tool.startsWith("mcp.")) return "mcp.tool.execute.v1";

  // Agent sessions
  if (tool.match(/agent\.session|session\.create/))
    return "agent.session.create.v1";
  if (tool.startsWith("session.")) return "agent.session.create.v1";

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

  // No mapping found
  return null;
}

/**
 * Canonicalize object for hashing (sort keys at every level, like jq -c -S).
 * Must match guardrail script's jq --sort-keys output so content_hash verifies.
 * Exported for tests.
 */
export function canonicalize(obj) {
  if (obj === null || typeof obj !== "object") return JSON.stringify(obj);
  if (Array.isArray(obj)) return "[" + obj.map(canonicalize).join(",") + "]";
  const keys = Object.keys(obj).sort();
  const parts = keys.map((k) => JSON.stringify(k) + ":" + canonicalize(obj[k]));
  return "{" + parts.join(",") + "}";
}

/**
 * Verify local decision file integrity (content_hash). Returns true if valid or no hash (legacy).
 * If the file was edited or moved, the hash will not match. Exported for tests.
 */
export function verifyDecisionIntegrity(decision) {
  if (!decision || !decision.content_hash) return true;
  const { content_hash, ...rest } = decision;
  const canonical = canonicalize(rest);
  const computed =
    "sha256:" + createHash("sha256").update(canonical, "utf8").digest("hex");
  return computed === content_hash;
}

/**
 * Verify action via local guardrail script.
 * toolName must match the script's case patterns (e.g. system.command.execute, messaging.message.send); the plugin passes the policy-derived name (policy id without .v1) so "exec" is not passed (script would treat it as unknown).
 * Decisions are written under config dir (decisions/) with content_hash and chain (prev_*);
 * they are left for audit and are tamper-resistant (edit or reorder breaks verification).
 */
async function verifyViaScript(
  toolName,
  params,
  { guardrailScript, passportFile },
) {
  const contextJson = JSON.stringify(params);
  // Unique decision file per invocation — no cache, no reuse. We only read the file we pass here.
  const configDir = dirname(passportFile);
  const decisionsDir = join(configDir, "decisions");
  await mkdir(decisionsDir, { recursive: true });
  const decisionFile = join(
    decisionsDir,
    `${Date.now()}-${Math.random().toString(36).slice(2, 10)}.json`,
  );

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
      // Always read the decision file we passed to this invocation only (script writes to it before exit).
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

/** Generate an idempotency key (10–64 chars, alphanumeric + hyphen/underscore) for API requests that require it. */
function ensureIdempotencyKey(context) {
  if (context && context.idempotency_key) return context;
  const ts = Date.now().toString(36);
  const r = Math.random().toString(36).slice(2, 10);
  const key = `idem_${ts}_${r}`.slice(0, 64);
  return { ...context, idempotency_key: key };
}

/**
 * Verify action via APort API
 * When agentId is set (hosted passport), API fetches passport from registry; no passport file.
 */
async function verifyViaAPI(
  policyName,
  params,
  { apiUrl, apiKey, passportFile, agentId },
) {
  try {
    const context = ensureIdempotencyKey(params);

    const url = `${apiUrl}/api/verify/policy/${policyName}`;
    const headers = {
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

    const data = await response.json();
    return data.decision || data;
  } catch (error) {
    throw new Error(`API verification failed: ${error.message}`);
  }
}

/**
 * Expand ~ to home directory
 */
function expandPath(path) {
  if (path.startsWith("~/")) {
    return join(homedir(), path.slice(2));
  }
  return path;
}

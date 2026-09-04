/**
 * CrewAI guardrail: before-tool-call check (sync) and decorator.
 * Feature parity with Python crewai_adapter (aport_guardrail_before_tool_call, register_aport_guardrail, with_aport_guardrail).
 * Reuses a module-level Evaluator to avoid creating one per tool call.
 */

import {
  Evaluator,
  findConfigPath,
  loadConfig,
  toolToPackId,
} from "@aporthq/aport-agent-guardrails-core";

export interface BeforeToolCallContext {
  tool_name: string;
  tool_input: unknown;
}

let _crewaiEvaluator: Evaluator | null = null;
let _crewaiEnforcementMode: "enforce" | "warn" | null = null;

function getCrewaiEvaluator(): Evaluator {
  if (!_crewaiEvaluator) {
    _crewaiEvaluator = new Evaluator(findConfigPath("crewai"), "crewai");
  }
  return _crewaiEvaluator;
}

function getCrewaiEnforcementMode(): "enforce" | "warn" {
  if (_crewaiEnforcementMode) return _crewaiEnforcementMode;
  const configPath = findConfigPath("crewai");
  const config = configPath ? loadConfig(configPath) : {};
  const raw =
    (config.enforcement_mode as string | undefined) ??
    (config.enforcementMode as string | undefined) ??
    process.env.APORT_ENFORCEMENT_MODE ??
    process.env.APORT_ENFORCEMENT;
  const normalized = String(raw || "enforce").toLowerCase().replace(/_/g, "-");
  _crewaiEnforcementMode = ["warn", "report-only", "audit-only", "observe", "observation"].includes(normalized)
    ? "warn"
    : "enforce";
  return _crewaiEnforcementMode;
}

function sanitizeDisplayText(value: unknown): string {
  return String(value ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
    .replace(/(?:apk|aprt)_[A-Za-z0-9_-]+/g, "[REDACTED_APORT_KEY]")
    .replace(/github_pat_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
    .replace(/gh[pousr]_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
    .replace(/xox[baprs]-[A-Za-z0-9-]+/g, "[REDACTED_SLACK_TOKEN]")
    .replace(/AKIA[0-9A-Z]{16}/g, "[REDACTED_AWS_KEY]")
    .replace(/(Authorization:?\s*Bearer|Bearer)\s+[A-Za-z0-9._~+/-]+=*/gi, "$1 [REDACTED]")
    .replace(/(password|passwd|pwd|token|secret|api[_-]?key)=\S+/gi, "$1=[REDACTED]")
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[REDACTED_PRIVATE_KEY]")
    .slice(0, 240);
}

/**
 * Build tool context for the evaluator (same shape as Python build_tool_context).
 */
function buildToolContext(
  toolName: string,
  toolInput: unknown
): Record<string, unknown> {
  const params =
    typeof toolInput === "object" && toolInput !== null
      ? (toolInput as Record<string, unknown>)
      : {};
  const inputStr =
    typeof toolInput === "object"
      ? JSON.stringify(toolInput)
      : String(toolInput);
  return { tool: toolName, input: inputStr, ...params };
}

/**
 * Before-tool-call guardrail: run APort verification synchronously.
 * Return false to block the tool call, null to allow (matches Python hook return).
 * Use from your CrewAI flow or before_tool_call hook when available.
 */
export function beforeToolCall(context: BeforeToolCallContext): false | null {
  const evaluator = getCrewaiEvaluator();
  const toolCtx = buildToolContext(context.tool_name, context.tool_input);
  const packId = toolToPackId(context.tool_name);
  const decision = evaluator.verifySync({}, { capability: packId }, toolCtx);
  if (!decision.allow) {
    const msg = sanitizeDisplayText(decision.reasons?.[0]?.message ?? "APort policy denied");
    const code = sanitizeDisplayText(decision.reasons?.[0]?.code ?? "oap.denied");
    if (getCrewaiEnforcementMode() === "warn") {
      console.warn(`[APort] warning: policy would have denied ${context.tool_name}. Reason: ${code}.`);
      return null;
    }
    console.warn(`[APort] denied ${context.tool_name}. Reason: ${code}. ${msg}`);
    return false;
  }
  return null;
}

/**
 * Register the APort before_tool_call hook globally.
 * No-op in Node (CrewAI Node SDK does not expose global hook registration); call beforeToolCall in your flow.
 */
export function registerAPortGuardrail(): void {
  // No-op: in Python we register with crewai.hooks; in Node the user wires beforeToolCall themselves.
}

/**
 * Run a function with APort guardrail semantics (parity with Python @with_aport_guardrail).
 * Registers the hook then runs fn. In Node, registration is a no-op; fn() is executed.
 */
export function withAPortGuardrail<T>(fn: () => T): T {
  registerAPortGuardrail();
  return fn();
}

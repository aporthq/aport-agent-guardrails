/**
 * LangChain callback handler: intercept tool start, call core evaluator, throw on deny.
 * Aligns with Python APortCallback (on_tool_start → evaluator.verify → GuardrailViolation).
 */

import { BaseCallbackHandler } from "@langchain/core/callbacks/base";
import type { Serialized } from "@langchain/core/load/serializable";
import { Evaluator, findConfigPath, loadConfig, toolToPackId } from "@aporthq/aport-agent-guardrails-core";

/** Thrown when the guardrail denies a tool call (policy deny). */
export class GuardrailViolationError extends Error {
  readonly reasons?: Array<{ code?: string; message?: string }>;

  constructor(
    message: string,
    reasons?: Array<{ code?: string; message?: string }>
  ) {
    super(message);
    this.name = "GuardrailViolationError";
    this.reasons = reasons;
  }
}

export interface APortGuardrailCallbackOptions {
  /** Optional path to config YAML (default: auto-detect from ~/.aport/langchain/). */
  configPath?: string | null;
  /** Optional framework key for config lookup (default: "langchain"). */
  framework?: string;
  /** enforce blocks denied tools; warn records/logs decisions and lets LangChain continue. */
  enforcementMode?: "enforce" | "warn";
}

/**
 * Callback handler that runs APort policy verification before each tool runs.
 * Register with LangChain/LangGraph so tool execution is blocked when policy denies.
 */
export class APortGuardrailCallback extends BaseCallbackHandler {
  name = "aport_guardrail";

  private evaluator: Evaluator;
  private enforcementMode: "enforce" | "warn";

  constructor(options: APortGuardrailCallbackOptions | string | null = {}) {
    super();
    const configPath =
      typeof options === "string" ? options : options?.configPath ?? null;
    const framework =
      typeof options === "object" && options && "framework" in options
        ? options.framework ?? "langchain"
        : "langchain";
    this.evaluator = new Evaluator(configPath, framework);
    this.enforcementMode = resolveEnforcementMode(
      typeof options === "object" && options ? options.enforcementMode : undefined,
      configPath,
      framework
    );
  }

  async handleToolStart(
    tool: Serialized,
    input: string,
    _runId: string,
    _parentRunId?: string,
    _tags?: string[],
    _metadata?: Record<string, unknown>,
    _runName?: string,
    _toolCallId?: string
  ): Promise<void> {
    const t = tool as unknown as { name?: string; id?: string };
    const toolName =
      t?.name ?? (typeof t?.id === "string" ? t.id : undefined) ?? "unknown";
    const packId = toolToPackId(toolName);
    // Parse input to extract tool-specific parameters (e.g. file_path for read tools)
    let params: Record<string, unknown> = {};
    try {
      const parsed = JSON.parse(input);
      if (typeof parsed === "object" && parsed !== null) params = parsed;
    } catch {
      // input is a plain string, not JSON
    }
    const decision = await this.evaluator.verify(
      {},
      { capability: packId },
      { tool: toolName, input, ...params }
    );
    if (!decision.allow) {
      const msg =
        decision.reasons?.[0]?.message ?? "APort policy denied tool execution";
      const code = decision.reasons?.[0]?.code ?? "oap.denied";
      const safeMessage = sanitizeDisplayText(msg);
      const safeCode = sanitizeDisplayText(code);
      if (this.enforcementMode === "warn") {
        console.warn(`[APort] warning: policy would have denied ${toolName}. Reason: ${safeCode}.`);
        return;
      }
      console.warn(`[APort] denied ${toolName}. Reason: ${safeCode}. ${safeMessage}`);
      throw new GuardrailViolationError(msg, decision.reasons);
    }
  }
}

function resolveEnforcementMode(
  explicit: string | undefined,
  configPath: string | null,
  framework: string
): "enforce" | "warn" {
  const foundConfigPath = configPath || findConfigPath(framework);
  const config = foundConfigPath ? loadConfig(foundConfigPath) : {};
  const raw =
    explicit ??
    (config.enforcement_mode as string | undefined) ??
    (config.enforcementMode as string | undefined) ??
    process.env.APORT_ENFORCEMENT_MODE ??
    process.env.APORT_ENFORCEMENT;
  const normalized = String(raw || "enforce").toLowerCase().replace(/_/g, "-");
  return ["warn", "report-only", "audit-only", "observe", "observation"].includes(normalized)
    ? "warn"
    : "enforce";
}

function sanitizeDisplayText(value: unknown): string {
  return String(value ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
    .replace(/apk_[A-Za-z0-9_-]+/g, "[REDACTED_APORT_KEY]")
    .replace(/github_pat_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
    .replace(/gh[pousr]_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
    .replace(/xox[baprs]-[A-Za-z0-9-]+/g, "[REDACTED_SLACK_TOKEN]")
    .replace(/AKIA[0-9A-Z]{16}/g, "[REDACTED_AWS_KEY]")
    .replace(/(Authorization:?\s*Bearer|Bearer)\s+[A-Za-z0-9._~+/-]+=*/gi, "$1 [REDACTED]")
    .replace(/(password|passwd|pwd|token|secret|api[_-]?key)=\S+/gi, "$1=[REDACTED]")
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[REDACTED_PRIVATE_KEY]")
    .slice(0, 240);
}

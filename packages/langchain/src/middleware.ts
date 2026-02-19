/**
 * LangChain callback handler: intercept tool start, call core evaluator, throw on deny.
 * Aligns with Python APortCallback (on_tool_start → evaluator.verify → GuardrailViolation).
 */

import { BaseCallbackHandler } from '@langchain/core/callbacks/base';
import type { Serialized } from '@langchain/core/load/serializable';
import { Evaluator, toolToPackId } from '@aporthq/aport-agent-guardrails-core';

/** Thrown when the guardrail denies a tool call (policy deny). */
export class GuardrailViolationError extends Error {
  readonly reasons?: Array<{ code?: string; message?: string }>;

  constructor(message: string, reasons?: Array<{ code?: string; message?: string }>) {
    super(message);
    this.name = 'GuardrailViolationError';
    this.reasons = reasons;
  }
}

export interface APortGuardrailCallbackOptions {
  /** Optional path to config YAML (default: auto-detect from ~/.aport/langchain/). */
  configPath?: string | null;
  /** Optional framework key for config lookup (default: "langchain"). */
  framework?: string;
}

/**
 * Callback handler that runs APort policy verification before each tool runs.
 * Register with LangChain/LangGraph so tool execution is blocked when policy denies.
 */
export class APortGuardrailCallback extends BaseCallbackHandler {
  name = 'aport_guardrail';

  private evaluator: Evaluator;

  constructor(options: APortGuardrailCallbackOptions | string | null = {}) {
    super();
    const configPath = typeof options === 'string' ? options : options?.configPath ?? null;
    const framework = typeof options === 'object' && options && 'framework' in options ? options.framework : 'langchain';
    this.evaluator = new Evaluator(configPath, framework);
  }

  async handleToolStart(
    tool: Serialized,
    input: string,
    _runId: string,
    _parentRunId?: string,
    _tags?: string[],
    _metadata?: Record<string, unknown>,
    _runName?: string
  ): Promise<void> {
    const t = tool as unknown as { name?: string; id?: string };
    const toolName = t?.name ?? (typeof t?.id === 'string' ? t.id : undefined) ?? 'unknown';
    const packId = toolToPackId(toolName);
    const decision = await this.evaluator.verify(
      {},
      { capability: packId },
      { tool: toolName, input }
    );
    if (!decision.allow) {
      const msg = decision.reasons?.[0]?.message ?? 'APort policy denied tool execution';
      console.warn('[APort] Denied:', toolName, decision.reasons ?? msg);
      throw new GuardrailViolationError(msg, decision.reasons);
    }
  }
}

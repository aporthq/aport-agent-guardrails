/**
 * CrewAI guardrail: before-tool-call check (sync) and decorator.
 * Feature parity with Python crewai_adapter (aport_guardrail_before_tool_call, register_aport_guardrail, with_aport_guardrail).
 * Reuses a module-level Evaluator to avoid creating one per tool call.
 */

import { Evaluator, findConfigPath, toolToPackId } from '@aporthq/aport-agent-guardrails-core';

export interface BeforeToolCallContext {
  tool_name: string;
  tool_input: unknown;
}

let _crewaiEvaluator: Evaluator | null = null;

function getCrewaiEvaluator(): Evaluator {
  if (!_crewaiEvaluator) {
    _crewaiEvaluator = new Evaluator(findConfigPath('crewai'), 'crewai');
  }
  return _crewaiEvaluator;
}

/**
 * Build tool context for the evaluator (same shape as Python build_tool_context).
 */
function buildToolContext(toolName: string, toolInput: unknown): { tool: string; input: string; params: Record<string, unknown> } {
  const params = typeof toolInput === 'object' && toolInput !== null ? (toolInput as Record<string, unknown>) : {};
  const inputStr = typeof toolInput === 'object' ? JSON.stringify(toolInput) : String(toolInput);
  return { tool: toolName, input: inputStr, params };
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
  const decision = evaluator.verifySync(
    {},
    { capability: packId },
    toolCtx
  );
  if (!decision.allow) {
    const msg = decision.reasons?.[0]?.message ?? 'APort policy denied';
    console.warn('[APort] Denied:', context.tool_name, decision.reasons ?? msg);
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

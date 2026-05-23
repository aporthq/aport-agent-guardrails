/**
 * OAPToolProcessor — Mastra processor for OAP (Open Agent Protocol) authorization.
 * 
 * Integrates with Mastra's processor pipeline to provide deterministic
 * tool-call authorization based on YAML policy configuration.
 * 
 * @example
 * ```typescript
 * import { Agent } from '@mastra/core';
 * import { OAPToolProcessor } from '@aporthq/aport-agent-guardrails-mastra';
 * 
 * const agent = new Agent({
 *   processors: [new OAPToolProcessor('./oap-policy.yaml')],
 *   tools: { webSearch, readFile },
 * });
 * ```
 */

import { randomUUID } from 'node:crypto';
import {
  Evaluator,
  findConfigPath,
  toolToPackId,
  type Decision,
  type ToolContext,
} from '@aporthq/aport-agent-guardrails-core';
import { OAPAuthorizationError, type OAPReceipt } from './errors.js';
import type {
  AgentContext,
  OAPToolProcessorConfig,
  PolicyDecision,
} from './types.js';

/**
 * OAPToolProcessor integrates OAP authorization into Mastra's processor pipeline.
 * 
 * This processor sits between tool invocation requests and tool execution,
 * enforcing policy-based authorization before any tool is called.
 */
export class OAPToolProcessor {
  public readonly name = 'oap-tool-processor';
  
  private evaluator: Evaluator | null = null;
  private config: OAPToolProcessorConfig;
  private policyCache: Map<string, PolicyDecision> = new Map();

  /**
   * Create a new OAPToolProcessor.
   * 
   * @param configOrPath - Either a configuration object or a path to the policy YAML file
   */
  constructor(configOrPath: OAPToolProcessorConfig | string) {
    if (typeof configOrPath === 'string') {
      this.config = { policyPath: configOrPath };
    } else {
      this.config = {
        framework: 'mastra',
        failOpenWhenMissing: false,
        ...configOrPath,
      };
    }
  }

  /**
   * Get or create the Evaluator instance.
   */
  private getEvaluator(): Evaluator {
    if (!this.evaluator) {
      const configPath = this.config.policyPath || findConfigPath(this.config.framework || 'mastra');
      this.evaluator = new Evaluator(configPath, this.config.framework || 'mastra');
    }
    return this.evaluator;
  }

  /**
   * Build tool context for the evaluator.
   */
  private buildToolContext(toolName: string, args: unknown): ToolContext {
    const params =
      typeof args === 'object' && args !== null
        ? (args as Record<string, unknown>)
        : {};
    const inputStr =
      typeof args === 'object' ? JSON.stringify(args) : String(args);
    return { tool: toolName, input: inputStr, ...params };
  }

  /**
   * Create an OAP receipt for the decision.
   */
  private createReceipt(
    toolName: string,
    decision: Decision,
    context: AgentContext
  ): OAPReceipt {
    return {
      receiptId: randomUUID(),
      tool: toolName,
      agent: context.agentId,
      allowed: decision.allow,
      reason: decision.reasons?.[0]?.message,
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Process the policy decision and handle the result.
   */
  private handleDecision(
    toolName: string,
    decision: Decision,
    context: AgentContext
  ): void {
    const receipt = this.createReceipt(toolName, decision, context);

    // Emit receipt for audit trail
    if (context.emit) {
      context.emit('oap:receipt', receipt);
    }

    // Call custom receipt handler if configured
    if (this.config.onReceipt) {
      this.config.onReceipt(receipt);
    }

    if (!decision.allow) {
      const reason = decision.reasons?.[0]?.message ?? 'OAP policy denied';
      throw new OAPAuthorizationError(
        `Tool "${toolName}" blocked by OAP policy: ${reason}`,
        receipt
      );
    }
  }

  /**
   * beforeToolCall hook — called by Mastra before executing any tool.
   * 
   * This is the main integration point. It:
   * 1. Looks up the tool's policy pack
   * 2. Evaluates the tool call against the policy
   * 3. Either allows the call or throws OAPAuthorizationError
   * 
   * @param toolName - Name of the tool being called
   * @param args - Arguments passed to the tool
   * @param context - Mastra agent context
   * @throws OAPAuthorizationError if the tool call is denied
   */
  public async beforeToolCall(
    toolName: string,
    args: unknown,
    context: AgentContext
  ): Promise<void> {
    const evaluator = this.getEvaluator();
    const toolCtx = this.buildToolContext(toolName, args);
    const packId = toolToPackId(toolName);

    // Run OAP verification
    const decision = evaluator.verifySync({}, { capability: packId }, toolCtx);

    // Handle the decision (throws if denied)
    this.handleDecision(toolName, decision, context);
  }

  /**
   * afterToolCall hook — called by Mastra after tool execution.
   * 
   * Currently a no-op but available for future audit logging of successful calls.
   */
  public async afterToolCall(
    _toolName: string,
    _args: unknown,
    _result: unknown,
    _context: AgentContext
  ): Promise<void> {
    // No-op: successful calls are already logged via oap:receipt event
  }

  /**
   * Clear the policy cache.
   * Useful for testing or when policies are updated dynamically.
   */
  public clearCache(): void {
    this.policyCache.clear();
  }

  /**
   * Get the current configuration.
   */
  public getConfig(): Readonly<OAPToolProcessorConfig> {
    return { ...this.config };
  }
}
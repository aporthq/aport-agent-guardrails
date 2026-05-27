/**
 * OAPToolProcessor — Mastra processor for OAP (Open Agent Protocol) authorization.
 * 
 * Integrates with Mastra's processor pipeline to provide deterministic
 * tool-call authorization based on YAML policy configuration.
 * 
 * This processor implements Mastra's Processor interface with processInput
 * and processOutput hooks for proper integration.
 * 
 * @example
 * ```typescript
 * import { Agent } from '@mastra/core';
 * import { OAPToolProcessor } from '@aporthq/aport-agent-guardrails-mastra';
 * 
 * const processor = new OAPToolProcessor('./oap-policy.yaml');
 * 
 * const agent = new Agent({
 *   inputProcessors: [processor],
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
   * 
   * Honors the failOpenWhenMissing config by setting the environment variable
   * before evaluator initialization if needed.
   */
  private getEvaluator(): Evaluator {
    if (!this.evaluator) {
      // Set fail-open env var before creating evaluator to honor the config option
      if (this.config.failOpenWhenMissing !== undefined) {
        process.env.APORT_FAIL_OPEN_WHEN_MISSING_CONFIG = this.config.failOpenWhenMissing ? '1' : '0';
      }
      const configPath = this.config.policyPath || findConfigPath(this.config.framework || 'mastra');
      this.evaluator = new Evaluator(configPath, this.config.framework || 'mastra');
    }
    return this.evaluator;
  }

  /**
   * Build tool context for the evaluator.
   * 
   * SECURITY: Params are nested under `params` key to prevent argument spoofing.
   * Tool arguments cannot overwrite trusted `tool` and `input` values.
   */
  private buildToolContext(toolName: string, args: unknown): ToolContext {
    const params =
      typeof args === 'object' && args !== null
        ? (args as Record<string, unknown>)
        : {};
    const inputStr =
      typeof args === 'object' ? JSON.stringify(args) : String(args);
    // Nest params to prevent spoofing - tool args cannot overwrite trusted values
    return { tool: toolName, input: inputStr, params };
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
   * processInput — Mastra processor hook called before tool execution.
   * 
   * This is the main integration point for Mastra's processor pipeline. It:
   * 1. Extracts tool name and arguments from the input
   * 2. Evaluates the tool call against the OAP policy
   * 3. Either allows the call or throws OAPAuthorizationError
   * 
   * @param input - The tool call input containing tool name and arguments
   * @param context - Mastra agent context
   * @returns The input (unchanged if allowed)
   * @throws OAPAuthorizationError if the tool call is denied
   */
  public async processInput(
    input: { toolName: string; args: unknown },
    context: AgentContext
  ): Promise<{ toolName: string; args: unknown }> {
    const { toolName, args } = input;
    const evaluator = this.getEvaluator();
    const toolCtx = this.buildToolContext(toolName, args);
    const packId = toolToPackId(toolName);

    // Load and apply policy from policyPath if it contains tool allow/deny rules
    const policy = await this.loadPolicyPack(toolName, packId);

    // Run OAP verification
    const decision = evaluator.verifySync({}, policy, toolCtx);

    // Handle the decision (throws if denied)
    this.handleDecision(toolName, decision, context);

    return input;
  }

  /**
   * processOutput — Mastra processor hook called after tool execution.
   * 
   * Currently a no-op but available for future audit logging of successful calls.
   * 
   * @param output - The tool execution result
   * @param context - Mastra agent context
   * @returns The output (unchanged)
   */
  public async processOutput(
    output: unknown,
    _context: AgentContext
  ): Promise<unknown> {
    // No-op: successful calls are already logged via oap:receipt event
    return output;
  }

  /**
   * Load policy pack for the tool, including tool allow/deny rules from policy file.
   * 
   * This reads the YAML policy file at policyPath to extract tool-specific
   * allow/deny configurations and passes them to the evaluator.
   */
  private async loadPolicyPack(
    toolName: string,
    packId: string
  ): Promise<{ capability: string; id?: string; tools?: { allowed?: string[]; denied?: string[] } }> {
    // Start with capability-based pack ID
    const policy: { capability: string; id?: string; tools?: { allowed?: string[]; denied?: string[] } } = {
      capability: packId,
    };

    // If policyPath is configured, try to load tool allow/deny rules from it
    if (this.config.policyPath) {
      try {
        const fs = await import('node:fs');
        const yaml = await import('yaml');
        
        if (fs.existsSync(this.config.policyPath)) {
          const content = fs.readFileSync(this.config.policyPath, 'utf8');
          const parsed = yaml.parse(content) as {
            tools?: {
              allowed?: Array<{ name: string } | string>;
              denied?: Array<{ name: string } | string>;
            };
          };

          if (parsed.tools) {
            // Extract allowed tool names
            const allowed = (parsed.tools.allowed || [])
              .map((t) => (typeof t === 'string' ? t : t.name))
              .filter(Boolean);

            // Extract denied tool names
            const denied = (parsed.tools.denied || [])
              .map((t) => (typeof t === 'string' ? t : t.name))
              .filter(Boolean);

            if (allowed.length > 0 || denied.length > 0) {
              policy.tools = { allowed, denied };
            }
          }
        }
      } catch {
        // Best-effort: if policy file can't be read, fall back to capability-only
      }
    }

    return policy;
  }

  /**
   * @deprecated Use processInput instead. Kept for backward compatibility.
   */
  public async beforeToolCall(
    toolName: string,
    args: unknown,
    context: AgentContext
  ): Promise<void> {
    await this.processInput({ toolName, args }, context);
  }

  /**
   * @deprecated Use processOutput instead. Kept for backward compatibility.
   */
  public async afterToolCall(
    _toolName: string,
    _args: unknown,
    result: unknown,
    context: AgentContext
  ): Promise<void> {
    await this.processOutput(result, context);
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
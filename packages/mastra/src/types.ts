/**
 * Type definitions for OAP Mastra integration.
 */

import type { OAPReceipt } from './errors.js';

/**
 * Mastra Agent Context passed to processors.
 * Based on Mastra's AgentContext interface.
 */
export interface AgentContext {
  agentId: string;
  agentName?: string;
  runId?: string;
  threadId?: string;
  resourceId?: string;
  userId?: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  memory?: Record<string, any>;
  
  /**
   * Emit an event to the agent's event bus.
   */
  emit: (eventName: string, payload: unknown) => void;
  
  /**
   * Get a value from the context store.
   */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  get: <T = any>(key: string) => T | undefined;
  
  /**
   * Set a value in the context store.
   */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  set: <T = any>(key: string, value: T) => void;
}

/**
 * Configuration options for OAPToolProcessor.
 */
export interface OAPToolProcessorConfig {
  /**
   * Path to the OAP policy YAML file.
   */
  policyPath: string;
  
  /**
   * Framework identifier for the evaluator.
   * @default "mastra"
   */
  framework?: string;
  
  /**
   * Whether to fail open (allow) when policy/config is missing.
   * @default false
   */
  failOpenWhenMissing?: boolean;
  
  /**
   * Custom receipt emitter function.
   */
  onReceipt?: (receipt: OAPReceipt) => void;
}

/**
 * Tool call parameters passed to beforeToolCall.
 */
export interface ToolCallParams {
  toolName: string;
  args: unknown;
  context: AgentContext;
}

/**
 * Policy decision result.
 */
export interface PolicyDecision {
  allowed: boolean;
  reason?: string;
  code?: string;
}

/**
 * Mastra BaseProcessor interface (subset we need).
 * The actual Mastra BaseProcessor has more methods, but we only need these.
 */
export interface MastraBaseProcessor {
  name: string;
  beforeToolCall?: (toolName: string, args: unknown, context: AgentContext) => Promise<void> | void;
  afterToolCall?: (toolName: string, args: unknown, result: unknown, context: AgentContext) => Promise<void> | void;
}
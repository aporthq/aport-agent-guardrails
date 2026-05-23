/**
 * @aporthq/aport-agent-guardrails-mastra
 * 
 * OAP (Open Agent Protocol) guardrails for Mastra agents.
 * 
 * Provides deterministic tool-call authorization via the OAPToolProcessor,
 * which integrates with Mastra's processor pipeline.
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

// Main processor
export { OAPToolProcessor } from './oap-tool-processor.js';

// Error classes
export {
  OAPAuthorizationError,
  OAPConfigurationError,
  OAPPolicyError,
  type OAPReceipt,
} from './errors.js';

// Types
export type {
  AgentContext,
  OAPToolProcessorConfig,
  ToolCallParams,
  PolicyDecision,
  MastraBaseProcessor,
} from './types.js';
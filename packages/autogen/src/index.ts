/**
 * @aporthq/aport-agent-guardrails-autogen
 * Pre-action authorization for AutoGen-compatible agents.
 */

export {
  APortGuardedTool,
  guardFunction,
  GuardrailViolationError,
} from './middleware.js';
export type { AutoGenTool, APortGuardedToolOptions } from './middleware.js';

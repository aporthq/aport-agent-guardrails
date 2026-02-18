/**
 * @aporthq/aport-agent-guardrails-crewai
 * Exports CrewAI guardrail: beforeToolCall (sync), registerAPortGuardrail, withAPortGuardrail.
 */

export {
  beforeToolCall,
  registerAPortGuardrail,
  withAPortGuardrail,
  type BeforeToolCallContext,
} from './middleware.js';

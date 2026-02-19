/**
 * @aporthq/aport-agent-guardrails-n8n
 * Exports n8n custom node (APort Verify node).
 */

import { Evaluator } from '@aporthq/aport-agent-guardrails-core';

export { Evaluator };

// TODO: Export n8n node descriptor when n8n SDK is added
export const nodeDescription = {
  name: 'APort Guardrail',
  description: 'Verify tool/action with APort before continuing',
};

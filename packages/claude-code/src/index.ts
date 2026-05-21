/**
 * @aporthq/aport-agent-guardrails-claude-code
 * Claude Code: re-exports Evaluator and helpers for hook path.
 * Runtime integration is via the bash hook installed by:
 *   npx @aporthq/aport-agent-guardrails claude-code
 */

import path from 'node:path';
import os from 'node:os';
import { Evaluator, toolToPackId } from '@aporthq/aport-agent-guardrails-core';

export { Evaluator, toolToPackId };
export {
  CLAUDE_CODE_READ_TOOLS,
  CLAUDE_CODE_TO_GUARDRAIL_TOOL,
  type ClaudeCodeGuardrailToolId,
} from './claudeCodeTools.js';

/**
 * Default path to the APort Claude Code hook script.
 * The installer writes the absolute repo/package path into ~/.claude/settings.json.
 * This helper returns the env override or the path relative to this package's bin/.
 */
export function getHookPath(): string {
  if (process.env.APORT_CLAUDE_CODE_HOOK_SCRIPT) {
    return process.env.APORT_CLAUDE_CODE_HOOK_SCRIPT;
  }
  // Resolve from this package's location (packages/claude-code/src -> ../../bin)
  const pkgBin = path.resolve(__dirname, '..', '..', '..', 'bin', 'aport-claude-code-hook.sh');
  try {
    if (require('fs').existsSync(pkgBin)) return pkgBin;
  } catch { /* ignore */ }
  // Fallback: common install location
  return path.join(os.homedir(), '.claude', 'aport-claude-code-hook.sh');
}

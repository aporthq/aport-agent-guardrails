/**
 * @aporthq/aport-agent-guardrails-cursor
 * Cursor IDE: re-exports Evaluator and helpers for hook path.
 * Runtime integration is via the bash hook installed by: npx @aporthq/aport-agent-guardrails cursor
 */

import path from 'node:path';
import os from 'node:os';
import { Evaluator } from '@aporthq/aport-agent-guardrails-core';

export { Evaluator };

/** Default path to the APort Cursor hook script. CLI installer may write a different path to ~/.cursor/hooks.json. */
export function getHookPath(): string {
  return (
    process.env.APORT_CURSOR_HOOK_SCRIPT ??
    path.join(os.homedir(), '.cursor', 'aport-cursor-hook.sh')
  );
}

/** Reserved for future VS Code extension; no-op when using bash hook from CLI. */
export function activate(): void {}

/** Reserved for future VS Code extension. */
export function deactivate(): void {}

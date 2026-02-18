/**
 * Placeholder CLI entry; real dispatch is bash: bin/agent-guardrails.
 * This module is reserved for future programmatic use (e.g. from Node runner).
 */

export async function runCli(args: string[]): Promise<void> {
  const framework = args[0] ?? 'openclaw';
  console.log(`APort Agent Guardrails — framework: ${framework}`);
}

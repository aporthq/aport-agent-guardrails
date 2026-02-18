/**
 * Tool name → OAP policy pack ID. Single source: tool-pack-mapping.json.
 * Used by evaluator and exported for adapters (LangChain, CrewAI) so they pass the correct capability.
 */

import path from 'node:path';
import { readFileSync } from 'node:fs';

interface MappingRule {
  prefixes?: string[];
  substrings?: string[];
  pack: string;
}

declare const __dirname: string;

const data: { default: string; rules: MappingRule[] } = JSON.parse(
  readFileSync(path.join(__dirname, 'tool-pack-mapping.json'), 'utf8')
);

/**
 * Map a tool name to the OAP policy pack ID. Single source of truth from tool-pack-mapping.json.
 */
export function toolToPackId(toolName: string): string {
  const t = (toolName ?? '').trim().toLowerCase();
  for (const rule of data.rules) {
    if (rule.prefixes?.some((pre) => t.startsWith(pre))) return rule.pack;
    if (rule.substrings?.some((sub) => t.includes(sub))) return rule.pack;
  }
  return data.default;
}

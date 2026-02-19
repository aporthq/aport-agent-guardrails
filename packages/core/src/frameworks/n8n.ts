/**
 * n8n adapter: custom node integration.
 * Reserved for programmatic use; CLI dispatch is bin/agent-guardrails (bash).
 */

import type { BaseAdapter } from './base.js';

export const n8nAdapter: BaseAdapter = {
  name: 'n8n',

  async detect() {
    return false;
  },

  async install() {
    // Run bin/frameworks/n8n.sh; install custom node to ~/.n8n/custom/
  },

  async verify() {
    return true;
  },

  async test() {
    return true;
  },
};

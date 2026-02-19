/**
 * OpenClaw adapter: before_tool_call plugin integration.
 * Reserved for programmatic use; CLI dispatch is bin/agent-guardrails (bash).
 */

import type { BaseAdapter } from './base.js';

export const openclawAdapter: BaseAdapter = {
  name: 'openclaw',

  async detect() {
    // Check for ~/.openclaw or OPENCLAW_HOME
    return false;
  },

  async install() {
    // Run bin/frameworks/openclaw.sh
  },

  async verify() {
    return true;
  },

  async test() {
    return true;
  },
};

/**
 * LangChain/LangGraph adapter: AsyncCallbackHandler integration.
 * Reserved for programmatic use; CLI dispatch is bin/agent-guardrails (bash).
 */

import type { BaseAdapter } from './base.js';

export const langchainAdapter: BaseAdapter = {
  name: 'langchain',

  async detect() {
    return false;
  },

  async install() {
    // Run bin/frameworks/langchain.sh
  },

  async verify() {
    return true;
  },

  async test() {
    return true;
  },
};

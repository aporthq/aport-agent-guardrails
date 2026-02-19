/**
 * @aporthq/aport-agent-guardrails-core
 * Main CLI entry point and exports for shared evaluator, passport, config.
 */

export { Evaluator, toolToPackId } from './core/evaluator.js';
export type { Decision, ToolContext, VerifyRequest, VerifyResponse } from './core/evaluator.js';
export { loadPassport, validatePassport } from './core/passport.js';
export type { Passport } from './core/passport.js';
export { loadConfig, writeConfig, findConfigPath } from './core/config.js';
export type { Config } from './core/config.js';
export { BaseAdapter } from './frameworks/base.js';

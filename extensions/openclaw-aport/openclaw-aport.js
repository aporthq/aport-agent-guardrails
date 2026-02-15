/**
 * OpenClaw extension entry point.
 * The loader resolves plugins by extension id, so it expects this file
 * (packageDir/openclaw-aport.js). Re-export the main plugin.
 */
export { default } from './index.js';
export * from './index.js';

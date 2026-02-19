# Changelog - APort OpenClaw Plugin

All notable changes to the APort OpenClaw plugin will be documented in this file.

## [1.1.0] - 2026-02-19

### Changed - OpenClaw 2026.2 Compatibility

**BREAKING CHANGE**: Updated to OpenClaw 2026.2 plugin architecture

- **Plugin structure**: Migrated from function-based to object-based plugin format
- **TypeScript**: Added `index.ts` as primary entry point (replaces function export from `index.js`)
- **Type safety**: Added TypeScript types from `openclaw/plugin-sdk`
- **Entry point**: Updated `package.json` `openclaw.extensions` to point to `"./index.ts"`

### Added

- `index.ts` - New TypeScript plugin entry point with object-based structure
- `tsconfig.json` - TypeScript configuration for the plugin
- `MIGRATION.md` - Comprehensive migration guide for upgrading to 2026.2
- `CHANGELOG.md` - This file
- TypeScript devDependencies: `@types/node`, `typescript`

### Technical Details

**Old Architecture (< 2026.2):**
```javascript
export default function (api) {
  api.on("before_tool_call", async (event, ctx) => { ... });
}
```

**New Architecture (>= 2026.2):**
```typescript
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";

const plugin = {
  id: "openclaw-aport",
  name: "APort Guardrails",
  description: "...",
  configSchema: { /* ... */ },
  register(api: OpenClawPluginApi) {
    api.on("before_tool_call", async (event, ctx) => { ... });
  },
};

export default plugin;
```

### Compatibility

- **Minimum OpenClaw version**: 2026.2.0
- **Backwards compatibility**: Old `index.js` preserved for legacy OpenClaw versions and test compatibility
- **Configuration**: No changes to `config.yaml` format - existing configurations work as-is

### Testing

- ✅ All 21 unit tests passing
- ✅ Integration tests with guardrail script passing
- ✅ Performance benchmarks maintained
- ✅ Tested with OpenClaw 2026.2.19-2

### Migration

If you're upgrading from OpenClaw < 2026.2, you don't need to change anything. The plugin will automatically use the new architecture when installed with OpenClaw 2026.2+.

If you have local modifications to the plugin, see [MIGRATION.md](./MIGRATION.md) for detailed migration instructions.

### References

- [OpenClaw 2026.2 Plugin Documentation](https://docs.openclaw.ai/tools/plugin)
- [OpenClaw GitHub PR #20874](https://github.com/openclaw/openclaw/pull/20874) - Security updates
- [OpenClaw GitHub PR #20846](https://github.com/openclaw/openclaw/pull/20846) - Agent-based access controls

---

## [1.0.0] - 2026-02-18

### Initial Release

- Function-based plugin for OpenClaw < 2026.2
- Local and API mode support
- before_tool_call and after_tool_call hooks
- Tool name to policy mapping
- Decision integrity verification
- Comprehensive test suite

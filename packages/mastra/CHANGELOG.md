# Changelog

All notable changes to this project will be documented in this file.

## 1.0.0 - 2026-05-23

### Added
- Initial release of `@aporthq/aport-agent-guardrails-mastra`
- `OAPToolProcessor` class for Mastra processor pipeline integration
- Policy-based tool authorization with YAML configuration
- Audit receipt emission for all tool calls
- `OAPAuthorizationError` for blocked tool calls with receipt details
- Full TypeScript support with type definitions
- Comprehensive test suite (80%+ coverage)
- Support for custom receipt handlers
- Integration with `@aporthq/aport-agent-guardrails-core`
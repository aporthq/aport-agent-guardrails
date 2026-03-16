---
"@aporthq/openclaw-aport": minor
---

feat(openclaw-aport): add aport_check and aport_passport optional agent tools

Adds two optional, opt-in tools to the OpenClaw plugin:
- `aport_check`: lets the agent query whether a tool call is authorized before executing it
- `aport_passport`: lets the agent inspect or scaffold its APort passport

Both tools are registered with `optional: true` and require explicit opt-in via `agents.list[].tools.allow`.
All logic reuses existing helpers (mapToolToPolicy, verifyViaScript/API, verifyDecisionIntegrity). No behavioral changes to the existing before_tool_call hook.

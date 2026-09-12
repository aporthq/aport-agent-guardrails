# APort Agent Guardrails — Documentation

**Public documentation** (for users integrating APort Repository Guard and runtime guardrails):

| Doc | Purpose |
|-----|---------|
| [GITHUB_PROTECTION.md](GITHUB_PROTECTION.md) | GitHub Actions report/enforce setup for repository provenance, merge/push evidence, and related local release-policy checks |
| [QUICKSTART.md](QUICKSTART.md) | GitHub-first setup, runtime hook setup, and hosted/local passport options |
| [**HOSTED_PASSPORT_SETUP.md**](HOSTED_PASSPORT_SETUP.md) | **Use passport from aport.io** — create hosted during setup or pass an existing `agent_id` |
| [OAP Decisions vs Harness Enforcement](https://github.com/aporthq/agent-passport/blob/main/docs/DECISION-VS-ENFORCEMENT.md) | Canonical model for signed OAP allow/deny decisions versus local warn/report-only enforcement disposition |
| [ENTERPRISE_DEVICE_DEPLOYMENT.md](ENTERPRISE_DEVICE_DEPLOYMENT.md) | IT-managed deploy, enforce, and uninstall scripts |
| [QUICKSTART_OPENCLAW_PLUGIN.md](QUICKSTART_OPENCLAW_PLUGIN.md) | OpenClaw plugin setup for OpenClaw-specific deployments |
| [OPENCLAW_LOCAL_INTEGRATION.md](OPENCLAW_LOCAL_INTEGRATION.md) | Full OpenClaw setup: API, passport, policies, Python example |
| [OPENCLAW_TOOLS_AND_POLICIES.md](OPENCLAW_TOOLS_AND_POLICIES.md) | exec, allowed_commands, unmapped tools, passport limits |
| [TOOL_POLICY_MAPPING.md](TOOL_POLICY_MAPPING.md) | How tool names map to policy packs |
| [IMPLEMENTING_YOUR_OWN_EVALUATOR.md](IMPLEMENTING_YOUR_OWN_EVALUATOR.md) | Build your own evaluator from the OAP spec |
| [OPENCLAW_COMPATIBILITY.md](OPENCLAW_COMPATIBILITY.md) | OpenClaw version alignment, paths, OPENCLAW_HOME |
| [AGENTS.md.example](AGENTS.md.example) | Example AGENTS.md section for pre-action authorization |
| [REPO_LAYOUT.md](REPO_LAYOUT.md) | What `bin/`, `src/`, `extensions/`, `external/` do |

**Support status and maintainer docs**:

| Doc | Purpose |
|-----|---------|
| [RELEASE.md](RELEASE.md) | Versioning, changelog, tagging, and publish process |
| [FRAMEWORK_ROADMAP.md](FRAMEWORK_ROADMAP.md) | Shipped repository/runtime surfaces, beta command-hook harnesses, and gated integrations |
| [SECURITY_MODEL.md](SECURITY_MODEL.md) | Threat model, fail-closed behavior, and deployment guidance |

Public setup docs should lead with GitHub Repository Guard, then shipped runtime
targets: Cursor, Claude Code for the `claude` CLI, OpenClaw, LangChain, CrewAI,
DeerFlow, and n8n setup. Codex, Gemini CLI, and Goose are beta command-hook
harnesses backed by shared adapter tests and setup tests. opencode remains gated
until an installed-version plugin smoke test verifies the current plugin API.

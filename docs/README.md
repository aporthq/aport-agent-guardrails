# APort Agent Guardrails — Documentation

**Public documentation** (for users integrating OpenClaw + APort guardrails):

| Doc | Purpose |
|-----|---------|
| [QUICKSTART_OPENCLAW_PLUGIN.md](QUICKSTART_OPENCLAW_PLUGIN.md) | **OpenClaw plugin** — one-command setup, deterministic enforcement (RECOMMENDED) |
| [**HOSTED_PASSPORT_SETUP.md**](HOSTED_PASSPORT_SETUP.md) | **Use passport from aport.io** — create hosted during setup or pass `npx @aporthq/aport-agent-guardrails openclaw <agent_id>` |
| [QUICKSTART.md](QUICKSTART.md) | Interactive setup and step-by-step hosted/local passport options |
| [ENTERPRISE_DEVICE_DEPLOYMENT.md](ENTERPRISE_DEVICE_DEPLOYMENT.md) | IT-managed deploy, enforce, and uninstall scripts |
| [GITHUB_PROTECTION.md](GITHUB_PROTECTION.md) | GitHub Actions report/enforce setup for repository provenance, merge/push evidence, and related local release-policy checks |
| [OPENCLAW_LOCAL_INTEGRATION.md](OPENCLAW_LOCAL_INTEGRATION.md) | Full OpenClaw setup: API, passport, policies, Python example |
| [OPENCLAW_TOOLS_AND_POLICIES.md](OPENCLAW_TOOLS_AND_POLICIES.md) | exec, allowed_commands, unmapped tools, passport limits |
| [TOOL_POLICY_MAPPING.md](TOOL_POLICY_MAPPING.md) | How tool names map to policy packs |
| [IMPLEMENTING_YOUR_OWN_EVALUATOR.md](IMPLEMENTING_YOUR_OWN_EVALUATOR.md) | Build your own evaluator from the OAP spec |
| [OPENCLAW_COMPATIBILITY.md](OPENCLAW_COMPATIBILITY.md) | OpenClaw version alignment, paths, OPENCLAW_HOME |
| [AGENTS.md.example](AGENTS.md.example) | Example AGENTS.md section for pre-action authorization |
| [REPO_LAYOUT.md](REPO_LAYOUT.md) | What `bin/`, `src/`, `extensions/`, `external/` do |

**Maintainer docs**:

| Doc | Purpose |
|-----|---------|
| [RELEASE.md](RELEASE.md) | Versioning, changelog, tagging, and publish process |
| [DEPLOYMENT_READINESS.md](DEPLOYMENT_READINESS.md) | Release-readiness checklist and supported framework status |
| [SECURITY_MODEL.md](SECURITY_MODEL.md) | Threat model, fail-closed behavior, and deployment guidance |

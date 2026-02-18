# DRY and FRAMEWORK_SUPPORT_PLAN alignment checklist

This doc confirms the codebase follows the structure, conventions, and best practices in [FRAMEWORK_SUPPORT_PLAN.md](FRAMEWORK_SUPPORT_PLAN.md). Use it to keep the repo DRY and aligned with the plan.

## Repository structure (plan vs actual)

| Plan | Actual | Status |
|------|--------|--------|
| `bin/lib/` common, passport, config, allowlist | `bin/lib/common.sh`, `passport.sh`, `config.sh`, `allowlist.sh`, `detect.sh`, `templates/` | ✅ |
| `bin/frameworks/<name>.sh` thin scripts | `bin/frameworks/openclaw.sh`, `langchain.sh`, `crewai.sh`, `n8n.sh` (<50 lines each) | ✅ |
| Shared wizard: `bin/aport-create-passport.sh` | All frameworks use it via `lib/passport.sh` or delegate (OpenClaw) | ✅ |
| Config locations: OpenClaw `~/.openclaw`, LangChain `~/.aport/langchain/`, etc. | `lib/config.sh` `get_config_dir()` + `write_config_template()` | ✅ |
| `integrations/<framework>/` | `integrations/openclaw/`, `langchain/`, `crewai/`, `n8n/` (README, examples) | ✅ |
| `python/aport_guardrails/` core | `core/evaluator.py`, `config.py`, `passport.py`, `exceptions.py` | ✅ |
| `python/.../langchain` adapter | `langchain_adapter/` + `aport_guardrails_langchain` import package | ✅ |

## Shared vs divergent (DRY)

- **Shared (no duplication):** Passport wizard, policy packs (`external/aport-policies`), tool→pack_id mapping (bash, Node, Python share same semantics), config read/write, kill switch = passport status only (no file).
- **Divergent (per-framework only):** Integration hook (callback vs decorator vs plugin), config file location, CLI entry (`aport-langchain` vs `bin/openclaw`).

## Verification: two passport options, two policy options

Per agent-passport API `POST /api/verify/policy/{pack_id}` (see agent-passport `functions/api/verify/policy/[pack_id].ts`):

- **Passport:** (1) **agent_id** in context → API fetches passport (cloud). (2) **passport** in body → API uses it directly (local via API).
- **Policy:** (1) **pack_id** in URL path → policy from registry. (2) **policy** in body when `pack_id=IN_BODY` → policy from request.

| Layer | agent_id | passport in body | pack_id in path | policy in body (API) |
|-------|----------|------------------|-----------------|----------------------|
| **Node (src/evaluator.js)** | ✅ context.agent_id | ✅ body.passport | ✅ URL | ✅ options.policyInBody → IN_BODY + body.policy |
| **Bash (aport-guardrail-api.sh)** | ✅ APORT_AGENT_ID | ✅ via Node (passport loaded and passed) | ✅ via Node | N/A (uses Node) |
| **Python (core/evaluator.py)** | ✅ context.agent_id | ✅ body.passport (from passport_path) | ✅ URL _tool_to_pack_id | ✅ full OAP pack → IN_BODY + body.policy |

**Note:** Local verification with policy-in-body (e.g. passing a policy object to the bash guardrail or a future local evaluator) is planned and not implemented yet.

## Test coverage (Story C and general)

- **Unit:** `aport_guardrails/frameworks/langchain.py` (LangChainAdapter) — pytest in core or adapter; callback deny → `GuardrailViolation` covered in `langchain_adapter/tests/test_callback.py`.
- **Integration:** Example under `examples/langchain/` with temp config/passport; ALLOW/DENY flows in `run_with_guardrail.py`.
- **E2E:** GH Action installs package, `aport-langchain setup --ci`, runs sample agent or example, expects ALLOW log (see `.github/workflows/e2e-langchain.yml` or equivalent).

## Doc references

- [FRAMEWORK_SUPPORT_PLAN.md](FRAMEWORK_SUPPORT_PLAN.md) — architecture, shared vs divergent, per-framework patterns.
- [USER_STORIES.md](USER_STORIES.md) — acceptance criteria and implementation status.
- [ADDING_A_FRAMEWORK.md](../ADDING_A_FRAMEWORK.md) — how to add a framework without copying passport/config logic.

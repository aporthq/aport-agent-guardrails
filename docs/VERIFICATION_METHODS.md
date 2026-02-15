# Verification methods: Local vs API

This doc compares how policy is evaluated in **local mode** (bash guardrail script) vs **API mode** (APort cloud or self-hosted agent-passport using the generic evaluator). It also summarizes the four ways you can run the guardrail (standalone bash, standalone API, plugin + local, plugin + API).

---

## Summary: when to use which

| Method | Best for | Robustness | Network |
|--------|----------|------------|---------|
| **API (default)** | Production, full OAP parity, new policy rules without code changes | Full: JSON Schema, assurance, regions, taxonomy, MCP, evaluation_rules from policy JSON, signed decisions | Yes (api.aport.io or self-hosted) |
| **Local (bash)** | Privacy, offline, air-gapped, or no API key | Core checks only; same policy packs but hand-coded per policy; new rules need script updates | No |

**Recommendation:** Use **API mode** (default in `./bin/openclaw`) for full policy fidelity and future policy packs. Use **local mode** when you must avoid the network or run fully offline.

---

## Four ways to run the guardrail

| # | Method | How | Typical use |
|---|--------|-----|-------------|
| 1 | **Standalone bash** | `OPENCLAW_PASSPORT_FILE=... ./bin/aport-guardrail-bash.sh <tool> '<context_json>'` | Scripts, CI, manual checks |
| 2 | **Standalone API** | `./bin/aport-guardrail-api.sh <tool> '<context_json>'` with `APORT_API_URL` | Same as above, but evaluation in cloud |
| 3 | **Plugin + local** | OpenClaw `before_tool_call` → plugin spawns `aport-guardrail-bash.sh` | OpenClaw with no API / offline |
| 4 | **Plugin + API** | OpenClaw `before_tool_call` → plugin calls APort API | OpenClaw with full OAP (default) |

All four produce OAP v1.0–shaped decisions (allow, reasons, policy_id, etc.). The **evaluation logic** differs between local (bash) and API (generic evaluator).

---

## Local evaluator (bash) vs API generic evaluator

The **APort API** (and self-hosted agent-passport) uses a **generic evaluator** that loads policy JSON and runs a full OAP pipeline. The **local guardrail** in this repo (`bin/aport-guardrail-bash.sh`) implements a **subset** of that pipeline in bash + jq.

### What the API generic evaluator does (full OAP)

1. **Passport status** — suspended/revoked → deny  
2. **Required context (JSON Schema)** — validates `required_context` from policy JSON against the request  
3. **Capabilities** — passport must have required capabilities (e.g. `system.command.execute`, `messaging.send`)  
4. **Assurance level** — `min_assurance` from policy (e.g. L2) vs passport assurance  
5. **Limits** — uses `evaluation_rules` from policy JSON (expression + custom_validator); supports capability-scoped limits, DB-backed rate limits, idempotency  
6. **Regions** — `requires_regions` from policy  
7. **Taxonomy** — policy-defined taxonomy checks  
8. **MCP** — MCP allowlist/validation when defined  
9. **Custom evaluation rules** — runs each `evaluation_rules` entry (expression or custom_validator) from the policy pack  
10. **Signed decisions** — Ed25519 signatures, optional chained audit  

Reference: [agent-passport generic-evaluator](https://github.com/aporthq/agent-passport) (`functions/utils/policy/generic-evaluator.ts`).

### What the local (bash) evaluator does

1. **Kill switch** — if `OPENCLAW_KILL_SWITCH` file exists → deny  
2. **Passport load** — read passport JSON; invalid or missing → deny  
3. **Passport status** — `status !== "active"` → deny  
4. **Spec version** — must be `oap/1.0`  
5. **Tool → policy mapping** — fixed `case` (e.g. `exec.*`/`system.*` → `system.command.execute.v1`, `messaging.*` → `messaging.message.send.v1`)  
6. **Capabilities** — passport must list required capability (with alias e.g. `messaging.message.send` → `messaging.send`)  
7. **Policy-specific limits (hand-coded):**  
   - **code.repository.merge** — PR size (`max_pr_size_kb`), `allowed_repos`, `allowed_base_branches`  
   - **system.command.execute** — `allowed_commands` (prefix or `*`), `blocked_patterns`  
   - **messaging.message.send** — `allowed_recipients` (optional)  
8. **Decision output** — OAP-shaped decision (allow, reasons, policy_id, passport_digest, content_hash, chain)  
9. **No** JSON Schema validation of context  
10. **No** assurance, regions, taxonomy, MCP, or generic `evaluation_rules` from policy JSON  

So: **local is robust enough for the core policies** (exec, messaging, repo merge) for allowlist/blocklist and the limits implemented in bash. It is **not** a full reimplementation of the generic evaluator. New policy packs or new rules in existing packs (e.g. `working_directory`, `environment_variables` in system.command.execute) require either API mode or updates to the bash script.

---

## Feature comparison (local vs API)

| Feature | Local (bash) | API (generic evaluator) |
|---------|--------------|--------------------------|
| Passport status check | ✅ | ✅ |
| Kill switch | ✅ (file-based) | N/A (handled by registry/suspend) |
| Capability check | ✅ (with messaging alias) | ✅ |
| JSON Schema required_context | ❌ | ✅ |
| Assurance level | ❌ | ✅ |
| Regions | ❌ | ✅ |
| Taxonomy | ❌ | ✅ |
| MCP validation | ❌ | ✅ |
| Limits from policy JSON | Hand-coded subset only | ✅ Full (evaluation_rules, custom_validators) |
| system.command.execute | allowed_commands, blocked_patterns | + execution_time, working_directory, env (if in policy) |
| code.repository.merge | PR size, allowed_repos, allowed_base_branches | Same + path_allowlist, require_review if in policy |
| messaging.message.send | allowed_recipients | + rate limits (msgs_per_min/day), channel allowlist (if in policy) |
| New policy packs | Requires bash changes | Load from policy JSON |
| Signed decisions | Local-unsigned only | Ed25519 signed (cloud) |
| Rate limits / idempotency | ❌ | ✅ (when API uses DB) |

---

## Conclusion

- **Local (bash):** Useful for privacy, offline, and the core use cases (exec allowlist/blocklist, messaging recipient, repo/PR limits). For full OAP parity and future policy packs, use **API mode**.
- **API (default):** Recommended for production and when you want the same behavior as [APort in Goose](https://raw.githubusercontent.com/aporthq/.github/refs/heads/main/profile/APORT_GOOSE_ARCHITECTURE.md) and the full generic evaluator (JSON Schema, assurance, regions, evaluation_rules, signed decisions).

The installer (`./bin/openclaw`) defaults to **API mode**; choose local only when you need to run without the network.

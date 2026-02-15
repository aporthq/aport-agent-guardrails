# Local overrides

Policy and passport files here **override or extend** the submodule content (`external/aport-policies`).

**Used by:**

- **bin/aport-guardrail-bash.sh** — loads policies from `local-overrides/policies/` when a pack is not found under `external/aport-policies` (e.g. a custom or not-yet-upstream policy).
- **src/evaluator.js** — same fallback when loading policy JSON for API evaluation.

**Layout:**

- **policies/** — Policy pack JSON files, e.g. `system.command.execute.v1.json`. Naming: `<policy_id>.json` (the script looks for `local-overrides/policies/<policy_base>.v*.json` or evaluator uses `<policyId>.json`).
- **templates/** — Optional passport templates (e.g. `passport.local.json`) for local use; not loaded automatically by the guardrail scripts.

See [docs/REPO_LAYOUT.md](../docs/REPO_LAYOUT.md) and [docs/TOOL_POLICY_MAPPING.md](../docs/TOOL_POLICY_MAPPING.md).

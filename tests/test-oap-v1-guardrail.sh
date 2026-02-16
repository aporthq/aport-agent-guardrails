#!/bin/bash
# OAP v1 guardrail tests: policy loading, allow/deny paths, decision shape (reasons[], passport_digest, etc.)

source "$(dirname "$0")/setup.sh"

# Run guardrail from repo root so script finds external/aport-policies
cd "$REPO_ROOT"

echo "  Guardrail: allow path (valid context)..."
rm -f "$OPENCLAW_DECISION_FILE"
if ! "$GUARDRAIL" git.create_pr '{"repo":"aporthq/test","files_changed":10}'; then
    echo "FAIL: guardrail should ALLOW valid context" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "decision.allow"
assert_json_has "$OPENCLAW_DECISION_FILE" "reasons" "OAP v1 decision must have reasons[]"
assert_json_has "$OPENCLAW_DECISION_FILE" "decision_id" "decision must have decision_id"
assert_json_has "$OPENCLAW_DECISION_FILE" "policy_id" "decision must have policy_id"
assert_json_has "$OPENCLAW_DECISION_FILE" "passport_digest" "decision must have passport_digest"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.allowed" "reasons[0].code"
assert_json_eq "$OPENCLAW_DECISION_FILE" "policy_id" "code.repository.merge.v1" "policy_id"

echo "  Guardrail: deny path (repo not in allowlist)..."
# Fixture has allowed_repos ["*"] so use a different passport with restricted repos
echo '{"passport_id":"x","kind":"template","spec_version":"oap/1.0","owner_id":"u","owner_type":"user","assurance_level":"L2","status":"active","capabilities":[{"id":"repo.pr.create"},{"id":"repo.merge"}],"limits":{"code.repository.merge":{"max_pr_size_kb":500,"allowed_repos":["aporthq/only"],"allowed_base_branches":["*"]}},"regions":["US"],"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","version":"1.0.0"}' > "$OPENCLAW_PASSPORT_FILE"
if "$GUARDRAIL" git.create_pr '{"repo":"other/repo","files_changed":5}' 2>/dev/null; then
    echo "FAIL: guardrail should DENY repo not in allowlist" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "decision.allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.repo_not_allowed" "reasons[0].code"

# Restore fixture for next tests
cp "$FIXTURE_PASSPORT" "$OPENCLAW_PASSPORT_FILE"

echo "  Guardrail: deny path (PR size exceeds limit)..."
if "$GUARDRAIL" git.create_pr '{"repo":"aporthq/test","files_changed":600}' 2>/dev/null; then
    echo "FAIL: guardrail should DENY when files_changed > max_pr_size_kb" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "decision.allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.limit_exceeded" "reasons[0].code"

echo "  Guardrail: decision has OAP v1 required fields..."
"$GUARDRAIL" git.push '{"repo":"a/b","files_changed":1}' || true
assert_json_has "$OPENCLAW_DECISION_FILE" "issued_at" "decision.issued_at"
assert_json_has "$OPENCLAW_DECISION_FILE" "expires_at" "decision.expires_at"
assert_json_has "$OPENCLAW_DECISION_FILE" "signature" "decision.signature"
assert_json_has "$OPENCLAW_DECISION_FILE" "kid" "decision.kid"
# reasons must be array with at least one object with code
code=$(jq -r '.reasons[0].code' "$OPENCLAW_DECISION_FILE")
if [ "$code" = "null" ] || [ -z "$code" ]; then
    echo "FAIL: decision.reasons[0].code must be set" >&2
    exit 1
fi

echo "  Guardrail: system.command.execute (allow)..."
"$GUARDRAIL" exec.run '{"command":"npm install"}' || true
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "true" "system command allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "policy_id" "system.command.execute.v1" "policy_id"

echo "  Guardrail: system.command.execute (deny blocked pattern)..."
# Use a command that matches allowlist (npm) but contains blocked pattern so we get oap.blocked_pattern
if "$GUARDRAIL" exec.run '{"command":"npm run build && rm -rf /tmp/x"}' 2>/dev/null; then
    echo "FAIL: guardrail should DENY blocked pattern" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "decision.allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.blocked_pattern" "reasons[0].code"

echo "  Guardrail: unknown tool denied..."
if "$GUARDRAIL" unknown.tool '{}' 2>/dev/null; then
    echo "FAIL: unknown tool should be denied" >&2
    exit 1
fi
assert_json_eq "$OPENCLAW_DECISION_FILE" "allow" "false" "decision.allow"
assert_json_eq "$OPENCLAW_DECISION_FILE" "reasons[0].code" "oap.unknown_capability" "reasons[0].code"

exit 0

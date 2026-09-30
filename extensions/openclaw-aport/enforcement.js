export const HARD_FAILURE_CODES = new Set([
  "oap.api_error",
  "oap.command_chain_unsupported",
  "oap.command_injection_detected",
  "oap.context_not_serializable",
  "oap.context_too_large",
  "oap.context_too_nested",
  "oap.decision_integrity_failed",
  "oap.decision_state_unavailable",
  "oap.domain_mismatch",
  "oap.evaluation_error",
  "oap.evaluator_crash",
  "oap.evaluator_error",
  "oap.evaluator_failed",
  "oap.glob_read_unsupported",
  "oap.input_too_large",
  "oap.interactive_browser_unsupported",
  "oap.invalid_context",
  "oap.invalid_file_path",
  "oap.invalid_json",
  "oap.invalid_limit",
  "oap.invalid_passport_path",
  "oap.invalid_session_count",
  "oap.invalid_session_duration",
  "oap.invalid_session_type",
  "oap.invalid_tool_arguments",
  "oap.invalid_tool_name",
  "oap.invalid_url",
  "oap.malformed_context",
  "oap.metadata_enumeration_unsupported",
  "oap.misconfigured",
  "oap.missing_command",
  "oap.missing_dependency",
  "oap.missing_file_path",
  "oap.missing_required_context",
  "oap.missing_tool_name",
  "oap.multi_path_read_unsupported",
  "oap.multi_path_write_unsupported",
  "oap.passport_invalid",
  "oap.passport_not_found",
  "oap.passport_suspended",
  "oap.passport_version_mismatch",
  "oap.path_resolution_error",
  "oap.path_traversal_attempt",
  "oap.policy_error",
  "oap.rate_state_unavailable",
  "oap.recursive_search_unsupported",
  "oap.session_state_unavailable",
  "oap.unrepresentable_tool",
  "oap.unknown_hook_event",
  "oap.unknown_tool",
  "oap.unsupported_limit",
]);

export function normalizeEnforcementMode(value) {
  const normalized = String(value || "enforce").toLowerCase().replace(/_/g, "-");
  if (["observe", "observation"].includes(normalized)) return "observe";
  if (["warn", "report-only", "audit-only"].includes(normalized)) return "warn";
  return "enforce";
}

export function primaryReasonCode(decision) {
  return String(decision?.reasons?.[0]?.code || "oap.denied");
}

export function isHardFailureDecision(decision) {
  return HARD_FAILURE_CODES.has(primaryReasonCode(decision));
}

export function shouldAllowDeniedDecision(enforcement, decision) {
  if (Boolean(decision?.allow)) return true;
  if (enforcement === "observe") return true;
  if (enforcement === "warn") return !isHardFailureDecision(decision);
  return false;
}

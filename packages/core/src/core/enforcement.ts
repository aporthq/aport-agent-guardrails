export type RuntimeEnforcementMode = "enforce" | "warn" | "observe";

export interface EnforcementDecision {
  allow?: boolean;
  reasons?: Array<{ code?: string; message?: string }>;
}

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
  "oap.invalid_agent_id",
  "oap.invalid_context",
  "oap.invalid_file_path",
  "oap.invalid_json",
  "oap.invalid_limit",
  "oap.invalid_mcp_server",
  "oap.invalid_passport_path",
  "oap.invalid_policy_pack_id",
  "oap.invalid_provider",
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
  "oap.path_invalid_characters",
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

export function normalizeEnforcementMode(value: unknown): RuntimeEnforcementMode {
  const raw = String(value || "enforce").trim().toLowerCase().replace(/_/g, "-");
  if (["warn", "report-only", "audit-only"].includes(raw)) return "warn";
  if (["observe", "observation"].includes(raw)) return "observe";
  return "enforce";
}

export function primaryReasonCode(decision: EnforcementDecision): string {
  const first = decision.reasons?.[0];
  return String(first?.code || "oap.denied");
}

export function isHardFailureDecision(decision: EnforcementDecision): boolean {
  return HARD_FAILURE_CODES.has(primaryReasonCode(decision));
}

export function shouldAllowDeniedDecision(
  enforcementMode: unknown,
  decision: EnforcementDecision,
): boolean {
  if (Boolean(decision.allow)) return true;
  const mode = normalizeEnforcementMode(enforcementMode);
  if (mode === "observe") return true;
  if (mode === "warn") return !isHardFailureDecision(decision);
  return false;
}

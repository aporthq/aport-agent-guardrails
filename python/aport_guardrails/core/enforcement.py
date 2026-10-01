"""Shared enforcement-mode semantics for Python adapters."""

from __future__ import annotations

from typing import Any


HARD_FAILURE_CODES = {
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
    "oap.missing_tool_name",
    "oap.missing_required_context",
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
}


def normalize_enforcement_mode(value: Any) -> str:
    """Normalize public aliases to enforce, warn, or observe."""
    raw = str(value or "enforce").strip().lower().replace("_", "-")
    if raw in {"warn", "report-only", "audit-only"}:
        return "warn"
    if raw in {"observe", "observation"}:
        return "observe"
    return "enforce"


def primary_reason_code(decision: dict[str, Any]) -> str:
    reasons = decision.get("reasons") if isinstance(decision, dict) else None
    if isinstance(reasons, list) and reasons:
        first = reasons[0]
        if isinstance(first, dict):
            return str(first.get("code") or "oap.denied")
    return "oap.denied"


def is_hard_failure_decision(decision: dict[str, Any]) -> bool:
    return primary_reason_code(decision) in HARD_FAILURE_CODES


def should_allow_denied_decision(enforcement_mode: Any, decision: dict[str, Any]) -> bool:
    """Return true when the runtime should allow a false APort decision."""
    if bool(decision.get("allow", False)):
        return True
    mode = normalize_enforcement_mode(enforcement_mode)
    if mode == "observe":
        return True
    if mode == "warn":
        return not is_hard_failure_decision(decision)
    return False

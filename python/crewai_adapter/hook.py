"""CrewAI before_tool_call hook: verify tool execution with APort."""

import os
import re
from typing import Any

from aport_guardrails.core import Evaluator, build_tool_context, tool_to_pack_id
from aport_guardrails.core.config import find_config_path, load_config

_crewai_evaluator: Evaluator | None = None
_crewai_enforcement_mode: str | None = None


def _get_crewai_evaluator() -> Evaluator:
    global _crewai_evaluator
    if _crewai_evaluator is None:
        _crewai_evaluator = Evaluator(config_path=find_config_path("crewai"), framework="crewai")
    return _crewai_evaluator


def _normalize_enforcement_mode(value: Any) -> str:
    normalized = str(value or "enforce").lower().replace("_", "-")
    return "warn" if normalized in {"warn", "report-only", "audit-only", "observe", "observation"} else "enforce"


def _get_enforcement_mode() -> str:
    global _crewai_enforcement_mode
    if _crewai_enforcement_mode is not None:
        return _crewai_enforcement_mode
    config_path = find_config_path("crewai")
    config = load_config(config_path) if config_path else {}
    _crewai_enforcement_mode = _normalize_enforcement_mode(
        config.get("enforcement_mode")
        or config.get("enforcementMode")
        or os.environ.get("APORT_ENFORCEMENT_MODE")
        or os.environ.get("APORT_ENFORCEMENT")
    )
    return _crewai_enforcement_mode


def _sanitize_display(value: Any) -> str:
    text = str(value or "")
    text = re.sub(r"[\r\n\t]+", " ", text)
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    text = re.sub(r"(?:apk|aprt)_[A-Za-z0-9_-]+", "[REDACTED_APORT_KEY]", text)
    text = re.sub(r"github_pat_[A-Za-z0-9_]+", "[REDACTED_GITHUB_TOKEN]", text)
    text = re.sub(r"gh[pousr]_[A-Za-z0-9_]+", "[REDACTED_GITHUB_TOKEN]", text)
    text = re.sub(r"xox[baprs]-[A-Za-z0-9-]+", "[REDACTED_SLACK_TOKEN]", text)
    text = re.sub(r"AKIA[0-9A-Z]{16}", "[REDACTED_AWS_KEY]", text)
    text = re.sub(r"(Authorization:?\s*Bearer|Bearer)\s+[A-Za-z0-9._~+/-]+=*", r"\1 [REDACTED]", text, flags=re.IGNORECASE)
    text = re.sub(r"(password|passwd|pwd|token|secret|api[_-]?key)=\S+", r"\1=[REDACTED]", text, flags=re.IGNORECASE)
    return text[:240]


def aport_guardrail_before_tool_call(context: Any) -> bool | None:
    """
    CrewAI before_tool_call hook: run APort verification; return False to block, None to allow.
    Use with @before_tool_call or register_before_tool_call_hook().
    Config is loaded from ~/.aport/crewai/config.yaml or .aport/config.yaml (see find_config_path).
    """
    evaluator = _get_crewai_evaluator()
    tool_ctx = build_tool_context(context.tool_name, context.tool_input)
    pack_id = tool_to_pack_id(context.tool_name)
    decision = evaluator.verify_sync(
        {},
        {"capability": pack_id},
        tool_ctx,
    )
    if not decision.get("allow", False):
        if _get_enforcement_mode() == "warn":
            reasons = decision.get("reasons") or [{}]
            code = _sanitize_display(reasons[0].get("code", "oap.denied") if reasons else "oap.denied")
            tool_name = _sanitize_display(context.tool_name)
            print(f"[APort] warning: policy would have denied {tool_name}. Reason: {code}.")
            return None
        return False
    return None


def register_aport_guardrail() -> None:
    """Register the APort before_tool_call hook globally. Call once before running crews."""
    from crewai.hooks import register_before_tool_call_hook

    register_before_tool_call_hook(aport_guardrail_before_tool_call)

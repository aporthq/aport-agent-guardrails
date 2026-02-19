"""
CrewAI before_tool_call hook: verify tool execution with APort; return False to block.
Uses Evaluator.verify_sync so the hook stays synchronous (CrewAI hooks are sync).
Reuses a module-level Evaluator to avoid creating one per tool call.
"""

from typing import Any

from aport_guardrails.core import Evaluator, build_tool_context, tool_to_pack_id
from aport_guardrails.core.config import find_config_path

_crewai_evaluator: Evaluator | None = None


def _get_crewai_evaluator() -> Evaluator:
    global _crewai_evaluator
    if _crewai_evaluator is None:
        _crewai_evaluator = Evaluator(config_path=find_config_path("crewai"), framework="crewai")
    return _crewai_evaluator


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
        return False
    return None


def register_aport_guardrail() -> None:
    """Register the APort before_tool_call hook globally. Call once before running crews."""
    from crewai.hooks import register_before_tool_call_hook

    register_before_tool_call_hook(aport_guardrail_before_tool_call)

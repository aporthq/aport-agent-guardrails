"""
aport-guardrails-crewai — CrewAI before_tool_call hook for APort guardrails.
Import as: from aport_guardrails_crewai import aport_guardrail_before_tool_call, register_aport_guardrail, with_aport_guardrail
"""

from crewai_adapter.hook import aport_guardrail_before_tool_call, register_aport_guardrail
from crewai_adapter.decorator import with_aport_guardrail

__all__ = ["aport_guardrail_before_tool_call", "register_aport_guardrail", "with_aport_guardrail"]

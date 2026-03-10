"""
aport-guardrails-autogen — AutoGen hook and decorator for APort agent guardrails.

Supports:
- AutoGen 0.4.x (autogen-agentchat / autogen-core):
    APortGuardedTool: wraps any BaseTool with APort pre-action verification.
    with_aport_guardrail: decorator for async/sync tool functions.
- AutoGen 0.2.x (pyautogen):
    wrap_agent_tools: patches agent.function_map with APort sync verification.

Import as:
    from aport_guardrails_autogen import APortGuardedTool, wrap_agent_tools, with_aport_guardrail
"""

# After `pip install aport-agent-guardrails-autogen`, both `autogen_adapter` and
# `aport_guardrails_autogen` are installed as top-level packages from the same
# distribution (see pyproject.toml [tool.setuptools.packages.find]).
# Absolute imports from autogen_adapter work in both editable-dev and installed modes.

from autogen_adapter.hook import APortGuardedTool, wrap_agent_tools, _get_evaluator
from autogen_adapter.decorator import with_aport_guardrail
from aport_guardrails.core import GuardrailViolation

__all__ = [
    "APortGuardedTool",
    "wrap_agent_tools",
    "with_aport_guardrail",
    "_get_evaluator",
    "GuardrailViolation",
]

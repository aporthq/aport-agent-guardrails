"""
Shared helpers for building evaluator context from framework-specific tool call data.
Used by LangChain (tool_name + input str) and CrewAI (tool_name + tool_input dict).
"""

import json
from typing import Any


def build_tool_context(tool_name: str, input_: str | dict[str, Any]) -> dict[str, Any]:
    """
    Build evaluator ToolContext from tool name and input (string or dict).
    Used by all framework adapters so context shape is consistent.
    """
    if isinstance(input_, dict):
        input_str = json.dumps(input_)
        params = input_
    else:
        input_str = str(input_)
        params = {}
    return {"tool": tool_name, "input": input_str, "params": params}

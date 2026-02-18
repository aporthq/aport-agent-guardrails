"""Unit tests for aport_guardrails.core.context (build_tool_context)."""

import json

import pytest

from aport_guardrails.core.context import build_tool_context


class TestBuildToolContext:
    """build_tool_context produces consistent ToolContext for LangChain and CrewAI."""

    def test_dict_input(self) -> None:
        tool_input = {"command": "ls", "cwd": "/tmp"}
        ctx = build_tool_context("exec.run", tool_input)
        assert ctx["tool"] == "exec.run"
        assert ctx["params"] == tool_input
        assert json.loads(ctx["input"]) == tool_input

    def test_str_input(self) -> None:
        ctx = build_tool_context("run_command", '{"command": "ls"}')
        assert ctx["tool"] == "run_command"
        assert ctx["input"] == '{"command": "ls"}'
        assert ctx["params"] == {}

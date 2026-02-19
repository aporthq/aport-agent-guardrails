"""Unit tests for CrewAI aport_guardrail_before_tool_call hook."""

import pytest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from crewai_adapter import hook
from crewai_adapter.hook import aport_guardrail_before_tool_call


def _fake_context(tool_name: str = "run_command", tool_input: dict | None = None) -> SimpleNamespace:
    return SimpleNamespace(tool_name=tool_name, tool_input=tool_input or {"command": "ls"})


class TestAportGuardrailBeforeToolCall:
    """Test aport_guardrail_before_tool_call with mocked Evaluator."""

    @patch("crewai_adapter.hook.Evaluator")
    def test_allow_returns_none(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator returns allow=True, hook returns None (allow execution)."""
        hook._crewai_evaluator = None  # reset cache so mock is used
        mock_evaluator_cls.return_value.verify_sync.return_value = {"allow": True}

        result = aport_guardrail_before_tool_call(_fake_context())

        assert result is None
        mock_evaluator_cls.return_value.verify_sync.assert_called_once()
        call_kw = mock_evaluator_cls.return_value.verify_sync.call_args
        context = call_kw[0][2]
        assert context.get("tool") == "run_command"
        assert "input" in context

    @patch("crewai_adapter.hook.Evaluator")
    def test_deny_returns_false(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator returns allow=False, hook returns False (block execution)."""
        hook._crewai_evaluator = None
        mock_evaluator_cls.return_value.verify_sync.return_value = {
            "allow": False,
            "reasons": [{"code": "oap.command_not_allowed", "message": "Command not in allowlist"}],
        }

        result = aport_guardrail_before_tool_call(_fake_context(tool_input={"command": "rm -rf /"}))

        assert result is False
        mock_evaluator_cls.return_value.verify_sync.assert_called_once()
        call_args = mock_evaluator_cls.return_value.verify_sync.call_args[0]
        assert call_args[2].get("tool") == "run_command"

    @patch("crewai_adapter.hook.Evaluator")
    def test_context_input_serialized(self, mock_evaluator_cls: MagicMock) -> None:
        """Tool input dict is JSON-serialized in context for evaluator."""
        hook._crewai_evaluator = None
        mock_evaluator_cls.return_value.verify_sync.return_value = {"allow": True}
        tool_input = {"command": "ls -la", "cwd": "/tmp"}

        aport_guardrail_before_tool_call(_fake_context(tool_name="exec.run", tool_input=tool_input))

        call_args = mock_evaluator_cls.return_value.verify_sync.call_args[0]
        context = call_args[2]
        assert context["tool"] == "exec.run"
        assert context["params"] == tool_input
        import json
        assert json.loads(context["input"]) == tool_input

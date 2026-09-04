"""Unit tests for LangChain APortCallback — mock evaluator, deny raises GuardrailViolation."""

import pytest
from unittest.mock import AsyncMock

from aport_guardrails_langchain import APortCallback, GuardrailViolation


class TestAPortCallback:
    """Test APortCallback with mocked Evaluator."""

    def test_callback_manager_propagates_denials(self):
        """LangChain callback managers only propagate callback errors when raise_error is true."""
        assert APortCallback.raise_error is True
        assert APortCallback(config_path="/nonexistent").raise_error is True

    @pytest.mark.asyncio
    async def test_allow_does_not_raise(self):
        """When evaluator returns allow=True, on_tool_start does not raise."""
        callback = APortCallback(config_path="/nonexistent")
        callback.evaluator = AsyncMock()
        callback.evaluator.verify = AsyncMock(return_value={"allow": True})

        await callback.on_tool_start("run_command", '{"command": "ls"}')

        callback.evaluator.verify.assert_called_once()
        # verify(passport, policy, context) — positional args (passport, policy, context)
        pos = callback.evaluator.verify.call_args[0]
        context = pos[2]
        assert context.get("tool") == "run_command"

    @pytest.mark.asyncio
    async def test_deny_raises_guardrail_violation(self):
        """When evaluator returns allow=False, on_tool_start raises GuardrailViolation."""
        callback = APortCallback(config_path="/nonexistent")
        callback.evaluator = AsyncMock()
        callback.evaluator.verify = AsyncMock(
            return_value={
                "allow": False,
                "reasons": [{"code": "oap.command_not_allowed", "message": "Command not in allowlist"}],
            }
        )

        with pytest.raises(GuardrailViolation) as exc_info:
            await callback.on_tool_start("run_command", '{"command": "rm -rf /"}')

        assert exc_info.value.code == "oap.command_not_allowed"
        assert "not in allowlist" in str(exc_info.value)
        assert len(exc_info.value.reasons) == 1

    @pytest.mark.asyncio
    async def test_deny_default_reason(self):
        """When reasons empty, GuardrailViolation still has message and code."""
        callback = APortCallback(config_path="/nonexistent")
        callback.evaluator = AsyncMock()
        callback.evaluator.verify = AsyncMock(return_value={"allow": False, "reasons": []})

        with pytest.raises(GuardrailViolation) as exc_info:
            await callback.on_tool_start("run_command", "{}")

        assert "APort denied" in str(exc_info.value)
        assert exc_info.value.code == "oap.denied"

    @pytest.mark.asyncio
    async def test_warn_mode_does_not_raise(self):
        """Explicit warn mode lets LangChain continue while preserving the deny decision."""
        callback = APortCallback(config_path="/nonexistent", enforcement_mode="warn")
        callback.evaluator = AsyncMock()
        callback.evaluator.verify = AsyncMock(
            return_value={
                "allow": False,
                "reasons": [{"code": "oap.command_not_allowed", "message": "Command not in allowlist"}],
            }
        )

        await callback.on_tool_start({"name": "run_command"}, None, inputs={"command": "rm -rf /"})

        callback.evaluator.verify.assert_called_once()
        context = callback.evaluator.verify.call_args[0][2]
        assert context["tool"] == "run_command"
        assert context["params"] == {"command": "rm -rf /"}

    @pytest.mark.asyncio
    async def test_warn_mode_sanitizes_tool_name(self, capsys):
        """Warn logs must not let dynamic tool names forge terminal or CI records."""
        callback = APortCallback(config_path="/nonexistent", enforcement_mode="warn")
        callback.evaluator = AsyncMock()
        callback.evaluator.verify = AsyncMock(
            return_value={
                "allow": False,
                "reasons": [{"code": "oap.command_not_allowed", "message": "Command not in allowlist"}],
            }
        )

        await callback.on_tool_start({"name": "run_command\n::error::fake"}, None, inputs={})

        captured = capsys.readouterr()
        assert "run_command : :error: :fake" in captured.out
        assert "\n::error::fake" not in captured.out

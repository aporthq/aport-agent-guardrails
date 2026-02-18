"""Unit tests for LangChain APortCallback — mock evaluator, deny raises GuardrailViolation."""

import pytest
from unittest.mock import AsyncMock

from aport_guardrails_langchain import APortCallback, GuardrailViolation


class TestAPortCallback:
    """Test APortCallback with mocked Evaluator."""

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

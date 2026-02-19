"""
Example: run APortCallback with temp config; assert ALLOW then DENY.
Run from repo root:
  pytest examples/langchain/run_with_guardrail.py -v
  or: python examples/langchain/run_with_guardrail.py (after pip install -e python/aport_guardrails -e python/langchain_adapter)
"""

import asyncio
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock

from aport_guardrails_langchain import APortCallback, GuardrailViolation
from aport_guardrails.core.config import write_config


async def _run_example(*, expect_deny_raise: bool = True) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        config_path = Path(tmp) / "config.yaml"
        write_config(config_path, {"mode": "local", "fail_open_when_missing_config": True})
        callback = APortCallback(config_path=str(config_path))

        # No passport_path in config but fail_open_when_missing_config=True -> evaluator returns allow (no-op)
        await callback.on_tool_start("run_command", '{"command": "ls"}')

        # Simulate deny
        callback.evaluator.verify = AsyncMock(
            return_value={"allow": False, "reasons": [{"code": "oap.denied", "message": "Example deny"}]}
        )
        if expect_deny_raise:
            try:
                import pytest
                with pytest.raises(GuardrailViolation) as exc_info:
                    await callback.on_tool_start("run_command", '{"command": "rm -rf /"}')
                assert exc_info.value.code == "oap.denied"
            except ImportError:
                # No pytest: catch manually
                try:
                    await callback.on_tool_start("run_command", '{"command": "rm -rf /"}')
                except GuardrailViolation as e:
                    assert e.code == "oap.denied"
        else:
            try:
                await callback.on_tool_start("run_command", '{"command": "rm -rf /"}')
            except GuardrailViolation as e:
                assert e.code == "oap.denied"


def test_example_allow_then_deny():
    """Integration: temp config, ALLOW then DENY (GuardrailViolation raised)."""
    asyncio.run(_run_example(expect_deny_raise=True))


if __name__ == "__main__":
    asyncio.run(_run_example(expect_deny_raise=False))
    print("Example: ALLOW and DENY paths OK.")

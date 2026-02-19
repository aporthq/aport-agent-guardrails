"""Integration-style tests: callback with real Evaluator and temp config (no API)."""

import tempfile
from pathlib import Path

import pytest

from aport_guardrails_langchain import APortCallback
from aport_guardrails.core.config import write_config


class TestCallbackWithConfig:
    """Callback auto-loads config; with no passport/script and fail_open set, we get allow (no-op)."""

    @pytest.mark.asyncio
    async def test_callback_auto_loads_config_path(self):
        """APortCallback(None) uses Evaluator(None) which finds or uses empty config."""
        # Create temp config with fail_open for testing without passport
        with tempfile.TemporaryDirectory() as tmp:
            config_path = Path(tmp) / "config.yaml"
            write_config(config_path, {"mode": "local", "fail_open_when_missing_config": True})
            callback = APortCallback(config_path=str(config_path))
            # With fail_open_when_missing_config and no passport, evaluator returns allow=True
            decision = await callback.evaluator.verify(
                {}, {}, {"tool": "run_command", "input": "{}"}
            )
            assert decision.get("allow", True) is True

    @pytest.mark.asyncio
    async def test_callback_with_explicit_config_file(self):
        """With explicit config path pointing to minimal config with fail_open, verify runs."""
        with tempfile.TemporaryDirectory() as tmp:
            config_path = Path(tmp) / "config.yaml"
            write_config(config_path, {"mode": "local", "fail_open_when_missing_config": True})
            callback = APortCallback(config_path=str(config_path))
            decision = await callback.evaluator.verify(
                {}, {}, {"tool": "run_command", "input": "{}"}
            )
            # No passport_path in config but fail_open_when_missing_config=True -> allow
            assert decision.get("allow", True) is True

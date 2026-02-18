"""Integration-style tests: callback with real Evaluator and temp config (no API)."""

import tempfile
from pathlib import Path

import pytest

from aport_guardrails_langchain import APortCallback
from aport_guardrails.core.config import write_config


class TestCallbackWithConfig:
    """Callback auto-loads config; with no passport/script we get allow (no-op)."""

    @pytest.mark.asyncio
    async def test_callback_auto_loads_config_path(self):
        """APortCallback(None) uses Evaluator(None) which finds or uses empty config."""
        callback = APortCallback()  # no config_path
        # With no config file, evaluator returns allow=True (no config)
        decision = await callback.evaluator.verify(
            {}, {}, {"tool": "run_command", "input": "{}"}
        )
        assert decision.get("allow", True) is True

    @pytest.mark.asyncio
    async def test_callback_with_explicit_config_file(self):
        """With explicit config path pointing to empty/minimal config, verify runs."""
        with tempfile.TemporaryDirectory() as tmp:
            config_path = Path(tmp) / "config.yaml"
            write_config(config_path, {"mode": "local"})
            callback = APortCallback(config_path=str(config_path))
            decision = await callback.evaluator.verify(
                {}, {}, {"tool": "run_command", "input": "{}"}
            )
            # No passport_path in config -> allow
            assert decision.get("allow", True) is True

"""
Example: run a minimal CrewAI crew with APort guardrail (allow/deny).
Requires: pip install -e python/aport_guardrails -e python/crewai_adapter crewai
Run from repo root:
  pytest examples/crewai/run_with_guardrail.py -v
  or: python examples/crewai/run_with_guardrail.py (after install)
"""

import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from aport_guardrails.core.config import write_config


def test_guardrail_hook_allow_then_deny() -> None:
    """Integration: register hook with temp config; ALLOW then DENY (hook returns False)."""
    try:
        from crewai.hooks import clear_before_tool_call_hooks
        from crewai_adapter.hook import aport_guardrail_before_tool_call
    except ImportError as e:
        pytest.skip(f"CrewAI not installed: {e}")

    clear_before_tool_call_hooks()
    with tempfile.TemporaryDirectory() as tmp:
        config_path = Path(tmp) / "config.yaml"
        write_config(config_path, {"mode": "local"})

        with patch("crewai_adapter.hook.find_config_path", return_value=config_path):
            with patch("crewai_adapter.hook.Evaluator") as MockEval:
                # First call allow, second deny
                MockEval.return_value.verify_sync.side_effect = [
                    {"allow": True},
                    {"allow": False, "reasons": [{"code": "oap.denied", "message": "Example deny"}]},
                ]

                class Ctx:
                    tool_name = "run_command"
                    tool_input = {"command": "ls"}

                assert aport_guardrail_before_tool_call(Ctx()) is None
                Ctx.tool_input = {"command": "rm -rf /"}
                assert aport_guardrail_before_tool_call(Ctx()) is False

    clear_before_tool_call_hooks()


def test_register_aport_guardrail() -> None:
    """register_aport_guardrail() registers the hook (no error)."""
    try:
        from crewai.hooks import get_before_tool_call_hooks, clear_before_tool_call_hooks
        from crewai_adapter.hook import register_aport_guardrail
    except ImportError as e:
        pytest.skip(f"CrewAI not installed: {e}")

    clear_before_tool_call_hooks()
    before = len(get_before_tool_call_hooks())
    register_aport_guardrail()
    after = len(get_before_tool_call_hooks())
    assert after == before + 1
    clear_before_tool_call_hooks()


if __name__ == "__main__":
    test_guardrail_hook_allow_then_deny()
    test_register_aport_guardrail()
    print("Example: ALLOW and DENY paths OK.")

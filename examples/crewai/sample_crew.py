"""
Integration: minimal CrewAI crew that triggers both ALLOW and DENY via the APort hook.
Uses a real Crew (Agent + Task + Crew) with a custom tool; the hook is registered with
a mocked Evaluator that allows the first tool call and denies the second.
Run from repo root (requires crewai, aport_guardrails, crewai_adapter):
  pytest examples/crewai/sample_crew.py -v
  or: python examples/crewai/sample_crew.py
Optional: set OPENAI_API_KEY (or CREWAI_FULL_INTEGRATION=1) to run the full crew; otherwise
the crew kickoff is skipped and we only assert hook/evaluator behavior.
"""

import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from aport_guardrails.core.config import write_config

# Run full crew (needs LLM) only when explicitly requested or API key is set
_RUN_FULL_CREW = os.environ.get("CREWAI_FULL_INTEGRATION") == "1" or bool(os.environ.get("OPENAI_API_KEY"))


def _make_crew_and_run(allow_then_deny: bool = True) -> list[str]:
    """Build a minimal crew, register guardrail with mock evaluator, run kickoff. Returns decision sequence."""
    try:
        from crewai.hooks import clear_before_tool_call_hooks
        from crewai_adapter.hook import register_aport_guardrail, aport_guardrail_before_tool_call
    except ImportError as e:
        pytest.skip(f"CrewAI not installed: {e}")

    decisions: list[str] = []

    def mock_verify_sync(*args: object, **kwargs: object) -> dict:
        if allow_then_deny and len(decisions) >= 1:
            decisions.append("deny")
            return {"allow": False, "reasons": [{"code": "oap.denied", "message": "Integration deny"}]}
        decisions.append("allow")
        return {"allow": True}

    clear_before_tool_call_hooks()
    with tempfile.TemporaryDirectory() as tmp:
        config_path = Path(tmp) / "config.yaml"
        write_config(config_path, {"mode": "local", "fail_open_when_missing_config": True})

        # Clear any cached evaluator from previous test runs
        import crewai_adapter.hook
        crewai_adapter.hook._crewai_evaluator = None

        with patch("crewai_adapter.hook.find_config_path", return_value=config_path):
            with patch("crewai_adapter.hook.Evaluator") as MockEval:
                MockEval.return_value.verify_sync.side_effect = mock_verify_sync
                register_aport_guardrail()

                if _RUN_FULL_CREW:
                    from crewai import Agent, Crew, Task
                    from crewai.tools import tool

                    @tool("Echo tool for agent guardrail demo")
                    def echo_tool(message: str) -> str:
                        """Echo the message. Used to trigger before_tool_call hook."""
                        return f"Echo: {message}"

                    agent = Agent(
                        role="Runner",
                        goal="Use the echo tool when asked.",
                        backstory="You use tools to echo.",
                        tools=[echo_tool],
                        verbose=False,
                    )
                    task1 = Task(
                        description="Use the echo tool to echo the word 'first'.",
                        expected_output="Echo: first",
                        agent=agent,
                    )
                    task2 = Task(
                        description="Use the echo tool to echo the word 'second'.",
                        expected_output="Echo: second",
                        agent=agent,
                    )
                    crew = Crew(agents=[agent], tasks=[task1, task2], verbose=False)
                    try:
                        crew.kickoff()
                    except Exception:
                        pass  # Second tool call may be blocked and raise
                else:
                    # Without LLM: simulate two tool calls through the hook (no Agent/Crew needed)
                    from types import SimpleNamespace
                    ctx1 = SimpleNamespace(tool_name="echo_tool", tool_input={"message": "first"})
                    ctx2 = SimpleNamespace(tool_name="echo_tool", tool_input={"message": "second"})
                    aport_guardrail_before_tool_call(ctx1)
                    aport_guardrail_before_tool_call(ctx2)

    clear_before_tool_call_hooks()
    return decisions


def test_sample_crew_allow_then_deny() -> None:
    """Integration: crew run triggers ALLOW on first tool call, DENY on second."""
    decisions = _make_crew_and_run(allow_then_deny=True)
    assert "allow" in decisions, "Expected at least one ALLOW from hook"
    assert "deny" in decisions, "Expected at least one DENY from hook"
    assert decisions[0] == "allow"
    assert decisions[1] == "deny"


def test_sample_crew_all_allowed() -> None:
    """Integration: when evaluator allows all, both tool calls succeed."""
    decisions = _make_crew_and_run(allow_then_deny=False)
    assert decisions == ["allow", "allow"]


if __name__ == "__main__":
    test_sample_crew_allow_then_deny()
    test_sample_crew_all_allowed()
    print("Sample crew: ALLOW and DENY paths OK.")

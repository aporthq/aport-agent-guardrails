"""Unit tests for AutoGen APortGuardedTool, wrap_agent_tools, and _utils helpers."""

import json
import pytest
import warnings
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

from autogen_adapter import hook as hook_module
from autogen_adapter.hook import APortGuardedTool, wrap_agent_tools
from autogen_adapter._utils import raise_if_denied


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_mock_tool(name: str = "send_email") -> MagicMock:
    """Return a MagicMock that looks like an AutoGen 0.4.x BaseTool."""
    tool = MagicMock()
    tool.name = name
    tool.description = f"Mock tool: {name}"
    tool.schema = {}
    tool.run_json = AsyncMock(return_value="ok")
    tool.run = AsyncMock(return_value="ok")
    return tool


def _make_mock_agent(function_map: dict | None = None) -> SimpleNamespace:
    """Return a SimpleNamespace that looks like an AutoGen 0.2.x ConversableAgent."""
    return SimpleNamespace(function_map=function_map or {"search": lambda q: f"results for {q}"})


# ---------------------------------------------------------------------------
# _utils.raise_if_denied
# ---------------------------------------------------------------------------


class TestRaiseIfDenied:
    """Tests for the shared raise_if_denied helper."""

    def test_allow_does_not_raise(self) -> None:
        """Decision with allow=True does not raise."""
        raise_if_denied({"allow": True})  # should not raise

    def test_deny_raises_guardrail_violation(self) -> None:
        """Decision with allow=False raises GuardrailViolation with correct code/message."""
        from aport_guardrails.core import GuardrailViolation

        with pytest.raises(GuardrailViolation) as exc_info:
            raise_if_denied(
                {
                    "allow": False,
                    "reasons": [{"code": "oap.blocked", "message": "Blocked by policy"}],
                }
            )
        assert exc_info.value.code == "oap.blocked"
        assert "Blocked by policy" in str(exc_info.value)

    def test_deny_empty_reasons_defaults(self) -> None:
        """Empty reasons list produces default code/message."""
        from aport_guardrails.core import GuardrailViolation

        with pytest.raises(GuardrailViolation) as exc_info:
            raise_if_denied({"allow": False, "reasons": []})

        assert exc_info.value.code == "oap.denied"
        assert "APort denied" in str(exc_info.value)

    def test_deny_missing_allow_field_defaults_to_deny(self) -> None:
        """Missing 'allow' key treated as deny (safe default)."""
        from aport_guardrails.core import GuardrailViolation

        with pytest.raises(GuardrailViolation):
            raise_if_denied({})


# ---------------------------------------------------------------------------
# APortGuardedTool — 0.4.x
# ---------------------------------------------------------------------------


class TestAPortGuardedTool:
    """Tests for APortGuardedTool (AutoGen 0.4.x)."""

    @pytest.mark.asyncio
    @patch("autogen_adapter.hook.Evaluator")
    async def test_allow_run_json(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator returns allow=True, run_json delegates to inner tool."""
        hook_module._autogen_evaluator = None
        inner = _make_mock_tool("send_email")
        mock_evaluator_cls.return_value.verify = AsyncMock(return_value={"allow": True})

        guarded = APortGuardedTool(inner)
        result = await guarded.run_json({"recipient": "test@example.com", "body": "Hello"})

        assert result == "ok"
        inner.run_json.assert_called_once()
        mock_evaluator_cls.return_value.verify.assert_called_once()

    @pytest.mark.asyncio
    @patch("autogen_adapter.hook.Evaluator")
    async def test_deny_run_json_raises(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator returns allow=False, run_json raises GuardrailViolation."""
        from aport_guardrails.core import GuardrailViolation

        hook_module._autogen_evaluator = None
        inner = _make_mock_tool("send_email")
        mock_evaluator_cls.return_value.verify = AsyncMock(
            return_value={
                "allow": False,
                "reasons": [{"code": "oap.tool_not_allowed", "message": "Email sending denied"}],
            }
        )

        guarded = APortGuardedTool(inner)
        with pytest.raises(GuardrailViolation) as exc_info:
            await guarded.run_json({"recipient": "evil@example.com"})

        assert exc_info.value.code == "oap.tool_not_allowed"
        assert "denied" in str(exc_info.value).lower()
        inner.run_json.assert_not_called()

    @pytest.mark.asyncio
    @patch("autogen_adapter.hook.Evaluator")
    async def test_context_includes_tool_name(self, mock_evaluator_cls: MagicMock) -> None:
        """Tool context passed to evaluator includes the tool name."""
        hook_module._autogen_evaluator = None
        inner = _make_mock_tool("read_file")
        mock_evaluator_cls.return_value.verify = AsyncMock(return_value={"allow": True})

        guarded = APortGuardedTool(inner)
        await guarded.run_json({"path": "/tmp/test.txt"})

        call_args = mock_evaluator_cls.return_value.verify.call_args[0]
        context = call_args[2]
        assert context.get("tool") == "read_file"
        assert "input" in context

    def test_name_description_schema_proxied(self) -> None:
        """name, description, schema are forwarded to the inner tool."""
        inner = _make_mock_tool("list_files")
        inner.description = "Lists files in a directory"
        inner.schema = {"type": "object", "properties": {"path": {"type": "string"}}}

        guarded = APortGuardedTool(inner)

        assert guarded.name == "list_files"
        assert guarded.description == "Lists files in a directory"
        assert guarded.schema == inner.schema

    def test_getattr_proxies_unknown_attrs(self) -> None:
        """Unrecognised attributes are proxied to the inner tool."""
        inner = _make_mock_tool()
        inner.custom_metadata = {"version": "1.0"}

        guarded = APortGuardedTool(inner)
        assert guarded.custom_metadata == {"version": "1.0"}

    @pytest.mark.asyncio
    @patch("autogen_adapter.hook.Evaluator")
    async def test_deny_empty_reasons_defaults(self, mock_evaluator_cls: MagicMock) -> None:
        """Empty reasons list produces default code/message in GuardrailViolation."""
        from aport_guardrails.core import GuardrailViolation

        hook_module._autogen_evaluator = None
        inner = _make_mock_tool()
        mock_evaluator_cls.return_value.verify = AsyncMock(
            return_value={"allow": False, "reasons": []}
        )

        guarded = APortGuardedTool(inner)
        with pytest.raises(GuardrailViolation) as exc_info:
            await guarded.run_json({})

        assert "APort denied" in str(exc_info.value)
        assert exc_info.value.code == "oap.denied"

    @pytest.mark.asyncio
    @patch("autogen_adapter.hook.Evaluator")
    async def test_run_json_fallback_to_run_when_no_run_json(self, mock_evaluator_cls: MagicMock) -> None:
        """run_json falls back to inner.run when inner has no run_json method."""
        hook_module._autogen_evaluator = None
        inner = MagicMock()
        inner.name = "no_run_json_tool"
        inner.description = "No run_json"
        inner.schema = {}
        del inner.run_json  # remove run_json from mock
        inner.run = AsyncMock(return_value="fallback_result")
        mock_evaluator_cls.return_value.verify = AsyncMock(return_value={"allow": True})

        guarded = APortGuardedTool(inner)
        result = await guarded.run_json({})
        assert result == "fallback_result"


# ---------------------------------------------------------------------------
# wrap_agent_tools — 0.2.x
# ---------------------------------------------------------------------------


class TestWrapAgentTools:
    """Tests for wrap_agent_tools (AutoGen 0.2.x)."""

    @patch("autogen_adapter.hook.Evaluator")
    def test_allow_executes_function(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator allows, wrapped function executes normally."""
        hook_module._autogen_evaluator = None
        mock_evaluator_cls.return_value.verify_sync.return_value = {"allow": True}

        called_with: list = []

        def search(query: str) -> str:
            called_with.append(query)
            return f"results: {query}"

        agent = _make_mock_agent({"search": search})
        wrap_agent_tools(agent)

        result = agent.function_map["search"](query="python testing")
        assert result == "results: python testing"
        assert called_with == ["python testing"]
        mock_evaluator_cls.return_value.verify_sync.assert_called_once()

    @patch("autogen_adapter.hook.Evaluator")
    def test_deny_raises_guardrail_violation(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator denies, wrapped function raises GuardrailViolation."""
        from aport_guardrails.core import GuardrailViolation

        hook_module._autogen_evaluator = None
        mock_evaluator_cls.return_value.verify_sync.return_value = {
            "allow": False,
            "reasons": [{"code": "oap.blocked", "message": "Tool blocked by policy"}],
        }

        agent = _make_mock_agent({"dangerous_tool": lambda: "danger"})
        wrap_agent_tools(agent)

        with pytest.raises(GuardrailViolation) as exc_info:
            agent.function_map["dangerous_tool"]()

        assert exc_info.value.code == "oap.blocked"

    def test_raises_if_no_function_map(self) -> None:
        """wrap_agent_tools raises AttributeError for agents without function_map."""
        bad_agent = SimpleNamespace()
        with pytest.raises(AttributeError, match="function_map"):
            wrap_agent_tools(bad_agent)

    @patch("autogen_adapter.hook.Evaluator")
    def test_all_tools_wrapped(self, mock_evaluator_cls: MagicMock) -> None:
        """All functions in function_map are wrapped."""
        hook_module._autogen_evaluator = None
        mock_evaluator_cls.return_value.verify_sync.return_value = {"allow": True}

        agent = _make_mock_agent(
            {
                "tool_a": lambda: "a",
                "tool_b": lambda: "b",
                "tool_c": lambda: "c",
            }
        )
        wrap_agent_tools(agent)

        assert set(agent.function_map.keys()) == {"tool_a", "tool_b", "tool_c"}
        for fn in agent.function_map.values():
            assert callable(fn)

    @patch("autogen_adapter.hook.Evaluator")
    def test_context_tool_name_matches_function_name(self, mock_evaluator_cls: MagicMock) -> None:
        """The tool name in the evaluator context matches the function_map key."""
        hook_module._autogen_evaluator = None
        mock_evaluator_cls.return_value.verify_sync.return_value = {"allow": True}

        agent = _make_mock_agent({"run_query": lambda sql: f"rows for {sql}"})
        wrap_agent_tools(agent)
        agent.function_map["run_query"](sql="SELECT 1")

        call_args = mock_evaluator_cls.return_value.verify_sync.call_args[0]
        context = call_args[2]
        assert context.get("tool") == "run_query"

    @pytest.mark.asyncio
    @patch("autogen_adapter.hook.Evaluator")
    async def test_async_function_in_function_map_warns_and_works(
        self, mock_evaluator_cls: MagicMock
    ) -> None:
        """Async function in function_map triggers a warning and uses await evaluator.verify()."""
        hook_module._autogen_evaluator = None
        mock_evaluator_cls.return_value.verify = AsyncMock(return_value={"allow": True})
        mock_evaluator_cls.return_value.verify_sync = MagicMock(return_value={"allow": True})

        async def async_search(query: str) -> str:
            return f"async results: {query}"

        agent = _make_mock_agent({"async_search": async_search})

        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            wrap_agent_tools(agent)
            assert any("async" in str(warning.message).lower() for warning in w)

        result = await agent.function_map["async_search"](query="test")
        assert result == "async results: test"

        # Async wrapper uses await evaluator.verify() (not blocking verify_sync)
        mock_evaluator_cls.return_value.verify.assert_called_once()
        mock_evaluator_cls.return_value.verify_sync.assert_not_called()


# ---------------------------------------------------------------------------
# _make_evaluator — config_path semantics
# ---------------------------------------------------------------------------


class TestMakeEvaluator:
    """Tests for _make_evaluator singleton vs dedicated evaluator logic."""

    @patch("autogen_adapter.hook.Evaluator")
    def test_none_config_path_uses_singleton(self, mock_evaluator_cls: MagicMock) -> None:
        """_make_evaluator(None) returns and reuses the module-level singleton."""
        hook_module._autogen_evaluator = None
        from autogen_adapter.hook import _make_evaluator

        e1 = _make_evaluator(None)
        e2 = _make_evaluator(None)
        assert e1 is e2
        assert mock_evaluator_cls.call_count == 1  # created once

    @patch("autogen_adapter.hook.Evaluator")
    def test_explicit_config_path_creates_dedicated(self, mock_evaluator_cls: MagicMock) -> None:
        """_make_evaluator('/path') creates a dedicated Evaluator, not the singleton."""
        hook_module._autogen_evaluator = None
        from autogen_adapter.hook import _make_evaluator

        e1 = _make_evaluator("/custom/config.yaml")
        e2 = _make_evaluator(None)
        assert mock_evaluator_cls.call_count == 2  # two separate instances
        assert hook_module._autogen_evaluator is e2  # singleton is the None-path one

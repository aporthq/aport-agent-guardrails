"""Unit tests for with_aport_guardrail decorator (async and sync functions)."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from autogen_adapter import decorator as decorator_module
from autogen_adapter.decorator import with_aport_guardrail


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _reset_evaluator(mock_cls: MagicMock) -> None:
    """Clear the per-decorator evaluator cache so the mock is used on next call."""
    # The decorator holds evaluator in a closure list; we patch Evaluator at
    # module level so the next function call creates a fresh instance.
    pass  # Patching at module level is sufficient since closures call Evaluator() lazily.


# ---------------------------------------------------------------------------
# Async functions
# ---------------------------------------------------------------------------


class TestWithAportGuardrailAsync:
    """Tests for @with_aport_guardrail on async (coroutine) functions."""

    @pytest.mark.asyncio
    @patch("autogen_adapter.decorator.Evaluator")
    async def test_allow_executes_async_fn(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator allows, async function executes and returns its value."""
        mock_evaluator_cls.return_value.verify = AsyncMock(return_value={"allow": True})

        @with_aport_guardrail
        async def send_email(recipient: str, body: str = "") -> str:
            return f"Sent to {recipient}"

        result = await send_email(recipient="user@example.com", body="Hello")
        assert result == "Sent to user@example.com"
        mock_evaluator_cls.return_value.verify.assert_called_once()

    @pytest.mark.asyncio
    @patch("autogen_adapter.decorator.Evaluator")
    async def test_deny_raises_async(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator denies, async function raises GuardrailViolation."""
        from aport_guardrails.core import GuardrailViolation

        mock_evaluator_cls.return_value.verify = AsyncMock(
            return_value={
                "allow": False,
                "reasons": [{"code": "oap.email_denied", "message": "Email tool is blocked"}],
            }
        )

        @with_aport_guardrail
        async def send_email(recipient: str) -> str:
            return f"Sent to {recipient}"

        with pytest.raises(GuardrailViolation) as exc_info:
            await send_email(recipient="attacker@evil.com")

        assert exc_info.value.code == "oap.email_denied"
        assert "blocked" in str(exc_info.value)

    @pytest.mark.asyncio
    @patch("autogen_adapter.decorator.Evaluator")
    async def test_context_uses_function_name_async(self, mock_evaluator_cls: MagicMock) -> None:
        """Tool context uses the decorated function name."""
        mock_evaluator_cls.return_value.verify = AsyncMock(return_value={"allow": True})

        @with_aport_guardrail
        async def call_external_api(url: str) -> str:
            return "response"

        await call_external_api(url="https://example.com")

        call_args = mock_evaluator_cls.return_value.verify.call_args[0]
        context = call_args[2]
        assert context.get("tool") == "call_external_api"

    @pytest.mark.asyncio
    @patch("autogen_adapter.decorator.Evaluator")
    async def test_wrapped_async_preserves_name(self, mock_evaluator_cls: MagicMock) -> None:
        """functools.wraps: wrapped function retains original __name__."""
        mock_evaluator_cls.return_value.verify = AsyncMock(return_value={"allow": True})

        @with_aport_guardrail
        async def my_async_tool() -> None:
            pass

        assert my_async_tool.__name__ == "my_async_tool"


# ---------------------------------------------------------------------------
# Sync functions
# ---------------------------------------------------------------------------


class TestWithAportGuardrailSync:
    """Tests for @with_aport_guardrail on plain (sync) functions."""

    @patch("autogen_adapter.decorator.Evaluator")
    def test_allow_executes_sync_fn(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator allows, sync function executes and returns its value."""
        mock_evaluator_cls.return_value.verify_sync.return_value = {"allow": True}

        @with_aport_guardrail
        def run_sql(query: str) -> str:
            return f"rows: {query}"

        result = run_sql(query="SELECT 1")
        assert result == "rows: SELECT 1"
        mock_evaluator_cls.return_value.verify_sync.assert_called_once()

    @patch("autogen_adapter.decorator.Evaluator")
    def test_deny_raises_sync(self, mock_evaluator_cls: MagicMock) -> None:
        """When evaluator denies, sync function raises GuardrailViolation."""
        from aport_guardrails.core import GuardrailViolation

        mock_evaluator_cls.return_value.verify_sync.return_value = {
            "allow": False,
            "reasons": [{"code": "oap.sql_denied", "message": "SQL execution blocked"}],
        }

        @with_aport_guardrail
        def run_sql(query: str) -> str:
            return f"rows: {query}"

        with pytest.raises(GuardrailViolation) as exc_info:
            run_sql(query="DROP TABLE users")

        assert exc_info.value.code == "oap.sql_denied"
        assert "blocked" in str(exc_info.value)

    @patch("autogen_adapter.decorator.Evaluator")
    def test_context_uses_function_name_sync(self, mock_evaluator_cls: MagicMock) -> None:
        """Tool context uses the decorated function name (sync path)."""
        mock_evaluator_cls.return_value.verify_sync.return_value = {"allow": True}

        @with_aport_guardrail
        def write_file(path: str, content: str) -> None:
            pass

        write_file(path="/tmp/out.txt", content="data")

        call_args = mock_evaluator_cls.return_value.verify_sync.call_args[0]
        context = call_args[2]
        assert context.get("tool") == "write_file"

    @patch("autogen_adapter.decorator.Evaluator")
    def test_wrapped_sync_preserves_name(self, mock_evaluator_cls: MagicMock) -> None:
        """functools.wraps: wrapped sync function retains original __name__."""
        mock_evaluator_cls.return_value.verify_sync.return_value = {"allow": True}

        @with_aport_guardrail
        def my_sync_tool() -> None:
            pass

        assert my_sync_tool.__name__ == "my_sync_tool"

    @pytest.mark.asyncio
    @patch("autogen_adapter.decorator.Evaluator")
    async def test_async_flag_detection(self, mock_evaluator_cls: MagicMock) -> None:
        """Async functions get async wrappers; sync functions get sync wrappers."""
        import asyncio

        mock_evaluator_cls.return_value.verify = AsyncMock(return_value={"allow": True})
        mock_evaluator_cls.return_value.verify_sync.return_value = {"allow": True}

        @with_aport_guardrail
        async def async_fn() -> str:
            return "async"

        @with_aport_guardrail
        def sync_fn() -> str:
            return "sync"

        assert asyncio.iscoroutinefunction(async_fn)
        assert not asyncio.iscoroutinefunction(sync_fn)

        assert await async_fn() == "async"
        assert sync_fn() == "sync"

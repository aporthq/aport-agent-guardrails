"""Unit tests for CrewAI with_aport_guardrail decorator."""

import pytest
from unittest.mock import MagicMock, patch

from crewai_adapter.decorator import with_aport_guardrail


class TestWithAportGuardrail:
    """Decorator intercepts args/kwargs, calls register_aport_guardrail, respects hook decisions."""

    @patch("crewai_adapter.decorator.register_aport_guardrail")
    def test_wrapped_invokes_register_then_fn(self, mock_register: MagicMock) -> None:
        """Decorator calls register_aport_guardrail() then the wrapped function."""
        fn = MagicMock(return_value="result")
        wrapped = with_aport_guardrail(fn)

        out = wrapped()

        mock_register.assert_called_once()
        fn.assert_called_once_with()
        assert out == "result"

    @patch("crewai_adapter.decorator.register_aport_guardrail")
    def test_passes_args_and_kwargs_through(self, mock_register: MagicMock) -> None:
        """Decorator passes *args and **kwargs to the wrapped function."""
        fn = MagicMock(return_value=42)
        wrapped = with_aport_guardrail(fn)

        out = wrapped(1, 2, x=3, y=4)

        fn.assert_called_once_with(1, 2, x=3, y=4)
        assert out == 42

    @patch("crewai_adapter.decorator.register_aport_guardrail")
    def test_returns_wrapped_return_value(self, mock_register: MagicMock) -> None:
        """Decorator returns the wrapped function's return value."""
        fn = MagicMock(return_value={"crew": "result"})
        wrapped = with_aport_guardrail(fn)

        out = wrapped()

        assert out == {"crew": "result"}

    @patch("crewai_adapter.decorator.register_aport_guardrail")
    def test_register_called_before_fn(self, mock_register: MagicMock) -> None:
        """register_aport_guardrail is called before the wrapped function runs."""
        call_order: list[str] = []

        def track_register() -> None:
            call_order.append("register")

        def track_fn() -> str:
            call_order.append("fn")
            return "ok"

        mock_register.side_effect = track_register
        wrapped = with_aport_guardrail(track_fn)

        wrapped()

        assert call_order == ["register", "fn"]

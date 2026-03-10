"""
AutoGen decorator: apply APort guardrails to a function before it is used as
an AutoGen 0.4.x tool (via FunctionTool) or called directly as an AutoGen
0.2.x function_map entry.

Usage (AutoGen 0.4.x — FunctionTool)::

    from autogen_core.tools import FunctionTool
    from autogen_adapter import with_aport_guardrail

    @with_aport_guardrail
    async def send_email(recipient: str, body: str) -> str:
        ...

    tool = FunctionTool(send_email, description="Send an email")

Usage (AutoGen 0.2.x — function_map)::

    from autogen import AssistantAgent
    from autogen_adapter import with_aport_guardrail

    @with_aport_guardrail
    def search_web(query: str) -> str:
        ...

    agent = AssistantAgent("assistant", ..., function_map={"search_web": search_web})
"""

from __future__ import annotations

import functools
import json
from typing import Any, Callable, Coroutine, TypeVar

from aport_guardrails.core import (
    Evaluator,
    GuardrailViolation,
    build_tool_context,
    tool_to_pack_id,
)
from aport_guardrails.core.config import find_config_path

F = TypeVar("F", bound=Callable[..., Any])


def with_aport_guardrail(fn: F) -> F:
    """
    Decorator: wrap *fn* with an APort pre-action policy check.

    - If *fn* is a coroutine function (``async def``), the wrapper is async.
    - If *fn* is a plain function, the wrapper is sync.

    The tool name is taken from ``fn.__name__``.  Override by passing a
    ``_aport_tool_name`` keyword argument at call time (stripped before
    forwarding to the original function).

    Config is auto-loaded from ``.aport/config.yaml`` or
    ``~/.aport/autogen/config.yaml``.
    """
    import inspect

    tool_name = fn.__name__
    evaluator_holder: list[Evaluator] = []  # lazy-init closure

    def _evaluator() -> Evaluator:
        if not evaluator_holder:
            evaluator_holder.append(
                Evaluator(config_path=find_config_path("autogen"), framework="autogen")
            )
        return evaluator_holder[0]

    def _build_ctx(args: tuple[Any, ...], kwargs: dict[str, Any]) -> dict[str, Any]:
        """Build context dict from positional + keyword args."""
        ctx: dict[str, Any] = dict(kwargs)
        if args:
            ctx.setdefault("args", list(args))
        try:
            input_str = json.dumps(ctx)
        except (TypeError, ValueError):
            input_str = str(ctx)
        return build_tool_context(tool_name, input_str)

    if inspect.iscoroutinefunction(fn):

        @functools.wraps(fn)
        async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
            tool_ctx = _build_ctx(args, kwargs)
            pack_id = tool_to_pack_id(tool_name)
            decision = await _evaluator().verify(
                {},
                {"capability": pack_id},
                tool_ctx,
            )
            if not decision.get("allow", False):
                reasons = decision.get("reasons") or [{}]
                msg = reasons[0].get("message", "APort denied") if reasons else "APort denied"
                code = reasons[0].get("code", "oap.denied") if reasons else "oap.denied"
                raise GuardrailViolation(msg, code=code, reasons=reasons)
            return await fn(*args, **kwargs)

        return async_wrapper  # type: ignore[return-value]

    else:

        @functools.wraps(fn)
        def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
            tool_ctx = _build_ctx(args, kwargs)
            pack_id = tool_to_pack_id(tool_name)
            decision = _evaluator().verify_sync(
                {},
                {"capability": pack_id},
                tool_ctx,
            )
            if not decision.get("allow", False):
                reasons = decision.get("reasons") or [{}]
                msg = reasons[0].get("message", "APort denied") if reasons else "APort denied"
                code = reasons[0].get("code", "oap.denied") if reasons else "oap.denied"
                raise GuardrailViolation(msg, code=code, reasons=reasons)
            return fn(*args, **kwargs)

        return sync_wrapper  # type: ignore[return-value]

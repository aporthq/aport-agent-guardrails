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
from typing import Any, Callable, TypeVar

from aport_guardrails.core import (
    build_tool_context,
    tool_to_pack_id,
)
from autogen_adapter._utils import raise_if_denied
from autogen_adapter.hook import _get_evaluator  # shared singleton evaluator

F = TypeVar("F", bound=Callable[..., Any])


def with_aport_guardrail(fn: F) -> F:
    """
    Decorator: wrap *fn* with an APort pre-action policy check.

    - If *fn* is a coroutine function (``async def``), the wrapper is async.
    - If *fn* is a plain function, the wrapper is sync.

    The tool name is taken from ``fn.__name__``.
    Config is auto-loaded from ``.aport/config.yaml`` or
    ``~/.aport/autogen/config.yaml`` (shared with the module-level evaluator).

    The evaluator is shared with the ``hook.py`` module-level instance so that
    all guardrail calls in a process use a single Evaluator and consistent config.
    """
    import inspect

    tool_name = fn.__name__

    def _build_tool_ctx(args: tuple[Any, ...], kwargs: dict[str, Any]) -> dict[str, Any]:
        """Build APort tool context dict from positional + keyword args."""
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
            tool_ctx = _build_tool_ctx(args, kwargs)
            pack_id = tool_to_pack_id(tool_name)
            evaluator = _get_evaluator()
            decision = await evaluator.verify(
                {},
                {"capability": pack_id},
                tool_ctx,
            )
            raise_if_denied(decision)
            return await fn(*args, **kwargs)

        return async_wrapper  # type: ignore[return-value]

    else:

        @functools.wraps(fn)
        def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
            tool_ctx = _build_tool_ctx(args, kwargs)
            pack_id = tool_to_pack_id(tool_name)
            evaluator = _get_evaluator()
            decision = evaluator.verify_sync(
                {},
                {"capability": pack_id},
                tool_ctx,
            )
            raise_if_denied(decision)
            return fn(*args, **kwargs)

        return sync_wrapper  # type: ignore[return-value]

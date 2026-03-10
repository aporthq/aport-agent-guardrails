"""
AutoGen hook: wrap agent tools with APort pre-action guardrails.

Supports:
- AutoGen 0.4.x (autogen-agentchat / autogen-core):
    APortGuardedTool — wraps any BaseTool with APort verification before run_json.
- AutoGen 0.2.x (pyautogen / autogen):
    wrap_agent_tools(agent) — patches agent.function_map callables with APort checks.

Usage (0.4.x):
    from autogen_adapter import APortGuardedTool
    guarded = APortGuardedTool(my_function_tool)
    agent = ToolAgent("MyAgent", tools=[guarded])

Usage (0.2.x):
    from autogen_adapter import wrap_agent_tools
    wrap_agent_tools(assistant)
    assistant.initiate_chat(...)
"""

from __future__ import annotations

import functools
import json
from typing import Any, Callable, Mapping

from aport_guardrails.core import (
    Evaluator,
    GuardrailViolation,
    build_tool_context,
    tool_to_pack_id,
)
from aport_guardrails.core.config import find_config_path

# Module-level cached evaluator (lazy-init, shared across tools in process).
_autogen_evaluator: Evaluator | None = None


def _get_evaluator(config_path: str | None = None) -> Evaluator:
    """Return the module-level Evaluator, creating it on first call."""
    global _autogen_evaluator
    if _autogen_evaluator is None:
        _autogen_evaluator = Evaluator(
            config_path=config_path or find_config_path("autogen"),
            framework="autogen",
        )
    return _autogen_evaluator


# ---------------------------------------------------------------------------
# AutoGen 0.4.x: APortGuardedTool
# ---------------------------------------------------------------------------


class APortGuardedTool:
    """
    Wraps any AutoGen 0.4.x BaseTool-compatible object with APort pre-action
    verification.  The wrapper forwards all attribute access to the inner tool;
    it only intercepts ``run_json`` (and ``run`` for convenience) to inject the
    APort policy check before execution.

    The inner tool is *not* imported at class-definition time — any object that
    satisfies the AutoGen BaseTool duck-type (``name``, ``description``,
    ``schema``, async ``run_json``) is accepted.

    Example (AutoGen 0.4.x)::

        from autogen_core.tools import FunctionTool
        from autogen_adapter import APortGuardedTool

        def get_weather(city: str) -> str:
            ...

        tool = APortGuardedTool(FunctionTool(get_weather, description="Get weather"))
        # Pass tool to ToolAgent or AssistantAgent.
    """

    def __init__(self, inner_tool: Any, config_path: str | None = None) -> None:
        self._inner = inner_tool
        self._evaluator = _get_evaluator(config_path)

    # ------------------------------------------------------------------ #
    # Forward attribute access / property proxying to inner tool          #
    # ------------------------------------------------------------------ #

    @property
    def name(self) -> str:
        return self._inner.name  # type: ignore[no-any-return]

    @property
    def description(self) -> str:
        return self._inner.description  # type: ignore[no-any-return]

    @property
    def schema(self) -> Any:
        return self._inner.schema  # type: ignore[no-any-return]

    def __getattr__(self, item: str) -> Any:
        # Proxy anything not explicitly overridden to the inner tool.
        return getattr(self._inner, item)

    # ------------------------------------------------------------------ #
    # Guarded execution hook                                              #
    # ------------------------------------------------------------------ #

    async def run_json(
        self,
        args: Mapping[str, Any],
        cancellation_token: Any = None,
    ) -> Any:
        """
        APort-guarded ``run_json``:
        1. Build tool context from args.
        2. Verify with APort evaluator.
        3. Raise ``GuardrailViolation`` on deny.
        4. Delegate to inner tool on allow.
        """
        tool_name = self.name
        input_str = json.dumps(dict(args))
        tool_ctx = build_tool_context(tool_name, input_str)
        pack_id = tool_to_pack_id(tool_name)

        decision = await self._evaluator.verify(
            {},
            {"capability": pack_id},
            tool_ctx,
        )

        if not decision.get("allow", False):
            reasons = decision.get("reasons") or [{}]
            msg = reasons[0].get("message", "APort denied") if reasons else "APort denied"
            code = reasons[0].get("code", "oap.denied") if reasons else "oap.denied"
            raise GuardrailViolation(msg, code=code, reasons=reasons)

        # AutoGen 0.4.x: run_json(args, cancellation_token)
        if cancellation_token is not None:
            return await self._inner.run_json(args, cancellation_token)
        return await self._inner.run_json(args)

    async def run(self, args: Any, cancellation_token: Any = None) -> Any:
        """
        APort-guarded ``run``: serialises args, runs the guardrail, then delegates
        to the inner tool's ``run`` (which in turn calls ``run_json``).

        Prefer attaching guardrails at the ``run_json`` level; this override
        prevents double-checking by delegating directly without calling
        ``self.run_json`` again.
        """
        tool_name = self.name
        try:
            input_str = json.dumps(args.model_dump() if hasattr(args, "model_dump") else args)
        except (TypeError, ValueError):
            input_str = str(args)
        tool_ctx = build_tool_context(tool_name, input_str)
        pack_id = tool_to_pack_id(tool_name)

        decision = await self._evaluator.verify(
            {},
            {"capability": pack_id},
            tool_ctx,
        )

        if not decision.get("allow", False):
            reasons = decision.get("reasons") or [{}]
            msg = reasons[0].get("message", "APort denied") if reasons else "APort denied"
            code = reasons[0].get("code", "oap.denied") if reasons else "oap.denied"
            raise GuardrailViolation(msg, code=code, reasons=reasons)

        if cancellation_token is not None:
            return await self._inner.run(args, cancellation_token)
        return await self._inner.run(args)


# ---------------------------------------------------------------------------
# AutoGen 0.2.x: wrap_agent_tools
# ---------------------------------------------------------------------------


def _make_guarded_callable(
    fn: Callable[..., Any],
    tool_name: str,
    evaluator: Evaluator,
) -> Callable[..., Any]:
    """
    Return a sync wrapper around *fn* that calls ``evaluator.verify_sync`` first.
    Used to patch ``agent.function_map`` for AutoGen 0.2.x.
    """

    @functools.wraps(fn)
    def guarded(*args: Any, **kwargs: Any) -> Any:
        context_dict = kwargs if kwargs else ({"args": list(args)} if args else {})
        try:
            input_str = json.dumps(context_dict)
        except (TypeError, ValueError):
            input_str = str(context_dict)
        tool_ctx = build_tool_context(tool_name, input_str)
        pack_id = tool_to_pack_id(tool_name)

        decision = evaluator.verify_sync(
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

    return guarded


def wrap_agent_tools(
    agent: Any,
    config_path: str | None = None,
) -> Any:
    """
    AutoGen 0.2.x: patch ``agent.function_map`` so every registered tool is
    verified by APort before execution.  Returns the same agent (mutated
    in-place) for convenient chaining.

    Example::

        from autogen import AssistantAgent
        from autogen_adapter import wrap_agent_tools

        assistant = AssistantAgent("assistant", llm_config={...}, function_map={"search": search_fn})
        wrap_agent_tools(assistant)
        user_proxy.initiate_chat(assistant, ...)

    Raises ``AttributeError`` if the agent has no ``function_map``.
    """
    if not hasattr(agent, "function_map") or not isinstance(agent.function_map, dict):
        raise AttributeError(
            f"wrap_agent_tools: agent {agent!r} has no 'function_map' dict. "
            "Expected an AutoGen 0.2.x ConversableAgent subclass."
        )

    evaluator = _get_evaluator(config_path)
    guarded_map: dict[str, Callable[..., Any]] = {}
    for name, fn in agent.function_map.items():
        guarded_map[name] = _make_guarded_callable(fn, name, evaluator)
    agent.function_map = guarded_map
    return agent

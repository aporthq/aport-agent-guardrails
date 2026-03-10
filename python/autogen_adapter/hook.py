"""
AutoGen hook: wrap agent tools with APort pre-action guardrails.

Supports:
- AutoGen 0.4.x (autogen-agentchat / autogen-core):
    APortGuardedTool — wraps any BaseTool with APort verification before run_json.
- AutoGen 0.2.x (pyautogen):
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

import asyncio
import functools
import json
import logging
import warnings
from typing import Any, Callable, Mapping

from aport_guardrails.core import (
    Evaluator,
    build_tool_context,
    tool_to_pack_id,
)
from aport_guardrails.core.config import find_config_path
from autogen_adapter._utils import raise_if_denied

logger = logging.getLogger(__name__)

# Module-level cached evaluator (lazy-init, shared across tools in process).
# This singleton is used by all hooks that don't specify an explicit config_path.
# First call wins: subsequent calls with a different config_path will NOT override
# the singleton — use APortGuardedTool(inner, config_path=...) to get a separate
# evaluator for that tool only.
_autogen_evaluator: Evaluator | None = None


def _get_evaluator(config_path: str | None = None) -> Evaluator:
    """
    Return the module-level Evaluator, creating it on first call.

    Args:
        config_path: Optional explicit path to a config YAML file.
                     Passed only during first-call initialisation; ignored if
                     the singleton is already created.  Pass ``None`` to use
                     auto-detected config.

    Note:
        The singleton is process-scoped.  If two callers pass different
        ``config_path`` values in the same process, the **first** call's path
        wins.  To use a non-default config for a specific tool, create a
        dedicated ``Evaluator`` instance rather than relying on this singleton.
    """
    global _autogen_evaluator
    if _autogen_evaluator is None:
        _autogen_evaluator = Evaluator(
            config_path=config_path or find_config_path("autogen"),
            framework="autogen",
        )
    return _autogen_evaluator


def _make_evaluator(config_path: str | None) -> Evaluator:
    """
    Return an Evaluator for the given config_path.

    - If ``config_path`` is None → return the shared module-level singleton.
    - If ``config_path`` is explicitly provided → create a *dedicated* Evaluator
      so that callers with custom config paths are not subject to the singleton's
      first-call-wins semantics.
    """
    if config_path is None:
        return _get_evaluator()
    return Evaluator(config_path=config_path, framework="autogen")


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

    Config:
        If ``config_path`` is ``None`` (default), the process-level shared
        Evaluator is used.  If ``config_path`` is provided, a dedicated Evaluator
        is created for this tool only (avoids singleton first-call-wins hazard).

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
        # Use dedicated evaluator when config_path is given; shared singleton otherwise.
        self._evaluator = _make_evaluator(config_path)

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
        # Proxy to inner tool for any attribute not explicitly defined on the
        # wrapper.  Note: methods defined on this class (run_json, run) are
        # resolved before __getattr__ fires, so they will NOT be bypassed.
        # __getattr__ only fires for attributes that genuinely don't exist on
        # the wrapper itself, making it safe for metadata/property access.
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
        2. Verify with APort evaluator (async — non-blocking).
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
        raise_if_denied(decision)

        if cancellation_token is not None:
            return await self._inner.run_json(args, cancellation_token)
        # Inner tool may or may not accept cancellation_token
        try:
            return await self._inner.run_json(args)
        except AttributeError:
            # Fallback: inner tool has no run_json method, delegate to run.
            # Note: if inner.run_json EXISTS but internally raises AttributeError,
            # this will silently fall through to run().  That edge case is unlikely
            # with well-behaved AutoGen tools but worth noting for future hardening.
            return await self._inner.run(args)

    async def run(self, args: Any, cancellation_token: Any = None) -> Any:
        """
        APort-guarded ``run``.  Serialises args, runs the guardrail, then
        delegates to the inner tool's ``run``.

        Note: ``run`` and ``run_json`` each independently check the guardrail.
        This avoids any path (framework calling run vs run_json) bypassing the
        policy gate.  The double-check is intentional: both entry points must be
        authorised separately.
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
        raise_if_denied(decision)

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
    Return a wrapper around *fn* that calls the APort evaluator first.
    Used to patch ``agent.function_map`` for AutoGen 0.2.x.

    Supports both sync and async callables:
    - Sync fn → sync wrapper (standard 0.2.x use case).
    - Async fn → async wrapper with ``await evaluator.verify()`` (avoids blocking
      the event loop), plus a ``warnings.warn()`` since 0.2.x function_map is
      typically sync.
    """
    if asyncio.iscoroutinefunction(fn):
        warnings.warn(
            f"wrap_agent_tools: tool '{tool_name}' is an async function registered in "
            "function_map. AutoGen 0.2.x function_map is typically sync. "
            "An async wrapper will be used; ensure your agent runtime awaits it. "
            "Note: APort policy verification is async and non-blocking in this wrapper.",
            stacklevel=2,  # points to the wrap_agent_tools(...) call site
        )

        @functools.wraps(fn)
        async def async_guarded(*args: Any, **kwargs: Any) -> Any:
            context_dict = kwargs if kwargs else ({"args": list(args)} if args else {})
            try:
                input_str = json.dumps(context_dict)
            except (TypeError, ValueError):
                input_str = str(context_dict)
            tool_ctx = build_tool_context(tool_name, input_str)
            pack_id = tool_to_pack_id(tool_name)

            # Use async verify to avoid blocking the event loop
            decision = await evaluator.verify(
                {},
                {"capability": pack_id},
                tool_ctx,
            )
            raise_if_denied(decision)
            return await fn(*args, **kwargs)

        return async_guarded

    @functools.wraps(fn)
    def sync_guarded(*args: Any, **kwargs: Any) -> Any:
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
        raise_if_denied(decision)
        return fn(*args, **kwargs)

    return sync_guarded


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

    # Use dedicated evaluator when config_path given; shared singleton otherwise.
    evaluator = _make_evaluator(config_path)
    guarded_map: dict[str, Callable[..., Any]] = {}
    for name, fn in agent.function_map.items():
        guarded_map[name] = _make_guarded_callable(fn, name, evaluator)
    agent.function_map = guarded_map
    return agent

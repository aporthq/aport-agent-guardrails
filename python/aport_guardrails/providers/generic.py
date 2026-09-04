"""Generic OAP guardrail provider. Wraps core Evaluator for any framework.

Any framework that calls provider.evaluate(request) -> result can use this.
The request object needs .tool_name (str), .tool_input (dict), and optionally
.agent_id (str). No framework-specific code.
"""

from __future__ import annotations

import os
from typing import Any

from aport_guardrails.core import Evaluator, build_tool_context, tool_to_pack_id
from aport_guardrails.core.config import find_config_path, load_config


class OAPGuardrailProvider:
    """Generic OAP provider. Works with any framework that calls evaluate(request).

    Usage in DeerFlow config.yaml:
        guardrails:
          provider:
            use: aport_guardrails.providers.generic:OAPGuardrailProvider

    Usage in any Python framework:
        from aport_guardrails.providers import OAPGuardrailProvider
        provider = OAPGuardrailProvider(framework="deerflow")
        result = provider.evaluate(request)
        if not result.allow:
            # handle denial
    """

    name = "aport"

    def __init__(
        self,
        framework: str = "generic",
        config_path: str | None = None,
        enforcement_mode: str | None = None,
    ):
        resolved_config_path = config_path or find_config_path(framework)
        loaded_config = load_config(resolved_config_path) if resolved_config_path else {}
        self._enforcement_mode = _normalize_enforcement_mode(
            enforcement_mode
            or loaded_config.get("enforcement_mode")
            or loaded_config.get("enforcementMode")
        )
        self._evaluator = Evaluator(
            resolved_config_path,
            framework=framework,
        )

    def _build_context(self, request: Any) -> dict:
        """Build evaluator context from request.

        The bash evaluator expects fields like .command, .repo, .recipient
        at the top level of the context JSON. build_tool_context() wraps them
        inside .params, so we merge params back to the top level.
        """
        tool_ctx = build_tool_context(request.tool_name, request.tool_input)
        # Flatten: merge params into top level so bash evaluator finds .command etc.
        if isinstance(tool_ctx.get("params"), dict):
            for k, v in tool_ctx["params"].items():
                tool_ctx.setdefault(k, v)
        return tool_ctx

    def evaluate(self, request: Any) -> _ProviderResult:
        """Sync evaluation. Request needs .tool_name, .tool_input, optional .agent_id."""
        tool_ctx = self._build_context(request)
        pack_id = tool_to_pack_id(request.tool_name)
        # Don't pass agent_id to the evaluator -- the evaluator reads agent_id
        # and passport_path from its own config (~/.aport/<framework>/config.yaml).
        # The request.agent_id from DeerFlow is the passport field from config.yaml
        # which may be a file path or a hosted ID; the evaluator handles both.
        decision = self._evaluator.verify_sync(
            {},
            {"capability": pack_id},
            tool_ctx,
        )
        return _to_result(decision, pack_id, self._enforcement_mode)

    async def aevaluate(self, request: Any) -> _ProviderResult:
        """Async evaluation."""
        tool_ctx = self._build_context(request)
        pack_id = tool_to_pack_id(request.tool_name)
        decision = await self._evaluator.verify(
            {},
            {"capability": pack_id},
            tool_ctx,
        )
        return _to_result(decision, pack_id, self._enforcement_mode)


class _Reason:
    """Reason with .code and .message attrs (matches OAP reason object)."""

    __slots__ = ("code", "message")

    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message


class _ProviderResult:
    """Lightweight result object. Attrs match what framework middlewares read."""

    __slots__ = ("allow", "reasons", "policy_id", "metadata")

    def __init__(
        self,
        allow: bool,
        reasons: list[_Reason],
        policy_id: str,
        metadata: dict[str, Any] | None = None,
    ):
        self.allow = allow
        self.reasons = reasons
        self.policy_id = policy_id
        self.metadata = metadata or {}


def _to_result(
    decision: dict,
    pack_id: str,
    enforcement_mode: str = "enforce",
) -> _ProviderResult:
    raw = decision.get("reasons") or []
    reasons = [_Reason(r.get("code", "oap.denied"), r.get("message", "")) for r in raw]
    original_allow = bool(decision.get("allow", False))
    effective_allow = True if enforcement_mode == "warn" else original_allow
    metadata = (
        {"enforcement_mode": enforcement_mode, "original_allow": original_allow}
        if enforcement_mode == "warn" or effective_allow != original_allow
        else None
    )
    return _ProviderResult(
        allow=effective_allow,
        reasons=reasons,
        policy_id=pack_id,
        metadata=metadata,
    )


def _normalize_enforcement_mode(value: Any) -> str:
    raw = str(
        value
        or os.environ.get("APORT_ENFORCEMENT_MODE")
        or os.environ.get("APORT_ENFORCEMENT")
        or os.environ.get("APORT_GUARDRAIL_ENFORCEMENT")
        or ""
    ).strip().lower()
    if raw in {"warn", "report-only", "report_only", "audit-only", "audit_only"}:
        return "warn"
    return "enforce"

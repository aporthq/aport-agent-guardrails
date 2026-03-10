"""
Shared helpers for the autogen_adapter package.
Centralises common patterns to avoid DRY violations across hook.py and decorator.py.
"""

from __future__ import annotations

from aport_guardrails.core import GuardrailViolation


def raise_if_denied(decision: dict) -> None:
    """
    Inspect an APort evaluator decision dict.
    If ``allow`` is False (or absent), extract the first reason's message + code
    and raise ``GuardrailViolation``.  Returns silently when the call is allowed.

    Args:
        decision: Dict with at least ``allow: bool`` and optional ``reasons: list``.

    Raises:
        GuardrailViolation: When ``decision["allow"]`` is False or missing.
    """
    if decision.get("allow", False):
        return
    # ``or [{}]`` guarantees reasons is non-empty; ``reason`` is always a dict.
    reasons = decision.get("reasons") or [{}]
    reason = reasons[0]
    msg = reason.get("message") or "APort denied"
    code = reason.get("code") or "oap.denied"
    raise GuardrailViolation(msg, code=code, reasons=reasons)

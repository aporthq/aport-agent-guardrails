"""Local copy of DeerFlow's AllowlistProvider for testing.

This mirrors deerflow.guardrails.builtin:AllowlistProvider exactly,
using the same _ProviderResult type from our generic provider.

Vendored from deerflow.guardrails.builtin on 2026-03-24 for test isolation.
"""

from aport_guardrails.providers.generic import _ProviderResult, _Reason


class AllowlistProvider:
    """Simple allowlist/denylist provider (same as DeerFlow's built-in)."""

    name = "allowlist"

    def __init__(self, *, allowed_tools: list[str] | None = None, denied_tools: list[str] | None = None):
        self._allowed = set(allowed_tools) if allowed_tools else None
        self._denied = set(denied_tools) if denied_tools else set()

    def evaluate(self, request) -> _ProviderResult:
        if self._allowed is not None and request.tool_name not in self._allowed:
            return _ProviderResult(allow=False, reasons=[_Reason("oap.tool_not_allowed", f"'{request.tool_name}' not in allowlist")], policy_id="builtin.allowlist")
        if request.tool_name in self._denied:
            return _ProviderResult(allow=False, reasons=[_Reason("oap.tool_not_allowed", f"'{request.tool_name}' denied")], policy_id="builtin.allowlist")
        return _ProviderResult(allow=True, reasons=[_Reason("oap.allowed", "")], policy_id="builtin.allowlist")

    async def aevaluate(self, request) -> _ProviderResult:
        return self.evaluate(request)

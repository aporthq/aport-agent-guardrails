"""LangChain AsyncCallbackHandler: intercept tool execution, call core evaluator."""

from aport_guardrails.core import Evaluator, GuardrailViolation, build_tool_context, tool_to_pack_id


class APortCallback:
    """Callback that verifies tool execution with APort before allowing. Auto-loads config from .aport/config.yaml or ~/.aport/langchain/."""

    def __init__(self, config_path: str | None = None) -> None:
        self.evaluator = Evaluator(config_path, framework="langchain")

    async def on_tool_start(self, tool_name: str, input_str: str, **kwargs: object) -> None:
        tool_ctx = build_tool_context(tool_name, input_str)
        pack_id = tool_to_pack_id(tool_name)
        decision = await self.evaluator.verify(
            {},
            {"capability": pack_id},
            tool_ctx,
        )
        if not decision.get("allow", False):
            reasons = decision.get("reasons") or [{}]
            msg = reasons[0].get("message", "APort denied") if reasons else "APort denied"
            code = reasons[0].get("code", "oap.denied") if reasons else "oap.denied"
            raise GuardrailViolation(msg, code=code, reasons=reasons)

"""LangChain callback handler: intercept tool execution, call core evaluator."""

import json
import os
from pathlib import Path
from typing import Any

try:
    from langchain_core.callbacks import AsyncCallbackHandler
except Exception:  # pragma: no cover - keeps the package usable without LangChain installed in unit tests.
    class AsyncCallbackHandler:  # type: ignore[no-redef]
        pass

from aport_guardrails.core.config import find_config_path, load_config
from aport_guardrails.core import Evaluator, GuardrailViolation, build_tool_context, tool_to_pack_id
from aport_guardrails.core.display import format_policy_warning


def _normalize_enforcement_mode(value: Any) -> str:
    normalized = str(value or "enforce").lower().replace("_", "-")
    return "warn" if normalized in {"warn", "report-only", "audit-only", "observe", "observation"} else "enforce"


def _resolve_enforcement_mode(config_path: str | None, framework: str, explicit: str | None) -> str:
    config: dict[str, Any] = {}
    path = Path(config_path).expanduser() if config_path else find_config_path(framework)
    if path:
        config = load_config(path)
    return _normalize_enforcement_mode(
        explicit
        or config.get("enforcement_mode")
        or config.get("enforcementMode")
        or os.environ.get("APORT_ENFORCEMENT_MODE")
        or os.environ.get("APORT_ENFORCEMENT")
    )


def _tool_name(serialized: Any) -> str:
    if isinstance(serialized, str):
        return serialized
    if isinstance(serialized, dict):
        return str(serialized.get("name") or serialized.get("id") or "unknown")
    return str(getattr(serialized, "name", None) or getattr(serialized, "id", None) or "unknown")


def _tool_input(input_str: Any, inputs: Any) -> str | dict[str, Any]:
    value = inputs if inputs is not None else input_str
    if isinstance(value, dict):
        return value
    if value is None:
        return ""
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass
    return str(value)


class APortCallback(AsyncCallbackHandler):
    """Callback that verifies tool execution with APort before allowing. Auto-loads config from .aport/config.yaml or ~/.aport/langchain/."""

    raise_error = True

    def __init__(self, config_path: str | None = None, enforcement_mode: str | None = None) -> None:
        self.config_path = config_path
        self.evaluator = Evaluator(config_path, framework="langchain")
        self.enforcement_mode = _resolve_enforcement_mode(config_path, "langchain", enforcement_mode)

    async def on_tool_start(self, serialized: Any, input_str: Any = None, **kwargs: object) -> None:
        tool_name = _tool_name(serialized)
        tool_input = _tool_input(input_str, kwargs.get("inputs"))
        tool_ctx = build_tool_context(tool_name, tool_input)
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
            if self.enforcement_mode == "warn":
                print(
                    format_policy_warning(
                        policy=pack_id,
                        reason_code=code,
                        reason_message=msg,
                        tool_name=tool_name,
                        framework="langchain",
                        config_path=self.config_path,
                    )
                )
                return
            raise GuardrailViolation(msg, code=code, reasons=reasons)

"""Display helpers for safe, actionable guardrail messages."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

from aport_guardrails.core.config import find_config_path, load_config


def sanitize_display(value: Any, limit: int = 320) -> str:
    """Strip control characters and redact common secrets before terminal output."""
    text = str(value or "").replace("\n", " ").replace("\r", " ").replace("\t", " ").replace("::", ": :")
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    replacements = (
        (r"(?:apk|aprt)_[A-Za-z0-9_-]+", "[REDACTED_APORT_KEY]"),
        (r"github_pat_[A-Za-z0-9_]+", "[REDACTED_GITHUB_TOKEN]"),
        (r"gh[pousr]_[A-Za-z0-9_]+", "[REDACTED_GITHUB_TOKEN]"),
        (r"xox[baprs]-[A-Za-z0-9-]+", "[REDACTED_SLACK_TOKEN]"),
        (r"AKIA[0-9A-Z]{16}", "[REDACTED_AWS_KEY]"),
        (r"(Authorization:?\s*Bearer|Bearer)\s+[A-Za-z0-9._~+/-]+=*", r"\1 [REDACTED]"),
        (r"(password|passwd|pwd|token|secret|api[_-]?key)=\S+", r"\1=[REDACTED]"),
        (r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", "[REDACTED_PRIVATE_KEY]"),
    )
    for pattern, replacement in replacements:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE | re.DOTALL)
    return text[:limit]


def policy_reference(*, framework: str | None = None, config_path: str | None = None) -> str:
    """Return the safest user-facing place to review the active passport/config."""
    app_url = os.environ.get("APORT_APP_URL", "https://aport.io").rstrip("/")
    config: dict[str, Any] = {}
    resolved_path: Path | None = None

    if config_path:
        resolved_path = Path(config_path).expanduser()
    elif framework:
        resolved_path = find_config_path(framework)

    if resolved_path:
        config = load_config(resolved_path)

    agent_id = (
        os.environ.get("APORT_AGENT_ID")
        or str(config.get("agent_id") or config.get("agentId") or config.get("hosted_agent_id") or "")
    )
    if agent_id:
        return f"Review or update the hosted passport: {app_url}/passports?details={agent_id}"

    passport_path = (
        os.environ.get("APORT_PASSPORT_FILE")
        or os.environ.get("PASSPORT_FILE")
        or str(config.get("passport_path") or config.get("passportFile") or "")
    )
    if passport_path:
        return f"Review or update the local passport file: {passport_path}"

    return f"Review the APort setup for this framework: {app_url}/quickstart"


def format_policy_warning(
    *,
    policy: str,
    reason_code: Any = "oap.denied",
    reason_message: Any = "",
    tool_name: Any = "",
    framework: str | None = None,
    config_path: str | None = None,
) -> str:
    """Build a consistent report-only warning for framework adapters."""
    safe_policy = sanitize_display(policy)
    safe_reason_code = sanitize_display(reason_code or "oap.denied")
    safe_reason_message = sanitize_display(reason_message or "")
    safe_tool_name = sanitize_display(tool_name)
    safe_reference = sanitize_display(policy_reference(framework=framework, config_path=config_path))

    parts = ["[APort] warning: policy would have denied this tool call."]
    if safe_tool_name:
        parts.append(f"Tool: {safe_tool_name}.")
    parts.append(f"Policy: {safe_policy}.")
    parts.append(f"Reason: {safe_reason_code}.")
    if safe_reason_message and safe_reason_message != safe_reason_code:
        parts.append(f"Detail: {safe_reason_message}.")
    parts.append(f"Review: {safe_reference}.")
    return " ".join(parts)

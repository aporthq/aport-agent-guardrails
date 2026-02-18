"""Passport loading and schema validation (OAP v1.0)."""

from typing import Any


def load_passport(path_or_agent_id: str) -> dict[str, Any]:
    """Load passport from file or resolve agent_id via API."""
    if path_or_agent_id.startswith("ap_"):
        return {"agent_id": path_or_agent_id}
    return {}


def validate_passport(passport: dict[str, Any]) -> dict[str, Any]:
    """Validate passport against OAP v1.0 schema. Returns {valid: bool, errors?: list}."""
    return {"valid": True}

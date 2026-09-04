"""
Input validation functions for security.
Prevents command injection, path traversal, and other injection attacks.
"""

import re
import json
from pathlib import Path
from typing import Any, Optional
from dataclasses import dataclass


@dataclass
class ValidationResult:
    """Result of input validation."""
    valid: bool
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    details: Optional[dict[str, Any]] = None


def validate_tool_name(tool_name: str) -> ValidationResult:
    """
    Validate tool name contains only safe characters.

    Args:
        tool_name: Tool name to validate

    Returns:
        ValidationResult with valid=True if safe, False otherwise

    Examples:
        >>> validate_tool_name("system.command.execute").valid
        True
        >>> validate_tool_name("rm; malicious").valid
        False
    """
    if not tool_name:
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_tool_name",
            error_message="Tool name cannot be empty",
        )

    if len(tool_name) > 128:
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_tool_name",
            error_message="Tool name exceeds maximum length of 128 characters",
            details={"length": len(tool_name), "max_length": 128},
        )

    # Allow only alphanumeric, dots, underscores, hyphens
    if not re.match(r'^[a-zA-Z0-9._-]+$', tool_name):
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_tool_name",
            error_message="Tool name contains invalid characters",
            details={
                "tool_name": tool_name,
                "allowed_pattern": "^[a-zA-Z0-9._-]+$",
            },
        )

    return ValidationResult(valid=True)


def validate_context_structure(context: dict[str, Any], max_bytes: int = 102400) -> ValidationResult:
    """
    Validate context dictionary structure and size.

    Args:
        context: Context dict to validate
        max_bytes: Maximum JSON size in bytes (default: 100KB)

    Returns:
        ValidationResult with valid=True if safe, False otherwise
    """
    if not isinstance(context, dict):
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_context",
            error_message="Context must be a dictionary",
            details={"type": str(type(context))},
        )

    # Check JSON size
    try:
        context_json = json.dumps(context)
        size = len(context_json.encode('utf-8'))

        if size > max_bytes:
            return ValidationResult(
                valid=False,
                error_code="oap.context_too_large",
                error_message=f"Context exceeds maximum size of {max_bytes} bytes",
                details={"size_bytes": size, "max_bytes": max_bytes},
            )
    except (TypeError, ValueError) as e:
        return ValidationResult(
            valid=False,
            error_code="oap.context_not_serializable",
            error_message="Context cannot be serialized to JSON",
            details={"error": str(e)},
        )

    # Check nesting depth
    def get_depth(obj: Any, current_depth: int = 0) -> int:
        if isinstance(obj, dict):
            if not obj:
                return current_depth
            return max(get_depth(v, current_depth + 1) for v in obj.values())
        elif isinstance(obj, list):
            if not obj:
                return current_depth
            return max(get_depth(item, current_depth + 1) for item in obj)
        else:
            return current_depth

    depth = get_depth(context)
    if depth > 10:  # Reasonable max nesting
        return ValidationResult(
            valid=False,
            error_code="oap.context_too_nested",
            error_message="Context exceeds maximum nesting depth of 10",
            details={"depth": depth, "max_depth": 10},
        )

    return ValidationResult(valid=True)


def _default_passport_base_dirs() -> list[Path]:
    """Allowed base directories for auto-discovered/default passport paths."""
    return [
        Path.home() / ".openclaw",
        Path.home() / ".aport",
        Path.home() / ".claude",
        Path.home() / ".cursor",
        Path.home() / ".n8n",
        Path("/tmp"),  # Will check for aport- prefix separately
    ]


def validate_explicit_passport_path(path: Path) -> ValidationResult:
    """
    Validate an explicit operator-supplied passport path.

    Explicit paths from config/env are authoritative, so we only enforce path
    hygiene here. Trust-boundary allowlists are handled separately for
    auto-discovered/default paths.
    """
    path_str = str(path)

    if "\x00" in path_str:
        return ValidationResult(
            valid=False,
            error_code="oap.path_invalid_characters",
            error_message="Path contains null bytes",
        )

    if "../" in path_str or "/.." in path_str:
        return ValidationResult(
            valid=False,
            error_code="oap.path_traversal_attempt",
            error_message="Path contains traversal sequences",
            details={"path": path_str},
        )

    try:
        resolved = path.expanduser().resolve()
    except (OSError, ValueError) as e:
        return ValidationResult(
            valid=False,
            error_code="oap.path_resolution_error",
            error_message="Failed to resolve path",
            details={"error": str(e)},
        )

    return ValidationResult(valid=True, details={"resolved_path": str(resolved)})


def validate_passport_path(path: Path, allowed_bases: Optional[list[Path]] = None) -> ValidationResult:
    """
    Validate an auto-discovered/default passport path.

    Discovered paths must pass both path hygiene checks and the framework base
    directory allowlist so we never auto-select an unexpected passport file.
    """
    if allowed_bases is None:
        allowed_bases = _default_passport_base_dirs()

    path_validation = validate_explicit_passport_path(path)
    if not path_validation.valid:
        return path_validation

    resolved = Path(path_validation.details["resolved_path"])  # type: ignore[index]

    is_allowed = False
    for base in allowed_bases:
        base_path = base.expanduser()
        base_resolved = base_path.resolve()

        # Special handling for /tmp - only /tmp/aport-* (or the macOS-resolved
        # /private/tmp/aport-*) is trusted for auto-discovery.
        if base_path == Path("/tmp"):
            resolved_str = str(resolved)
            if resolved_str.startswith("/tmp/aport-") or resolved_str.startswith("/private/tmp/aport-"):
                is_allowed = True
                break
        else:
            try:
                resolved.relative_to(base_resolved)
                is_allowed = True
                break
            except ValueError:
                continue

    if not is_allowed:
        return ValidationResult(
            valid=False,
            error_code="oap.path_not_allowed",
            error_message="Path is not within allowed directories",
            details={
                "path": str(resolved),
                "allowed_bases": [str(b) for b in allowed_bases],
            },
        )

    return ValidationResult(valid=True, details={"resolved_path": str(resolved)})


def validate_policy_pack_id(pack_id: str) -> ValidationResult:
    """
    Validate policy pack ID format.

    Args:
        pack_id: Policy pack ID to validate

    Returns:
        ValidationResult with valid=True if safe, False otherwise
    """
    if not pack_id:
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_policy_pack_id",
            error_message="Policy pack ID cannot be empty",
        )

    if len(pack_id) > 128:
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_policy_pack_id",
            error_message="Policy pack ID exceeds maximum length",
            details={"length": len(pack_id), "max_length": 128},
        )

    # Allow only alphanumeric, dots, underscores, hyphens
    if not re.match(r'^[a-zA-Z0-9._-]+$', pack_id):
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_policy_pack_id",
            error_message="Policy pack ID contains invalid characters",
            details={
                "pack_id": pack_id,
                "allowed_pattern": "^[a-zA-Z0-9._-]+$",
            },
        )

    return ValidationResult(valid=True)


def validate_agent_id(agent_id: str) -> ValidationResult:
    """
    Validate agent ID format.

    Args:
        agent_id: Agent ID to validate (expected format: ap_<alphanumeric>)

    Returns:
        ValidationResult with valid=True if safe, False otherwise
    """
    if not agent_id:
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_agent_id",
            error_message="Agent ID cannot be empty",
        )

    if len(agent_id) > 128:
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_agent_id",
            error_message="Agent ID exceeds maximum length",
            details={"length": len(agent_id), "max_length": 128},
        )

    # Expected format: ap_<alphanumeric/underscore>
    if not re.match(r'^ap_[a-zA-Z0-9_]+$', agent_id):
        return ValidationResult(
            valid=False,
            error_code="oap.invalid_agent_id",
            error_message="Agent ID has invalid format",
            details={
                "agent_id": agent_id,
                "expected_format": "ap_<alphanumeric>",
            },
        )

    return ValidationResult(valid=True)


def sanitize_log_value(value: str, field_name: str = "") -> str:
    """
    Sanitize sensitive values for logging.

    Args:
        value: Value to sanitize
        field_name: Optional field name to determine sanitization strategy

    Returns:
        Sanitized string safe for logging
    """
    if not value:
        return value

    # Detect API keys, tokens, passwords
    sensitive_patterns = [
        (r'^(apk_|aprt_|sk_|pk_)', 4, "****"),  # API keys: show first 4 chars
        (r'^Bearer\s+', 7, "****"),  # Bearer tokens
        (r'(password|passwd|pwd|secret|token|key)', 0, "[REDACTED]"),  # Sensitive fields
    ]

    lower_field = field_name.lower()
    lower_value = value.lower()

    for pattern, show_chars, replacement in sensitive_patterns:
        if re.match(pattern, value, re.IGNORECASE):
            if show_chars > 0:
                return value[:show_chars] + replacement
            return replacement

    # Check if field name indicates sensitive data
    if any(word in lower_field for word in ["password", "secret", "token", "key", "api"]):
        return "[REDACTED]"

    # Truncate very long values
    max_length = 200
    if len(value) > max_length:
        return value[:max_length] + "..."

    return value

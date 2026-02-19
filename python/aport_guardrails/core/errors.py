"""
Error handling utilities for APort Guardrails.
Provides consistent error codes, messages, and response formatting.
"""

import time
import uuid
from enum import Enum
from typing import Any, Optional
from dataclasses import dataclass, field
from datetime import datetime, timezone


class ErrorCode(str, Enum):
    """Standard error codes for APort Guardrails.

    Format: oap.<category>.<specific>
    See: docs/development/ERROR_CODES.md
    """

    # Invalid Input Errors
    INVALID_TOOL_NAME = "oap.invalid_input.tool_name"
    CONTEXT_TOO_LARGE = "oap.invalid_input.context_too_large"
    CONTEXT_TOO_NESTED = "oap.invalid_input.context_too_nested"
    CONTEXT_NOT_SERIALIZABLE = "oap.invalid_input.context_not_serializable"
    INVALID_AGENT_ID = "oap.invalid_input.agent_id"
    INVALID_POLICY_PACK_ID = "oap.invalid_input.policy_pack_id"

    # Path Security Errors
    PATH_NOT_ALLOWED = "oap.path.not_allowed"
    PATH_TRAVERSAL_ATTEMPT = "oap.path.traversal_attempt"
    PATH_INVALID_CHARACTERS = "oap.path.invalid_characters"
    PATH_RESOLUTION_ERROR = "oap.path.resolution_error"

    # Passport Errors
    PASSPORT_NOT_FOUND = "oap.passport.not_found"
    PASSPORT_INVALID_FORMAT = "oap.passport.invalid_format"
    PASSPORT_EXPIRED = "oap.passport.expired"
    PASSPORT_REVOKED = "oap.passport.revoked"
    PASSPORT_MISSING_CAPABILITY = "oap.passport.missing_capability"

    # Policy Errors
    POLICY_NOT_FOUND = "oap.policy.not_found"
    POLICY_INVALID_FORMAT = "oap.policy.invalid_format"
    POLICY_EVALUATION_FAILED = "oap.policy.evaluation_failed"
    POLICY_EVALUATION_TIMEOUT = "oap.policy.evaluation_timeout"
    POLICY_DENIED = "oap.policy.denied"

    # API Errors
    API_CONNECTION_FAILED = "oap.api.connection_failed"
    API_AUTHENTICATION_FAILED = "oap.api.authentication_failed"
    API_RATE_LIMIT_EXCEEDED = "oap.api.rate_limit_exceeded"
    API_TIMEOUT = "oap.api.timeout"
    API_INVALID_RESPONSE = "oap.api.invalid_response"
    API_NOT_FOUND_404 = "oap.api.not_found_404"
    API_ERROR = "oap.api.error"

    # Configuration Errors
    CONFIG_NOT_FOUND = "oap.config.not_found"
    CONFIG_INVALID_FORMAT = "oap.config.invalid_format"
    CONFIG_MISSING_REQUIRED = "oap.config.missing_required"

    # System Errors
    EVALUATOR_ERROR = "oap.system.evaluator_error"
    COMMAND_INJECTION_DETECTED = "oap.system.command_injection_detected"
    DEPENDENCY_MISSING = "oap.system.dependency_missing"
    INSUFFICIENT_PERMISSIONS = "oap.system.insufficient_permissions"

    # Rate Limiting Errors
    RATE_LIMIT_EXCEEDED = "oap.rate_limit.exceeded"
    RATE_LIMIT_PER_AGENT = "oap.rate_limit.per_agent"

    # Validation Errors
    VALIDATION_FAILED = "oap.validation.failed"
    VALIDATION_REQUIRED_FIELD = "oap.validation.required_field"
    VALIDATION_INVALID_FORMAT = "oap.validation.invalid_format"

    # Misconfigured
    MISCONFIGURED = "oap.misconfigured"


@dataclass
class ErrorDetails:
    """Structured error details for debugging and resolution."""

    code: str
    message: str
    details: Optional[dict[str, Any]] = None
    resolution: Optional[str] = None
    request_id: str = field(default_factory=lambda: f"req_{int(time.time() * 1000)}_{uuid.uuid4().hex[:6]}")
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary format."""
        result = {
            "code": self.code,
            "message": self.message,
            "request_id": self.request_id,
            "timestamp": self.timestamp,
        }
        if self.details:
            result["details"] = self.details
        if self.resolution:
            result["resolution"] = self.resolution
        return result

    def to_reason(self) -> dict[str, Any]:
        """Convert to reason format (for Decision.reasons)."""
        reason: dict[str, Any] = {
            "code": self.code,
            "message": self.message,
        }
        if self.details:
            reason["details"] = self.details
        if self.resolution:
            reason["resolution"] = self.resolution
        return reason


def create_error_response(
    code: str | ErrorCode,
    message: str,
    details: Optional[dict[str, Any]] = None,
    resolution: Optional[str] = None,
    request_id: Optional[str] = None,
) -> dict[str, Any]:
    """
    Create a standardized error response.

    Args:
        code: Error code (from ErrorCode enum or string)
        message: Human-readable error message
        details: Optional additional details for debugging
        resolution: Optional resolution steps
        request_id: Optional request ID (auto-generated if not provided)

    Returns:
        Standardized error response dictionary

    Example:
        >>> create_error_response(
        ...     ErrorCode.INVALID_TOOL_NAME,
        ...     "Tool name contains invalid characters",
        ...     details={"tool_name": "rm; malicious"},
        ...     resolution="Use only alphanumeric characters, dots, underscores, and hyphens"
        ... )
        {
            "allow": False,
            "reasons": [{
                "code": "oap.invalid_input.tool_name",
                "message": "Tool name contains invalid characters",
                "details": {"tool_name": "rm; malicious"},
                "resolution": "Use only alphanumeric characters..."
            }],
            "request_id": "req_1234567890_abc123",
            "timestamp": "2026-02-19T10:30:00.000Z"
        }
    """
    error_code = code.value if isinstance(code, ErrorCode) else code

    if request_id is None:
        request_id = f"req_{int(time.time() * 1000)}_{uuid.uuid4().hex[:6]}"

    error = ErrorDetails(
        code=error_code,
        message=message,
        details=details,
        resolution=resolution,
        request_id=request_id,
    )

    return {
        "allow": False,
        "reasons": [error.to_reason()],
        "request_id": error.request_id,
        "timestamp": error.timestamp,
    }


def create_deny_response(
    policy_id: str,
    reason: str,
    details: Optional[dict[str, Any]] = None,
    request_id: Optional[str] = None,
) -> dict[str, Any]:
    """
    Create a policy denial response.

    Args:
        policy_id: Policy pack ID that denied the operation
        reason: Reason for denial
        details: Optional additional details
        request_id: Optional request ID

    Returns:
        Policy denial response

    Example:
        >>> create_deny_response(
        ...     "system.command.execute.v1",
        ...     "Command not in allowed list",
        ...     details={"command": "rm -rf /"}
        ... )
    """
    return create_error_response(
        code=ErrorCode.POLICY_DENIED,
        message=reason,
        details={
            "policy_id": policy_id,
            **(details or {}),
        },
        resolution="Review policy rules and ensure operation is allowed",
        request_id=request_id,
    )


def create_allow_response(
    policy_id: Optional[str] = None,
    message: str = "All policy checks passed",
    request_id: Optional[str] = None,
) -> dict[str, Any]:
    """
    Create a policy allow response.

    Args:
        policy_id: Policy pack ID that allowed the operation
        message: Success message
        request_id: Optional request ID

    Returns:
        Policy allow response
    """
    if request_id is None:
        request_id = f"req_{int(time.time() * 1000)}_{uuid.uuid4().hex[:6]}"

    response: dict[str, Any] = {
        "allow": True,
        "reasons": [{"message": message}],
        "request_id": request_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    if policy_id:
        response["policy_id"] = policy_id

    return response


# Resolution messages for common errors
RESOLUTIONS = {
    ErrorCode.INVALID_TOOL_NAME: (
        "Use only alphanumeric characters, dots, underscores, and hyphens in tool names. "
        "Keep tool names under 128 characters."
    ),
    ErrorCode.CONTEXT_TOO_LARGE: (
        "Reduce context data size by removing unnecessary fields or summarizing large data. "
        "Default limit: 100KB. Set APORT_MAX_CONTEXT_SIZE to increase (not recommended)."
    ),
    ErrorCode.CONTEXT_TOO_NESTED: (
        "Flatten nested structures to reduce nesting depth. Maximum depth: 10 levels."
    ),
    ErrorCode.PATH_NOT_ALLOWED: (
        "Use standard APort directories: ~/.openclaw/, ~/.aport/, or /tmp/aport-*. "
        "Contact administrator to add custom allowed directories."
    ),
    ErrorCode.PATH_TRAVERSAL_ATTEMPT: (
        "Use absolute paths without parent directory references (../ or /..). "
        "This is a security feature to prevent path traversal attacks."
    ),
    ErrorCode.PASSPORT_NOT_FOUND: (
        "Create a passport by running: npx @aporthq/agent-guardrails openclaw\n"
        "See: https://github.com/aporthq/agent-guardrails#passport-setup"
    ),
    ErrorCode.PASSPORT_MISSING_CAPABILITY: (
        "Request capability be added to passport or generate new passport with required capabilities."
    ),
    ErrorCode.POLICY_NOT_FOUND: (
        "Verify policy pack ID is correct and update policy submodule: "
        "git submodule update --init --recursive"
    ),
    ErrorCode.API_CONNECTION_FAILED: (
        "Check internet connectivity, verify API URL (APORT_API_URL), "
        "and check firewall allows outbound HTTPS."
    ),
    ErrorCode.API_AUTHENTICATION_FAILED: (
        "Verify API key is set (APORT_API_KEY) and generate new API key if needed from APort dashboard."
    ),
    ErrorCode.API_RATE_LIMIT_EXCEEDED: (
        "Wait for rate limit to reset (see retry-after), reduce request frequency, "
        "or use local evaluation mode instead of API mode."
    ),
    ErrorCode.MISCONFIGURED: (
        "Run setup: npx @aporthq/agent-guardrails <framework>. "
        "Check passport exists at ~/.openclaw/passport.json and guardrail script at ~/.openclaw/.skills/aport-guardrail.sh"
    ),
}


def get_resolution(code: str | ErrorCode) -> Optional[str]:
    """Get standard resolution message for an error code."""
    error_code = code if isinstance(code, ErrorCode) else ErrorCode(code) if code in [e.value for e in ErrorCode] else None
    return RESOLUTIONS.get(error_code) if error_code else None  # type: ignore


class APortError(Exception):
    """Base exception for APort Guardrails errors."""

    def __init__(
        self,
        code: str | ErrorCode,
        message: str,
        details: Optional[dict[str, Any]] = None,
        resolution: Optional[str] = None,
    ):
        """
        Initialize APort error.

        Args:
            code: Error code
            message: Error message
            details: Additional details
            resolution: Resolution steps
        """
        self.code = code.value if isinstance(code, ErrorCode) else code
        self.message = message
        self.details = details or {}
        self.resolution = resolution or get_resolution(code)
        self.error_details = ErrorDetails(
            code=self.code,
            message=message,
            details=details,
            resolution=self.resolution,
        )
        super().__init__(message)

    def to_response(self) -> dict[str, Any]:
        """Convert to error response format."""
        return create_error_response(
            code=self.code,
            message=self.message,
            details=self.details,
            resolution=self.resolution,
            request_id=self.error_details.request_id,
        )


class ValidationError(APortError):
    """Validation error."""

    def __init__(self, message: str, details: Optional[dict[str, Any]] = None):
        super().__init__(
            code=ErrorCode.VALIDATION_FAILED,
            message=message,
            details=details,
        )


class ConfigurationError(APortError):
    """Configuration error."""

    def __init__(self, message: str, details: Optional[dict[str, Any]] = None):
        super().__init__(
            code=ErrorCode.CONFIG_INVALID_FORMAT,
            message=message,
            details=details,
        )


class PassportError(APortError):
    """Passport-related error."""

    def __init__(self, code: str | ErrorCode, message: str, details: Optional[dict[str, Any]] = None):
        super().__init__(
            code=code,
            message=message,
            details=details,
        )


class PolicyError(APortError):
    """Policy-related error."""

    def __init__(self, code: str | ErrorCode, message: str, details: Optional[dict[str, Any]] = None):
        super().__init__(
            code=code,
            message=message,
            details=details,
        )


class APIError(APortError):
    """API-related error."""

    def __init__(self, code: str | ErrorCode, message: str, details: Optional[dict[str, Any]] = None):
        super().__init__(
            code=code,
            message=message,
            details=details,
        )

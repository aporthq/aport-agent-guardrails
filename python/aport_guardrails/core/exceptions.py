"""Exceptions raised when a guardrail denies execution."""


class GuardrailViolation(Exception):
    """Raised when APort policy denies a tool call."""

    def __init__(self, message: str, code: str = "oap.denied", reasons: list | None = None):
        super().__init__(message)
        self.code = code
        self.reasons = reasons or []

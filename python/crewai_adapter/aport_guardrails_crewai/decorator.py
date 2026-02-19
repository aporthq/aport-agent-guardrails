"""CrewAI guardrail registration: decorator to apply APort hook before running a crew."""

from typing import Callable, TypeVar

from .hook import register_aport_guardrail

F = TypeVar("F", bound=Callable[..., object])


def with_aport_guardrail(fn: F) -> F:
    """
    Decorator: register the APort before_tool_call hook, then run the function.
    Use on your entry point so the hook is active for the crew run.

    Example:
        @with_aport_guardrail
        def main():
            crew.kickoff()
        main()
    """
    def wrapped(*args: object, **kwargs: object) -> object:
        register_aport_guardrail()
        return fn(*args, **kwargs)
    return wrapped  # type: ignore[return-value]

"""AutoGen adapter: APortGuardedTool (0.4.x) and wrap_agent_tools (0.2.x)."""

from aport_guardrails.frameworks.base import BaseAdapter


class AutoGenAdapter(BaseAdapter):
    @property
    def name(self) -> str:
        return "autogen"

    async def detect(self) -> bool:
        """Return True if autogen-agentchat or pyautogen is importable."""
        try:
            import importlib
            for pkg in ("autogen_agentchat", "autogen_core", "autogen"):
                if importlib.util.find_spec(pkg) is not None:
                    return True
        except Exception:
            pass
        return False

    async def install(self) -> None:
        pass

    async def verify(self) -> bool:
        return True

    async def test(self) -> bool:
        return True

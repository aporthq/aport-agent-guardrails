"""CrewAI adapter: task decorator."""

from aport_guardrails.frameworks.base import BaseAdapter


class CrewAIAdapter(BaseAdapter):
    @property
    def name(self) -> str:
        return "crewai"

    async def detect(self) -> bool:
        return False

    async def install(self) -> None:
        pass

    async def verify(self) -> bool:
        return True

    async def test(self) -> bool:
        return True

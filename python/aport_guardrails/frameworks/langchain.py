"""LangChain/LangGraph adapter: AsyncCallbackHandler."""

from aport_guardrails.frameworks.base import BaseAdapter


class LangChainAdapter(BaseAdapter):
    @property
    def name(self) -> str:
        return "langchain"

    async def detect(self) -> bool:
        return False

    async def install(self) -> None:
        pass

    async def verify(self) -> bool:
        return True

    async def test(self) -> bool:
        return True

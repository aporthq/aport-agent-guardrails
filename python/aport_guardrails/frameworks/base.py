"""Base adapter interface for framework-specific integrations."""

from abc import ABC, abstractmethod


class BaseAdapter(ABC):
    """Interface for framework adapters."""

    @property
    @abstractmethod
    def name(self) -> str:
        ...

    @abstractmethod
    async def detect(self) -> bool:
        ...

    @abstractmethod
    async def install(self) -> None:
        ...

    @abstractmethod
    async def verify(self) -> bool:
        ...

    @abstractmethod
    async def test(self) -> bool:
        ...

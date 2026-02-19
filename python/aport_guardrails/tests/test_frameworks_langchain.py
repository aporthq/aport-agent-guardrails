"""Unit tests for aport_guardrails.frameworks.langchain (LangChainAdapter)."""

import pytest
from aport_guardrails.frameworks.langchain import LangChainAdapter


class TestLangChainAdapter:
    """LangChainAdapter: name, detect, install, verify, test."""

    def test_name(self):
        adapter = LangChainAdapter()
        assert adapter.name == "langchain"

    @pytest.mark.asyncio
    async def test_detect_returns_false(self):
        adapter = LangChainAdapter()
        assert await adapter.detect() is False

    @pytest.mark.asyncio
    async def test_install_no_op(self):
        adapter = LangChainAdapter()
        await adapter.install()  # no raise

    @pytest.mark.asyncio
    async def test_verify_returns_true(self):
        adapter = LangChainAdapter()
        assert await adapter.verify() is True

    @pytest.mark.asyncio
    async def test_test_returns_true(self):
        adapter = LangChainAdapter()
        assert await adapter.test() is True

"""Tests for the generic OAP guardrail provider."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from aport_guardrails.providers.generic import OAPGuardrailProvider, _Reason, _ProviderResult, _to_result


class TestProviderResult:
    def test_allow_result(self):
        result = _ProviderResult(allow=True, reasons=[_Reason("oap.allowed", "ok")], policy_id="test.v1")
        assert result.allow is True
        assert result.reasons[0].code == "oap.allowed"
        assert result.policy_id == "test.v1"

    def test_deny_result(self):
        result = _ProviderResult(
            allow=False,
            reasons=[_Reason("oap.command_not_allowed", "blocked")],
            policy_id="system.command.execute.v1",
        )
        assert result.allow is False
        assert result.reasons[0].code == "oap.command_not_allowed"
        assert result.reasons[0].message == "blocked"


class TestToResult:
    def test_allow_decision(self):
        decision = {"allow": True, "reasons": [{"code": "oap.allowed", "message": "ok"}]}
        result = _to_result(decision, "test.v1")
        assert result.allow is True
        assert len(result.reasons) == 1
        assert result.reasons[0].code == "oap.allowed"

    def test_deny_decision(self):
        decision = {"allow": False, "reasons": [{"code": "oap.denied", "message": "nope"}]}
        result = _to_result(decision, "test.v1")
        assert result.allow is False
        assert result.reasons[0].message == "nope"

    def test_empty_reasons(self):
        decision = {"allow": True, "reasons": []}
        result = _to_result(decision, "test.v1")
        assert result.allow is True
        assert result.reasons == []

    def test_missing_reasons(self):
        decision = {"allow": False}
        result = _to_result(decision, "test.v1")
        assert result.allow is False
        assert result.reasons == []

    def test_missing_allow_defaults_false(self):
        decision = {}
        result = _to_result(decision, "test.v1")
        assert result.allow is False


class TestOAPGuardrailProvider:
    @patch("aport_guardrails.providers.generic.find_config_path", return_value=None)
    @patch("aport_guardrails.providers.generic.Evaluator")
    def test_constructor_passes_enforcement_override_to_evaluator(self, mock_evaluator_cls, mock_find):
        OAPGuardrailProvider(framework="deerflow", enforcement_mode="warn")

        mock_evaluator_cls.assert_called_once_with(
            None,
            framework="deerflow",
            enforcement_mode="warn",
            harness="deerflow",
        )

    @patch("aport_guardrails.providers.generic.find_config_path", return_value=None)
    @patch("aport_guardrails.providers.generic.Evaluator")
    def test_evaluate_calls_verify_sync(self, mock_evaluator_cls, mock_find):
        mock_evaluator = MagicMock()
        mock_evaluator.verify_sync.return_value = {"allow": True, "reasons": [{"code": "oap.allowed", "message": ""}]}
        mock_evaluator_cls.return_value = mock_evaluator

        provider = OAPGuardrailProvider(framework="deerflow")
        request = MagicMock()
        request.tool_name = "bash"
        request.tool_input = {"command": "ls"}
        request.agent_id = None

        result = provider.evaluate(request)
        assert result.allow is True
        mock_evaluator.verify_sync.assert_called_once()

    @patch("aport_guardrails.providers.generic.find_config_path", return_value=None)
    @patch("aport_guardrails.providers.generic.Evaluator")
    def test_evaluate_does_not_pass_agent_id(self, mock_evaluator_cls, mock_find):
        """Provider does NOT pass agent_id to evaluator -- the evaluator reads
        agent_id and passport_path from its own config file."""
        mock_evaluator = MagicMock()
        mock_evaluator.verify_sync.return_value = {"allow": True, "reasons": []}
        mock_evaluator_cls.return_value = mock_evaluator

        provider = OAPGuardrailProvider(framework="deerflow")
        request = MagicMock()
        request.tool_name = "bash"
        request.tool_input = {}
        request.agent_id = "ap_abc123"

        provider.evaluate(request)
        call_args = mock_evaluator.verify_sync.call_args
        # First arg (passport) should be empty -- evaluator uses its own config
        assert call_args[0][0] == {}

    @pytest.mark.asyncio
    @patch("aport_guardrails.providers.generic.find_config_path", return_value=None)
    @patch("aport_guardrails.providers.generic.Evaluator")
    async def test_aevaluate_calls_verify(self, mock_evaluator_cls, mock_find):
        mock_evaluator = MagicMock()
        mock_evaluator.verify = AsyncMock(return_value={"allow": False, "reasons": [{"code": "oap.denied", "message": "no"}]})
        mock_evaluator_cls.return_value = mock_evaluator

        provider = OAPGuardrailProvider(framework="deerflow")
        request = MagicMock()
        request.tool_name = "web_search"
        request.tool_input = {"query": "test"}
        request.agent_id = None

        result = await provider.aevaluate(request)
        assert result.allow is False
        assert result.reasons[0].code == "oap.denied"
        mock_evaluator.verify.assert_called_once()

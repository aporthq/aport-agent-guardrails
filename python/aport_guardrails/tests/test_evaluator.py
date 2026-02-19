"""Unit tests for aport_guardrails.core.evaluator (API policy-in-body, _is_full_policy_pack, _call_api_sync)."""

import json
from unittest.mock import patch, MagicMock

import pytest

from aport_guardrails.core.evaluator import (
    IN_BODY_PACK_ID,
    _is_full_policy_pack,
    _call_api_sync,
    Evaluator,
)


class TestIsFullPolicyPack:
    """_is_full_policy_pack identifies OAP policy packs for IN_BODY."""

    def test_true_when_id_and_requires_capabilities(self):
        assert _is_full_policy_pack({"id": "x.v1", "requires_capabilities": []}) is True
        assert _is_full_policy_pack({"id": "a", "requires_capabilities": ["c1"]}) is True

    def test_false_when_missing_id(self):
        assert _is_full_policy_pack({"requires_capabilities": []}) is False

    def test_false_when_missing_requires_capabilities(self):
        assert _is_full_policy_pack({"id": "x.v1"}) is False
        assert _is_full_policy_pack({"id": "x", "requires_capabilities": None}) is False

    def test_false_for_empty_or_non_dict(self):
        assert _is_full_policy_pack(None) is False
        assert _is_full_policy_pack({}) is False
        assert _is_full_policy_pack([]) is False


class TestCallApiSyncPolicyInBody:
    """_call_api_sync uses IN_BODY path and body.policy when policy_pack is provided."""

    @patch("aport_guardrails.core.evaluator.urlopen")
    def test_policy_in_body_url_and_body(self, urlopen_mock):
        resp = MagicMock()
        resp.read.return_value = json.dumps({"allow": True, "reasons": []}).encode()
        resp.__enter__ = MagicMock(return_value=resp)
        resp.__exit__ = MagicMock(return_value=False)
        urlopen_mock.return_value = resp

        policy_pack = {"id": "custom.policy.v1", "requires_capabilities": ["cap"]}
        _call_api_sync(
            "https://api.example.com",
            "system.command.execute.v1",
            {"tool": "exec.run"},
            agent_id="agent-1",
            policy_pack=policy_pack,
        )

        call_args = urlopen_mock.call_args[0][0]
        assert call_args.full_url.endswith(f"/api/verify/policy/{IN_BODY_PACK_ID}")
        body = json.loads(call_args.data.decode())
        assert body.get("policy") == policy_pack
        assert body["context"].get("agent_id") == "agent-1"

    @patch("aport_guardrails.core.evaluator.urlopen")
    def test_pack_id_in_path_when_no_policy_pack(self, urlopen_mock):
        resp = MagicMock()
        resp.read.return_value = json.dumps({"allow": True, "reasons": []}).encode()
        resp.__enter__ = MagicMock(return_value=resp)
        resp.__exit__ = MagicMock(return_value=False)
        urlopen_mock.return_value = resp

        _call_api_sync(
            "https://api.example.com",
            "system.command.execute.v1",
            {"tool": "exec.run"},
            agent_id="agent-1",
        )

        call_args = urlopen_mock.call_args[0][0]
        assert "/api/verify/policy/system.command.execute.v1" in call_args.full_url
        body = json.loads(call_args.data.decode())
        assert "policy" not in body


class TestEvaluatorVerifyPolicyInBody:
    """Evaluator.verify() passes full policy pack to API as policy_pack (IN_BODY)."""

    @pytest.mark.asyncio
    @patch("aport_guardrails.core.evaluator._call_api_sync")
    async def test_verify_with_full_policy_pack_calls_api_with_policy_pack(self, call_api_mock):
        call_api_mock.return_value = {"allow": True, "reasons": []}

        evaluator = Evaluator()
        evaluator._config = {
            "mode": "api",
            "api_url": "https://api.example.com",
            "agent_id": "agent-1",
        }

        full_policy = {"id": "custom.v1", "requires_capabilities": ["c1"]}
        await evaluator.verify(
            passport={"agent_id": "agent-1"},
            policy=full_policy,
            context={"tool": "run"},
        )

        call_api_mock.assert_called_once()
        kwargs = call_api_mock.call_args[1]
        assert kwargs.get("policy_pack") == full_policy
        assert kwargs.get("agent_id") == "agent-1"

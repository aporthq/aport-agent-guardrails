"""Unit tests for aport_guardrails.core.evaluator (API policy-in-body, _is_full_policy_pack, _call_api_sync)."""

import json
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from aport_guardrails.core.evaluator import (
    IN_BODY_PACK_ID,
    _is_full_policy_pack,
    _call_api_sync,
    _get_guardrail_script_path,
    _resolve_passport_path,
    _run_guardrail_sync,
    Evaluator,
)
from aport_guardrails.core.runtime_assets import install_runtime_tree


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
    def test_preserves_full_decision_metadata(self, urlopen_mock):
        resp = MagicMock()
        resp.read.return_value = json.dumps({
            "decision": {
                "decision_id": "dec-123",
                "policy_id": "system.command.execute.v1",
                "passport_id": "passport-123",
                "agent_id": "agent-123",
                "owner_id": "owner-123",
                "assurance_level": "L2",
                "allow": True,
                "reasons": [{"code": "oap.allowed", "message": "ok"}],
                "issued_at": "2026-04-12T00:00:00Z",
                "created_at": "2026-04-12T00:00:00Z",
                "expires_at": "2026-04-12T01:00:00Z",
                "expires_in": 3600,
                "passport_digest": "sha256:test",
                "signature": "ed25519:test",
                "kid": "oap:test:key"
            }
        }).encode()
        resp.__enter__ = MagicMock(return_value=resp)
        resp.__exit__ = MagicMock(return_value=False)
        urlopen_mock.return_value = resp

        decision = _call_api_sync(
            "https://api.example.com",
            "system.command.execute.v1",
            {"tool": "exec.run"},
            agent_id="agent-1",
        )

        assert decision["allow"] is True
        assert decision["decision_id"] == "dec-123"
        assert decision["agent_id"] == "agent-123"
        assert decision["created_at"] == "2026-04-12T00:00:00Z"
        assert decision["expires_in"] == 3600
        assert decision["signature"] == "ed25519:test"
        assert decision["passport_digest"] == "sha256:test"


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


class TestGuardrailScriptResolution:
    def test_prefers_framework_runtime_installed_under_config_dir(self, tmp_path: Path):
        config_dir = tmp_path / ".aport" / "crewai"
        runtime_dir = install_runtime_tree(config_dir)
        assert runtime_dir is not None

        config_path = config_dir / "config.yaml"
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("mode: local\n")

        script_path = _get_guardrail_script_path({}, config_path=config_path)
        assert script_path == str(runtime_dir / "bin" / "aport-guardrail.sh")


class TestPassportResolution:
    def test_prefers_passport_installed_under_config_dir(self, tmp_path: Path):
        config_dir = tmp_path / ".aport" / "crewai"
        passport_path = config_dir / "aport" / "passport.json"
        passport_path.parent.mkdir(parents=True, exist_ok=True)
        passport_path.write_text("{}")

        config_path = config_dir / "config.yaml"
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text("mode: local\n")

        resolved = _resolve_passport_path({}, config_path=config_path)

        assert resolved == str(passport_path)


class TestRunGuardrailSync:
    @patch("aport_guardrails.core.evaluator.subprocess.run")
    def test_preserves_local_decision_metadata(self, run_mock, tmp_path: Path):
        passport_path = tmp_path / "passport.json"
        passport_path.write_text("{}")
        decision_path = tmp_path / "decision.json"
        decision_path.write_text(json.dumps({
            "decision_id": "local-123",
            "policy_id": "system.command.execute.v1",
            "passport_id": "passport-123",
            "agent_id": "agent-123",
            "owner_id": "owner-123",
            "assurance_level": "L1",
            "allow": False,
            "reasons": [{"code": "oap.denied", "message": "blocked"}],
            "issued_at": "2026-04-12T00:00:00Z",
            "created_at": "2026-04-12T00:00:00Z",
            "expires_at": "2026-04-12T01:00:00Z",
            "expires_in": 3600,
            "passport_digest": "sha256:test",
            "signature": "local-unsigned",
            "kid": "oap:local:dev-key",
            "verification_mode": "local"
        }))
        run_mock.return_value = MagicMock(returncode=1)

        decision = _run_guardrail_sync(
            "/tmp/fake-guardrail.sh",
            str(passport_path),
            "exec.run",
            {"command": "sudo ls"},
        )

        assert decision["allow"] is False
        assert decision["decision_id"] == "local-123"
        assert decision["agent_id"] == "agent-123"
        assert decision["created_at"] == "2026-04-12T00:00:00Z"
        assert decision["expires_in"] == 3600
        assert decision["verification_mode"] == "local"

"""End-to-end tests for OAPGuardrailProvider as DeerFlow would use it.

Simulates the exact flow: DeerFlow's GuardrailMiddleware calls
provider.evaluate(request) where request has .tool_name, .tool_input,
.agent_id -- and the provider returns .allow, .reasons[0].code, .policy_id.

Tests cover:
1. Local mode with real passport + real bash evaluator
2. API mode with hosted agent_id (mocked API)
3. Tool-to-policy-pack mapping for DeerFlow tools
"""

from __future__ import annotations

import asyncio
import json
import os
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from aport_guardrails.providers.generic import OAPGuardrailProvider

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
FIXTURE_PASSPORT = REPO_ROOT / "tests" / "fixtures" / "passport.oap-v1.json"
GUARDRAIL_SCRIPT = REPO_ROOT / "bin" / "aport-guardrail.sh"


def _request(tool_name: str, tool_input: dict, agent_id: str | None = None):
    """Simulates what DeerFlow's GuardrailMiddleware._build_request() creates."""
    return SimpleNamespace(tool_name=tool_name, tool_input=tool_input, agent_id=agent_id)


@pytest.fixture
def oap_provider():
    """Real OAPGuardrailProvider with local passport and bash evaluator."""
    if not FIXTURE_PASSPORT.exists():
        pytest.skip("Fixture passport not found")
    if not GUARDRAIL_SCRIPT.exists():
        pytest.skip("Guardrail script not found")

    test_dir = Path(tempfile.mkdtemp(prefix="aport-", dir="/tmp")) / "test-e2e"
    test_dir.mkdir(parents=True, exist_ok=True)
    passport_dest = test_dir / "aport" / "passport.json"
    passport_dest.parent.mkdir(parents=True, exist_ok=True)
    passport_dest.write_text(FIXTURE_PASSPORT.read_text())

    config_path = test_dir / "config.yaml"
    config_path.write_text(
        f"mode: local\n"
        f"passport_path: {passport_dest}\n"
        f"guardrail_script: {GUARDRAIL_SCRIPT}\n"
        f"audit_log: false\n"
    )

    yield OAPGuardrailProvider(framework="test", config_path=str(config_path))

    import shutil
    shutil.rmtree(test_dir.parent, ignore_errors=True)


# -- Local mode: real passport, real bash evaluator --


class TestLocalModeAllow:
    """DeerFlow tool calls that the passport allows."""

    def test_bash_npm_install(self, oap_provider):
        r = oap_provider.evaluate(_request("bash", {"command": "npm install"}))
        assert r.allow is True
        assert r.policy_id == "system.command.execute.v1"

    def test_bash_git_status(self, oap_provider):
        r = oap_provider.evaluate(_request("bash", {"command": "git status"}))
        assert r.allow is True

    def test_bash_ls(self, oap_provider):
        r = oap_provider.evaluate(_request("bash", {"command": "ls -la"}))
        assert r.allow is True

    def test_git_create_pr(self, oap_provider):
        r = oap_provider.evaluate(_request("git.create_pr", {"repo": "aporthq/test", "files_changed": 5}))
        assert r.allow is True
        assert r.policy_id == "code.repository.merge.v1"


class TestLocalModeDeny:
    """DeerFlow tool calls that the passport blocks."""

    def test_bash_blocked_pattern_sudo(self, oap_provider):
        r = oap_provider.evaluate(_request("bash", {"command": "sudo ls"}))
        assert r.allow is False
        # "sudo" is not in allowed_commands, so it gets oap.command_not_allowed
        # OR it matches blocked_patterns, getting oap.blocked_pattern
        assert any("not_allowed" in x.code or "blocked" in x.code for x in r.reasons)

    def test_bash_blocked_pattern_rm_rf(self, oap_provider):
        r = oap_provider.evaluate(_request("bash", {"command": "rm -rf /tmp"}))
        assert r.allow is False

    def test_pr_exceeds_limit(self, oap_provider):
        r = oap_provider.evaluate(_request("git.create_pr", {"repo": "aporthq/test", "files_changed": 600}))
        assert r.allow is False

    def test_suspended_passport(self):
        if not FIXTURE_PASSPORT.exists():
            pytest.skip("Fixture passport not found")

        test_dir = Path(tempfile.mkdtemp(prefix="aport-", dir="/tmp")) / "test-suspended"
        test_dir.mkdir(parents=True, exist_ok=True)
        passport_data = json.loads(FIXTURE_PASSPORT.read_text())
        passport_data["status"] = "suspended"
        passport_dest = test_dir / "aport" / "passport.json"
        passport_dest.parent.mkdir(parents=True, exist_ok=True)
        passport_dest.write_text(json.dumps(passport_data))
        config_path = test_dir / "config.yaml"
        config_path.write_text(
            f"mode: local\npassport_path: {passport_dest}\n"
            f"guardrail_script: {GUARDRAIL_SCRIPT}\naudit_log: false\n"
        )
        try:
            p = OAPGuardrailProvider(framework="test", config_path=str(config_path))
            r = p.evaluate(_request("bash", {"command": "echo hello"}))
            assert r.allow is False
        finally:
            import shutil
            shutil.rmtree(test_dir.parent, ignore_errors=True)


class TestLocalModeAsync:
    """Async path (DeerFlow's awrap_tool_call)."""

    def test_aevaluate_allow(self, oap_provider):
        r = asyncio.run(oap_provider.aevaluate(_request("bash", {"command": "ls"})))
        assert r.allow is True

    def test_aevaluate_deny(self, oap_provider):
        r = asyncio.run(oap_provider.aevaluate(_request("bash", {"command": "sudo ls"})))
        assert r.allow is False


# -- API mode: hosted agent_id (mocked) --


class TestApiMode:
    """DeerFlow with passport: ap_xxx in config.yaml (hosted mode)."""

    @patch("aport_guardrails.providers.generic.find_config_path", return_value=None)
    @patch("aport_guardrails.providers.generic.Evaluator")
    def test_evaluator_uses_own_config(self, mock_eval_cls, mock_find):
        """Provider delegates identity resolution to the evaluator's config,
        not via request.agent_id. The evaluator reads agent_id or passport_path
        from ~/.aport/<framework>/config.yaml."""
        mock_eval = MagicMock()
        mock_eval.verify_sync.return_value = {"allow": True, "reasons": [{"code": "oap.allowed", "message": "ok"}]}
        mock_eval_cls.return_value = mock_eval

        p = OAPGuardrailProvider(framework="deerflow")
        r = p.evaluate(_request("bash", {"command": "ls"}, agent_id="ap_fa2f6d53bb5b4c98b9af0124285b6e0f"))

        assert r.allow is True
        # Passport dict should be empty -- evaluator handles identity from its config
        call_args = mock_eval.verify_sync.call_args[0]
        assert call_args[0] == {}

    @patch("aport_guardrails.providers.generic.find_config_path", return_value=None)
    @patch("aport_guardrails.providers.generic.Evaluator")
    def test_api_deny(self, mock_eval_cls, mock_find):
        mock_eval = MagicMock()
        mock_eval.verify_sync.return_value = {
            "allow": False,
            "reasons": [{"code": "oap.command_not_allowed", "message": "blocked by policy"}],
        }
        mock_eval_cls.return_value = mock_eval

        p = OAPGuardrailProvider(framework="deerflow")
        r = p.evaluate(_request("bash", {"command": "bad"}, agent_id="ap_test"))
        assert r.allow is False
        assert r.reasons[0].code == "oap.command_not_allowed"


# -- DeerFlow tool name to OAP policy pack mapping --


class TestDeerFlowToolMapping:
    """Verify DeerFlow tool names map to correct OAP policy packs."""

    @patch("aport_guardrails.providers.generic.find_config_path", return_value=None)
    @patch("aport_guardrails.providers.generic.Evaluator")
    def _check(self, tool, expected_pack, mock_eval_cls, mock_find):
        mock_eval = MagicMock()
        mock_eval.verify_sync.return_value = {"allow": True, "reasons": []}
        mock_eval_cls.return_value = mock_eval
        p = OAPGuardrailProvider(framework="deerflow")
        r = p.evaluate(_request(tool, {}))
        assert r.policy_id == expected_pack

    def test_bash(self):
        self._check("bash", "system.command.execute.v1")

    def test_web_search(self):
        self._check("web_search", "web.fetch.v1")

    def test_read_file(self):
        self._check("read_file", "data.file.read.v1")

    def test_git(self):
        self._check("git.create_pr", "code.repository.merge.v1")

    def test_mcp(self):
        self._check("mcp.github.issues", "mcp.tool.execute.v1")

    def test_message(self):
        self._check("messaging.send", "messaging.message.send.v1")

    def test_write_file(self):
        self._check("write_file", "data.file.write.v1")

    def test_str_replace(self):
        self._check("str_replace", "data.file.write.v1")

    def test_present_file(self):
        self._check("present_file", "data.file.read.v1")

    def test_view_image(self):
        self._check("view_image", "data.file.read.v1")

    def test_ls(self):
        self._check("ls", "data.file.read.v1")

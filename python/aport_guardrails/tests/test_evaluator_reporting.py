"""Real sync/async evaluator lifecycle: reporting work happens only for enrolled installations."""

import json
import os
import shutil
import subprocess
from pathlib import Path
from unittest.mock import patch

import pytest

from aport_guardrails.core import installation_reporting as reporting
from aport_guardrails.core.evaluator import Evaluator, _ReportingDecision

from .test_installation_reporting import enroll

API_DECISION = {"allow": False, "decision_id": "decision_fixture", "reasons": [{"code": "oap.denied", "message": "no"}]}
CONTEXT = {"tool": "exec", "command": "PRIVATE_TOOL_INPUT"}


def hosted_config(config_dir: Path, **extra) -> Path:
    config_dir.mkdir(parents=True, exist_ok=True)
    config_path = config_dir / "config.yaml"
    lines = ["mode: api", "agent_id: ap_fixture", "api_url: https://127.0.0.1:1", f"audit_log: {config_dir / 'audit.log'}"]
    lines += [f"{key}: {value}" for key, value in extra.items()]
    config_path.write_text("\n".join(lines) + "\n")
    return config_path


@pytest.fixture
def spawns(monkeypatch):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append({"argv": list(argv), "env": dict(kwargs.get("env") or {}), "input": kwargs.get("input")})
        return subprocess.CompletedProcess(argv, 0)

    monkeypatch.setattr(reporting.subprocess, "run", fake_run)
    return calls


@pytest.fixture(autouse=True)
def isolated_environment(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.delenv("APORT_AGENT_ID", raising=False)
    monkeypatch.delenv("APORT_REPORTING_DISABLED", raising=False)
    monkeypatch.delenv("OPENCLAW_PASSPORT_FILE", raising=False)
    monkeypatch.delenv("APORT_AUDIT_LOG", raising=False)


def run_lifecycle(evaluator: Evaluator, run_id: str, *, use_async: bool):
    with patch("aport_guardrails.core.evaluator._call_api_sync", return_value=dict(API_DECISION)):
        if use_async:
            import asyncio
            decision = asyncio.run(evaluator.verify({}, {}, dict(CONTEXT)))
        else:
            decision = evaluator.verify_sync({}, {}, dict(CONTEXT))
    evaluator.track_tool_call(run_id, decision)
    evaluator.complete_tool_call(run_id)
    return decision


def audit_entries(config_dir: Path):
    log = config_dir / "audit.log"
    if not log.exists():
        return []
    return [line for line in log.read_text().splitlines() if line.strip()]


@pytest.mark.parametrize("use_async", [False, True], ids=["sync", "async"])
class TestUnenrolledHostedLifecycle:
    def test_no_binding_means_no_subprocess_state_or_correlation(self, tmp_path, spawns, use_async):
        config_dir = tmp_path / "config"
        config_path = hosted_config(config_dir)
        evaluator = Evaluator(config_path)

        decision = run_lifecycle(evaluator, "run_1", use_async=use_async)

        assert spawns == []
        assert decision == API_DECISION
        assert not isinstance(decision, _ReportingDecision)
        assert evaluator._reporting_calls == {}
        assert sorted(p.name for p in config_dir.iterdir()) == ["audit.log", "config.yaml"]
        entries = audit_entries(config_dir)
        assert len(entries) == 1
        assert "tool=exec allow=false policy=system.command.execute.v1 code=oap.denied agent_id=ap_fixture" in entries[0]

    def test_disabled_reporting_means_no_subprocess_even_when_enrolled(self, tmp_path, spawns, monkeypatch, use_async):
        config_dir = tmp_path / "config"
        config_path = hosted_config(config_dir)
        enroll(config_dir)
        monkeypatch.setenv("APORT_REPORTING_DISABLED", "1")

        decision = run_lifecycle(Evaluator(config_path), "run_1", use_async=use_async)

        assert spawns == []
        assert decision == API_DECISION
        assert not (config_dir / ".aport-reporting").exists()

    def test_local_mode_never_reports(self, tmp_path, spawns, use_async):
        config_dir = tmp_path / "config"
        config_dir.mkdir()
        config_path = config_dir / "config.yaml"
        config_path.write_text("mode: local\nfail_open_when_missing_config: true\n")
        enroll(config_dir)
        evaluator = Evaluator(config_path)

        if use_async:
            import asyncio
            decision = asyncio.run(evaluator.verify({}, {}, dict(CONTEXT)))
        else:
            decision = evaluator.verify_sync({}, {}, dict(CONTEXT))
        evaluator.track_tool_call("run_1", decision)
        evaluator.complete_tool_call("run_1")

        assert spawns == []
        assert decision.get("allow") is True
        assert evaluator._reporting_calls == {}


@pytest.mark.parametrize("use_async", [False, True], ids=["sync", "async"])
class TestEnrolledHostedLifecycle:
    def test_enrolled_lifecycle_reports_through_the_shared_cli(self, tmp_path, spawns, use_async):
        config_dir = tmp_path / "config"
        config_path = hosted_config(config_dir, enforcement_mode="warn")
        enroll(config_dir)
        evaluator = Evaluator(config_path)

        decision = run_lifecycle(evaluator, "run_1", use_async=use_async)

        assert [call["argv"][-1] for call in spawns] == ["decision", "remember", "post"]
        assert decision == API_DECISION
        assert isinstance(decision, _ReportingDecision)
        for call in spawns:
            assert call["env"]["APORT_AGENT_ID"] == "ap_fixture"
            assert call["env"]["APORT_ENFORCEMENT_MODE"] == "warn"
            assert call["env"]["APORT_CONFIG_DIR"] == str(config_dir)
            assert call["env"]["APORT_API_URL"] == "https://127.0.0.1:1"
            assert "PRIVATE_TOOL_INPUT" not in json.dumps(call)
        assert json.loads(spawns[1]["input"])["decision_id"] == "decision_fixture"

    def test_later_enrollment_is_seen_without_a_new_evaluator(self, tmp_path, spawns, use_async):
        config_dir = tmp_path / "config"
        config_path = hosted_config(config_dir)
        evaluator = Evaluator(config_path)

        run_lifecycle(evaluator, "run_before", use_async=use_async)
        assert spawns == []

        enroll(config_dir)
        run_lifecycle(evaluator, "run_after", use_async=use_async)
        assert [call["argv"][-1] for call in spawns] == ["decision", "remember", "post"]

    def test_removed_state_stops_completion_without_recreating_it(self, tmp_path, spawns, use_async):
        config_dir = tmp_path / "config"
        config_path = hosted_config(config_dir)
        enroll(config_dir)
        evaluator = Evaluator(config_path)

        with patch("aport_guardrails.core.evaluator._call_api_sync", return_value=dict(API_DECISION)):
            if use_async:
                import asyncio
                decision = asyncio.run(evaluator.verify({}, {}, dict(CONTEXT)))
            else:
                decision = evaluator.verify_sync({}, {}, dict(CONTEXT))
        assert [call["argv"][-1] for call in spawns] == ["decision"]

        shutil.rmtree(config_dir / "aport")
        evaluator.track_tool_call("run_1", decision)
        evaluator.complete_tool_call("run_1")

        assert [call["argv"][-1] for call in spawns] == ["decision"]
        assert not (config_dir / "aport").exists()
        assert not (config_dir / ".aport-reporting").exists()

    def test_completion_keeps_the_evaluated_identity_and_mode(self, tmp_path, spawns, monkeypatch, use_async):
        config_dir = tmp_path / "config"
        config_path = hosted_config(config_dir, enforcement_mode="warn")
        enroll(config_dir)
        evaluator = Evaluator(config_path)

        with patch("aport_guardrails.core.evaluator._call_api_sync", return_value=dict(API_DECISION)):
            if use_async:
                import asyncio
                decision = asyncio.run(evaluator.verify({}, {}, dict(CONTEXT)))
            else:
                decision = evaluator.verify_sync({}, {}, dict(CONTEXT))
        monkeypatch.setenv("APORT_AGENT_ID", "ap_other")
        config_path.write_text("mode: api\nagent_id: ap_other\napi_url: https://127.0.0.1:2\nenforcement_mode: enforce\n")
        evaluator.track_tool_call("run_1", decision)
        evaluator.complete_tool_call("run_1")
        evaluator.complete_tool_call("run_1")

        assert [call["argv"][-1] for call in spawns] == ["decision", "remember", "post"]
        for call in spawns:
            assert call["env"]["APORT_AGENT_ID"] == "ap_fixture"
            assert call["env"]["APORT_ENFORCEMENT_MODE"] == "warn"
            assert call["env"]["APORT_API_URL"] == "https://127.0.0.1:1"

    def test_ambiguous_correlation_never_posts(self, tmp_path, spawns, use_async):
        config_dir = tmp_path / "config"
        config_path = hosted_config(config_dir)
        enroll(config_dir)
        evaluator = Evaluator(config_path)

        with patch("aport_guardrails.core.evaluator._call_api_sync", return_value=dict(API_DECISION)):
            if use_async:
                import asyncio
                decision = asyncio.run(evaluator.verify({}, {}, dict(CONTEXT)))
            else:
                decision = evaluator.verify_sync({}, {}, dict(CONTEXT))
        evaluator.track_tool_call("run_1", decision)
        evaluator.track_tool_call("run_1", {"allow": True})
        evaluator.complete_tool_call("run_1")
        evaluator.complete_tool_call("never_tracked")

        assert [call["argv"][-1] for call in spawns] == ["decision", "remember"]
        assert len(evaluator._reporting_calls) == 1

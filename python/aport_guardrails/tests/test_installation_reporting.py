"""Optional reporting eligibility: cheap presence check, no subprocess work when unenrolled."""

import json
import os
import subprocess
from pathlib import Path

import pytest

from aport_guardrails.core import installation_reporting as reporting

BINDING_NAME = "installation-v1-" + "a" * 64 + ".json"
BINDING = {"installation_id": "ai_fixture", "reporter_token": "air1.fixture.fixture"}


def enroll(config_dir: Path) -> Path:
    state_dir = config_dir / "aport"
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    binding = state_dir / BINDING_NAME
    binding.write_text(json.dumps(BINDING) + "\n")
    binding.chmod(0o600)
    return binding


def hosted_config(config_dir: Path) -> Path:
    config_dir.mkdir(parents=True, exist_ok=True)
    config_path = config_dir / "config.yaml"
    config_path.write_text("mode: api\nagent_id: ap_fixture\napi_url: https://127.0.0.1:1\n")
    return config_path


@pytest.fixture
def spawns(monkeypatch):
    """Deterministic subprocess counter: every reporter launch is recorded, none runs."""
    calls = []

    def fake_run(argv, **kwargs):
        calls.append({"argv": list(argv), "env": kwargs.get("env"), "input": kwargs.get("input")})
        return subprocess.CompletedProcess(argv, 0)

    monkeypatch.setattr(reporting.subprocess, "run", fake_run)
    return calls


class TestReportingStatePresent:
    def test_absent_state_is_not_present_and_nothing_is_created(self, tmp_path):
        assert reporting.reporting_state_present(tmp_path) is False
        assert list(tmp_path.iterdir()) == []

    def test_none_or_empty_config_dir(self):
        assert reporting.reporting_state_present(None) is False
        assert reporting.reporting_state_present("") is False

    def test_reporting_directory_is_present(self, tmp_path):
        (tmp_path / ".aport-reporting").mkdir(mode=0o700)
        assert reporting.reporting_state_present(tmp_path) is True

    def test_binding_file_is_present(self, tmp_path):
        enroll(tmp_path)
        assert reporting.reporting_state_present(tmp_path) is True

    def test_symlinked_reporting_directory_is_not_followed(self, tmp_path):
        target = tmp_path / "victim"
        target.mkdir(mode=0o700)
        (tmp_path / ".aport-reporting").symlink_to(target)
        assert reporting.reporting_state_present(tmp_path) is False

    def test_symlinked_state_directory_is_not_followed(self, tmp_path):
        other = tmp_path / "other"
        enroll(other)
        config_dir = tmp_path / "config"
        config_dir.mkdir()
        (config_dir / "aport").symlink_to(other / "aport")
        assert reporting.reporting_state_present(config_dir) is False

    def test_symlinked_binding_file_is_not_followed(self, tmp_path):
        real = enroll(tmp_path / "other")
        config_dir = tmp_path / "config"
        (config_dir / "aport").mkdir(parents=True, mode=0o700)
        (config_dir / "aport" / BINDING_NAME).symlink_to(real)
        assert reporting.reporting_state_present(config_dir) is False

    def test_nested_binding_is_not_found_recursively(self, tmp_path):
        enroll(tmp_path / "aport" / "nested")
        assert reporting.reporting_state_present(tmp_path) is False

    @pytest.mark.parametrize("name", ["installation-v2-" + "a" * 64 + ".json", "installation-v1-abc.json",
                                      "installation-v1-" + "a" * 64, "installation-v1-" + "A" * 64 + ".json"])
    def test_unrelated_state_files_are_ignored(self, tmp_path, name):
        state_dir = tmp_path / "aport"
        state_dir.mkdir(mode=0o700)
        (state_dir / name).write_text("{}")
        assert reporting.reporting_state_present(tmp_path) is False

    @pytest.mark.skipif(os.geteuid() == 0, reason="root bypasses directory permissions")
    def test_inaccessible_state_directory_is_not_present(self, tmp_path):
        enroll(tmp_path)
        (tmp_path / "aport").chmod(0)
        try:
            assert reporting.reporting_state_present(tmp_path) is False
        finally:
            (tmp_path / "aport").chmod(0o700)

    def test_scan_is_bounded(self, tmp_path, monkeypatch):
        state_dir = tmp_path / "aport"
        state_dir.mkdir(mode=0o700)
        for index in range(reporting._MAX_STATE_ENTRIES + 100):
            (state_dir / f"unrelated-{index}").write_text("")
        consumed = []
        real_scandir = os.scandir

        class Counting:
            def __init__(self, path):
                self.inner = real_scandir(path)

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                self.inner.close()

            def __iter__(self):
                return self

            def __next__(self):
                consumed.append(1)
                return next(self.inner)

        monkeypatch.setattr(reporting.os, "scandir", Counting)
        assert reporting.reporting_state_present(tmp_path) is False
        assert len(consumed) <= reporting._MAX_STATE_ENTRIES + 1

    def test_never_shells_out(self, tmp_path, monkeypatch):
        enroll(tmp_path)

        def forbidden(*args, **kwargs):
            raise AssertionError("presence check must not launch processes")

        monkeypatch.setattr(reporting.subprocess, "run", forbidden)
        monkeypatch.setattr(reporting.subprocess, "Popen", forbidden)
        assert reporting.reporting_state_present(tmp_path) is True


class TestReportingEligible:
    def test_local_mode_is_never_eligible(self, tmp_path):
        config_path = hosted_config(tmp_path)
        enroll(tmp_path)
        assert reporting.reporting_eligible({"mode": "local"}, config_path) is False
        assert reporting.reporting_eligible({}, config_path) is False
        assert reporting.reporting_eligible(None, config_path) is False

    def test_disabled_is_never_eligible(self, tmp_path, monkeypatch):
        config_path = hosted_config(tmp_path)
        enroll(tmp_path)
        monkeypatch.setenv("APORT_REPORTING_DISABLED", "1")
        assert reporting.reporting_eligible({"mode": "api"}, config_path) is False
        monkeypatch.setenv("APORT_INSTALLATION_HANDOFF_FILE", str(tmp_path / "handoff.json"))
        assert reporting.reporting_eligible({"mode": "api"}, config_path, allow_handoff=True) is False

    def test_hosted_without_state_is_not_eligible(self, tmp_path):
        config_path = hosted_config(tmp_path)
        assert reporting.reporting_eligible({"mode": "api"}, config_path) is False
        assert reporting.reporting_eligible({"mode": "api"}, None) is False

    def test_hosted_with_state_is_eligible(self, tmp_path):
        config_path = hosted_config(tmp_path)
        enroll(tmp_path)
        assert reporting.reporting_eligible({"mode": "api"}, config_path) is True

    def test_handoff_only_counts_for_setup(self, tmp_path, monkeypatch):
        config_path = hosted_config(tmp_path)
        monkeypatch.setenv("APORT_INSTALLATION_HANDOFF_FILE", str(tmp_path / "handoff.json"))
        assert reporting.reporting_eligible({"mode": "api"}, config_path) is False
        assert reporting.reporting_eligible({"mode": "api"}, config_path, allow_handoff=True) is True


class TestProducers:
    def test_unenrolled_producers_launch_nothing(self, tmp_path, spawns, capsys):
        config_path = hosted_config(tmp_path)
        config = {"mode": "api", "agent_id": "ap_fixture", "api_url": "https://127.0.0.1:1"}
        assert reporting.report_decision(config, config_path, "langchain", {"decision_id": "d1"}, "enforce", "ap_fixture") is False
        reporting.report_completion(config, config_path, "langchain", "run", "enforce", {"decision_id": "d1", "allow": True}, "ap_fixture")
        reporting.report_completion(config, config_path, "langchain", "run", "enforce", None, "ap_fixture")
        reporting.setup_reporting(config, config_path, "langchain")
        assert spawns == []
        assert "Reporting" not in capsys.readouterr().out
        assert not (tmp_path / ".aport-reporting").exists()
        assert not (tmp_path / "aport").exists()

    def test_disabled_producers_launch_nothing(self, tmp_path, spawns, monkeypatch):
        config_path = hosted_config(tmp_path)
        enroll(tmp_path)
        monkeypatch.setenv("APORT_REPORTING_DISABLED", "1")
        config = {"mode": "api", "agent_id": "ap_fixture"}
        assert reporting.report_decision(config, config_path, "langchain", {"decision_id": "d1"}, "enforce", "ap_fixture") is False
        reporting.report_completion(config, config_path, "langchain", "run", "enforce", None, "ap_fixture")
        reporting.setup_reporting(config, config_path, "langchain")
        assert spawns == []

    def test_enrolled_producers_use_the_shared_cli(self, tmp_path, spawns):
        config_path = hosted_config(tmp_path)
        enroll(tmp_path)
        config = {"mode": "api", "agent_id": "ap_fixture", "api_url": "https://127.0.0.1:1"}
        assert reporting.report_decision(config, config_path, "langchain", {"decision_id": "d1"}, "warn", "ap_fixture") is True
        reporting.report_completion(config, config_path, "langchain", "run", "warn", {"decision_id": "d1", "allow": False}, "ap_fixture")
        reporting.report_completion(config, config_path, "langchain", "run", "warn", None, "ap_fixture")
        assert [call["argv"][-1] for call in spawns] == ["decision", "remember", "post"]
        assert all(call["argv"][1].endswith("src/installation-reporting/cli.js") for call in spawns)
        assert all(call["env"]["APORT_AGENT_ID"] == "ap_fixture" for call in spawns)
        assert all(call["env"]["APORT_ENFORCEMENT_MODE"] == "warn" for call in spawns)
        assert all(call["env"]["APORT_CONFIG_DIR"] == str(tmp_path) for call in spawns)
        assert json.loads(spawns[0]["input"]) == {"decision_id": "d1"}
        assert sorted(json.loads(spawns[1]["input"])) == ["allow", "call_key", "decision_id"]
        assert list(json.loads(spawns[2]["input"])) == ["call_key"]

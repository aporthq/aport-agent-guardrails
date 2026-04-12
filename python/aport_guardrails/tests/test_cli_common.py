from pathlib import Path
from unittest.mock import MagicMock, patch

from aport_guardrails.core.cli_common import run_wizard


@patch("aport_guardrails.core.cli_common.subprocess.run")
def test_run_wizard_prefers_runtime_script_over_npx(
    mock_run: MagicMock,
    tmp_path,
    monkeypatch,
):
    mock_run.return_value.returncode = 0
    script_path = tmp_path / "aport-create-passport.sh"
    script_path.write_text("#!/bin/sh\nexit 0\n")
    monkeypatch.delenv("CI", raising=False)
    monkeypatch.delenv("APORT_NONINTERACTIVE", raising=False)

    with patch("aport_guardrails.core.cli_common.resolve_runtime_script", return_value=script_path):
        ok = run_wizard("crewai", extra_args=["--integration-mode=native"])

    assert ok is True
    cmd = mock_run.call_args[0][0]
    assert cmd == [
        str(script_path),
        "--framework=crewai",
        "--integration-mode=native",
    ]


@patch("aport_guardrails.core.cli_common.resolve_runtime_script", return_value=None)
@patch("aport_guardrails.core.cli_common.subprocess.run")
def test_run_wizard_forwards_native_integration_mode_to_npx(
    mock_run: MagicMock,
    _mock_script: MagicMock,
    monkeypatch,
):
    mock_run.return_value.returncode = 0
    monkeypatch.delenv("CI", raising=False)
    monkeypatch.delenv("APORT_NONINTERACTIVE", raising=False)

    ok = run_wizard("crewai", extra_args=["--integration-mode=native"])

    assert ok is True
    cmd = mock_run.call_args[0][0]
    assert cmd == [
        "npx",
        "--yes",
        "@aporthq/aport-agent-guardrails",
        "--framework=crewai",
        "--integration-mode=native",
    ]


@patch("aport_guardrails.core.cli_common.resolve_runtime_script", return_value=None)
@patch("aport_guardrails.core.cli_common.subprocess.run")
def test_run_wizard_adds_non_interactive_flag_in_ci(
    mock_run: MagicMock,
    _mock_script: MagicMock,
    monkeypatch,
):
    mock_run.return_value.returncode = 0
    monkeypatch.setenv("CI", "1")
    monkeypatch.delenv("APORT_NONINTERACTIVE", raising=False)

    ok = run_wizard("crewai", extra_args=["--integration-mode=native"])

    assert ok is True
    cmd = mock_run.call_args[0][0]
    assert cmd == [
        "npx",
        "--yes",
        "@aporthq/aport-agent-guardrails",
        "--framework=crewai",
        "--integration-mode=native",
        "--non-interactive",
    ]

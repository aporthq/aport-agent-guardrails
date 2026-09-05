"""Tests for safe, actionable display helpers."""

from aport_guardrails.core.display import format_policy_warning, policy_reference, sanitize_display


def test_sanitize_display_redacts_tokens_and_control_text():
    output = sanitize_display("tool\n::error::fake apk_secret github_pat_secret")

    assert "\n::error::" not in output
    assert "apk_secret" not in output
    assert "github_pat_secret" not in output
    assert "[REDACTED_APORT_KEY]" in output
    assert "[REDACTED_GITHUB_TOKEN]" in output


def test_policy_reference_prefers_hosted_agent_id(monkeypatch):
    monkeypatch.setenv("APORT_AGENT_ID", "ap_1234567890abcdef1234567890abcdef")

    assert (
        policy_reference(framework="langchain")
        == "Review or update the hosted passport: https://aport.io/passports?details=ap_1234567890abcdef1234567890abcdef"
    )


def test_policy_reference_uses_local_passport_file(monkeypatch):
    monkeypatch.delenv("APORT_AGENT_ID", raising=False)
    monkeypatch.setenv("APORT_PASSPORT_FILE", "/tmp/aport/passport.json")

    assert policy_reference(framework="crewai") == "Review or update the local passport file: /tmp/aport/passport.json"


def test_format_policy_warning_includes_actionable_review(monkeypatch):
    monkeypatch.setenv("APORT_AGENT_ID", "ap_abcdefabcdefabcdefabcdefabcdef12")

    output = format_policy_warning(
        policy="system.command.execute.v1",
        reason_code="oap.command_not_allowed",
        reason_message="Command not in allowlist",
        tool_name="run_command",
        framework="langchain",
    )

    assert "policy would have denied this tool call" in output
    assert "Tool: run_command." in output
    assert "Policy: system.command.execute.v1." in output
    assert "Reason: oap.command_not_allowed." in output
    assert "Detail: Command not in allowlist." in output
    assert "Review: Review or update the hosted passport:" in output

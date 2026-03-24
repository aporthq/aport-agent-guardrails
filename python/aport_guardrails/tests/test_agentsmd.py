"""Tests for aport_guardrails.core.agentsmd — AGENTS.md enforcement block parser."""

import os
import textwrap
from pathlib import Path

import pytest

from aport_guardrails.core.agentsmd import resolve_agentsmd_enforcement


@pytest.fixture
def repo_dir(tmp_path):
    """Create a temp dir simulating a repo root."""
    return tmp_path


def _write_agentsmd(repo: Path, content: str, name: str = "AGENTS.md"):
    (repo / name).write_text(textwrap.dedent(content))


class TestLocalPassport:
    def test_local_passport(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: aport
              passport: ./.aport/passport.json
            ---

            # Instructions
        """)
        result = resolve_agentsmd_enforcement(repo_dir)
        assert result is not None
        assert result["engine"] == "aport"
        assert result["passport"] == str((repo_dir / ".aport" / "passport.json").resolve())
        assert "agent_id" not in result


class TestHostedAgentId:
    def test_hosted_agent_id(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: aport
              agent_id: ap_fa2f6d53abcdef1234567890abcdef12
            ---
        """)
        result = resolve_agentsmd_enforcement(repo_dir)
        assert result is not None
        assert result["engine"] == "aport"
        assert result["agent_id"] == "ap_fa2f6d53abcdef1234567890abcdef12"
        assert "passport" not in result


class TestBothPassportAndAgentId:
    def test_both_present(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: aport
              passport: ./.aport/passport.json
              agent_id: ap_abc123
            ---
        """)
        result = resolve_agentsmd_enforcement(repo_dir)
        assert result["engine"] == "aport"
        assert result["agent_id"] == "ap_abc123"
        assert "passport" in result


class TestNoEnforcement:
    def test_no_enforcement_block(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            version: 1.0
            ---

            # Instructions
        """)
        assert resolve_agentsmd_enforcement(repo_dir) is None

    def test_no_agentsmd(self, repo_dir):
        assert resolve_agentsmd_enforcement(repo_dir) is None

    def test_no_frontmatter(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            # Instructions
            No frontmatter here.
        """)
        assert resolve_agentsmd_enforcement(repo_dir) is None

    def test_empty_enforcement(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
            other: stuff
            ---
        """)
        assert resolve_agentsmd_enforcement(repo_dir) is None


class TestDotfileVariant:
    def test_dotfile_agents_md(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: aport
              agent_id: ap_lowercase_variant
            ---
        """, name=".agents.md")
        result = resolve_agentsmd_enforcement(repo_dir)
        assert result is not None
        assert result["agent_id"] == "ap_lowercase_variant"

    def test_uppercase_takes_precedence(self, repo_dir):
        """AGENTS.md is checked before .agents.md."""
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: aport
              agent_id: ap_uppercase
            ---
        """, name="AGENTS.md")
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: aport
              agent_id: ap_lowercase
            ---
        """, name=".agents.md")
        result = resolve_agentsmd_enforcement(repo_dir)
        assert result["agent_id"] == "ap_uppercase"


class TestDirectoryWalkUp:
    def test_walk_up(self, repo_dir):
        subdir = repo_dir / "src" / "components"
        subdir.mkdir(parents=True)
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: aport
              passport: ./.aport/passport.json
            ---
        """)
        result = resolve_agentsmd_enforcement(subdir)
        assert result is not None
        assert result["engine"] == "aport"
        assert result["passport"] == str((repo_dir / ".aport" / "passport.json").resolve())


class TestInlineComments:
    def test_comments_stripped(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: aport  # the engine
              agent_id: ap_test123  # hosted mode
            ---
        """)
        result = resolve_agentsmd_enforcement(repo_dir)
        assert result["engine"] == "aport"
        assert result["agent_id"] == "ap_test123"


class TestMixedFrontmatter:
    def test_enforcement_alongside_other_blocks(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            version: 1.0
            permissions:
              files:
                read: allow
                delete: deny
            enforcement:
              engine: aport
              passport: ./policy/passport.json
            other:
              key: value
            ---

            # Instructions
        """)
        result = resolve_agentsmd_enforcement(repo_dir)
        assert result["engine"] == "aport"
        assert result["passport"] == str((repo_dir / "policy" / "passport.json").resolve())


class TestQuotedValues:
    def test_quoted_strings(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: "aport"
              agent_id: 'ap_quoted123'
            ---
        """)
        result = resolve_agentsmd_enforcement(repo_dir)
        assert result["engine"] == "aport"
        assert result["agent_id"] == "ap_quoted123"


class TestAbsolutePassportPath:
    def test_absolute_path_preserved(self, repo_dir):
        _write_agentsmd(repo_dir, """\
            ---
            enforcement:
              engine: aport
              passport: /etc/aport/passport.json
            ---
        """)
        result = resolve_agentsmd_enforcement(repo_dir)
        assert result["passport"] == "/etc/aport/passport.json"

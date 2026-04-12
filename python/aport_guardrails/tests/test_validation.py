from pathlib import Path

from aport_guardrails.core.validation import (
    validate_explicit_passport_path,
    validate_passport_path,
)


class TestExplicitPassportPathValidation:
    def test_explicit_path_allows_non_default_tmp_location(self):
        result = validate_explicit_passport_path(Path("/tmp/custom-passports/aport/passport.json"))
        assert result.valid is True

    def test_explicit_path_rejects_traversal(self):
        result = validate_explicit_passport_path(Path("../secrets/passport.json"))
        assert result.valid is False
        assert result.error_code == "oap.path_traversal_attempt"


class TestDiscoveredPassportPathValidation:
    def test_discovered_path_accepts_known_framework_dirs(self):
        assert validate_passport_path(Path.home() / ".claude" / "aport" / "passport.json").valid is True
        assert validate_passport_path(Path.home() / ".cursor" / "aport" / "passport.json").valid is True
        assert validate_passport_path(Path.home() / ".aport" / "deerflow" / "aport" / "passport.json").valid is True
        assert validate_passport_path(Path.home() / ".n8n" / "aport" / "passport.json").valid is True

    def test_discovered_path_rejects_untrusted_tmp_location(self):
        result = validate_passport_path(Path("/tmp/custom-passports/aport/passport.json"))
        assert result.valid is False
        assert result.error_code == "oap.path_not_allowed"

    def test_discovered_path_accepts_aport_prefixed_tmp_location(self):
        assert validate_passport_path(Path("/tmp/aport-test/passport.json")).valid is True

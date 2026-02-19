"""
Default passport path per framework. Single source: default-passport-paths.json.
Aligns with bin/lib/config.sh get_config_dir() + /aport/passport.json.
Canonical file: packages/core/src/core/default-passport-paths.json (sync this copy when updating).
"""

import json
from pathlib import Path

_MAPPING_DIR = Path(__file__).resolve().parent
_CACHED: dict[str, str] | None = None


def get_default_passport_paths() -> dict[str, str]:
    """Return default passport path per framework (copy of JSON; do not mutate)."""
    global _CACHED
    if _CACHED is not None:
        return dict(_CACHED)
    p = _MAPPING_DIR / "default-passport-paths.json"
    _CACHED = json.loads(p.read_text())
    return dict(_CACHED)

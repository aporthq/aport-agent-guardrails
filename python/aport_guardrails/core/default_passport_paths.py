"""Default passport paths loaded from the packaged JSON source of truth."""

from __future__ import annotations

import json
from pathlib import Path

_MAPPING_DIR = Path(__file__).resolve().parent
_CACHED: dict[str, str] | None = None

def get_default_passport_paths() -> dict[str, str]:
    """Return default passport paths from package data."""
    global _CACHED
    if _CACHED is not None:
        return dict(_CACHED)
    p = _MAPPING_DIR / "default-passport-paths.json"
    if not p.is_file():
        raise RuntimeError(f"Missing default passport paths mapping: {p}")
    _CACHED = json.loads(p.read_text())
    return dict(_CACHED)

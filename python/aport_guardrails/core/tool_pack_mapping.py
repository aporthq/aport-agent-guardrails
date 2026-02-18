"""
Tool name → OAP policy pack ID. Single source: tool-pack-mapping.json.
Canonical file: packages/core/src/core/tool-pack-mapping.json (sync this copy when updating).
"""

import json
from pathlib import Path

_MAPPING_DIR = Path(__file__).resolve().parent
_CACHED: dict | None = None


def _load_mapping() -> dict:
    global _CACHED
    if _CACHED is not None:
        return _CACHED
    p = _MAPPING_DIR / "tool-pack-mapping.json"
    _CACHED = json.loads(p.read_text())
    return _CACHED


def tool_to_pack_id(tool_name: str) -> str:
    """Map a tool name to the OAP policy pack ID. Single source: tool-pack-mapping.json."""
    t = (tool_name or "").strip().lower()
    data = _load_mapping()
    default = data.get("default", "system.command.execute.v1")
    for rule in data.get("rules", []):
        if rule.get("prefixes") and any(t.startswith(pre) for pre in rule["prefixes"]):
            return rule["pack"]
        if rule.get("substrings") and any(sub in t for sub in rule["substrings"]):
            return rule["pack"]
    return default

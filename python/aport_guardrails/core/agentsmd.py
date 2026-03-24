"""
Parse AGENTS.md enforcement block. Single source of truth for AGENTS.md discovery (Python side).
Mirrors bin/lib/agentsmd.sh — keep in sync.
No external dependencies (no pyyaml). Parses simple YAML frontmatter with stdlib.
"""

from pathlib import Path
from typing import Any


def resolve_agentsmd_enforcement(start_dir: str | Path | None = None) -> dict[str, Any] | None:
    """Walk up from start_dir to find AGENTS.md, parse enforcement: block.

    Returns dict with engine, passport (absolute), agent_id — or None if not found.
    """
    d = Path(start_dir or Path.cwd()).resolve()

    # Walk up to find AGENTS.md
    agentsmd = None
    while True:
        for name in ("AGENTS.md", ".agents.md"):
            candidate = d / name
            if candidate.is_file():
                agentsmd = candidate
                break
        if agentsmd:
            break
        parent = d.parent
        if parent == d:
            return None
        d = parent

    agentsmd_dir = agentsmd.parent

    # Extract YAML frontmatter
    try:
        lines = agentsmd.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None

    if not lines or lines[0].strip() != "---":
        return None

    frontmatter_lines: list[str] = []
    for line in lines[1:]:
        if line.strip() == "---":
            break
        frontmatter_lines.append(line)
    else:
        return None  # no closing ---

    if not frontmatter_lines:
        return None

    # Parse enforcement: block (simple indentation-based, no YAML dep)
    result: dict[str, Any] = {}
    in_enforcement = False
    for line in frontmatter_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if stripped.startswith("enforcement:"):
            in_enforcement = True
            continue

        if in_enforcement:
            # Non-indented line = end of enforcement block
            if not line[0].isspace():
                break
            # Parse key: value
            if ":" in stripped:
                key, _, val = stripped.partition(":")
                key = key.strip()
                val = val.strip()
                # Strip matching quote pairs only (not asymmetric)
                if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
                    val = val[1:-1]
                # Strip inline comments
                if " #" in val:
                    val = val[:val.index(" #")].strip()
                if key == "engine":
                    result["engine"] = val
                elif key == "passport":
                    # Resolve relative to AGENTS.md location; preserve absolute paths as-is
                    p = Path(val)
                    if p.is_absolute():
                        result["passport"] = str(p)
                    else:
                        result["passport"] = str((agentsmd_dir / p).resolve())
                elif key == "agent_id":
                    result["agent_id"] = val

    return result if result else None

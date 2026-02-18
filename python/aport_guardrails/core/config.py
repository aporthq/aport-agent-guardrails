"""Config management: read/write framework config files."""

from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    yaml = None  # type: ignore[assignment]


def _load_yaml(path: Path) -> dict[str, Any]:
    if yaml is None:
        return {}
    text = path.read_text()
    return yaml.safe_load(text) or {}


def _dump_yaml(data: dict[str, Any]) -> str:
    if yaml is None:
        return ""
    return yaml.safe_dump(data, default_flow_style=False, sort_keys=False)


def load_config(path: str | Path) -> dict[str, Any]:
    """Load config from YAML file. Returns {} if file missing or invalid."""
    p = Path(path).expanduser().resolve()
    if not p.is_file():
        return {}
    try:
        return _load_yaml(p)
    except Exception:
        return {}


def write_config(path: str | Path, config: dict[str, Any]) -> None:
    """Write config to YAML file."""
    p = Path(path).expanduser().resolve()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(_dump_yaml(config))


def find_config_path(framework: str = "langchain") -> Path | None:
    """Return first existing config path: .aport/config.yaml, then ~/.aport/<framework>/config.yaml."""
    cwd = Path.cwd()
    for candidate in [
        cwd / ".aport" / "config.yaml",
        cwd / ".aport" / "config.yml",
        Path.home() / ".aport" / framework / "config.yaml",
        Path.home() / ".aport" / "config.yaml",
    ]:
        if candidate.is_file():
            return candidate
    return None

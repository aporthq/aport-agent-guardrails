"""Helpers for locating APort runtime assets from source or installed wheels."""

from __future__ import annotations

import shutil
from pathlib import Path


# VCS metadata and build caches are not runtime material. `.git` is a directory in a recursive clone and a
# gitlink file in a worktree checkout, so both shapes are excluded by name.
_EXCLUDED_RUNTIME_NAMES = frozenset(
    {".git", ".gitmodules", ".github", "__pycache__", ".pytest_cache", ".DS_Store"}
)


def _ignore_vcs_metadata(_directory: str, names: list[str]) -> set[str]:
    return {name for name in names if name in _EXCLUDED_RUNTIME_NAMES}


def find_runtime_root() -> Path | None:
    """Return the runtime root from the source repo or the installed wheel bundle."""
    package_root = Path(__file__).resolve().parent.parent
    candidate = package_root.parent.parent
    if (candidate / "bin" / "aport-create-passport.sh").is_file():
        return candidate
    bundled = package_root / "runtime-bundle"
    if (bundled / "manifest.txt").is_file():
        return bundled
    return None


def _load_runtime_manifest(root: Path) -> list[tuple[str, str]]:
    manifest_path = root / "bin" / "lib" / "runtime-manifest.txt"
    if not manifest_path.is_file():
        manifest_path = root / "manifest.txt"
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Runtime manifest not found: {manifest_path}")

    entries: list[tuple[str, str]] = []
    for raw_line in manifest_path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        kind, rel_path = line.split(" ", 1)
        entries.append((kind, rel_path))
    return entries


def install_runtime_tree(config_dir: Path) -> Path | None:
    """Install a self-contained local runtime under <config_dir>/aport/runtime."""
    root = find_runtime_root()
    if root is None:
        return None

    runtime_dir = config_dir / "aport" / "runtime"
    runtime_dir.mkdir(parents=True, exist_ok=True)

    for kind, rel_path in _load_runtime_manifest(root):
        src = root / rel_path
        dest = runtime_dir / rel_path

        if kind == "file":
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
            if dest.suffix in {".sh", ".js"}:
                try:
                    dest.chmod(dest.stat().st_mode | 0o111)
                except OSError:
                    pass
        elif kind == "tree":
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(src, dest, ignore=_ignore_vcs_metadata)
        elif kind == "mkdir":
            dest.mkdir(parents=True, exist_ok=True)
        else:
            raise RuntimeError(f"Unsupported runtime manifest entry: {kind} {rel_path}")

    return runtime_dir


def resolve_runtime_script(script_name: str) -> Path | None:
    """Return a runtime script path and ensure it is executable."""
    root = find_runtime_root()
    if root is None:
        return None
    script = root / "bin" / script_name
    if not script.is_file():
        return None
    try:
        script.chmod(script.stat().st_mode | 0o111)
    except OSError:
        pass
    return script

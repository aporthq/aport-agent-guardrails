"""Setuptools glue for packaging the shared runtime bundle into Python builds."""

from __future__ import annotations

import shutil
from pathlib import Path

from setuptools import setup
from setuptools.command.build_py import build_py as _build_py
from setuptools.command.sdist import sdist as _sdist

_PACKAGE_ROOT = Path(__file__).resolve().parent
_REPO_ROOT = _PACKAGE_ROOT.parent.parent
_BUNDLE_DIRNAME = "runtime-bundle"


def _runtime_source() -> tuple[Path, Path]:
    repo_manifest = _REPO_ROOT / "bin" / "lib" / "runtime-manifest.txt"
    if repo_manifest.is_file():
        return _REPO_ROOT, repo_manifest

    packaged_root = _PACKAGE_ROOT / _BUNDLE_DIRNAME
    packaged_manifest = packaged_root / "manifest.txt"
    if packaged_manifest.is_file():
        return packaged_root, packaged_manifest

    raise FileNotFoundError("Unable to locate APort runtime assets for Python packaging")


def _load_manifest(manifest_path: Path) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for raw_line in manifest_path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        kind, rel_path = line.split(" ", 1)
        entries.append((kind, rel_path))
    return entries


def _copy_runtime_bundle(dest_package_root: Path) -> None:
    source_root, manifest_path = _runtime_source()
    bundle_root = dest_package_root / _BUNDLE_DIRNAME

    if bundle_root.exists():
        shutil.rmtree(bundle_root)
    bundle_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(manifest_path, bundle_root / "manifest.txt")

    for kind, rel_path in _load_manifest(manifest_path):
        src = source_root / rel_path
        dest = bundle_root / rel_path

        if kind == "file":
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
        elif kind == "tree":
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(src, dest)
        elif kind == "mkdir":
            dest.mkdir(parents=True, exist_ok=True)
        else:
            raise RuntimeError(f"Unsupported runtime manifest entry: {kind} {rel_path}")


class build_py(_build_py):
    def run(self) -> None:
        super().run()
        _copy_runtime_bundle(Path(self.build_lib) / "aport_guardrails")


class sdist(_sdist):
    def make_release_tree(self, base_dir: str, files: list[str]) -> None:
        super().make_release_tree(base_dir, files)
        _copy_runtime_bundle(Path(base_dir))


setup(
    cmdclass={
        "build_py": build_py,
        "sdist": sdist,
    }
)

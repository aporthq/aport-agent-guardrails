"""
Shared CLI logic for framework setup (LangChain, CrewAI).
Single source of truth for config dir, wizard, and config write.
"""

import subprocess
from pathlib import Path

from aport_guardrails.core.config import load_config, write_config

DEFAULT_CONFIG = {"mode": "local"}


def get_config_dir(framework: str) -> Path:
    """Config directory for framework: ~/.aport/<framework>/."""
    return Path.home() / ".aport" / framework


def run_wizard(framework: str) -> bool:
    """Run passport wizard via npx agent-guardrails. Returns True if run successfully."""
    try:
        r = subprocess.run(
            ["npx", "--yes", "@aporthq/agent-guardrails", f"--framework={framework}"],
            check=False,
            timeout=120,
            capture_output=True,
        )
        return r.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def run_setup(
    framework: str,
    *,
    ci: bool = False,
    no_wizard: bool = False,
    next_steps_lines: list[str],
) -> None:
    """
    Shared setup: ensure config dir and config.yaml, optionally run wizard, print next steps.
    Adapters pass framework name and their next-steps text.
    """
    config_dir = get_config_dir(framework)
    config_dir.mkdir(parents=True, exist_ok=True)
    config_path = config_dir / "config.yaml"

    if not config_path.exists() or not load_config(config_path):
        write_config(config_path, DEFAULT_CONFIG)
        print(f"[aport] Config written to: {config_path}")
    else:
        print(f"[aport] Config exists: {config_path}")

    if not ci and not no_wizard:
        print(f"[aport] Run the passport wizard with: npx @aporthq/agent-guardrails --framework={framework}")
        if run_wizard(framework):
            print("[aport] Wizard completed.")
        else:
            print(f"[aport] Install passport: npx @aporthq/agent-guardrails --framework={framework}")

    print("")
    for line in next_steps_lines:
        print(line)
    print("")

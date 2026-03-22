"""
Shared CLI logic for framework setup.
Single source of truth for config dir, wizard, and config write.

Works for Python and Node entry points. The passport wizard
(bin/aport-create-passport.sh) is pure bash+jq — no Node dependency.
"""

import os
import subprocess
import sys
from pathlib import Path

from aport_guardrails.core.config import load_config, write_config

DEFAULT_CONFIG = {"mode": "local"}

# Framework-specific config directories (keep in sync with bin/lib/config.sh)
_CONFIG_DIRS = {
    "openclaw": "~/.openclaw",
    "langchain": "~/.aport/langchain",
    "crewai": "~/.aport/crewai",
    "deerflow": "~/.aport/deerflow",
    "n8n": "~/.n8n",
    "cursor": "~/.cursor",
    "claude-code": "~/.claude",
}


def get_config_dir(framework: str) -> Path:
    """Config directory for framework. Matches bin/lib/config.sh get_config_dir()."""
    env_key = f"APORT_{framework.upper().replace('-', '_')}_CONFIG_DIR"
    env_val = os.environ.get(env_key)
    if env_val:
        return Path(env_val).expanduser()
    template = _CONFIG_DIRS.get(framework, f"~/.aport/{framework}")
    return Path(template).expanduser()


def get_default_passport_path(framework: str) -> Path:
    """Default passport path: <config_dir>/aport/passport.json."""
    return get_config_dir(framework) / "aport" / "passport.json"


def _find_repo_root() -> Path | None:
    """Find the repo root by looking for bin/aport-create-passport.sh relative to this file."""
    # From python/aport_guardrails/core/cli_common.py -> repo root is ../../..
    here = Path(__file__).resolve().parent
    for ancestor in [here.parent.parent.parent, here.parent.parent.parent.parent]:
        candidate = ancestor / "bin" / "aport-create-passport.sh"
        if candidate.exists():
            return ancestor
    return None


def run_wizard(framework: str, agent_id: str | None = None) -> bool:
    """Run the passport creation wizard.

    Tries in order:
    1. bin/aport-create-passport.sh (pure bash+jq, no Node needed)
    2. npx @aporthq/aport-agent-guardrails (fallback if bash script not found)
    """
    repo_root = _find_repo_root()
    wizard_script = repo_root / "bin" / "aport-create-passport.sh" if repo_root else None

    if wizard_script and wizard_script.exists():
        # Direct call — no Node/npx dependency
        cmd = [str(wizard_script), f"--framework={framework}"]
        if agent_id:
            cmd.append(f"--output={get_default_passport_path(framework)}")
        env = {**os.environ, "APORT_FRAMEWORK": framework}
        try:
            r = subprocess.run(cmd, check=False, timeout=120, env=env)
            return r.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

    # Fallback: npx (for when installed via npm, not pip from source)
    try:
        cmd = ["npx", "--yes", "@aporthq/aport-agent-guardrails", f"--framework={framework}"]
        if agent_id:
            cmd.append(agent_id)
        r = subprocess.run(cmd, check=False, timeout=120, capture_output=True)
        return r.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def run_setup(
    framework: str,
    *,
    ci: bool = False,
    no_wizard: bool = False,
    agent_id: str | None = None,
    next_steps_lines: list[str] | None = None,
) -> None:
    """
    Full setup: create config dir, write config, run passport wizard, print next steps.
    This is the Python-native entry point — no npx required when run from source.
    """
    config_dir = get_config_dir(framework)
    passport_dir = config_dir / "aport"
    passport_path = passport_dir / "passport.json"
    config_path = config_dir / "config.yaml"

    # Create dirs with correct permissions
    config_dir.mkdir(parents=True, exist_ok=True)
    passport_dir.mkdir(parents=True, exist_ok=True)
    passport_dir.chmod(0o700)

    # Write default config if missing
    if not config_path.exists() or not load_config(config_path):
        write_config(config_path, DEFAULT_CONFIG)
        print(f"[aport] Config written to: {config_path}")
    else:
        print(f"[aport] Config exists: {config_path}")

    # Run passport wizard (unless CI or --no-wizard)
    if not ci and not no_wizard:
        if run_wizard(framework, agent_id=agent_id):
            print("[aport] Passport wizard completed.")
            # Harden passport permissions
            if passport_path.exists():
                passport_path.chmod(0o600)
        else:
            print(f"[aport] Passport wizard did not complete.", file=sys.stderr)
            print(f"  Run manually: aport setup --framework {framework}", file=sys.stderr)

    # Print next steps
    if next_steps_lines:
        print("")
        for line in next_steps_lines:
            # Substitute $config_dir
            print(line.replace("$config_dir", str(config_dir)))
        print("")

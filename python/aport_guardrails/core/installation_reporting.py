"""Metadata-only bridge to the shared Node reporter; no Python HTTP client."""
import json
import os
import re
import stat
import subprocess
import hashlib
from pathlib import Path
from uuid import UUID
from .runtime_assets import find_runtime_root

# Mirrors the presence check in bin/lib/installation-reporting.sh. Binding,
# identity, permission and schema validation stay in src/installation-reporting.
_BINDING_FILE = re.compile(r"^installation-v1-[a-f0-9]{64}\.json$")
_MAX_STATE_ENTRIES = 512


def _is_directory_no_follow(path):
    try:
        return stat.S_ISDIR(os.lstat(path).st_mode)
    except OSError:
        return False


def reporting_state_present(config_dir):
    """Cheap, bounded presence check for enrolled reporting state.

    Looks only at ``<config_dir>/.aport-reporting`` and the top level of
    ``<config_dir>/aport``. It never follows symlinks, never recurses, never
    creates state, never shells out and never reads a binding; absent,
    inaccessible or oversized state is simply "not present".
    """
    if not config_dir:
        return False
    config_dir = Path(config_dir)
    if _is_directory_no_follow(config_dir / ".aport-reporting"):
        return True
    state_dir = config_dir / "aport"
    if not _is_directory_no_follow(state_dir):
        return False
    try:
        with os.scandir(state_dir) as entries:
            for index, entry in enumerate(entries):
                if index >= _MAX_STATE_ENTRIES:
                    return False
                try:
                    if _BINDING_FILE.match(entry.name) and entry.is_file(follow_symlinks=False):
                        return True
                except OSError:
                    continue
    except OSError:
        return False
    return False


def reporting_eligible(config, config_path, *, allow_handoff=False):
    """Whether a producer may invoke the shared Node reporter at all.

    Evaluated on every call so later enrollment, disable/re-enable, reset or
    reinstall are seen immediately; nothing is cached. ``allow_handoff`` is
    only for setup, where a pending handoff file is enough to proceed.
    """
    if not isinstance(config, dict) or config.get("mode", "local") != "api":
        return False
    if os.environ.get("APORT_REPORTING_DISABLED") == "1":
        return False
    if allow_handoff and os.environ.get("APORT_INSTALLATION_HANDOFF_FILE"):
        return True
    if not config_path:
        return False
    return reporting_state_present(Path(config_path).parent)


def _environment(config, config_path, framework, enforcement, passport_id):
    return {"PATH": os.environ.get("PATH", ""),
            "APORT_CONFIG_DIR": str(config_path.parent), "APORT_HOOK_FRAMEWORK": framework,
            "APORT_AGENT_ID": passport_id if isinstance(passport_id, str) else "",
            "APORT_API_URL": config.get("api_url") or os.environ.get("APORT_API_URL", "https://api.aport.io"),
            "APORT_GUARDRAIL_MODE": "api", "APORT_ENFORCEMENT_MODE": enforcement}


def setup_reporting(config, config_path, framework):
    if not reporting_eligible(config, config_path, allow_handoff=True):
        return
    try:
        from .enforcement import normalize_enforcement_mode
        root = find_runtime_root()
        if not root:
            return
        env = _environment(config, config_path, framework, normalize_enforcement_mode(config.get("enforcement_mode")),
                           config.get("agent_id") or os.environ.get("APORT_AGENT_ID"))
        for key in ("APORT_INSTALLATION_HANDOFF_FILE", "APORT_INSTALLATION_ROTATE", "APORT_REPORT_DECLARED_COVERAGE", "APORT_INSTALLATION_COVERAGE_FILE"):
            if key in os.environ:
                env[key] = os.environ[key]
        result = subprocess.run(["node", str(root / "src/installation-reporting/cli.js"), "setup"],
                                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=False)
        print("[aport] Reporting receipt queued; connection unverified." if result.returncode == 0 else "[aport] Reporting connection unresolved.")
    except Exception:
        print("[aport] Reporting connection unresolved.")


def report_decision(config, config_path, framework, decision, enforcement, passport_id=None):
    """Return True only when the shared reporter was handed the decision metadata."""
    if not reporting_eligible(config, config_path):
        return False
    try:
        root = find_runtime_root()
        if not root:
            return False
        env = _environment(config, config_path, framework, enforcement, passport_id)
        # Bounded metadata goes over stdin, never a command string or environment.
        metadata = json.dumps({"decision_id": decision.get("decision_id")})
        if len(metadata.encode()) > 2048:
            return False
        subprocess.run(["node", str(root / "src/installation-reporting/cli.js"), "decision"],
                       input=metadata, text=True, env=env, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=1, check=False)
        return True
    except Exception:
        return False


def report_completion(config, config_path, framework, run_id, enforcement, decision=None, passport_id=None):
    if not reporting_eligible(config, config_path):
        return
    try:
        if not isinstance(run_id, (str, UUID)) or not str(run_id) or len(str(run_id)) > 256:
            return
        root = find_runtime_root()
        if not root:
            return
        metadata = {"call_key": hashlib.sha256(str(run_id).encode()).hexdigest()}
        if decision is not None:
            metadata.update(decision_id=decision.get("decision_id"), allow=decision.get("allow"))
        data = json.dumps(metadata)
        if len(data.encode()) > 2048:
            return
        subprocess.run(["node", str(root / "src/installation-reporting/cli.js"), "remember" if decision is not None else "post"],
                       input=data, text=True, env=_environment(config, config_path, framework, enforcement, passport_id),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1, check=False)
    except Exception:
        pass

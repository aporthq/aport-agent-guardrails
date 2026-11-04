"""Metadata-only bridge to the shared Node reporter; no Python HTTP client."""
import json
import os
import subprocess
import hashlib
from uuid import UUID
from .runtime_assets import find_runtime_root


def _environment(config, config_path, framework, enforcement, passport_id):
    return {"PATH": os.environ.get("PATH", ""),
            "APORT_CONFIG_DIR": str(config_path.parent), "APORT_HOOK_FRAMEWORK": framework,
            "APORT_AGENT_ID": passport_id if isinstance(passport_id, str) else "",
            "APORT_API_URL": config.get("api_url") or os.environ.get("APORT_API_URL", "https://api.aport.io"),
            "APORT_GUARDRAIL_MODE": "api", "APORT_ENFORCEMENT_MODE": enforcement}


def setup_reporting(config, config_path, framework):
    if config.get("mode", "local") != "api" or os.environ.get("APORT_REPORTING_DISABLED") == "1":
        return
    if not os.environ.get("APORT_INSTALLATION_HANDOFF_FILE") and not (config_path.parent / ".aport-reporting").is_dir() and not any((config_path.parent / "aport").glob("installation-v1-*.json")):
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
    if config.get("mode", "local") != "api" or os.environ.get("APORT_REPORTING_DISABLED") == "1":
        return
    try:
        root = find_runtime_root()
        if not root or not config_path:
            return
        env = _environment(config, config_path, framework, enforcement, passport_id)
        # Bounded metadata goes over stdin, never a command string or environment.
        metadata = json.dumps({"decision_id": decision.get("decision_id")})
        if len(metadata.encode()) > 2048:
            return
        subprocess.run(["node", str(root / "src/installation-reporting/cli.js"), "decision"],
                       input=metadata, text=True, env=env, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=1, check=False)
    except Exception:
        pass


def report_completion(config, config_path, framework, run_id, enforcement, decision=None, passport_id=None):
    if config.get("mode", "local") != "api" or os.environ.get("APORT_REPORTING_DISABLED") == "1":
        return
    try:
        if not isinstance(run_id, (str, UUID)) or not str(run_id) or len(str(run_id)) > 256 or not config_path:
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

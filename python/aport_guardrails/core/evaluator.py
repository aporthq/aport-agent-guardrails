"""
Shared evaluator: verify tool execution against passport + policy.
Used by all Python framework adapters (LangChain, CrewAI, AutoGen).
"""

import asyncio
import json
import os
import ssl
import subprocess
from pathlib import Path
from typing import Any, TypedDict
from urllib.request import Request, urlopen
from urllib.error import URLError

from aport_guardrails.core.config import find_config_path, load_config
from aport_guardrails.core.default_passport_paths import get_default_passport_paths
from aport_guardrails.core.tool_pack_mapping import tool_to_pack_id as _tool_to_pack_id
from aport_guardrails.core.validation import (
    validate_tool_name,
    validate_context_structure,
    validate_passport_path,
)


def _resolve_passport_path(config: dict[str, Any]) -> str | None:
    """Resolve passport path: config, env, framework default, or first existing default path."""
    path = config.get("passport_path") or os.environ.get("OPENCLAW_PASSPORT_FILE")
    if path:
        path_obj = Path(path).expanduser()
        # SECURITY: Validate passport path to prevent path traversal
        path_validation = validate_passport_path(path_obj)
        if not path_validation.valid:
            # Log warning but don't fail - continue to try default paths
            import sys
            print(f"WARNING: Invalid passport path: {path_validation.error_message}", file=sys.stderr)
        elif path_obj.exists():
            return str(path_obj)
        # Path specified but doesn't exist - still validate and return
        elif path_validation.valid:
            return str(path_obj)

    default_paths = get_default_passport_paths()
    framework = config.get("framework")
    if framework and framework in default_paths:
        candidate = Path(default_paths[framework]).expanduser()
        # Validate default paths too
        path_validation = validate_passport_path(candidate)
        if path_validation.valid and candidate.exists():
            return str(candidate)
    for candidate_path in default_paths.values():
        p = Path(candidate_path).expanduser()
        path_validation = validate_passport_path(p)
        if path_validation.valid and p.exists():
            return str(p)
    return None


class Passport(TypedDict, total=False):
    agent_id: str


class PolicyPack(TypedDict, total=False):
    capability: str


class ToolContext(TypedDict, total=False):
    tool: str
    input: str
    params: dict[str, Any]


class Decision(TypedDict, total=False):
    allow: bool
    reasons: list[dict[str, str]]


def _get_fail_open_when_missing_config(config: dict[str, Any]) -> bool:
    """True if config or env allows legacy fail-open when passport/script missing."""
    v = config.get("fail_open_when_missing_config") or os.environ.get("APORT_FAIL_OPEN_WHEN_MISSING_CONFIG")
    return v in (True, "1", "true")


def _get_guardrail_script_path(config: dict[str, Any]) -> str | None:
    """Resolve path to aport-guardrail-bash.sh or wrapper."""
    script = config.get("guardrail_script") or os.environ.get("APORT_GUARDRAIL_SCRIPT")
    if script and Path(script).exists():
        return script
    # Default wrapper installed by npx agent-guardrails
    default = Path.home() / ".openclaw" / ".skills" / "aport-guardrail.sh"
    if default.exists():
        return str(default)
    return None


def _run_guardrail_sync(
    guardrail_script: str,
    passport_path: str,
    tool_name: str,
    context: dict[str, Any],
) -> Decision:
    """Run guardrail script; read decision from same dir as passport. Sync for asyncio.to_thread."""
    # SECURITY: Validate tool_name to prevent injection attacks
    tool_validation = validate_tool_name(tool_name)
    if not tool_validation.valid:
        return {
            "allow": False,
            "reasons": [{
                "code": tool_validation.error_code or "oap.invalid_tool_name",
                "message": tool_validation.error_message or "Invalid tool name",
            }],
        }

    # SECURITY: Validate context structure and size
    context_validation = validate_context_structure(context)
    if not context_validation.valid:
        return {
            "allow": False,
            "reasons": [{
                "code": context_validation.error_code or "oap.invalid_context",
                "message": context_validation.error_message or "Invalid context",
            }],
        }

    # SECURITY: Validate passport path to prevent path traversal
    passport_path_obj = Path(passport_path)
    path_validation = validate_passport_path(passport_path_obj)
    if not path_validation.valid:
        return {
            "allow": False,
            "reasons": [{
                "code": path_validation.error_code or "oap.invalid_passport_path",
                "message": path_validation.error_message or "Invalid passport path",
            }],
        }

    env = os.environ.copy()
    env["OPENCLAW_PASSPORT_FILE"] = str(passport_path_obj.resolve())
    data_dir = passport_path_obj.resolve().parent
    decision_file = data_dir / "decision.json"
    context_json = json.dumps(context)
    try:
        proc = subprocess.run(
            [guardrail_script, tool_name, context_json],
            env=env,
            capture_output=True,
            timeout=30,
            cwd=data_dir,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return {
            "allow": False,
            "reasons": [{"code": "oap.evaluator_error", "message": str(e)}],
        }
    if decision_file.exists():
        try:
            data = json.loads(decision_file.read_text())
            allow = data.get("allow", False)
            reasons = data.get("reasons", [{"message": "Policy evaluation failed"}])
            return {"allow": allow, "reasons": reasons}
        except (json.JSONDecodeError, OSError):
            pass
    return {
        "allow": False,
        "reasons": [
            {"code": "oap.evaluator_error", "message": f"Script exit {proc.returncode}"}
        ],
    }


# Literal path segment for policy-in-body (agent-passport API)
IN_BODY_PACK_ID = "IN_BODY"


def _get_ssl_context(verify_ssl: bool = True) -> ssl.SSLContext | None:
    """
    Create SSL context for API calls.

    Args:
        verify_ssl: Whether to verify SSL certificates (default: True)

    Returns:
        SSLContext with appropriate verification settings, or None for unverified
    """
    if not verify_ssl:
        # SECURITY WARNING: Only disable SSL verification in development/testing
        import sys
        print("WARNING: SSL certificate verification disabled. This is insecure!", file=sys.stderr)
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        return context

    # Default: verify SSL certificates
    return ssl.create_default_context()


def _is_full_policy_pack(p: Any) -> bool:
    """True if p looks like an OAP policy pack (id + requires_capabilities) for IN_BODY."""
    if not p or not isinstance(p, dict):
        return False
    return bool(p.get("id") and p.get("requires_capabilities") is not None)


def _call_api_sync(
    api_url: str,
    pack_id: str,
    context: dict[str, Any],
    *,
    agent_id: str | None = None,
    passport: dict[str, Any] | None = None,
    policy_pack: dict[str, Any] | None = None,
    api_key: str | None = None,
    verify_ssl: bool = True,
) -> Decision:
    """
    Call APort API: POST /api/verify/policy/{pack_id}.
    Passport: (1) agent_id in context (cloud); (2) passport in body (local via API).
    Policy: (1) pack_id in path; (2) pack_id=IN_BODY + body.policy when policy_pack is provided.
    See agent-passport functions/api/verify/policy/[pack_id].ts.
    """
    base = api_url.rstrip("/")
    path_id = IN_BODY_PACK_ID if policy_pack and _is_full_policy_pack(policy_pack) else pack_id
    url = f"{base}/api/verify/policy/{path_id}"
    body_context = dict(context)
    if agent_id:
        body_context["agent_id"] = agent_id
    body_context.setdefault("policy_id", path_id if path_id != IN_BODY_PACK_ID else (policy_pack or {}).get("id", ""))
    if not agent_id and not passport:
        return {
            "allow": False,
            "reasons": [{"code": "oap.api_error", "message": "Either agent_id or passport required"}],
        }
    body: dict[str, Any] = {"context": body_context}
    if passport:
        body["passport"] = passport
    if policy_pack and _is_full_policy_pack(policy_pack):
        body["policy"] = policy_pack
    try:
        req = Request(url, data=json.dumps(body).encode(), method="POST")
        req.add_header("Content-Type", "application/json")
        if api_key:
            req.add_header("Authorization", f"Bearer {api_key}")
        # SECURITY: Use explicit SSL context for certificate verification
        ssl_context = _get_ssl_context(verify_ssl)
        with urlopen(req, timeout=15, context=ssl_context) as resp:
            data = json.loads(resp.read().decode())
            decision = data.get("decision") if isinstance(data.get("decision"), dict) else data
            if not decision:
                decision = data
            return {
                "allow": decision.get("allow", False),
                "reasons": decision.get("reasons", [{"message": "API response"}]),
            }
    except (URLError, OSError, json.JSONDecodeError) as e:
        return {
            "allow": False,
            "reasons": [{"code": "oap.api_error", "message": str(e)}],
        }


class Evaluator:
    """API or local verification client. Auto-loads config from default paths if config_path not given."""

    def __init__(
        self,
        config_path: str | Path | None = None,
        *,
        framework: str = "langchain",
    ) -> None:
        self.config_path = Path(config_path) if config_path else None
        self._framework = framework
        self._config: dict[str, Any] | None = None

    def _load_config(self) -> dict[str, Any]:
        if self._config is not None:
            return self._config
        if self.config_path and self.config_path.is_file():
            self._config = load_config(self.config_path)
            return self._config
        found = find_config_path(self._framework)
        if found:
            self._config = load_config(found)
            return self._config
        self._config = {}
        return self._config

    async def verify(
        self,
        passport: Passport,
        policy: PolicyPack,
        context: ToolContext,
    ) -> Decision:
        """
        Verify tool execution. Supports:
        - API: agent_id in context (cloud) or passport in body (local via API).
        - API policy: pack_id in path (from tool name) or policy in body (IN_BODY) when policy is a full OAP pack.
        - Local: guardrail script + passport file (policy-in-body for local coming soon).
        """
        config = self._load_config()
        mode = config.get("mode", "local")
        tool_name = context.get("tool", "unknown")
        pack_id = _tool_to_pack_id(tool_name)
        ctx = dict(context)
        # If policy is a full OAP pack (id + requires_capabilities), use IN_BODY for API
        policy_pack: dict[str, Any] | None = None
        if isinstance(policy, dict) and _is_full_policy_pack(policy):
            policy_pack = policy

        if mode == "api":
            api_url = config.get("api_url") or os.environ.get("APORT_API_URL", "https://api.aport.io")
            api_key = config.get("api_key") or os.environ.get("APORT_API_KEY")
            agent_id = config.get("agent_id") or passport.get("agent_id")
            # SECURITY: Check if SSL verification should be disabled (dev/test only)
            verify_ssl = config.get("verify_ssl", True)
            if os.environ.get("APORT_VERIFY_SSL") == "0":
                verify_ssl = False
            passport_path = _resolve_passport_path(config)
            passport_body: dict[str, Any] | None = None
            if passport_path:
                try:
                    raw = Path(passport_path).read_text()
                    passport_body = json.loads(raw)
                    if not passport_body.get("agent_id") and passport_body.get("passport_id"):
                        passport_body["agent_id"] = passport_body["passport_id"]
                except (OSError, json.JSONDecodeError):
                    passport_body = None
            if agent_id:
                return await asyncio.to_thread(
                    _call_api_sync,
                    api_url,
                    pack_id,
                    ctx,
                    agent_id=agent_id,
                    policy_pack=policy_pack,
                    api_key=api_key,
                    verify_ssl=verify_ssl,
                )
            if passport_body:
                return await asyncio.to_thread(
                    _call_api_sync,
                    api_url,
                    pack_id,
                    ctx,
                    passport=passport_body,
                    policy_pack=policy_pack,
                    api_key=api_key,
                    verify_ssl=verify_ssl,
                )
        # Local mode or fallback
        passport_path = _resolve_passport_path(config)
        guardrail_script = _get_guardrail_script_path(config)
        if not passport_path or not guardrail_script:
            if _get_fail_open_when_missing_config(config):
                return {"allow": True}
            return {
                "allow": False,
                "reasons": [
                    {
                        "code": "oap.misconfigured",
                        "message": "Passport or guardrail script not found; deny by default. Set fail_open_when_missing_config or APORT_FAIL_OPEN_WHEN_MISSING_CONFIG=1 for legacy behavior.",
                    }
                ],
            }
        return await asyncio.to_thread(
            _run_guardrail_sync,
            guardrail_script,
            passport_path,
            tool_name,
            ctx,
        )

    def verify_sync(
        self,
        passport: Passport,
        policy: PolicyPack,
        context: ToolContext,
    ) -> Decision:
        """
        Synchronous verify for sync callers (e.g. CrewAI before_tool_call hooks).
        Same semantics as verify(); uses API or local script without asyncio.
        """
        config = self._load_config()
        mode = config.get("mode", "local")
        tool_name = context.get("tool", "unknown")
        pack_id = _tool_to_pack_id(tool_name)
        ctx = dict(context)
        policy_pack: dict[str, Any] | None = None
        if isinstance(policy, dict) and _is_full_policy_pack(policy):
            policy_pack = policy

        if mode == "api":
            api_url = config.get("api_url") or os.environ.get("APORT_API_URL", "https://api.aport.io")
            api_key = config.get("api_key") or os.environ.get("APORT_API_KEY")
            agent_id = config.get("agent_id") or passport.get("agent_id")
            # SECURITY: Check if SSL verification should be disabled (dev/test only)
            verify_ssl = config.get("verify_ssl", True)
            if os.environ.get("APORT_VERIFY_SSL") == "0":
                verify_ssl = False
            passport_path = _resolve_passport_path(config)
            passport_body: dict[str, Any] | None = None
            if passport_path:
                try:
                    raw = Path(passport_path).read_text()
                    passport_body = json.loads(raw)
                    if not passport_body.get("agent_id") and passport_body.get("passport_id"):
                        passport_body["agent_id"] = passport_body["passport_id"]
                except (OSError, json.JSONDecodeError):
                    passport_body = None
            if agent_id:
                return _call_api_sync(
                    api_url, pack_id, ctx, agent_id=agent_id, policy_pack=policy_pack, api_key=api_key, verify_ssl=verify_ssl
                )
            if passport_body:
                return _call_api_sync(
                    api_url, pack_id, ctx, passport=passport_body, policy_pack=policy_pack, api_key=api_key, verify_ssl=verify_ssl
                )
        passport_path = _resolve_passport_path(config)
        guardrail_script = _get_guardrail_script_path(config)
        if not passport_path or not guardrail_script:
            if _get_fail_open_when_missing_config(config):
                return {"allow": True}
            return {
                "allow": False,
                "reasons": [
                    {
                        "code": "oap.misconfigured",
                        "message": "Passport or guardrail script not found; deny by default. Set fail_open_when_missing_config or APORT_FAIL_OPEN_WHEN_MISSING_CONFIG=1 for legacy behavior.",
                    }
                ],
            }
        return _run_guardrail_sync(
            guardrail_script,
            passport_path,
            tool_name,
            ctx,
        )

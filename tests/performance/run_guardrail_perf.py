#!/usr/bin/env python3
"""
Guardrail performance test: measure latency with REAL API verification (real passport + policy).
Outputs a formatted table (and optional JSON/Markdown) for reporting.

What is measured:
  - Pure API latency (HTTP round-trip / eval only): Node and Python API runs. Use these as the
    reference for server and in-process evaluation cost.
  - Bash API timings include subprocess spawn + script run + exit, so they are end-to-end
    "time to run the script that does the API call," not pure HTTP latency. For pure API
    latency use Node or Python.

Usage (real API, default):
  PYTHONPATH=python python3 tests/performance/run_guardrail_perf.py [--agent-id ap_xxx] [--api-url URL]
  Uses remote passport (agent_id) and real APort API; policy from registry.

Options:
  --agent-id ID   Remote passport agent ID (default: ap_dd86bb4458524d4db529de7de9e8dc8a).
  --api-url URL   API base URL (default: https://api.aport.io).
  --mock          Run mock/local scenarios instead (no network, for comparison).
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

# Ensure we can import aport_guardrails when run from repo root
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(REPO_ROOT / "python") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "python"))

# Tests dir for optional in-process mock server (load by path to avoid package requirement)
TESTS_DIR = REPO_ROOT / "tests"
PERF_DIR = REPO_ROOT / "tests" / "performance"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------


def percentile(sorted_arr, p):
    """p in [0,100]. Returns value at percentile."""
    if not sorted_arr:
        return 0.0
    k = (len(sorted_arr) - 1) * (p / 100)
    f = int(k)
    c = f + 1 if f + 1 < len(sorted_arr) else f
    return sorted_arr[f] + (k - f) * (sorted_arr[c] - sorted_arr[f])


def stats(latencies_ms):
    if not latencies_ms:
        return {"mean": 0, "p50": 0, "p95": 0, "p99": 0, "n": 0}
    s = sorted(latencies_ms)
    n = len(s)
    return {
        "mean": sum(s) / n,
        "p50": percentile(s, 50),
        "p95": percentile(s, 95),
        "p99": percentile(s, 99),
        "n": n,
    }


def format_ms(x):
    return f"{x:.2f}"


# Passport fixture for "passport in body" API and for Local (valid OAP shape)
PASSPORT_FIXTURE = {
    "spec_version": "oap/1.0",
    "passport_id": "perf-p1",
    "owner_id": "perf-o1",
    "agent_id": "perf-a1",
    "status": "active",
    "assurance_level": "L0",
    "capabilities": [{"id": "system.command.execute", "description": "Run"}],
    "limits": {"allowed_commands": ["ls", "pwd"], "blocked_patterns": []},
    "issued_at": "2020-01-01T00:00:00Z",
    "expires_at": "2030-01-01T00:00:00Z",
}


def _load_policy_pack(repo_root: Path) -> dict:
    """Load system.command.execute.v1 policy from external/aport-policies."""
    policy_path = repo_root / "external" / "aport-policies" / "system.command.execute.v1" / "policy.json"
    if not policy_path.exists():
        return {"id": "system.command.execute.v1", "requires_capabilities": ["system.command.execute"]}
    return json.loads(policy_path.read_text())


# -----------------------------------------------------------------------------
# Scenario runners (return list of latencies in ms)
# -----------------------------------------------------------------------------


def run_python_api_mock_async(iterations: int, warmup: int) -> list:
    import asyncio
    from unittest.mock import patch
    from aport_guardrails.core.evaluator import Evaluator, _call_api_sync

    decision = {"allow": True, "reasons": [{"message": "OK"}]}

    def mock_urlopen(req, timeout=15):
        class Resp:
            def read(self):
                return json.dumps(decision).encode()

            def __enter__(self):
                return self

            def __exit__(self, *a):
                pass

        return Resp()

    async def run():
        evaluator = Evaluator(config_path="/nonexistent")
        evaluator._config = {
            "mode": "api",
            "api_url": "https://api.example.com",
            "agent_id": "perf-agent",
        }
        with patch("aport_guardrails.core.evaluator.urlopen", side_effect=mock_urlopen):
            for _ in range(warmup):
                await evaluator.verify(
                    {"agent_id": "perf-agent"},
                    {"capability": "x"},
                    {"tool": "run"},
                )
            latencies = []
            for _ in range(iterations):
                t0 = time.perf_counter()
                await evaluator.verify(
                    {"agent_id": "perf-agent"},
                    {"capability": "system.command.execute.v1"},
                    {"tool": "system.command.execute", "input": '{"command":"ls"}'},
                )
                latencies.append((time.perf_counter() - t0) * 1000)
        return latencies

    return asyncio.run(run())


# -----------------------------------------------------------------------------
# Real API + Local runners (all identity/policy variants)
# -----------------------------------------------------------------------------


def _probe_real_api(api_url: str, agent_id: str, repo_root: Path) -> None:
    """Run one real API call and print result so we confirm the actual API is being used."""
    from aport_guardrails.core.evaluator import _call_api_sync

    url = f"{api_url.rstrip('/')}/api/verify/policy/system.command.execute.v1"
    context = {"tool": "system.command.execute", "input": '{"command":"ls"}'}
    t0 = time.perf_counter()
    try:
        decision = _call_api_sync(
            api_url,
            "system.command.execute.v1",
            context,
            agent_id=agent_id,
            passport=None,
            policy_pack=None,
        )
        elapsed_ms = (time.perf_counter() - t0) * 1000
        allow = decision.get("allow", False)
        print(f"      Probe: POST {url} -> allow={allow} in {format_ms(elapsed_ms)} ms")
    except Exception as e:
        print(f"      Probe: POST {url} -> ERROR: {e}")
        raise


def _run_node_harness(
    iterations: int, warmup: int, repo_root: Path, api_url: str, variant: str, identity: str
) -> list:
    """Node harness: variant = agent_path | agent_body | passport_path | passport_body; identity = agent_id or path to passport.json."""
    harness = repo_root / "tests" / "performance" / "node_api_harness_real.cjs"
    total = warmup + iterations
    out = subprocess.run(
        ["node", str(harness), str(total), api_url, variant, identity],
        capture_output=True,
        text=True,
        cwd=str(repo_root),
        timeout=180,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr or out.stdout or "Node harness failed")
    all_latencies = json.loads(out.stdout.strip())
    return all_latencies[warmup:] if len(all_latencies) >= total else all_latencies


def run_python_api_variant(
    iterations: int, warmup: int, api_url: str, agent_id: str, use_passport_body: bool, use_policy_body: bool, repo_root: Path
) -> list:
    """Python API: identity = agent_id or passport in body; policy = path or full pack in body."""
    import asyncio
    from aport_guardrails.core.evaluator import Evaluator, _call_api_sync

    passport_body = None
    if use_passport_body:
        passport_body = {**PASSPORT_FIXTURE, "agent_id": PASSPORT_FIXTURE.get("agent_id") or PASSPORT_FIXTURE.get("passport_id")}
    policy_arg = _load_policy_pack(repo_root) if use_policy_body else {"capability": "system.command.execute.v1"}
    pack_id = "system.command.execute.v1"
    context = {"tool": "system.command.execute", "input": '{"command":"ls"}'}

    async def run():
        for _ in range(warmup):
            await asyncio.to_thread(
                _call_api_sync,
                api_url,
                pack_id,
                context,
                agent_id=None if use_passport_body else agent_id,
                passport=passport_body,
                policy_pack=policy_arg if use_policy_body else None,
            )
        latencies = []
        for _ in range(iterations):
            t0 = time.perf_counter()
            await asyncio.to_thread(
                _call_api_sync,
                api_url,
                pack_id,
                context,
                agent_id=None if use_passport_body else agent_id,
                passport=passport_body,
                policy_pack=policy_arg if use_policy_body else None,
            )
            latencies.append((time.perf_counter() - t0) * 1000)
        return latencies

    return asyncio.run(run())


def run_bash_api_agent(
    iterations: int, warmup: int, repo_root: Path, api_url: str, agent_id: str
) -> list:
    """Bash API: APORT_AGENT_ID (cloud); policy from path only. Latency = E2E (spawn + script + API), not pure HTTP."""
    script = repo_root / "bin" / "aport-guardrail-api.sh"
    if not script.exists():
        raise FileNotFoundError(str(script))
    env = os.environ.copy()
    env["APORT_AGENT_ID"] = agent_id
    env["APORT_API_URL"] = api_url
    latencies = []
    for _ in range(warmup + iterations):
        t0 = time.perf_counter()
        subprocess.run(
            [str(script), "system.command.execute", '{"command":"ls"}'],
            capture_output=True, env=env, cwd=str(repo_root), timeout=30,
        )
        latencies.append((time.perf_counter() - t0) * 1000)
    return latencies[warmup:]


def run_bash_api_passport(
    iterations: int, warmup: int, repo_root: Path, api_url: str
) -> list:
    """Bash API: passport in body (OPENCLAW_PASSPORT_FILE); policy from path only. Latency = E2E (spawn + script + API)."""
    script = repo_root / "bin" / "aport-guardrail-api.sh"
    if not script.exists():
        raise FileNotFoundError(str(script))
    with tempfile.TemporaryDirectory() as tmp:
        pf = Path(tmp) / "passport.json"
        pf.write_text(json.dumps(PASSPORT_FIXTURE))
        env = os.environ.copy()
        env["OPENCLAW_PASSPORT_FILE"] = str(pf)
        env["APORT_API_URL"] = api_url
        latencies = []
        for _ in range(warmup + iterations):
            t0 = time.perf_counter()
            subprocess.run(
                [str(script), "system.command.execute", '{"command":"ls"}'],
                capture_output=True, env=env, cwd=str(repo_root), timeout=30,
            )
            latencies.append((time.perf_counter() - t0) * 1000)
        return latencies[warmup:]


def run_node_api_mock(iterations: int, warmup: int, repo_root: Path) -> list:
    harness = repo_root / "tests" / "performance" / "node_api_harness.cjs"
    total = warmup + iterations
    out = subprocess.run(
        ["node", str(harness), str(total), "https://api.example.com"],
        capture_output=True,
        text=True,
        cwd=str(repo_root),
        timeout=60,
    )
    if out.returncode != 0:
        return []
    try:
        all_latencies = json.loads(out.stdout.strip())
        return all_latencies[warmup:] if len(all_latencies) >= total else all_latencies
    except (json.JSONDecodeError, IndexError):
        return []


def run_bash_local(iterations: int, warmup: int, repo_root: Path) -> list:
    script = repo_root / "bin" / "aport-guardrail-bash.sh"
    if not script.exists():
        return []
    with tempfile.TemporaryDirectory() as tmp:
        passport_file = Path(tmp) / "passport.json"
        passport_file.write_text(json.dumps(PASSPORT_FIXTURE))
        env = os.environ.copy()
        env["OPENCLAW_PASSPORT_FILE"] = str(passport_file)
        latencies = []
        for _ in range(warmup + iterations):
            t0 = time.perf_counter()
            subprocess.run(
                [str(script), "system.command.execute", '{"command":"ls"}'],
                capture_output=True,
                env=env,
                cwd=str(repo_root),
                timeout=5,
            )
            latencies.append((time.perf_counter() - t0) * 1000)
        return latencies[warmup:]


def run_bash_api_mock(iterations: int, warmup: int, repo_root: Path) -> list:
    import importlib.util
    from http.server import HTTPServer

    spec = importlib.util.spec_from_file_location(
        "mock_api_server",
        repo_root / "tests" / "performance" / "mock_api_server.py",
    )
    mod = importlib.util.module_from_spec(spec)
    old_argv = sys.argv
    sys.argv = ["mock_api_server.py", "0"]
    try:
        spec.loader.exec_module(mod)
    finally:
        sys.argv = old_argv
    MockVerifyHandler = mod.MockVerifyHandler

    server = HTTPServer(("127.0.0.1", 0), MockVerifyHandler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    time.sleep(0.3)

    script = repo_root / "bin" / "aport-guardrail-api.sh"
    if not script.exists():
        return []
    with tempfile.TemporaryDirectory() as tmp:
        passport_file = Path(tmp) / "passport.json"
        passport_file.write_text(json.dumps(PASSPORT_FIXTURE))
        env = os.environ.copy()
        env["OPENCLAW_PASSPORT_FILE"] = str(passport_file)
        env["APORT_API_URL"] = f"http://127.0.0.1:{port}"
        latencies = []
        for _ in range(warmup + iterations):
            t0 = time.perf_counter()
            try:
                subprocess.run(
                    [str(script), "system.command.execute", '{"command":"ls"}'],
                    capture_output=True,
                    env=env,
                    cwd=str(repo_root),
                    timeout=15,
                )
            except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
                break
            latencies.append((time.perf_counter() - t0) * 1000)
        return latencies[warmup:]


def run_python_local(iterations: int, warmup: int, repo_root: Path) -> list:
    import asyncio
    from aport_guardrails.core.evaluator import Evaluator

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        passport_file = tmp / "passport.json"
        passport_file.write_text(json.dumps(PASSPORT_FIXTURE))
        config_file = tmp / "config.yaml"
        guardrail_script = repo_root / "bin" / "aport-guardrail-bash.sh"
        config_file.write_text(
            f"mode: local\npassport_path: {passport_file}\nguardrail_script: {guardrail_script}\n"
        )
        evaluator = Evaluator(config_path=str(config_file))

        async def run():
            for _ in range(warmup):
                await evaluator.verify(
                    {"agent_id": "perf-a1"},
                    {"capability": "system.command.execute.v1"},
                    {"tool": "system.command.execute", "input": '{"command":"ls"}'},
                )
            latencies = []
            for _ in range(iterations):
                t0 = time.perf_counter()
                await evaluator.verify(
                    {"agent_id": "perf-a1"},
                    {"capability": "system.command.execute.v1"},
                    {"tool": "system.command.execute", "input": '{"command":"ls"}'},
                )
                latencies.append((time.perf_counter() - t0) * 1000)
            return latencies

        try:
            return asyncio.run(run())
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return []


# -----------------------------------------------------------------------------
# Output: grouped (Apple-style, narrow) and wide table
# -----------------------------------------------------------------------------


def _short_identity(identity: str) -> str:
    if identity and "agent_id" in identity:
        return "agent_id"
    if identity and "passport in body" in identity:
        return "passport"
    if identity and "passport file" in identity:
        return "passport"
    return (identity or "—")[:12]


def _short_policy(policy: str) -> str:
    if not policy or policy == "—":
        return "—"
    if "body" in policy:
        return "body"
    return "path"


def build_grouped_report(rows, max_width=58):
    """Stack by Language; compact lines (Apple-style). Keeps width under max_width."""
    by_lang = {}
    for r in rows:
        lang = r.get("language", "")
        by_lang.setdefault(lang, []).append(r)

    lines = []
    for lang in ("Node", "Python", "Bash"):
        if lang not in by_lang:
            continue
        block = by_lang[lang]
        lines.append("")
        lines.append(f"  {lang}")  # section header
        for i, r in enumerate(block):
            last = i == len(block) - 1
            prefix = "  └─ " if last else "  ├─ "
            method = (r.get("method") or "").strip()[:5]  # "API" or "Local"
            ident = _short_identity(r.get("identity") or "")
            pol = _short_policy(r.get("policy") or "")
            if r.get("n") == "—" or r.get("mean") is None:
                lat = "—"
                p95_str = ""
            else:
                lat = f"{format_ms(r['mean'])} ms"
                p95_str = f"  (p95 {format_ms(r.get('p95') or 0)})"
            note = (r.get("notes") or "").strip()
            if note:
                note = f"  · {note[:26]}" if len(note) > 26 else f"  · {note}"
            line = f"{prefix}{method}  {ident} · {pol}  {lat}{p95_str}{note}"
            if len(line) > max_width and note:
                line = f"{prefix}{method}  {ident} · {pol}  {lat}{p95_str}"
                lines.append(line)
                lines.append(f"      {note.strip()}")
            else:
                lines.append(line)
    return "\n".join(lines).lstrip()


def _latency_cell(r) -> list:
    """One cell content as 4 lines: mean, p50, p95, p99 (stacked). N/A → one line '—'."""
    if r.get("n") == "—" or r.get("mean") is None:
        return ["—"]
    return [
        f"mean {format_ms(r['mean'])}",
        f"p50  {format_ms(r.get('p50') or 0)}",
        f"p95  {format_ms(r.get('p95') or 0)}",
        f"p99  {format_ms(r.get('p99') or 0)}",
    ]


def _print_pure_latency_note(results: list) -> None:
    """Print a one-line reference: pure API latency = Node/Python (eval/HTTP only); Bash = E2E."""
    has_node_python_api = any(
        r.get("language") in ("Node", "Python") and r.get("method") == "API" and r.get("n") != "—"
        for r in results
    )
    if has_node_python_api:
        print("  · Pure API latency (reference): Node and Python = eval/HTTP only. Bash API = E2E (spawn+script+API).")


# Canonical note text -> footnote number (for table footer)
NOTE_TO_FOOTNOTE = {
    "No local evaluator": "¹",
    "policy in body not yet": "²",
    "E2E (spawn+script+API)": "³",
    "per-call process spawn": "³",
    "script does not support": "⁴",
}


def build_table(rows):
    """ASCII table: Language | Method | Identity | Policy | Latency (stacked) | N | ref. Notes as footnotes."""
    headers = ["Language", "Method", "Identity", "Policy", "Latency (ms)", "N", " "]
    w_lang = max(8, max(len(str(r.get("language", ""))) for r in rows))
    w_method = max(6, max(len(str(r.get("method", ""))) for r in rows))
    w_ident = max(10, max(len(str(r.get("identity", ""))) for r in rows))
    w_policy = max(8, max(len(str(r.get("policy", ""))) for r in rows))
    w_lat = 14
    w_n = 4
    w_ref = 2
    col_widths = [w_lang, w_method, w_ident, w_policy, w_lat, w_n, w_ref]

    def sep_line():
        return "+" + "+".join("-" * (c + 2) for c in col_widths) + "+"

    def row_line(*vals):
        return "|" + "|".join(f" {str(v or ''):<{col_widths[i]}} " for i, v in enumerate(vals)) + "|"

    # Assign footnote ref per row (only when note is non-empty and matches)
    refs = []
    for r in rows:
        note = (r.get("notes") or "").strip()
        ref = ""
        if note:
            for key, mark in NOTE_TO_FOOTNOTE.items():
                if key in note:
                    ref = mark
                    break
        refs.append(ref)

    out = [sep_line(), row_line(*headers), sep_line()]
    for r, ref in zip(rows, refs):
        lat_lines = _latency_cell(r)
        n_val = r.get("n") if r.get("n") != "—" else "—"
        lang = r.get("language", "")
        method = r.get("method", "")
        ident = (r.get("identity") or "")[: col_widths[2]]
        policy = (r.get("policy") or "")[: col_widths[3]]
        for i, lat in enumerate(lat_lines):
            if i == 0:
                out.append(row_line(lang, method, ident, policy, lat, n_val, ref))
            else:
                out.append(row_line("", "", "", "", lat, "", ""))
        out.append(sep_line())

    # Footnotes (only include those that appear in the table)
    used = set(refs)
    footnotes = []
    if "¹" in used:
        footnotes.append("¹ No local evaluator (Node).")
    if "²" in used:
        footnotes.append("² Policy in body not yet for local.")
    if "³" in used:
        footnotes.append("³ Bash API: E2E (subprocess spawn + script + API). For pure API latency use Node or Python.")
    if "⁴" in used:
        footnotes.append("⁴ Script does not support policy in body.")
    if footnotes:
        out.append("")
        out.append("  " + "  ".join(footnotes))
    return "\n".join(out)


def build_table_wide(rows):
    """Full 10-column table (original wide layout)."""
    headers = ["Language", "Method", "Identity", "Policy", "Mean (ms)", "p50", "p95", "p99", "N", "Notes"]
    col_widths = [10, 6, 18, 12, 10, 8, 8, 8, 4, 24]
    for r in rows:
        for i, k in enumerate(["language", "method", "identity", "policy", "mean", "p50", "p95", "p99", "n", "notes"]):
            val = r.get(k)
            if k in ("mean", "p50", "p95", "p99") and val is not None and r.get("n") != "—":
                val = format_ms(val)
            col_widths[i] = max(col_widths[i], len(str(val or "")))
    w = col_widths
    sep = "+" + "+".join("-" * (wi + 2) for wi in w) + "+"
    line = "|" + "|".join(f" {{:<{wi}}} " for wi in w) + "|"
    def fmt_row(*vals):
        return line.format(*[str(v or "")[: w[i]] for i, v in enumerate(vals)])
    out = [sep, fmt_row(*headers), sep]
    for r in rows:
        mean = format_ms(r["mean"]) if r.get("n") != "—" and r.get("mean") is not None else (r.get("mean") or "—")
        p50 = format_ms(r["p50"]) if r.get("n") != "—" and r.get("p50") is not None else (r.get("p50") or "—")
        p95 = format_ms(r["p95"]) if r.get("n") != "—" and r.get("p95") is not None else (r.get("p95") or "—")
        p99 = format_ms(r["p99"]) if r.get("n") != "—" and r.get("p99") is not None else (r.get("p99") or "—")
        n = r.get("n") if r.get("n") != "—" else "—"
        out.append(fmt_row(r.get("language", ""), r.get("method", ""), r.get("identity", ""), r.get("policy", ""), mean, p50, p95, p99, n, r.get("notes") or ""))
    out.append(sep)
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(
        description="Guardrail latency: real API + Local, all languages, identity/policy variants (infra-style report)."
    )
    ap.add_argument("--iterations", "-n", type=int, default=30,
                    help="Timed runs per scenario (default 30; use 50+ for docs)")
    ap.add_argument("--warmup", "-w", type=int, default=10,
                    help="Warmup runs excluded from stats (default 10 for stable numbers)")
    ap.add_argument("--output", "-o", choices=["table", "grouped", "wide", "json", "markdown"], default="table",
                help="table=ASCII table, latency stacked (default); grouped=tree by lang; wide=all columns; json|markdown")
    ap.add_argument("--agent-id", "-a", default="ap_dd86bb4458524d4db529de7de9e8dc8a", help="Remote passport agent_id (API cloud)")
    ap.add_argument("--api-url", "-u", default=os.environ.get("APORT_API_URL", "https://api.aport.io"), help="APort API base URL")
    ap.add_argument("--mock", action="store_true", help="Run mock/local only (no real API)")
    ap.add_argument("--skip-bash", action="store_true", help="Skip Bash scenarios")
    args = ap.parse_args()

    repo_root = REPO_ROOT
    iterations = max(1, min(args.iterations, 500))
    warmup = max(0, min(args.warmup, 50))
    api_url = (args.api_url or "https://api.aport.io").rstrip("/")
    agent_id = args.agent_id or "ap_dd86bb4458524d4db529de7de9e8dc8a"

    if args.mock:
        print("  ⚠️  MOCK MODE — No real API calls. All 'API' scenarios use in-process mocks (no HTTP).")
        print("      Node/Python API: in-process only (~0–2 ms). Bash API: E2E (spawn+script+API), ~80 ms.")
        print("      To measure actual API latency, run WITHOUT --mock (e.g. no --mock flag).")
        print()
        _scenarios = [
            ("Node", "API", "mock", "path", None, lambda: run_node_api_mock(iterations, warmup, repo_root)),
            ("Python", "API", "mock", "path", None, lambda: run_python_api_mock_async(iterations, warmup)),
            ("Python", "Local", "passport file", "path", "policy in body not yet", lambda: run_python_local(iterations, warmup, repo_root)),
            ("Bash", "Local", "passport file", "path", None, lambda: run_bash_local(iterations, warmup, repo_root)),
            ("Bash", "API", "mock", "path", None, lambda: run_bash_api_mock(iterations, warmup, repo_root)),
        ]
        scenario_rows = [(lang, method, ident, pol, notes) for lang, method, ident, pol, notes, _ in _scenarios]
        runners = [r for *_, r in _scenarios]
    else:
        print("  🌐 REAL API MODE — Node and Python will call the actual API (pure latency). Bash = E2E (spawn+script+API).")
        print(f"      API: {api_url}   Agent: {agent_id[:32]}…")
        print("      Ensure your agent_id is valid (create at aport.io or use a hosted passport).")
        try:
            _probe_real_api(api_url, agent_id, repo_root)
        except Exception as e:
            print(f"      Probe failed; continuing anyway. Error: {e}")
        print()
        # Full matrix: Language, Method, Identity, Policy, Notes, runner
        def node_agent_path(): return _run_node_harness(iterations, warmup, repo_root, api_url, "agent_path", agent_id)
        def node_agent_body(): return _run_node_harness(iterations, warmup, repo_root, api_url, "agent_body", agent_id)
        def node_passport_path():
            with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
                f.write(json.dumps(PASSPORT_FIXTURE))
                path_ = f.name
            try:
                return _run_node_harness(iterations, warmup, repo_root, api_url, "passport_path", path_)
            finally:
                Path(path_).unlink(missing_ok=True)
        def node_passport_body():
            with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
                f.write(json.dumps(PASSPORT_FIXTURE))
                path_ = f.name
            try:
                return _run_node_harness(iterations, warmup, repo_root, api_url, "passport_body", path_)
            finally:
                Path(path_).unlink(missing_ok=True)

        scenario_rows = []
        runners = []

        # Python first, then Node, then Bash
        # Python: 4 API + 1 Local
        scenario_rows += [
            ("Python", "API", "agent_id (cloud)", "pack in path", None),
            ("Python", "API", "agent_id (cloud)", "policy in body", None),
            ("Python", "API", "passport in body", "pack in path", None),
            ("Python", "API", "passport in body", "policy in body", None),
            ("Python", "Local", "passport file", "pack in path", "policy in body not yet"),
        ]
        runners += [
            lambda: run_python_api_variant(iterations, warmup, api_url, agent_id, False, False, repo_root),
            lambda: run_python_api_variant(iterations, warmup, api_url, agent_id, False, True, repo_root),
            lambda: run_python_api_variant(iterations, warmup, api_url, agent_id, True, False, repo_root),
            lambda: run_python_api_variant(iterations, warmup, api_url, agent_id, True, True, repo_root),
            lambda: run_python_local(iterations, warmup, repo_root),
        ]

        # Node: 4 API variants + Local N/A
        scenario_rows += [
            ("Node", "API", "agent_id (cloud)", "pack in path", None),
            ("Node", "API", "agent_id (cloud)", "policy in body", None),
            ("Node", "API", "passport in body", "pack in path", None),
            ("Node", "API", "passport in body", "policy in body", None),
            ("Node", "Local", "—", "—", "No local evaluator"),
        ]
        runners += [node_agent_path, node_agent_body, node_passport_path, node_passport_body, None]

        # Bash: 2 API (path only) + 2 N/A (policy in body) + 1 Local
        if not args.skip_bash:
            scenario_rows += [
                ("Bash", "API", "agent_id (cloud)", "pack in path", "E2E (spawn+script+API)"),
                ("Bash", "API", "passport in body", "pack in path", "E2E (spawn+script+API)"),
                ("Bash", "API", "agent_id (cloud)", "policy in body", "script does not support"),
                ("Bash", "API", "passport in body", "policy in body", "script does not support"),
                ("Bash", "Local", "passport file", "pack in path", None),
            ]
            runners += [
                lambda: run_bash_api_agent(iterations, warmup, repo_root, api_url, agent_id),
                lambda: run_bash_api_passport(iterations, warmup, repo_root, api_url),
                None,
                None,
                lambda: run_bash_local(iterations, warmup, repo_root),
            ]

    results = []
    for (language, method, identity, policy, notes), runner in zip(scenario_rows, runners):
        row = {
            "language": language,
            "method": method,
            "identity": identity,
            "policy": policy,
            "notes": notes or "",
        }
        if runner is None:
            row["mean"] = row["p50"] = row["p95"] = row["p99"] = None
            row["n"] = "—"
            results.append(row)
            continue
        try:
            latencies = runner()
            s = stats(latencies)
            row["mean"] = s["mean"]
            row["p50"] = s["p50"]
            row["p95"] = s["p95"]
            row["p99"] = s["p99"]
            row["n"] = s["n"]
            results.append(row)
        except Exception as e:
            if os.environ.get("APORT_PERF_VERBOSE"):
                import traceback
                traceback.print_exc()
            row["mean"] = row["p50"] = row["p95"] = row["p99"] = None
            row["n"] = 0
            row["error"] = str(e)
            row["notes"] = (row.get("notes") or "") + (" " if row.get("notes") else "") + ("error: " + str(e)[:40])
            results.append(row)

    if args.output == "json":
        print(json.dumps(results, indent=2))
        return
    if args.output == "markdown":
        print("| Language | Method | Identity | Policy | Mean (ms) | p50 | p95 | p99 | N | Notes |")
        print("|----------|--------|----------|--------|-----------|-----|-----|-----|---|-------|")
        for r in results:
            mean = format_ms(r["mean"]) if r.get("n") != "—" and r.get("mean") is not None else "—"
            p50 = format_ms(r["p50"]) if r.get("n") != "—" and r.get("p50") is not None else "—"
            p95 = format_ms(r["p95"]) if r.get("n") != "—" and r.get("p95") is not None else "—"
            p99 = format_ms(r["p99"]) if r.get("n") != "—" and r.get("p99") is not None else "—"
            n = r.get("n", "—")
            print(f"| {r['language']} | {r['method']} | {r.get('identity','')} | {r.get('policy','')} | {mean} | {p50} | {p95} | {p99} | {n} | {r.get('notes','')} |")
        return

    # Report
    print("  APort Guardrail — Latency (real API + Local)")
    print(f"  API: {api_url}   Agent: {agent_id[:24]}…   n={iterations}  warmup={warmup}")
    print()
    if args.output == "wide":
        print(build_table_wide(results))
    elif args.output == "grouped":
        print(build_grouped_report(results))
        print()
        _print_pure_latency_note(results)
        print("  · Bash API: E2E (spawn+script+API). Local: policy in body not yet.")
    else:
        # table = proper ASCII table with stacked latency (mean, p50, p95, p99)
        print(build_table(results))
        print()
        _print_pure_latency_note(results)
        print("  · Latency: mean, p50, p95, p99 (ms). Warmup excluded; N = timed samples. Pure API ref = Node/Python.")
        if args.mock:
            print("  · API (mock): no HTTP — in-process only. For real server latency run without --mock.")
        print("  · For docs: run with -n 50 -w 10 (or default -n 30 -w 10) when machine is idle.")
    print()


if __name__ == "__main__":
    main()

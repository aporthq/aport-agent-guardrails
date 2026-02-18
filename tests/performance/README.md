# Guardrail performance tests

Measures **latency** of the guardrail path with **real API verification** (real passport + policy). Use this to track performance, compare implementations, and report metrics.

**Default = real API.** If you run the script **without** `--mock`, it sends **real HTTP requests** to the APort API. You will see server latency (typically tens to hundreds of ms). Use `--agent-id <your_agent_id>` (or set `APORT_AGENT_ID`). Create a passport at [APort](https://aport.io) to get an `agent_id`.

**`--mock` = no network.** With `--mock`, all "API" scenarios use **in-process mocks** (no HTTP). Timings will be ~0–0.2 ms for Node/Python and ~80 ms for Bash (process spawn). Use `--mock` only for local comparison or when you cannot reach the API.

## Quick run (real API — requests hit the server)

From **repo root**:

```bash
# Real API: requests are sent to https://api.aport.io (or APORT_API_URL)
PYTHONPATH=python python3 tests/performance/run_guardrail_perf.py --agent-id <your_agent_id>
```

If you don’t pass `--agent-id`, the script uses a default (may not exist on the server; use your own for valid results). **Create a passport** at [aport.io](https://aport.io) to get an `agent_id`; then run the benchmark for your region and API endpoint.

**API URL:** Default is `https://api.aport.io`. Override with `--api-url` or `APORT_API_URL` (e.g. for self-hosted or a different region).

## Arguments

- `--agent-id ID` — Your **hosted passport** agent ID (or set `APORT_AGENT_ID`). Required for real API runs.
- `--api-url URL` — API base (default: https://api.aport.io or `APORT_API_URL`).
- `--iterations N` (default 30) — Timed runs per scenario (use 50+ for documentation).
- `--warmup W` (default 10) — Warmup runs excluded from stats (reduces cold-start variance).
- `--output table|grouped|wide|json|markdown` — Output format.
- `--skip-bash` — Skip Bash-based scenarios.
- `--mock` — **No real API calls.** All "API" scenarios use in-process mocks; timings ~0–0.2 ms. Use only for local comparison.

**Methodology:** Each scenario runs `warmup` iterations (discarded), then `iterations` timed runs. Reported mean and p50/p95/p99 are from the timed runs only. API latency includes network RTT and server evaluation; Bash API also includes per-call process spawn.

**Documentation-quality results:** For numbers you can document or compare over time, run with more samples and minimal background load:

```bash
PYTHONPATH=python python3 tests/performance/run_guardrail_perf.py --agent-id <your_agent_id> -n 50 -w 10
```

Run when the machine is idle. Use the same API and agent_id when comparing runs.

## Examples

```bash
# Your hosted passport (recommended)
PYTHONPATH=python python3 tests/performance/run_guardrail_perf.py --agent-id <your_agent_id>

# Custom API (e.g. self-hosted)
PYTHONPATH=python python3 tests/performance/run_guardrail_perf.py --agent-id <your_agent_id> --api-url https://your-api.example.com

# More samples for docs
PYTHONPATH=python python3 tests/performance/run_guardrail_perf.py --agent-id <your_agent_id> -n 50 -w 10

# JSON for CI/reporting
PYTHONPATH=python python3 tests/performance/run_guardrail_perf.py --agent-id <your_agent_id> -o json

# Mock only (no HTTP; in-process; timings ~0 ms for API)
PYTHONPATH=python python3 tests/performance/run_guardrail_perf.py --mock
```

## Scenarios (real API)

| Language | Method       | Description |
|----------|--------------|-------------|
| **Python** | API (real) | `Evaluator.verify()` with `agent_id`; real API (typically fastest). |
| **Node** | API (real)   | `loadPolicyPack()` + `evaluatePolicy()` with `agentId`; real API. |
| **Bash** | API (real)   | `bin/aport-guardrail-api.sh` with `APORT_AGENT_ID`; real API (includes per-call process spawn). |

All scenarios verify against your **remote passport** and **real policy** (e.g. system.command.execute.v1). Local (no API) scenarios also run for Python and Bash where supported.

## Output

- **table** (default) — ASCII table with Language, Method, Identity, Policy, Latency (mean/p50/p95/p99), N, and footnotes.
- **grouped** — Tree view by language.
- **wide** — Full column set.
- **json** | **markdown** — For CI or docs.

Lower latency is better. N = number of timed samples (warmup excluded).

## Reporting and improving performance

1. **Baseline** — Run with your agent_id and default or `-n 50 -w 10`; record table or JSON.  
2. **Compare** — Re-run with same `-n`/`-w` and compare mean/p95 across languages.  
3. **Report** — Use `--output markdown` for PRs/docs; `--output json` for CI.  
4. **Stable numbers** — Higher `-n` (e.g. 50) and `-w` (10); run when machine is idle.

**Requirements:** Python 3.10+, Node (for Node/Bash API), network access to APort API. A valid **agent_id** (hosted passport from [APort](https://aport.io)) for real API runs.

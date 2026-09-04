# Framework Drift Watch

APort supports fast-moving agent runtimes. The weekly drift watch keeps that
support honest without depending on manual memory or AI-generated guesses.

## What It Checks

The checker in `scripts/framework-drift-check.mjs` reads one watchlist covering:

- OpenClaw plugin hooks
- Cursor hooks
- Claude Code hooks
- LangChain / LangGraph middleware
- CrewAI tool and MCP events
- DeerFlow 2.x harness docs
- n8n AI Agent and preview Agents docs
- GitHub Actions workflow/OIDC docs

For each upstream source it verifies required markers and compares the current
source signature or latest tag against `docs/framework-drift-baseline.json`.

## Weekly Workflow

`.github/workflows/framework-drift-watch.yml` runs every Monday and can be run
manually. It writes a Markdown report to the job summary, uploads the JSON and
Markdown reports as artifacts, and creates or updates a `framework-drift` issue
when any source changes or becomes unreachable.

## Updating The Baseline

Only update the baseline after reviewing the upstream changes and confirming
that APort's implementation and docs are still accurate.

```bash
node scripts/framework-drift-check.mjs --update-baseline
```

Then review:

```bash
git diff docs/framework-drift-baseline.json
```

Do not update the baseline just to make a scheduled issue disappear. Treat the
issue as a prompt to inspect the affected framework integration and its tests.

## Local Smoke Test

The test suite runs the checker in offline mode so CI does not depend on
upstream framework availability:

```bash
bash tests/unit/test-framework-drift-check.sh
```

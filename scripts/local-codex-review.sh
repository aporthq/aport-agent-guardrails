#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${CODEX_REVIEW_BASE:-origin/staging}"
PROMPT_FILE="${CODEX_REVIEW_PROMPT_FILE:-$REPO_ROOT/.github/codex/prompts/guardrails-review.md}"

cd "$REPO_ROOT"

if ! command -v codex > /dev/null 2>&1; then
    echo "[aport] ERROR: codex CLI is not installed or not on PATH." >&2
    echo "[aport] Install/login to Codex, then rerun npm run local-pr-review." >&2
    exit 1
fi

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "[aport] ERROR: local Codex review must run inside a git worktree." >&2
    exit 1
fi

if ! git rev-parse --verify "$BASE" > /dev/null 2>&1; then
    echo "[aport] ERROR: review base '$BASE' is not available locally." >&2
    echo "[aport] Run: git fetch origin staging" >&2
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    echo "[aport] ERROR: Codex review prompt not found at $PROMPT_FILE." >&2
    exit 1
fi

echo "[aport] Running Codex local review against $BASE"
echo "[aport] Review rules: $REPO_ROOT/AGENTS.md"
if [ -f "$PROMPT_FILE" ]; then
    echo "[aport] Supplemental prompt for CI codex exec workflows: $PROMPT_FILE"
fi

# The current Codex CLI does not accept a custom positional prompt together
# with --base, so shared review guidance lives in AGENTS.md, which Codex reads
# for both local and GitHub PR reviews.
exec codex review --base "$BASE"

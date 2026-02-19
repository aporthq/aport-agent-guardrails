#!/usr/bin/env bash
# Add APort Agent Guardrails to an awesome list and open a PR.
# Uses standard open-source workflow: fork upstream → clone your fork → edit → push → PR to upstream.
#
# Usage:
#   ./docs/launch/scripts/add-aport-awesome-pr.sh <owner/repo>        # fork (if needed), clone fork, create branch
#   ./docs/launch/scripts/add-aport-awesome-pr.sh <owner/repo> pr       # commit (if any), push to your fork, open PR to upstream
#
# Clones go to /tmp/aport-awesome-prs/<owner>-<repo>/ (e.g. SamurAIGPT-awesome-openclaw). Origin = your fork.
# See docs/launch/ADD_APORT_AWESOME_LISTS_INSTRUCTIONS.md for per-repo edit instructions.

set -e
REPO="${1:?Usage: $0 <owner/repo> [pr]}"
STEP="${2:-clone}"
TEMP_BASE="/tmp/aport-awesome-prs"
# Unique dir per owner/repo so e2b-dev/awesome-ai-agents and slavakurilyak/awesome-ai-agents don't collide
DIR_NAME="${REPO//\//-}"
CLONE_DIR="${TEMP_BASE}/${DIR_NAME}"
REPO_NAME="${REPO#*/}"
BRANCH="add-aport-agent-guardrails"

PR_TITLE="Add APort Agent Guardrails"
PR_BODY="Adds [APort Agent Guardrails](https://github.com/aporthq/aport-agent-guardrails) — pre-action authorization for OpenClaw and compatible agent frameworks. Policy runs in the platform \`before_tool_call\` hook; 40+ blocked patterns, allowlist, local or API. Setup: \`npx @aporthq/aport-agent-guardrails\`."

case "$STEP" in
  clone)
    mkdir -p "$TEMP_BASE"
    if [[ -d "$CLONE_DIR" ]]; then
      echo "Directory already exists: $CLONE_DIR (your fork clone)"
      echo "To start over, remove it first: rm -rf $CLONE_DIR"
      cd "$CLONE_DIR"
      git fetch origin
      if git checkout "$BRANCH" 2>/dev/null; then true; else git checkout main 2>/dev/null || git checkout master; git pull origin HEAD; git checkout -b "$BRANCH"; fi
    else
      cd "$TEMP_BASE"
      # Fork upstream to your account and clone the fork (origin = your fork)
      gh repo fork "$REPO" --clone
      # Move clone to unique dir (owner-repo) so same repo name from different owners don't collide
      [[ -d "$REPO_NAME" ]] && [[ "$REPO_NAME" != "$DIR_NAME" ]] && mv "$REPO_NAME" "$DIR_NAME"
      cd "$CLONE_DIR"
      git checkout -b "$BRANCH"
    fi
    echo ""
    echo "Clone (your fork): $CLONE_DIR"
    echo "Branch: $BRANCH"
    echo "PR will go: your fork → $REPO"
    echo ""
    echo "Next: Edit the file(s) per repo (see ADD_APORT_AWESOME_LISTS_INSTRUCTIONS.md)."
    echo "Then run: $0 $REPO pr"
    ;;
  pr)
    if [[ ! -d "$CLONE_DIR" ]]; then
      echo "Clone dir not found: $CLONE_DIR. Run: $0 $REPO first (fork and clone)."
      exit 1
    fi
    cd "$CLONE_DIR"
    git add -A
    if ! git diff --staged --quiet || ! git diff --quiet; then
      git commit -m "$PR_TITLE"
    fi
    git push -u origin "$BRANCH"
    gh pr create --title "$PR_TITLE" --body "$PR_BODY"
    echo "PR created: your fork → $REPO"
    ;;
  *)
    echo "Unknown step: $STEP. Use 'clone' (default) or 'pr'."
    exit 1
    ;;
esac

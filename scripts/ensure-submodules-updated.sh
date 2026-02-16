#!/bin/bash
# Ensure submodules are initialized and optionally up-to-date before push.
# Exits 0 if OK; 1 if submodules were updated and need to be committed (blocks push until committed).
# Usage: ./scripts/ensure-submodules-updated.sh [--update-remote]
#   --update-remote: run git submodule update --remote first (fetch latest); then require commit if refs changed.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

UPDATE_REMOTE=false
for arg in "$@"; do
    case "$arg" in
        --update-remote) UPDATE_REMOTE=true ;;
    esac
done

# Ensure submodules exist (support both old and new layout)
if [ -f .gitmodules ]; then
    git submodule update --init --recursive
fi

# Optionally fetch latest from remotes and update working tree to latest commit
if [ "$UPDATE_REMOTE" = true ]; then
    git submodule update --remote --recursive
fi

# Check if any submodule refs are uncommitted (would mean we updated and didn't commit)
SUBMODULE_STATUS=$(git submodule status 2>/dev/null || true)
if [ -z "$SUBMODULE_STATUS" ]; then
    exit 0
fi

# git submodule status: leading + means submodule is at a different commit than recorded in parent
if git submodule status 2>/dev/null | grep -q '^+'; then
    echo "error: Submodule references were updated but not committed." >&2
    echo "  Run: git add external/ && git commit -m 'chore: Update submodules to latest'" >&2
    echo "  Then push again." >&2
    exit 1
fi

# Uncommitted submodule refs (modified in index)
if git status 2>/dev/null | grep -q "new commits"; then
    echo "error: Submodules have new commits. Commit the submodule reference updates before pushing." >&2
    echo "  Run: git add external/ && git commit -m 'chore: Update submodules to latest'" >&2
    exit 1
fi

exit 0

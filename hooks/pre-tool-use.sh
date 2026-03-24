#!/usr/bin/env bash
# APort PreToolUse hook entry point for Claude Code plugin.
# Sets ROOT_DIR to the repo/plugin root so all scripts resolve
# dependencies correctly, then execs the real hook.
set -e

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT_DIR="$(cd "$HOOK_DIR/.." && pwd)"

exec "$ROOT_DIR/bin/aport-claude-code-hook.sh"

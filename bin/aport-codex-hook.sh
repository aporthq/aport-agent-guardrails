#!/usr/bin/env bash
# Thin Codex wrapper around the shared APort command-hook adapter.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/lib/command-hook-adapter.sh" codex "$@"

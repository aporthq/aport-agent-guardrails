#!/usr/bin/env bash
# Alias for the creator CLI name: `gemini`.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/gemini-cli.sh" "$@"

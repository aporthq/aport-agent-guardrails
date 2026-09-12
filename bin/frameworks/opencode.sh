#!/usr/bin/env bash
# opencode setup is intentionally gated until the plugin API version is smoke-tested.

set -euo pipefail

echo "[aport] opencode support is planned but not enabled in this release." >&2
echo "[aport] Reason: opencode v2 plugin hooks require installed-version validation before APort can safely claim enforcement." >&2
echo "[aport] Track this in docs/FRAMEWORK_ROADMAP.md. Use GitHub Repository Guard, Claude Code, Cursor, Codex, Gemini CLI, Goose, OpenClaw, LangChain, CrewAI, DeerFlow, or n8n today." >&2
exit 1

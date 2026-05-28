#!/usr/bin/env bash
# APort generic device install — macOS, Linux, and Windows (via Node.js).
#
# Registers the device with APort, mints a runtime setup key, and runs the
# framework installer (e.g. Claude Code, Cursor) in API guardrail mode.
#
# Requirements on the device: Node.js 18+, npm/npx, curl.
# Windows: run with PowerShell using aport-device-deploy.ps1, or Git Bash / WSL with this script.

set -euo pipefail

# ==============================================================================
# APORT DEVICE DEPLOYMENT - EDIT THIS SECTION ONLY
# ==============================================================================
#
# Required values:
#
#   Variable             Example / Allowed values
#   -------------------  --------------------------------------------------------
#   APORT_API_KEY        apk_... with "issue" scope from the APort dashboard
#   APORT_TEMPLATE_ID    ap_... template passport to instantiate per device/user
#   APORT_FRAMEWORK      claude-code | cursor | openclaw | langchain | crewai |
#                        deerflow | n8n
#
# Optional values:
#
#   Variable             Default
#   -------------------  --------------------------------------------------------
#   APORT_API_URL        https://api.aport.io
#   APORT_TARGET_USER    interactive user on the device (OS-specific detection)
#   APORT_TARGET_HOME    user profile / home directory
#   APORT_DEVICE_ID      stable device identifier (OS-specific if unset)
#   APORT_STATE_DIR      OS-specific system state directory (see README)
#   DISABLE_DEVICE_INFO  false           # set to 1/true/yes to skip device metadata
#
# Run as the target user, or as root/admin with APORT_TARGET_USER and APORT_TARGET_HOME set.
# On Windows, prefer aport-device-deploy.ps1.
#
# ==============================================================================

export APORT_API_KEY="${APORT_API_KEY:-}"
export APORT_TEMPLATE_ID="${APORT_TEMPLATE_ID:-}"
export APORT_FRAMEWORK="${APORT_FRAMEWORK:-claude-code}"
export APORT_API_URL="${APORT_API_URL:-https://api.aport.io}"
export APORT_TARGET_USER="${APORT_TARGET_USER:-}"
export APORT_TARGET_HOME="${APORT_TARGET_HOME:-}"
export APORT_DEVICE_ID="${APORT_DEVICE_ID:-}"
export DISABLE_DEVICE_INFO="${DISABLE_DEVICE_INFO:-}"

# ==============================================================================
# NO CHANGES NEEDED BELOW THIS LINE
# ==============================================================================

if [ -z "${BASH_SOURCE[0]+x}" ] || [ "${BASH_SOURCE[0]}" = "bash" ]; then
    printf '%s\n' \
        '[aport-device] ERROR: This file is not safe for "curl | bash".' \
        '[aport-device] Use the bundled release script instead, e.g.:' \
        '  curl -fsSL https://api.aport.io/enterprise/scripts/deploy | bash' \
        '[aport-device] Or save the bundled script and run: bash aport-device-deploy.bundled.sh' >&2
    exit 1
fi

_APORT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=enterprise-scripts/aport-device-lib.sh
. "$_APORT_SCRIPT_DIR/aport-device-lib.sh"

aport_device_invoke install

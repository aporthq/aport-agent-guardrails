#!/usr/bin/env bash
# APort generic device enforcement — macOS, Linux, and Windows (via Node.js).
#
# Verifies local state and framework hooks; reinstalls if missing.
# Same configuration block as aport-device-deploy.sh.

set -euo pipefail

# ==============================================================================
# APORT DEVICE ENFORCEMENT - EDIT THIS SECTION ONLY
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
#   APORT_TARGET_USER    interactive user on the device
#   APORT_TARGET_HOME    user profile / home directory
#   APORT_DEVICE_ID      stable device identifier
#   DISABLE_DEVICE_INFO  false
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
        '  curl -fsSL https://api.aport.io/enterprise/scripts/enforce | bash' \
        '[aport-device] Or save the bundled script and run: bash aport-device-enforce.bundled.sh' >&2
    exit 1
fi

_APORT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=enterprise-scripts/aport-device-lib.sh
. "$_APORT_SCRIPT_DIR/aport-device-lib.sh"

aport_device_invoke enforce

#!/usr/bin/env bash
# APort generic device uninstall — macOS, Linux, and Windows (via Node.js).

set -euo pipefail

# ==============================================================================
# APORT DEVICE UNINSTALL - EDIT THIS SECTION ONLY
# ==============================================================================
#
# Required values:
#
#   Variable             Example / Allowed values
#   -------------------  --------------------------------------------------------
#   APORT_FRAMEWORK      claude-code | cursor | openclaw | langchain | crewai |
#                        deerflow | n8n
#
# Optional values:
#
#   Variable             Default
#   -------------------  --------------------------------------------------------
#   APORT_TARGET_USER    interactive user on the device
#   APORT_TARGET_HOME    user profile / home directory
#
# ==============================================================================

export APORT_FRAMEWORK="${APORT_FRAMEWORK:-claude-code}"
export APORT_TARGET_USER="${APORT_TARGET_USER:-}"
export APORT_TARGET_HOME="${APORT_TARGET_HOME:-}"

# ==============================================================================
# NO CHANGES NEEDED BELOW THIS LINE
# ==============================================================================

_APORT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=enterprise-scripts/aport-device-lib.sh
. "$_APORT_SCRIPT_DIR/aport-device-lib.sh"

aport_device_invoke uninstall

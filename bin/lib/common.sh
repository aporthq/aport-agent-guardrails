#!/usr/bin/env bash
# Shared bash functions for APort agent-guardrails (multi-framework)
# Used by passport wizard, config helpers, and framework installers.

set -euo pipefail

# Resolve script directory and project root
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)}"
# Project root: bin/lib -> repo root
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_DIR/../.." 2> /dev/null && pwd)}"

# Log helpers
log_info() { echo "[aport] $*" >&2; }
log_warn() { echo "[aport] WARN: $*" >&2; }
log_error() { echo "[aport] ERROR: $*" >&2; }

# Check required commands
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
}

# The evaluator's own request bound, in whole seconds, under the same rules apiTimeoutMs() applies in
# src/evaluator.js: a finite positive APORT_API_TIMEOUT is used, anything else falls back to 15.
#
# Framework installers derive their hook timeout from this. They used to read $APORT_API_TIMEOUT straight into
# shell arithmetic, which disagreed with the evaluator in both directions: APORT_API_TIMEOUT=0 or -5 made the
# evaluator use 15 s while the hook budget came out at 15 s or 12 s, and since a Claude Code hook that reaches
# its timeout does NOT block the tool call, the shorter budget fails open. "1.5" or "abc" produced a bash
# arithmetic error during setup instead. Fractional values round up so the budget never understates the bound.
# The evaluator reads APORT_API_TIMEOUT with JavaScript's Number(), which accepts exponent notation ("1e3" is
# 1000), so awk does the parsing here rather than a bash regex: a bash-only check that rejected "1e3" would
# fall back to 15 while the evaluator waited 1000 s, and the hook would time out first and fail open. awk is
# already a hard dependency of this repo. Fractions round UP so the budget never understates the bound.
aport_api_timeout_seconds() {
    local raw="${1-${APORT_API_TIMEOUT:-}}"
    local seconds
    seconds="$(
        printf '%s' "$raw" | awk '
          {
            line = $0
            # Number() ignores surrounding whitespace; anything else non-numeric makes it NaN.
            gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", line)
            # Hex first, then the decimal grammar Number accepts: an optional sign, digits with an optional
            # fraction or a bare fraction, an optional exponent. "15s", "NaN" and "Infinity" fall through to
            # 15, which is what the evaluator does with them too (Infinity is not finite).
            if (line ~ /^0[xX][0-9a-fA-F]+$/) {
              # Number("0x10") is 16. awk would read "0x10" as 0, so convert the digits by hand.
              hex = substr(line, 3); n = 0
              for (i = 1; i <= length(hex); i++) {
                n = n * 16 + index("0123456789abcdef", tolower(substr(hex, i, 1))) - 1
              }
            } else if (line !~ /^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$/) {
              print 15; exit
            } else {
              n = line + 0
            }
            if (n <= 0) { print 15; exit }
            s = int(n)
            if (s < n) s = s + 1
            if (s < 1) s = 1
            print s
          }
          END { if (NR == 0) print 15 }
        ' 2> /dev/null
    )"
    case "$seconds" in '' | *[!0-9]*) seconds=15 ;; esac
    printf '%s\n' "$seconds"
}

# Export for subshells
export SCRIPT_DIR ROOT_DIR
export -f log_info log_warn log_error require_cmd aport_api_timeout_seconds

#!/usr/bin/env bash
# Print or append APort provenance trailers for a commit message.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/aport-resolve-paths.sh
. "$SCRIPT_DIR/aport-resolve-paths.sh"

usage() {
    cat << 'EOF'
Usage:
  aport-git-trailers.sh [--print]
  aport-git-trailers.sh --message-file COMMIT_MSG_FILE

Adds or prints:
  APort-Session: <session id when available>
  APort-Decision: <latest decision id>
  APort-Agent: <passport/agent id>
EOF
}

mode="print"
message_file=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --print)
            mode="print"
            ;;
        --message-file)
            shift
            message_file="${1:-}"
            mode="message-file"
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift || true
done

if ! command -v jq > /dev/null 2>&1; then
    echo "jq is required to read APort decision metadata" >&2
    exit 1
fi

session_id="${APORT_SESSION_ID:-}"
session_log="${APORT_SESSION_DECISIONS_FILE:-$(dirname "$DECISION_FILE")/session-decisions.jsonl}"

decision_id=""
agent_id=""

if [ -f "$DECISION_FILE" ]; then
    decision_id="$(jq -r '.decision_id // empty' "$DECISION_FILE" 2> /dev/null || true)"
    agent_id="$(jq -r '.agent_id // .passport_id // empty' "$DECISION_FILE" 2> /dev/null || true)"
fi

if { [ -z "$decision_id" ] || [ -z "$agent_id" ]; } && [ -f "$session_log" ]; then
    latest_session_record="$(tail -n 1 "$session_log" 2> /dev/null || true)"
    decision_id="$(printf '%s' "$latest_session_record" | jq -r '.decision.decision_id // empty' 2> /dev/null || true)"
    agent_id="$(printf '%s' "$latest_session_record" | jq -r '.decision.agent_id // .decision.passport_id // empty' 2> /dev/null || true)"
    if [ -z "$session_id" ]; then
        session_id="$(printf '%s' "$latest_session_record" | jq -r '.session_id // empty' 2> /dev/null || true)"
    fi
fi

if [ -z "$session_id" ]; then
    if [ -f "$session_log" ]; then
        session_id="$(tail -n 1 "$session_log" | jq -r '.session_id // empty' 2> /dev/null || true)"
    fi
fi

if [ -z "$decision_id" ] || [ -z "$agent_id" ]; then
    echo "Latest APort decision is missing decision_id or agent_id. Checked $DECISION_FILE and $session_log" >&2
    exit 1
fi

print_trailers() {
    [ -n "$session_id" ] && printf 'APort-Session: %s\n' "$session_id"
    printf 'APort-Decision: %s\n' "$decision_id"
    printf 'APort-Agent: %s\n' "$agent_id"
}

if [ "$mode" = "print" ]; then
    print_trailers
    exit 0
fi

if [ -z "$message_file" ]; then
    echo "--message-file requires a path" >&2
    exit 1
fi
if [ ! -f "$message_file" ]; then
    echo "Commit message file not found: $message_file" >&2
    exit 1
fi

if command -v git > /dev/null 2>&1; then
    args=(interpret-trailers --in-place)
    [ -n "$session_id" ] && args+=(--trailer "APort-Session=$session_id")
    args+=(--trailer "APort-Decision=$decision_id")
    args+=(--trailer "APort-Agent=$agent_id")
    args+=("$message_file")
    git "${args[@]}"
else
    {
        printf '\n'
        print_trailers
    } >> "$message_file"
fi

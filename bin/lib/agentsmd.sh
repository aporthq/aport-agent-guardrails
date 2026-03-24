#!/bin/bash
# Parse AGENTS.md enforcement block. Single source of truth for AGENTS.md discovery (bash side).
# Sets: AGENTSMD_ENGINE, AGENTSMD_PASSPORT, AGENTSMD_AGENT_ID, AGENTSMD_DIR
# All empty if no AGENTS.md or no enforcement block found.

resolve_agentsmd_enforcement() {
    AGENTSMD_ENGINE=""
    AGENTSMD_PASSPORT=""
    AGENTSMD_AGENT_ID=""
    AGENTSMD_DIR=""

    # Walk up from PWD to find AGENTS.md (same pattern as git root detection)
    local dir="$PWD"
    local agentsmd=""
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/AGENTS.md" ]; then
            agentsmd="$dir/AGENTS.md"
            break
        elif [ -f "$dir/.agents.md" ]; then
            agentsmd="$dir/.agents.md"
            break
        fi
        dir="$(dirname "$dir")"
    done
    [ -z "$agentsmd" ] && return 1

    AGENTSMD_DIR="$(dirname "$agentsmd")"

    # Extract YAML frontmatter (between --- delimiters)
    local in_frontmatter=0
    local frontmatter=""
    while IFS= read -r line; do
        if [ "$in_frontmatter" -eq 0 ]; then
            [ "$line" = "---" ] && in_frontmatter=1 && continue
            return 1  # first line isn't ---, no frontmatter
        fi
        [ "$line" = "---" ] && break
        frontmatter+="$line"$'\n'
    done < "$agentsmd"
    [ -z "$frontmatter" ] && return 1

    # Parse enforcement fields (simple key: value extraction, no YAML dep)
    local found_enforcement=0
    local in_enforcement=0
    while IFS= read -r line; do
        # Skip empty/comment lines
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Detect enforcement: block start
        if [[ "$line" =~ ^enforcement: ]]; then
            in_enforcement=1
            found_enforcement=1
            continue
        fi
        # If in enforcement block, parse indented keys
        if [ "$in_enforcement" -eq 1 ]; then
            # Non-indented line = end of enforcement block
            [[ ! "$line" =~ ^[[:space:]] ]] && break
            local key val
            key="$(echo "$line" | sed -n 's/^[[:space:]]*\([a-z_]*\):.*/\1/p')"
            val="$(echo "$line" | sed -n 's/^[[:space:]]*[a-z_]*:[[:space:]]*//p' | sed 's/[[:space:]]*#.*$//' | sed 's/^["'"'"']\(.*\)["'"'"']$/\1/')"
            case "$key" in
                engine)   AGENTSMD_ENGINE="$val" ;;
                passport)
                    # Resolve relative paths against AGENTS.md location
                    if [[ "$val" == ./* ]]; then
                        AGENTSMD_PASSPORT="$AGENTSMD_DIR/${val#./}"
                    elif [[ "$val" != /* ]]; then
                        AGENTSMD_PASSPORT="$AGENTSMD_DIR/$val"
                    else
                        AGENTSMD_PASSPORT="$val"
                    fi
                    ;;
                agent_id) AGENTSMD_AGENT_ID="$val" ;;
            esac
        fi
    done <<< "$frontmatter"

    [ "$found_enforcement" -eq 0 ] && return 1
    return 0
}

# Shared setup helper: check AGENTS.md enforcement and conditionally run passport wizard.
# Used by framework setup scripts (claude-code.sh, cursor.sh) to avoid duplicating logic.
# Requires: log_info (from common.sh), run_passport_wizard (from passport.sh).
setup_from_agentsmd_or_wizard() {
    if resolve_agentsmd_enforcement 2>/dev/null; then
        if [ -n "$AGENTSMD_AGENT_ID" ]; then
            log_info "Found AGENTS.md enforcement block with agent_id: $AGENTSMD_AGENT_ID"
            log_info "Using hosted passport — skipping wizard."
            export APORT_AGENT_ID="$AGENTSMD_AGENT_ID"
        elif [ -n "$AGENTSMD_PASSPORT" ] && [ -f "$AGENTSMD_PASSPORT" ]; then
            log_info "Found AGENTS.md enforcement block with passport: $AGENTSMD_PASSPORT"
            log_info "Using existing passport — skipping wizard."
        elif [ -n "$AGENTSMD_PASSPORT" ]; then
            log_info "Found AGENTS.md enforcement block — passport path: $AGENTSMD_PASSPORT"
            log_info "Passport not found at declared path. Running wizard to create it..."
            export APORT_PASSPORT_OUTPUT="$AGENTSMD_PASSPORT"
            mkdir -p "$(dirname "$AGENTSMD_PASSPORT")"
            run_passport_wizard "$@"
        else
            run_passport_wizard "$@"
        fi
    else
        run_passport_wizard "$@"
    fi
}

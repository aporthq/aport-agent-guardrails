#!/usr/bin/env bash
# Reuse an APort passport that already exists on this device.
#
# Every framework installer used to create a fresh passport in its own state directory, so a machine with Claude
# Code, Codex and Cursor ended up with three passports for one person. This library finds passports the other
# frameworks already have (hosted ids from guardrail-mode.env, or local passport.json files) and lets an install
# reuse one: interactively as a menu before the usual hosted/local choice, or non-interactively with
# --reuse-from=<framework|path|agent_id> (env: APORT_REUSE_PASSPORT_FROM).
#
# Sourced by quick-hosted.sh after its helpers exist. Needs get_config_dir from config.sh.

_passport_reuse_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
if ! command -v get_config_dir > /dev/null 2>&1; then
    # shellcheck source=config.sh
    source "$_passport_reuse_lib_dir/config.sh"
fi
if ! command -v refuse_symlink_path > /dev/null 2>&1; then
    # shellcheck source=framework-setup.sh
    source "$_passport_reuse_lib_dir/framework-setup.sh"
fi

# Print one line per passport found on this device, excluding the framework being installed:
#   <framework>|hosted|<agent_id>
#   <framework>|local|<path to passport.json>
aport_list_device_passports() {
    local exclude="${1:-}"
    local kind_filter="${2:-}" # empty, "hosted" or "local"
    local fw passport mode_file mode agent_id
    for fw in "${APORT_SUPPORTED_FRAMEWORKS[@]}"; do
        [[ "$fw" = "$exclude" ]] && continue
        passport="$(get_default_passport_path "$fw")"
        mode_file="${passport%/passport.json}/guardrail-mode.env"
        if [[ -r "$mode_file" && "$kind_filter" != "local" ]]; then
            mode="$(aport_quick_hosted_mode_file_value "$mode_file" "APORT_GUARDRAIL_MODE" | tr '[:upper:]' '[:lower:]')"
            agent_id="$(aport_quick_hosted_mode_file_value "$mode_file" "APORT_AGENT_ID")"
            if [[ "$mode" = "api" ]] && aport_quick_hosted_is_valid_agent_id "$agent_id"; then
                printf '%s|hosted|%s\n' "$fw" "$agent_id"
                continue
            fi
        fi
        if [[ -r "$passport" && "$kind_filter" != "hosted" ]]; then
            printf '%s|local|%s\n' "$fw" "$passport"
        fi
    done
}

# Apply one "<framework>|<kind>|<ref>" line to the install in progress.
#   hosted: exports APORT_AGENT_ID (and the source's API key and URL when present); the caller skips the wizard.
#   local:  copies passport.json into <config_dir>/aport/, exports APORT_PASSPORT_REUSED=1; callers skip the wizard.
aport_apply_reused_passport() {
    local line="$1"
    local config_dir="$2"
    local fw kind ref
    IFS='|' read -r fw kind ref <<< "$line"
    case "$kind" in
        hosted)
            # "cli" marks a bare agent id from --reuse-from; it is not a framework and has no config dir. For a
            # framework, the same reader that picks up a saved hosted config exports its id, key and URL.
            if [[ "$fw" != cli ]]; then
                local src_dir
                src_dir="$(get_config_dir "$fw")"
                aport_try_reuse_existing_hosted_config "${src_dir/#\~/$HOME}" > /dev/null 2>&1 || true
            fi
            export APORT_AGENT_ID="$ref"
            export APORT_PASSPORT_REUSED_FROM="$fw"
            log_info "Reusing hosted passport $ref from $fw"
            return 0
            ;;
        local)
            local dest_dir="$config_dir/aport"
            local dest="$dest_dir/passport.json"
            if [[ ! -r "$ref" ]]; then
                log_error "Passport not readable: $ref"
                return 1
            fi
            if ! aport_reuse_file_is_passport "$ref"; then
                log_error "Not a passport file: $ref"
                return 1
            fi
            # The same symlink refusal every other passport write path applies: a planted link at the
            # destination or its directory must not be followed.
            refuse_symlink_path "$config_dir" || return 1
            refuse_symlink_path "$dest_dir" || return 1
            refuse_symlink_path "$dest" || return 1
            refuse_symlink_path "$dest.bak" || return 1
            mkdir -p "$dest_dir"
            chmod 700 "$dest_dir" 2> /dev/null || true
            if [[ "$ref" != "$dest" ]]; then
                # Both copies are checked explicitly. Callers invoke this function inside an `if` or after a
                # `||`, which turns errexit off for everything it runs, so an unchecked `cp` that failed would
                # fall straight through to the success log and `return 0`: a failed backup would report a
                # backup that is not there while the destination is overwritten anyway, and a failed
                # destination copy would set the reuse flags and skip the wizard with no passport in place.
                if [[ -f "$dest" ]]; then
                    if ! cp "$dest" "$dest.bak"; then
                        log_error "Could not back up the existing passport to $dest.bak; leaving $dest unchanged"
                        return 1
                    fi
                    log_info "Existing passport kept at $dest.bak"
                fi
                if ! cp "$ref" "$dest"; then
                    log_error "Could not copy $ref to $dest"
                    return 1
                fi
            fi
            chmod 600 "$dest" 2> /dev/null || true
            unset APORT_AGENT_ID APORT_API_KEY APORT_API_URL APORT_SELECTED_API_URL
            export APORT_PASSPORT_REUSED=1
            export APORT_PASSPORT_REUSED_FROM="$fw"
            log_info "Reusing local passport from $fw ($ref)"
            return 0
            ;;
        *)
            log_error "Unknown passport kind: $kind"
            return 1
            ;;
    esac
}

# Turn a --reuse-from value (framework name, passport path, or hosted agent id) into a list line, or fail.
aport_resolve_reuse_ref() {
    local ref="$1"
    local exclude="${2:-}"
    local kind_filter="${3:-}"
    local line
    # Framework names first, so a stray file in the cwd named like a framework can never shadow one.
    while IFS= read -r line; do
        [[ "${line%%|*}" = "$ref" ]] && {
            printf '%s\n' "$line"
            return 0
        }
    done < <(aport_list_device_passports "$exclude" "$kind_filter")
    # A bare agent id is a hosted passport, so it is not an answer when only local ones are wanted.
    if [[ "$kind_filter" != "local" ]] && aport_quick_hosted_is_valid_agent_id "$ref"; then
        printf 'cli|hosted|%s\n' "$ref"
        return 0
    fi
    # A path must look like one and hold a passport, not any readable file.
    if [[ "$kind_filter" != "hosted" && ("$ref" == */* || "$ref" == *.json) ]] && [[ -f "$ref" ]]; then
        if aport_reuse_file_is_passport "$ref"; then
            printf 'cli|local|%s\n' "$ref"
            return 0
        fi
        log_error "--reuse-from: $ref is not a passport file (expected JSON with spec_version and capabilities)"
        return 1
    fi
    log_error "--reuse-from: no ${kind_filter:+$kind_filter }passport found for \"$ref\" (expected a framework name, a passport.json path, or a hosted agent id)"
    return 1
}

# A passport file parses as JSON and carries the two keys every OAP passport has.
aport_reuse_file_is_passport() {
    local file="$1"
    if command -v jq > /dev/null 2>&1; then
        jq -e '(type == "object") and has("spec_version") and has("capabilities")' "$file" > /dev/null 2>&1
    elif command -v node > /dev/null 2>&1; then
        node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.exit(p && typeof p==="object" && "spec_version" in p && "capabilities" in p ? 0 : 1)' "$file" > /dev/null 2>&1
    else
        return 1
    fi
}

# Called by aport_maybe_configure_hosted_passport before the hosted/local menu.
# Returns 0 when a passport was reused (hosted or local), 1 when the install should continue as before.
aport_maybe_reuse_device_passport() {
    local framework="$1"
    local config_dir="$2"
    local kind_filter="${3:-}"
    local noninteractive="${APORT_NONINTERACTIVE:-${CI:-}}"
    local requested="${APORT_REUSE_PASSPORT_FROM_CLI:-${APORT_REUSE_PASSPORT_FROM:-}}"

    # Only once per install: the mode=local branch and the main branch may both ask.
    [[ -n "${APORT_PASSPORT_REUSE_DECIDED:-}" ]] && return 1
    export APORT_PASSPORT_REUSE_DECIDED=1

    if [[ -n "$requested" ]]; then
        # An explicit request the installer cannot honour must stop the install: falling through would mint the
        # duplicate passport the flag exists to prevent.
        local line
        line="$(aport_resolve_reuse_ref "$requested" "$framework" "$kind_filter")" || exit 1
        aport_apply_reused_passport "$line" "$config_dir" || exit 1
        return 0
    fi

    # Never guess in non-interactive mode: an explicit --reuse-from is the only opt-in there.
    [[ -n "$noninteractive" ]] && return 1

    # The menu never offers to copy over a passport this framework already has; the installer's own
    # "overwrite?" prompt owns that decision. Hosted entries are still offered.
    local menu_filter="$kind_filter"
    if [[ -f "$config_dir/aport/passport.json" ]]; then
        [[ "$kind_filter" = "local" ]] && return 1
        menu_filter="hosted"
    fi

    local found=()
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && found+=("$line")
    done < <(aport_list_device_passports "$framework" "$menu_filter")
    ((${#found[@]} > 0)) || return 1

    echo ""
    echo "  Existing APort passports on this device:"
    local i=1 fw kind ref
    for line in "${found[@]}"; do
        IFS='|' read -r fw kind ref <<< "$line"
        if [[ "$kind" = "hosted" ]]; then
            echo "    $i. $fw (hosted, $ref)"
        else
            echo "    $i. $fw (local, ${ref/#$HOME/~})"
        fi
        i=$((i + 1))
    done
    echo "    n. Create a new passport for $framework"
    echo ""
    local choice
    read -r -p "  Reuse one? [1-${#found[@]}/n]: " choice
    choice="${choice:-n}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#found[@]})); then
        aport_apply_reused_passport "${found[$((choice - 1))]}" "$config_dir"
        return $?
    fi
    return 1
}

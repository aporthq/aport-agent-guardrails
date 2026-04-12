#!/usr/bin/env bash

_aport_tool_mapping_file() {
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"

    local candidates=(
        "$lib_dir/../../python/aport_guardrails/core/tool-pack-mapping.json"
        "$lib_dir/../python/aport_guardrails/core/tool-pack-mapping.json"
        "$lib_dir/../../aport/runtime/python/aport_guardrails/core/tool-pack-mapping.json"
    )

    local candidate=""
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

resolve_policy_id_from_tool_name() {
    local tool_name="${1:-}"
    local mapping_file=""
    local normalized=""
    local policy_id=""

    normalized="$(printf '%s' "$tool_name" | tr '[:upper:]' '[:lower:]')"
    mapping_file="$(_aport_tool_mapping_file)" || return 1

    policy_id="$(
        jq -r --arg tool "$normalized" '
            first(
              .rules[]?
              | select(
                  (.prefixes // [] | any(. as $prefix | $tool | startswith($prefix)))
                  or
                  (.substrings // [] | any(. as $substring | $tool | contains($substring)))
                )
              | .pack
            ) // empty
        ' "$mapping_file"
    )"

    if [[ -n "$policy_id" && "$policy_id" != "null" ]]; then
        printf '%s\n' "$policy_id"
        return 0
    fi

    return 1
}

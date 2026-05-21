# APort enterprise device scripts — launcher helpers.
# Cross-platform logic lives in aport-device-core.mjs (Node.js).
# shellcheck shell=bash

aport_device_script_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

aport_device_invoke() {
    local command="$1"
    local dir core
    dir="$(aport_device_script_dir)"
    core="$dir/aport-device-core.mjs"
    [ -f "$core" ] || {
        printf '[aport-device] ERROR: missing %s\n' "$core" >&2
        exit 1
    }
    export APORT_DEVICE_COMMAND="$command"
    exec node "$core" "$command"
}

#!/usr/bin/env bash

# Give every compositor/shell smoke test a complete throw-away user profile.
# Setting only XDG_CONFIG_HOME is insufficient: Qt writes GenericStateLocation
# through XDG_STATE_HOME and several shell services intentionally fall back to
# HOME. A test must never read or mutate the developer's desktop profile.
kaskad_prepare_smoke_environment()
{
    local root=${1:?smoke environment root is required}

    install -d -m 0700 \
        "$root/home" \
        "$root/runtime" \
        "$root/config" \
        "$root/cache" \
        "$root/data" \
        "$root/state"

    export HOME="$root/home"
    export XDG_RUNTIME_DIR="$root/runtime"
    export XDG_CONFIG_HOME="$root/config"
    export XDG_CACHE_HOME="$root/cache"
    export XDG_DATA_HOME="$root/data"
    export XDG_STATE_HOME="$root/state"
}

#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_root=${KASKAD_BUILD_ROOT:-"$repo_root/build/compositor"}
extra_library_path=${KASKAD_EXTRA_LIBRARY_PATH:-}
kaskad_binary="$build_root/bin/kaskad-compositor"

if [[ ! -x "$kaskad_binary" ]]; then
    echo "Missing compositor build: $kaskad_binary" >&2
    echo "Build the kaskad-compositor target first. See docs/BUILDING.md." >&2
    exit 1
fi

smoke_dir=$(mktemp -d /tmp/kaskad-smoke.XXXXXX)
cleanup()
{
    rm -r -- "$smoke_dir"
}
trap cleanup EXIT

# shellcheck source=lib/smoke-environment.sh
source "$repo_root/scripts/lib/smoke-environment.sh"
kaskad_prepare_smoke_environment "$smoke_dir"

echo "Starting an isolated virtual compositor smoke test..."

unset DISPLAY WAYLAND_DISPLAY QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_QPA_PLATFORMTHEME_QT6 GDK_BACKEND

env \
    HOME="$HOME" \
    XDG_RUNTIME_DIR="$smoke_dir/runtime" \
    XDG_CONFIG_HOME="$smoke_dir/config" \
    XDG_CACHE_HOME="$smoke_dir/cache" \
    XDG_DATA_HOME="$smoke_dir/data" \
    XDG_STATE_HOME="$smoke_dir/state" \
    KWIN_COMPOSE=Q \
    LD_LIBRARY_PATH="${extra_library_path:+$extra_library_path:}$build_root/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    QT_PLUGIN_PATH="$build_root/bin:$build_root/lib" \
    dbus-run-session -- timeout 15s \
    "$kaskad_binary" \
        --virtual \
        --width 1280 \
        --height 720 \
        --socket kaskad-smoke \
        --exit-with-session /usr/bin/true

echo "Virtual compositor smoke test passed."

if [[ -n ${KASKAD_CURSOR_BASE:-} ]]; then
    cursor_smoke="$build_root/bin/kaskad-cursor-x11-smoke"
    [[ -x "$cursor_smoke" ]] || {
        echo "Missing XWayland cursor smoke helper: $cursor_smoke" >&2
        exit 1
    }
    echo "Testing the legacy XWayland hidden-to-visible cursor lifecycle..."
    env \
        HOME="$HOME" \
        XDG_RUNTIME_DIR="$smoke_dir/runtime" \
        XDG_CONFIG_HOME="$smoke_dir/config" \
        XDG_CACHE_HOME="$smoke_dir/cache" \
        XDG_DATA_HOME="$smoke_dir/data" \
        XDG_STATE_HOME="$smoke_dir/state" \
        XCURSOR_THEME=KaskadCursorBase \
        XCURSOR_SIZE=24 \
        XCURSOR_PATH="$(dirname -- "$KASKAD_CURSOR_BASE")" \
        KASKAD_COMPOSITOR_CURSOR_THEME=KaskadCursorBase \
        KASKAD_CURSOR_ACCENT='#a884ff' \
        KWIN_COMPOSE=Q \
        LD_LIBRARY_PATH="${extra_library_path:+$extra_library_path:}$build_root/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        QT_PLUGIN_PATH="$build_root/bin:$build_root/lib" \
        dbus-run-session -- timeout 20s \
        "$kaskad_binary" \
            --virtual \
            --xwayland \
            --width 1280 \
            --height 720 \
            --socket kaskad-cursor-smoke \
            --exit-with-session "$cursor_smoke"
    echo "XWayland cursor lifecycle test passed."
fi

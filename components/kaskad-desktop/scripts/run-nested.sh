#!/usr/bin/env bash

set -euo pipefail

die()
{
    echo "run-nested: $*" >&2
    exit 1
}

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
compositor="$repo_root/build/compositor/bin/kaskad-compositor"
shell_session="$repo_root/session/run-kaskad-nested"
qml_module="$repo_root/build/quickshell-kaskad"
host_wayland=${WAYLAND_DISPLAY:-}
nested_socket="kaskad-nested-$$"
nested_profile=${KASKAD_NESTED_PROFILE:-"$repo_root/build/nested-profile"}

[[ -n "$host_wayland" ]] ||
    die "WAYLAND_DISPLAY is empty; run this inside KDE Wayland or Hyprland"
[[ -n ${XDG_RUNTIME_DIR:-} && -d ${XDG_RUNTIME_DIR:-} ]] ||
    die "XDG_RUNTIME_DIR is unavailable"
[[ -x "$compositor" ]] ||
    die "missing $compositor; build the compositor first"
[[ -x "$shell_session" ]] ||
    die "missing $shell_session"
[[ -f "$qml_module/Kaskad/Ipc/qmldir" ]] ||
    die "missing the Quickshell Kaskad module; build it first"

# Nested development sessions keep a persistent development profile, but it is
# intentionally separate from the real login profile. This prevents virtual
# output names and experimental settings from replacing the user's panel/dock
# placement. Set KASKAD_NESTED_PROFILE to choose another isolated location.
install -d -m 0700 \
    "$nested_profile/home" \
    "$nested_profile/config" \
    "$nested_profile/cache" \
    "$nested_profile/data" \
    "$nested_profile/state"

export HOME="$nested_profile/home"
export XDG_CONFIG_HOME="$nested_profile/config"
export XDG_CACHE_HOME="$nested_profile/cache"
export XDG_DATA_HOME="$nested_profile/data"
export XDG_STATE_HOME="$nested_profile/state"

export KASKAD_DESKTOP_ROOT="$repo_root"
export QT_PLUGIN_PATH="$repo_root/build/compositor/bin:$repo_root/build/compositor/lib${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
export QML2_IMPORT_PATH="$qml_module${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
export LD_LIBRARY_PATH="$repo_root/build/compositor/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_CURRENT_DESKTOP=KaskadDesktop
export XDG_SESSION_DESKTOP=KaskadDesktop
export QT_QPA_PLATFORM=wayland

echo "Opening Kaskad DE in a 1280x720 window on $host_wayland"
echo "Close the window to stop the nested session."

exec "$compositor" \
    --wayland-display "$host_wayland" \
    --socket "$nested_socket" \
    --width "${KASKAD_NESTED_WIDTH:-1280}" \
    --height "${KASKAD_NESTED_HEIGHT:-720}" \
    --xwayland \
    --no-global-shortcuts \
    --exit-with-session "$shell_session"

#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_root=${KASKAD_INSTALLER_BUILD_ROOT:-"$repo_root/../../build/kaskad-installer-compositor"}
compositor="$build_root/bin/kaskad-installer"
client_qml="$repo_root/compositor/tests/installer-smoke.qml"

if [[ ! -x "$compositor" ]]; then
    echo "Missing installer compositor build: $compositor" >&2
    exit 1
fi

if ! command -v qml6 >/dev/null; then
    echo "qml6 is required for the installer compositor smoke test." >&2
    exit 1
fi

echo "Starting the minimal KaskadOS installer compositor smoke test..."

dbus-run-session -- bash -c '
set -euo pipefail

build_root=$1
compositor=$2
client_qml=$3
repo_root=$4
test_dir=$(mktemp -d)

cleanup()
{
    if [[ -n ${compositor_pid:-} ]]; then
        kill "$compositor_pid" 2>/dev/null || true
        wait "$compositor_pid" 2>/dev/null || true
    fi
    rm -rf -- "$test_dir"
}
trap cleanup EXIT

source "$repo_root/scripts/lib/smoke-environment.sh"
kaskad_prepare_smoke_environment "$test_dir"
unset DISPLAY WAYLAND_DISPLAY QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_QPA_PLATFORMTHEME_QT6 GDK_BACKEND

env \
    KWIN_COMPOSE=Q \
    LD_LIBRARY_PATH="$build_root/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    QT_PLUGIN_PATH="$build_root/bin:$build_root/lib" \
    "$compositor" \
        --virtual \
        --width 1280 \
        --height 720 \
        --socket kaskad-installer-smoke \
        --lock \
        --no-global-shortcuts \
        >"$test_dir/compositor.log" 2>&1 &
compositor_pid=$!

for _ in $(seq 1 50); do
    [[ -S "$XDG_RUNTIME_DIR/kaskad-installer-smoke" ]] && break
    sleep 0.1
done
if [[ ! -S "$XDG_RUNTIME_DIR/kaskad-installer-smoke" ]]; then
    cat "$test_dir/compositor.log" >&2
    exit 1
fi

WAYLAND_DISPLAY=kaskad-installer-smoke \
QT_QPA_PLATFORM=wayland \
QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
timeout 8s qml6 "$client_qml" >"$test_dir/client.log" 2>&1

if [[ ! -f "$test_dir/config/kaskadinstallerrc" ]]; then
    echo "The installer compositor did not use its isolated configuration." >&2
    exit 1
fi

if find "$build_root/bin" -type f \
    \( -path "*/effects/*" -o -path "*/scripts/*" -o -path "*/plugins/*.so" \) \
    -print -quit | grep -q .; then
    echo "The minimal installer build contains an extension payload." >&2
    exit 1
fi
' _ "$build_root" "$compositor" "$client_qml" "$repo_root"

echo "Minimal installer compositor smoke test passed."

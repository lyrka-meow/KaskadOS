#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_root=${KASKAD_BUILD_ROOT:-"$repo_root/build/compositor"}
module_build=${KASKAD_QUICKSHELL_BUILD_ROOT:-"$repo_root/build/quickshell-kaskad"}
kaskad_binary="$build_root/bin/kaskad-compositor"
smoke_qml="$repo_root/quickshell/kaskad-module/tests/smoke.qml"

if [[ ! -x "$kaskad_binary" ]]; then
    echo "Missing compositor build: $kaskad_binary" >&2
    exit 1
fi

if [[ ! -f "$module_build/Kaskad/Ipc/qmldir" ]]; then
    echo "Missing Quickshell module build. See docs/BUILDING.md." >&2
    exit 1
fi

echo "Starting the Kaskad and Quickshell integration smoke test..."

dbus-run-session -- bash -c '
set -euo pipefail

repo_root=$1
kaskad_binary=$2
module_build=$3
smoke_qml=$4
build_root=$5
test_dir=$(mktemp -d)

cleanup()
{
    if [[ -n ${kaskad_pid:-} ]]; then
        kill "$kaskad_pid" 2>/dev/null || true
        wait "$kaskad_pid" 2>/dev/null || true
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
    "$kaskad_binary" \
        --virtual \
        --width 1280 \
        --height 720 \
        --socket kaskad-quickshell-smoke \
        --no-global-shortcuts \
        >"$test_dir/kaskad.log" 2>&1 &
kaskad_pid=$!

for _ in $(seq 1 50); do
    if qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
        org.kaskados.Compositor1.protocolVersion >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

set +e
WAYLAND_DISPLAY=kaskad-quickshell-smoke \
QML2_IMPORT_PATH="$module_build" \
QT_NO_XDG_DESKTOP_PORTAL=1 \
timeout 10s quickshell --no-color -p "$smoke_qml"
quickshell_status=$?
set -e

# The smoke QML intentionally stays alive. A timeout therefore means that it
# loaded successfully and kept its compositor connection for the full test.
if [[ $quickshell_status -ne 0 && $quickshell_status -ne 124 ]]; then
    exit "$quickshell_status"
fi
' _ "$repo_root" "$kaskad_binary" "$module_build" "$smoke_qml" "$build_root"

echo "Kaskad and Quickshell integration smoke test passed."

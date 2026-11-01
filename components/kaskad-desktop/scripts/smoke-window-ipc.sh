#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_root=${KASKAD_BUILD_ROOT:-"$repo_root/build/compositor"}
kaskad_binary="$build_root/bin/kaskad-compositor"

if [[ ! -x "$kaskad_binary" ]]; then
    echo "Missing compositor build: $kaskad_binary" >&2
    exit 1
fi

if command -v foot >/dev/null; then
    test_client=foot
elif command -v alacritty >/dev/null; then
    test_client=alacritty
elif command -v kitty >/dev/null; then
    test_client=kitty
else
    echo "foot, alacritty, or kitty is required for the window IPC smoke test." >&2
    exit 1
fi

echo "Starting the Kaskad window command smoke test..."

dbus-run-session -- bash -c '
set -euo pipefail

repo_root=$1
kaskad_binary=$2
build_root=$3
test_client=$4
test_dir=$(mktemp -d)

cleanup()
{
    for pid in "${foot_pid:-}" "${kaskad_pid:-}"; do
        if [[ -n $pid ]]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    rm -rf -- "$test_dir"
}
trap cleanup EXIT

source "$repo_root/scripts/lib/smoke-environment.sh"
kaskad_prepare_smoke_environment "$test_dir"
unset DISPLAY WAYLAND_DISPLAY QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_QPA_PLATFORMTHEME_QT6 GDK_BACKEND

env \
    LD_LIBRARY_PATH="$build_root/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    KWIN_COMPOSE=Q \
    QT_PLUGIN_PATH="$build_root/bin:$build_root/lib" \
    "$kaskad_binary" \
        --virtual \
        --width 1280 \
        --height 720 \
        --socket kaskad-window-smoke \
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

case "$test_client" in
    foot)
        WAYLAND_DISPLAY=kaskad-window-smoke \
            foot --app-id kaskad-ipc-smoke sh -c "sleep 30" >/dev/null 2>&1 &
        ;;
    alacritty)
        WAYLAND_DISPLAY=kaskad-window-smoke \
            alacritty --class kaskad-ipc-smoke -e sh -c "sleep 30" >/dev/null 2>&1 &
        ;;
    kitty)
        WAYLAND_DISPLAY=kaskad-window-smoke \
            kitty --class kaskad-ipc-smoke sh -c "sleep 30" >/dev/null 2>&1 &
        ;;
esac
foot_pid=$!

window_id=
for _ in $(seq 1 50); do
    windows=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
        org.kaskados.Compositor1.windows)
    window_id=$(sed -n "s/^id: //p" <<<"$windows" | head -n 1)
    [[ -n $window_id ]] && break
    sleep 0.1
done
[[ -n $window_id ]]

call()
{
    qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
        "org.kaskados.Compositor1.$1" "${@:2}"
}

call setWindowFullscreen "$window_id" true | grep -q true
sleep 0.2
call windows | grep -q "fullscreen: true"
call setWindowFullscreen "$window_id" false | grep -q true

call setWindowMinimized "$window_id" true | grep -q true
sleep 0.2
call windows | grep -q "minimized: true"
call setWindowMinimized "$window_id" false | grep -q true

second_workspace=$(call createWorkspace 2 "Second")
call moveWindowToWorkspace "$window_id" "$second_workspace" | grep -q true
sleep 0.2
call windows | grep -q "$second_workspace"

call activateWindow "$window_id" | grep -q true
call closeWindow "$window_id" | grep -q true
for _ in $(seq 1 50); do
    kill -0 "$foot_pid" 2>/dev/null || break
    sleep 0.1
done
! kill -0 "$foot_pid" 2>/dev/null
' _ "$repo_root" "$kaskad_binary" "$build_root" "$test_client"

echo "Kaskad window command smoke test passed."

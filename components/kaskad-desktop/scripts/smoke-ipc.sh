#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_root=${KASKAD_BUILD_ROOT:-"$repo_root/build/compositor"}
kaskad_binary="$build_root/bin/kaskad-compositor"

if [[ ! -x "$kaskad_binary" ]]; then
    echo "Missing compositor build: $kaskad_binary" >&2
    exit 1
fi

if ! command -v qdbus6 >/dev/null; then
    echo "qdbus6 is required for the IPC smoke test." >&2
    exit 1
fi

echo "Starting Kaskad in an isolated D-Bus session..."

dbus-run-session -- bash -c '
set -euo pipefail

repo_root=$1
kaskad_binary=$2
build_root=$3
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
    HOME="$HOME" \
    XDG_RUNTIME_DIR="$test_dir/runtime" \
    XDG_CONFIG_HOME="$test_dir/config" \
    XDG_CACHE_HOME="$test_dir/cache" \
    XDG_DATA_HOME="$test_dir/data" \
    XDG_STATE_HOME="$test_dir/state" \
    LD_LIBRARY_PATH="$build_root/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    KWIN_COMPOSE=Q \
    QT_PLUGIN_PATH="$build_root/bin:$build_root/lib" \
    "$kaskad_binary" \
        --virtual \
        --width 1280 \
        --height 720 \
        --socket kaskad-ipc-smoke \
        --no-global-shortcuts \
        >"$test_dir/kaskad.log" 2>&1 &
kaskad_pid=$!

for _ in $(seq 1 50); do
    version=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
        org.kaskados.Compositor1.protocolVersion 2>/dev/null || true)
    if [[ $version == 24 ]]; then
        break
    fi
    sleep 0.1
done

if [[ ${version:-} != 24 ]]; then
    cat "$test_dir/kaskad.log" >&2
    echo "Kaskad IPC did not become ready." >&2
    exit 1
fi

compositor_version=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.compositorVersion)
outputs=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.outputs)
workspaces=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.workspaces)

[[ $compositor_version == 0.1.0-dev ]]
grep -q "name: Virtual-0" <<<"$outputs"
grep -q "width: 1280" <<<"$outputs"
grep -q "height: 720" <<<"$outputs"
grep -q "name: Desktop 1" <<<"$workspaces"

default_layouts=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.keyboardLayouts)
grep -q "code: us" <<<"$default_layouts"

gdbus call --session \
    --dest org.kaskados.Compositor1 \
    --object-path /org/kaskados/Compositor1 \
    --method org.kaskados.Compositor1.setDecorationPalette \
    "{\"surface\": <\"#ff112233\">, \"accent\": <\"#ff336699\">, \"outline\": <\"#ff778899\">}" | grep -q true

decoration_palette=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.decorationPalette)
grep -q "surface: #ff112233" <<<"$decoration_palette"
grep -q "accent: #ff336699" <<<"$decoration_palette"
grep -q "outline: #ff778899" <<<"$decoration_palette"

gdbus call --session \
    --dest org.kaskados.Compositor1 \
    --object-path /org/kaskados/Compositor1 \
    --method org.kaskados.Compositor1.setKeyboardLayouts \
    "[\"us\", \"ru\"]" | grep -q true

layouts=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.keyboardLayouts)
grep -q "code: us" <<<"$layouts"
grep -q "code: ru" <<<"$layouts"

second_workspace=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.createWorkspace 2 "Second")
[[ -n $second_workspace ]]

qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.activateWorkspace "$second_workspace" | grep -q true
qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.renameWorkspace "$second_workspace" "Renamed" | grep -q true

workspaces=$(qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.workspaces)
grep -q "name: Renamed" <<<"$workspaces"

qdbus6 org.kaskados.Compositor1 /org/kaskados/Compositor1 \
    org.kaskados.Compositor1.removeWorkspace "$second_workspace" | grep -q true
' _ "$repo_root" "$kaskad_binary" "$build_root"

echo "Kaskad IPC smoke test passed."

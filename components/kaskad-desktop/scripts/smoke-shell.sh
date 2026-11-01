#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_root=${KASKAD_BUILD_ROOT:-"$repo_root/build/compositor"}
module_build=${KASKAD_QUICKSHELL_BUILD_ROOT:-"$repo_root/build/quickshell-kaskad"}
shell_root=${KASKAD_SHELL_ROOT:-"$repo_root/shell/KaskadShell/quickshell"}
backend=${KASKAD_SHELL_BACKEND:-"$repo_root/shell/KaskadShell/core/bin/kaskad-shell"}
portal=${KASKAD_PORTAL_BINARY:-"$repo_root/build/portal/bin/xdg-desktop-portal-kaskad"}
desktop_root=${KASKAD_DESKTOP_ROOT:-"$repo_root"}
kaskad_binary="$build_root/bin/kaskad-compositor"

[[ -x "$kaskad_binary" ]] || { echo "Missing compositor build: $kaskad_binary" >&2; exit 1; }
[[ -f "$module_build/Kaskad/Ipc/qmldir" ]] || { echo "Missing Quickshell Kaskad module: $module_build" >&2; exit 1; }
[[ -f "$shell_root/shell.qml" ]] || { echo "Missing shell entrypoint: $shell_root/shell.qml" >&2; exit 1; }
[[ -x "$backend" ]] || { echo "Missing shell backend: $backend" >&2; exit 1; }
[[ -x "$portal" ]] || { echo "Missing desktop portal: $portal" >&2; exit 1; }
command -v qs >/dev/null 2>&1 || { echo "qs is required for the shell smoke test" >&2; exit 1; }
command -v qdbus6 >/dev/null 2>&1 || { echo "qdbus6 is required for the shell smoke test" >&2; exit 1; }
command -v busctl >/dev/null 2>&1 || { echo "busctl is required for the shell smoke test" >&2; exit 1; }
[[ -x /usr/lib/xdg-desktop-portal ]] || { echo "xdg-desktop-portal is required for the shell smoke test" >&2; exit 1; }

echo "Starting an isolated canonical KaskadOS session smoke test..."

dbus-run-session -- bash -c '
set -euo pipefail

build_root=$1
module_build=$2
shell_root=$3
kaskad_binary=$4
backend=$5
portal=$6
desktop_root=$7
test_dir=$(mktemp -d)
kaskad_pid=""
portal_pid=""
frontend_portal_pid=""
shell_pid=""

cleanup()
{
    if [[ -n "$shell_pid" ]]; then
        kill "$shell_pid" 2>/dev/null || true
        wait "$shell_pid" 2>/dev/null || true
    fi
    if [[ -n "$frontend_portal_pid" ]]; then
        kill "$frontend_portal_pid" 2>/dev/null || true
        wait "$frontend_portal_pid" 2>/dev/null || true
    fi
    if [[ -n "$portal_pid" ]]; then
        kill "$portal_pid" 2>/dev/null || true
        wait "$portal_pid" 2>/dev/null || true
    fi
    if [[ -n "$kaskad_pid" ]]; then
        kill "$kaskad_pid" 2>/dev/null || true
        wait "$kaskad_pid" 2>/dev/null || true
    fi
    rm -rf -- "$test_dir"
}
trap cleanup EXIT

source "$desktop_root/scripts/lib/smoke-environment.sh"
kaskad_prepare_smoke_environment "$test_dir"
mkdir -p "$test_dir/config/xdg-desktop-portal"
mkdir -p "$test_dir/data/xdg-desktop-portal/portals"
install -m 0644 "$desktop_root/portal/data/kaskad.portal" \
    "$test_dir/data/xdg-desktop-portal/portals/kaskad.portal"
printf "[preferred]\ndefault=kaskad\n" \
    >"$test_dir/config/xdg-desktop-portal/portals.conf"
unset DISPLAY WAYLAND_DISPLAY QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_QPA_PLATFORMTHEME_QT6 GDK_BACKEND
export XDG_CURRENT_DESKTOP=KaskadDesktop
export XDG_SESSION_DESKTOP=KaskadDesktop
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export QT_NO_XDG_DESKTOP_PORTAL=1
export KASKAD_DESKTOP_ROOT="$desktop_root"

env \
    KWIN_COMPOSE=Q \
    LD_LIBRARY_PATH="$build_root/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    QT_PLUGIN_PATH="$build_root/bin:$build_root/lib" \
    "$kaskad_binary" \
        --virtual \
        --width 1280 \
        --height 720 \
        --socket kaskad-shell-smoke \
        --no-global-shortcuts \
        >"$test_dir/kaskad.log" 2>&1 &
kaskad_pid=$!

for _ in $(seq 1 80); do
    [[ -S "$XDG_RUNTIME_DIR/kaskad-shell-smoke" ]] && break
    kill -0 "$kaskad_pid" 2>/dev/null || { cat "$test_dir/kaskad.log" >&2; exit 1; }
    sleep 0.1
done
[[ -S "$XDG_RUNTIME_DIR/kaskad-shell-smoke" ]] || { cat "$test_dir/kaskad.log" >&2; exit 1; }

export WAYLAND_DISPLAY=kaskad-shell-smoke
export QML2_IMPORT_PATH="$module_build"
export QT_PLUGIN_PATH="$build_root/bin:$build_root/lib"
export LD_LIBRARY_PATH="$build_root/bin:$module_build${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

"$portal" >"$test_dir/portal.log" 2>&1 &
portal_pid=$!

for _ in $(seq 1 80); do
    if [[ $(qdbus6 org.freedesktop.DBus \
        /org/freedesktop/DBus \
        org.freedesktop.DBus.NameHasOwner \
        org.freedesktop.impl.portal.desktop.kaskad 2>/dev/null || true) == true ]]; then
        if qdbus6 org.freedesktop.impl.portal.desktop.kaskad \
            /org/freedesktop/portal/desktop \
            org.freedesktop.DBus.Properties.Get \
            org.freedesktop.impl.portal.ScreenCast \
            version >/dev/null 2>&1; then
            break
        fi
    fi
    kill -0 "$portal_pid" 2>/dev/null || { cat "$test_dir/portal.log" >&2; exit 1; }
    sleep 0.1
done
qdbus6 org.freedesktop.impl.portal.desktop.kaskad \
    /org/freedesktop/portal/desktop \
    org.freedesktop.DBus.Properties.Get \
    org.freedesktop.impl.portal.ScreenCast \
    version >/dev/null 2>&1 || { cat "$test_dir/portal.log" >&2; exit 1; }

# Applications use the public frontend, not the backend name above. Verify the
# frontend discovers the fully initialised backend; this catches a startup race
# that otherwise leaves ScreenCast version 0 until the user logs out.
/usr/lib/xdg-desktop-portal --verbose >"$test_dir/frontend-portal.log" 2>&1 &
frontend_portal_pid=$!
frontend_ready=false
for _ in $(seq 1 100); do
    if [[ $(qdbus6 org.freedesktop.DBus \
        /org/freedesktop/DBus \
        org.freedesktop.DBus.NameHasOwner \
        org.freedesktop.portal.Desktop 2>/dev/null || true) != true ]]; then
        kill -0 "$frontend_portal_pid" 2>/dev/null \
            || { cat "$test_dir/frontend-portal.log" >&2; exit 1; }
        sleep 0.1
        continue
    fi
    version=$(busctl --user get-property \
        org.freedesktop.portal.Desktop \
        /org/freedesktop/portal/desktop \
        org.freedesktop.portal.ScreenCast \
        version 2>/dev/null || true)
    sources=$(busctl --user get-property \
        org.freedesktop.portal.Desktop \
        /org/freedesktop/portal/desktop \
        org.freedesktop.portal.ScreenCast \
        AvailableSourceTypes 2>/dev/null || true)
    cursors=$(busctl --user get-property \
        org.freedesktop.portal.Desktop \
        /org/freedesktop/portal/desktop \
        org.freedesktop.portal.ScreenCast \
        AvailableCursorModes 2>/dev/null || true)
    if [[ $version == "u 4" && $sources == "u 7" && $cursors == "u 7" ]]; then
        frontend_ready=true
        break
    fi
    kill -0 "$frontend_portal_pid" 2>/dev/null \
        || { cat "$test_dir/frontend-portal.log" >&2; exit 1; }
    sleep 0.1
done
if [[ $frontend_ready != true ]]; then
    cat "$test_dir/frontend-portal.log" >&2
    exit 1
fi

KASKAD_DISABLE_NETWORK=1 \
KASKAD_DISABLE_EVDEV=1 \
KASKAD_DISABLE_GEOLOCATION=1 \
QT_QUICK_BACKEND=software \
    "$backend" run -c "$shell_root" >"$test_dir/shell.log" 2>&1 &
shell_pid=$!

shell_loaded=false
for _ in $(seq 1 150); do
    if grep -Fq "[KaskadShell" "$test_dir/shell.log" && grep -Fq "Loaded" "$test_dir/shell.log"; then
        shell_loaded=true
        break
    fi
    if ! kill -0 "$shell_pid" 2>/dev/null; then
        wait "$shell_pid" || true
        cat "$test_dir/shell.log" >&2
        exit 1
    fi
    sleep 0.1
done

if [[ "$shell_loaded" != true ]]; then
    cat "$test_dir/shell.log" >&2
    exit 1
fi

# Regression guard: the shell must persist its session inside the disposable
# XDG state tree. Before alpha.66 this landed in the real user profile under
# ~/.local/state and replaced physical monitor placement with Virtual-0.
isolated_session="$XDG_STATE_HOME/KaskadShell/session.json"
for _ in $(seq 1 30); do
    [[ -s "$isolated_session" ]] && break
    sleep 0.1
done
if [[ ! -s "$isolated_session" ]]; then
    echo "Shell smoke test did not use isolated XDG_STATE_HOME: $isolated_session" >&2
    cat "$test_dir/shell.log" >&2
    exit 1
fi

# Instantiate the task manager and let it complete at least one metadata and
# dgop sampling cycle. This catches process-model errors that normal shell
# startup cannot see because the modal is loaded lazily.
"$backend" ipc call processlist open >/dev/null
for _ in $(seq 1 45); do
    kill -0 "$shell_pid" 2>/dev/null || { cat "$test_dir/shell.log" >&2; exit 1; }
    sleep 0.1
done
if grep -E "(DgopService|ProcessesView|ProcessContextMenu).*(TypeError|ReferenceError|SyntaxError|is not a function)" "$test_dir/shell.log" >&2; then
    cat "$test_dir/shell.log" >&2
    exit 1
fi

# Exercise the real ScreenCast request path. Merely introspecting the portal is
# insufficient: the KaskadOS rename once sent requests into the legacy QML
# chooser, which then failed only when an application tried to share a screen.
session_path=/org/freedesktop/portal/desktop/session/smoke/screencast
request_path=/org/freedesktop/portal/desktop/request/smoke/screencast
busctl --user call org.freedesktop.impl.portal.desktop.kaskad \
    /org/freedesktop/portal/desktop \
    org.freedesktop.impl.portal.ScreenCast CreateSession \
    "oosa{sv}" "$request_path" "$session_path" "" 0 >/dev/null
busctl --user call org.freedesktop.impl.portal.desktop.kaskad \
    /org/freedesktop/portal/desktop \
    org.freedesktop.impl.portal.ScreenCast SelectSources \
    "oosa{sv}" "$request_path" "$session_path" "" \
    2 types u 3 multiple b false >/dev/null
busctl --user call org.freedesktop.impl.portal.desktop.kaskad \
    /org/freedesktop/portal/desktop \
    org.freedesktop.impl.portal.ScreenCast Start \
    "oossa{sv}" "$request_path" "$session_path" "" "" 0 \
    >"$test_dir/screencast-start.log" 2>&1 &
screencast_pid=$!
chooser_ready=false
for _ in $(seq 1 50); do
    if busctl --user introspect org.freedesktop.impl.portal.desktop.kaskad \
        /org/kaskados/ScreenCastChooser1 org.kaskados.ScreenCastChooser1 >/dev/null 2>&1; then
        chooser_ready=true
        break
    fi
    kill -0 "$portal_pid" 2>/dev/null || { cat "$test_dir/portal.log" >&2; exit 1; }
    kill -0 "$shell_pid" 2>/dev/null || { cat "$test_dir/shell.log" >&2; exit 1; }
    sleep 0.1
done
kill "$screencast_pid" 2>/dev/null || true
wait "$screencast_pid" 2>/dev/null || true
if [[ "$chooser_ready" != true ]]; then
    cat "$test_dir/portal.log" >&2
    cat "$test_dir/shell.log" >&2
    exit 1
fi
if grep -Fq "module \"org.kde.taskmanager\" is not installed" "$test_dir/portal.log"; then
    cat "$test_dir/portal.log" >&2
    exit 1
fi
' _ "$build_root" "$module_build" "$shell_root" "$kaskad_binary" "$backend" "$portal" "$desktop_root"

echo "Canonical KaskadOS session smoke test passed."

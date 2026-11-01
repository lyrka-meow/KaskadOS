#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$repo_root/start-kaskad-desktop"
desktop_file="$repo_root/session/kaskad-desktop.desktop"

if [[ ! -x "$repo_root/build/compositor/bin/kaskad-compositor" ]]; then
    echo "Missing compositor build. See docs/BUILDING.md." >&2
    exit 1
fi

if [[ ! -x "$repo_root/shell/KaskadShell/core/bin/kaskad-shell" ]]; then
    echo "Missing Kaskad Shell backend. Run:" >&2
    echo "  make -C $repo_root/shell/KaskadShell/core dev" >&2
    exit 1
fi

if [[ ! -f "$repo_root/build/quickshell-kaskad/Kaskad/Ipc/qmldir" ]]; then
    echo "Missing Kaskad Compositor QML module. See docs/BUILDING.md." >&2
    exit 1
fi

if [[ ! -x "$repo_root/build/portal/bin/xdg-desktop-portal-kaskad" ]]; then
    echo "Missing KaskadOS portal build. See docs/BUILDING.md." >&2
    exit 1
fi

echo "Installing the Kaskad DE development session..."
sudo install -Dm755 "$launcher" /usr/local/bin/start-kaskad-desktop
printf '%s\n' "$repo_root" |
    sudo install -Dm644 /dev/stdin /etc/kaskad-desktop/dev-root
sudo install -Dm644 "$desktop_file" \
    /usr/share/wayland-sessions/kaskad-desktop.desktop
sudo install -Dm644 "$repo_root/session/kaskaddesktop-portals.conf" \
    /usr/share/xdg-desktop-portal/kaskaddesktop-portals.conf
sudo install -Dm644 "$repo_root/portal/data/kaskad.portal" \
    /usr/local/share/xdg-desktop-portal/portals/kaskad.portal
sed "s|@KASKAD_PORTAL_EXECUTABLE@|$repo_root/build/portal/bin/xdg-desktop-portal-kaskad|g" \
    "$repo_root/session/org.freedesktop.impl.portal.desktop.kaskad.desktop.in" |
    sudo install -Dm644 /dev/stdin \
        /usr/local/share/applications/org.freedesktop.impl.portal.desktop.kaskad.desktop
sed "s|@KASKAD_PORTAL_EXECUTABLE@|$repo_root/build/portal/bin/xdg-desktop-portal-kaskad|g" \
    "$repo_root/session/org.freedesktop.impl.portal.desktop.kaskad.service.in" |
    sudo install -Dm644 /dev/stdin \
        /usr/local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kaskad.service
sed "s|@KASKAD_PORTAL_EXECUTABLE@|$repo_root/build/portal/bin/xdg-desktop-portal-kaskad|g" \
    "$repo_root/session/xdg-desktop-portal-kaskad.service.in" |
    sudo install -Dm644 /dev/stdin \
        /usr/local/lib/systemd/user/xdg-desktop-portal-kaskad.service
systemctl --user daemon-reload 2>/dev/null || true

echo "Installed Kaskad DE as an additional Wayland session."
echo "Log out, select Kaskad DE in SDDM, and log in."
echo "To remove it, run: $repo_root/session/uninstall-dev-session.sh"

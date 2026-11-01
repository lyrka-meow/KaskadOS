#!/usr/bin/env bash

set -euo pipefail

systemctl --user stop xdg-desktop-portal-kaskad.service 2>/dev/null || true
sudo rm -f \
    /usr/local/bin/start-kaskad-desktop \
    /usr/share/wayland-sessions/kaskad-desktop.desktop \
    /usr/share/xdg-desktop-portal/kaskaddesktop-portals.conf \
    /usr/local/lib/systemd/user/xdg-desktop-portal-kaskad.service \
    /usr/local/share/applications/org.freedesktop.impl.portal.desktop.kaskad.desktop \
    /usr/local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kaskad.service \
    /usr/local/share/xdg-desktop-portal/portals/kaskad.portal \
    /etc/kaskad-desktop/dev-root

sudo rmdir /etc/kaskad-desktop 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true

echo "Removed the Kaskad DE development session."

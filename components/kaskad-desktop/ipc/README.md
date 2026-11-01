# Kaskad DE IPC

The compositor exports the `org.kaskados.Compositor1` interface at
`/org/kaskados/Compositor1` on the session bus, using the same service name.
The `Kaskad.Ipc` QML module consumes that interface through the `Kaskad`
singleton. Its implementation is in `quickshell/kaskad-module`.

The QML module claims `org.kaskados.Shell1` for the shell. The desktop portal
exports `org.kaskados.ScreenCastChooser1` at `/org/kaskados/ScreenCastChooser1`
under `org.freedesktop.impl.portal.desktop.kaskad`. Selection replies are
accepted only from the owner of `org.kaskados.Shell1`.

The session identity is `KaskadDesktop`. Portal discovery uses
`session/kaskaddesktop-portals.conf` and the `kaskad` portal backend.

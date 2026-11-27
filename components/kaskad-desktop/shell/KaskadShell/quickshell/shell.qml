//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_MEDIA_BACKEND=ffmpeg
//@ pragma Env QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
//@ pragma Env QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=vaapi
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Material
//@ pragma UseQApplication
//@ pragma AppId org.kaskados.Shell

import QtQuick
import Quickshell
import Kaskad.Ipc 1.0
import qs.Common
import qs.Modules
import qs.Services

ShellRoot {
    id: entrypoint

    readonly property bool disableHotReload: Quickshell.env("KASKAD_DISABLE_HOT_RELOAD") === "1" || Quickshell.env("KASKAD_DISABLE_HOT_RELOAD") === "true"
    readonly property color decorationActiveSurface: Theme.isLightMode ? Theme.blend(Theme.surfaceContainer, Theme.primary, 0.05) : Theme.surfaceContainer
    readonly property string decorationPaletteSignature: [
        decorationActiveSurface,
        Theme.surfaceContainer,
        Theme.surfaceText,
        Theme.surfaceVariantText,
        Theme.outline,
        Theme.primary,
        Theme.error,
        SettingsData.windowOutlineEnabled
    ].map(color => color.toString()).join("|")

    function syncDecorationPalette() {
        if (!Kaskad.available || Kaskad.protocolVersion < 16)
            return;
        Kaskad.setDecorationPalette({
            "surface": decorationActiveSurface.toString(),
            "surfaceInactive": Theme.surfaceContainer.toString(),
            "foreground": Theme.surfaceText.toString(),
            "foregroundInactive": Theme.surfaceVariantText.toString(),
            "outline": Theme.outline.toString(),
            "accent": Theme.primary.toString(),
            "error": Theme.error.toString(),
            "outlineEnabled": SettingsData.windowOutlineEnabled
        });
    }

    Component.onCompleted: {
        Quickshell.watchFiles = !disableHotReload;
        decorationPaletteSync.restart();
    }

    onDecorationPaletteSignatureChanged: decorationPaletteSync.restart()

    Connections {
        target: Kaskad
        function onAvailableChanged() {
            if (Kaskad.available)
                decorationPaletteSync.restart();
        }
    }

    Timer {
        id: decorationPaletteSync
        interval: 80
        repeat: false
        onTriggered: entrypoint.syncDecorationPalette()
    }

    Loader {
        id: wallpaperLoader
        asynchronous: false

        sourceComponent: Scope {
            WallpaperBackground {}

            Loader {
                active: SettingsData.blurredWallpaperLayer && CompositorService.isNiri
                asynchronous: false
                sourceComponent: BlurredWallpaperBackground {}
            }
        }
    }

    Loader {
        id: shellCoreLoader
        asynchronous: true
        source: "ShellCore.qml"
    }

    Loader {
        id: kaskadShellShellLoader
        active: shellCoreLoader.status === Loader.Ready
        asynchronous: true
        sourceComponent: Component {
            KaskadShell {}
        }

        onStatusChanged: {
            if (status === Loader.Error)
                console.error("KaskadShell failed to load");
        }
    }

    Binding {
        target: kaskadShellShellLoader.item
        property: "core"
        value: shellCoreLoader.item
        when: kaskadShellShellLoader.item !== null
    }
}

import QtQuick
import Quickshell
import Kaskad.Ipc
import qs.Common
import qs.Modules.Dock

Variants {
    model: Quickshell.screens

    delegate: DockContextMenuBase {
        id: menu

        required property var modelData
        property string windowId: ""
        property var windowData: ({})

        screen: modelData
        layerNamespace: "kaskad:window-menu"
        menuMinWidth: 220

        function outputData() {
            return Kaskad.outputs.find(output => output.name === modelData.name) ?? null;
        }

        function refreshWindowData() {
            windowData = Kaskad.windows.find(window => window.id === windowId) ?? ({});
            if (windowId && !windowData.id)
                close();
        }

        function showForWindow(id, globalX, globalY) {
            const output = outputData();
            if (!output)
                return;
            const logicalWidth = modelData.width;
            const logicalHeight = modelData.height;
            if (globalX < output.x || globalY < output.y
                    || globalX >= output.x + logicalWidth
                    || globalY >= output.y + logicalHeight)
                return;

            windowId = id;
            refreshWindowData();
            if (!windowData.id)
                return;

            anchorPos = Qt.point(globalX - output.x, globalY - output.y);
            visible = true;
        }

        property Connections ipcConnections: Connections {
            target: Kaskad

            function onWindowMenuRequested(windowId, x, y) {
                menu.showForWindow(windowId, x, y);
            }

            function onWindowsChanged() {
                if (menu.visible)
                    menu.refreshWindowData();
            }
        }

        DockTrashMenuItem {
            width: parent.width
            iconName: "open_in_new"
            text: I18n.tr("Activate window")
            onTriggered: {
                Kaskad.activateWindow(menu.windowId);
                menu.close();
            }
        }

        DockTrashMenuItem {
            width: parent.width
            enabled: menu.windowData.minimizable ?? false
            iconName: (menu.windowData.minimized ?? false) ? "select_window" : "minimize"
            text: (menu.windowData.minimized ?? false) ? I18n.tr("Restore window") : I18n.tr("Minimize window")
            onTriggered: {
                Kaskad.setWindowMinimized(menu.windowId, !(menu.windowData.minimized ?? false));
                menu.close();
            }
        }

        DockTrashMenuItem {
            width: parent.width
            enabled: menu.windowData.fullscreenable ?? false
            iconName: (menu.windowData.fullscreen ?? false) ? "fullscreen_exit" : "fullscreen"
            text: (menu.windowData.fullscreen ?? false) ? I18n.tr("Exit fullscreen") : I18n.tr("Fullscreen")
            onTriggered: {
                Kaskad.setWindowFullscreen(menu.windowId, !(menu.windowData.fullscreen ?? false));
                menu.close();
            }
        }

        DockTrashMenuItem {
            width: parent.width
            enabled: menu.windowData.closeable ?? false
            iconName: "close"
            text: I18n.tr("Close window")
            isDestructive: true
            onTriggered: {
                Kaskad.closeWindow(menu.windowId);
                menu.close();
            }
        }
    }
}

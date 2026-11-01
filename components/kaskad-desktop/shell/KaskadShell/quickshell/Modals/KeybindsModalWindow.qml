import QtQuick
import Quickshell
import qs.Common
import qs.Modals
import qs.Services
import qs.Widgets

FloatingWindow {
    id: win

    property bool disablePopupTransparency: true
    property alias shouldBeVisible: win.visible

    signal floatingToggleRequested

    function show() {
        visible = true;
    }

    function hide() {
        visible = false;
    }

    function toggle() {
        visible = !visible;
    }

    objectName: "keybindsModalWindow"
    title: I18n.tr("Keybinds")
    minimumSize: Qt.size(Math.min(560, Screen.width), Math.min(400, Screen.height))
    implicitWidth: 1000
    implicitHeight: screen ? Math.min(820, screen.height - 100) : 820
    color: Theme.surfaceContainer
    visible: false

    onVisibleChanged: {
        if (!visible)
            return;
        if (!Object.keys(KeybindsService.cheatsheet).length && KeybindsService.cheatsheetAvailable)
            KeybindsService.loadCheatsheet();
        Qt.callLater(() => {
            keybindsContent.forceActiveFocus();
            keybindsContent.searchField.forceActiveFocus();
        });
    }

    onClosed: win.visible = false

    Item {
        anchors.fill: parent

        KeybindsContent {
            id: keybindsContent
            anchors.fill: parent
            showFloatingToggle: true
            floating: true
            onFloatingToggleRequested: win.floatingToggleRequested()
            onCloseRequested: win.hide()
        }
    }
}

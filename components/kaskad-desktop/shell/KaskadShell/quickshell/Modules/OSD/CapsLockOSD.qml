import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

KaskadOSD {
    id: root

    osdWidth: Theme.iconSize + Theme.spacingS * 2
    osdHeight: Theme.iconSize + Theme.spacingS * 2
    autoHideInterval: 2000
    enableMouseInteraction: false

    property bool lastCapsLockState: false

    Connections {
        target: KaskadService

        function onCapsLockStateChanged() {
            if (lastCapsLockState !== KaskadService.capsLockState && SettingsData.osdCapsLockEnabled) {
                root.show()
            }
            lastCapsLockState = KaskadService.capsLockState
        }
    }

    Component.onCompleted: {
        lastCapsLockState = KaskadService.capsLockState
    }

    content: KaskadIcon {
        anchors.centerIn: parent
        name: KaskadService.capsLockState ? "shift_lock" : "shift_lock_off"
        size: Theme.iconSize
        color: Theme.primary
    }
}

import QtQuick
import Quickshell

QtObject {
    // Keep this dynamic: concrete singleton services expose their own refCount
    // property, which is not part of the generic Singleton base type.
    required property var service

    Component.onCompleted: service.refCount++
    Component.onDestruction: service.refCount = Math.max(0, service.refCount - 1)
}

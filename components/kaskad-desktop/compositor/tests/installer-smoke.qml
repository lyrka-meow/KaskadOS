import QtQuick
import QtQuick.Window

Window {
    visible: true
    width: 960
    height: 640
    title: "KaskadOS installer Qt smoke test"
    color: "#18201b"

    Rectangle {
        anchors.centerIn: parent
        width: 420
        height: 180
        radius: 24
        color: "#9fddb5"
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: Qt.quit()
    }
}

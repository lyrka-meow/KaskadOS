// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

Item {
    id: root

    required property var scheme
    property bool checked: true
    property bool kernoraStyle: false

    implicitWidth: 52
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.scheme.primary : root.scheme.surfaceContainerHighest
        border.width: root.checked ? 0 : 2
        border.color: root.scheme.outline

        Rectangle {
            width: root.checked ? 24 : 16
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 4 : 8
            color: root.checked ? root.scheme.onPrimary : root.scheme.outline

            Text {
                anchors.centerIn: parent
                visible: root.checked
                text: "✓"
                color: root.scheme.primary
                font.pixelSize: 14
                font.weight: Font.Bold
            }

            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 160 } }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.checked = !root.checked
    }
}

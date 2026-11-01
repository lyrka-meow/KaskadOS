// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

Item {
    id: root

    required property var scheme
    property bool expressive: false
    property real value: 0.62
    property string icon: "☀"

    signal moved(real value)

    implicitHeight: expressive ? 52 : 40
    activeFocusOnTab: true

    readonly property real clampedValue: Math.max(0, Math.min(1, value))
    readonly property real gap: expressive ? 6 : 3
    readonly property real slot: 4
    readonly property real handleCenter: slot / 2 + clampedValue * (width - slot)
    readonly property real activeWidth: Math.max(0, handleCenter - gap)
    readonly property real inactiveX: handleCenter + gap
    readonly property real inactiveWidth: Math.max(0, width - inactiveX)

    function setFromX(x) {
        const next = Math.max(0, Math.min(1, (x - slot / 2) / Math.max(1, width - slot)));
        value = next;
        moved(next);
    }

    Item {
        anchors.fill: parent
        visible: root.expressive

        Rectangle {
            x: 0
            width: root.activeWidth
            height: 40
            anchors.verticalCenter: parent.verticalCenter
            radius: Math.min(12, width / 2)
            color: root.scheme.primary

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.width >= 48
                text: root.icon
                color: root.scheme.onPrimary
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            x: root.inactiveX
            width: root.inactiveWidth
            height: 40
            anchors.verticalCenter: parent.verticalCenter
            radius: Math.min(12, width / 2)
            color: root.scheme.secondaryContainer

            Rectangle {
                width: 4
                height: 4
                radius: 2
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.width > 24
                color: root.scheme.primary
            }
        }

        Rectangle {
            x: root.handleCenter - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: drag.pressed ? 2 : 4
            height: 44
            radius: width / 2
            color: root.scheme.primary

            Behavior on width { NumberAnimation { duration: 100 } }
        }
    }

    Item {
        anchors.fill: parent
        visible: !root.expressive

        Rectangle {
            width: parent.width
            height: 12
            anchors.verticalCenter: parent.verticalCenter
            radius: 6
            color: root.scheme.surfaceContainerHigh
        }

        Rectangle {
            width: Math.max(0, root.handleCenter - 3)
            height: 12
            anchors.verticalCenter: parent.verticalCenter
            radius: 6
            color: root.scheme.primary
        }

        Rectangle {
            x: root.handleCenter - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: 20
            radius: 2
            color: root.scheme.primary

            Rectangle {
                anchors.centerIn: parent
                width: 28
                height: 28
                radius: 14
                color: root.scheme.primary
                opacity: drag.pressed ? 0.16 : drag.containsMouse ? 0.08 : 0
            }
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => root.setFromX(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                root.setFromX(mouse.x);
        }
    }
}

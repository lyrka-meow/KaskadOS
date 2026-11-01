import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Card {
    id: root
    pad: Theme.spacingS

    Component.onCompleted: {
        DgopService.addRef(["cpu", "memory", "system"]);
    }
    Component.onDestruction: {
        DgopService.removeRef(["cpu", "memory", "system"]);
    }

    Row {
        anchors.fill: parent
        spacing: Theme.spacingS

        // CPU Bar
        Column {
            width: (parent.width - 2 * parent.spacing) / 3
            height: parent.height
            spacing: Theme.spacingXXS

            StyledText {
                width: parent.width
                height: Theme.fontSizeSmall
                text: Math.round(DgopService.cpuUsage || 0)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                width: 8
                height: parent.height - Theme.fontSizeSmall - Theme.iconSizeSmall - parent.spacing * 2
                radius: 4
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.outlineHeavy

                Rectangle {
                    width: parent.width
                    height: parent.height * Math.min((DgopService.cpuUsage || 6) / 100, 1)
                    radius: parent.radius
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: {
                        if (DgopService.cpuUsage > 80)
                            return Theme.error;
                        if (DgopService.cpuUsage > 60)
                            return Theme.warning;
                        return Theme.primary;
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.iconSizeSmall

                KaskadIcon {
                    name: "memory"
                    size: Theme.iconSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    color: {
                        if (DgopService.cpuUsage > 80)
                            return Theme.error;
                        if (DgopService.cpuUsage > 60)
                            return Theme.warning;
                        return Theme.primary;
                    }
                }
            }
        }

        // Temperature Bar
        Column {
            width: (parent.width - 2 * parent.spacing) / 3
            height: parent.height
            spacing: Theme.spacingXXS

            StyledText {
                width: parent.width
                height: Theme.fontSizeSmall
                text: Math.round(DgopService.cpuTemperature || 0) + "°"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                width: 8
                height: parent.height - Theme.fontSizeSmall - Theme.iconSizeSmall - parent.spacing * 2
                radius: 4
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.outlineHeavy

                Rectangle {
                    width: parent.width
                    height: parent.height * Math.min(Math.max((DgopService.cpuTemperature || 40) / 100, 0), 1)
                    radius: parent.radius
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: {
                        if (DgopService.cpuTemperature > 85)
                            return Theme.error;
                        if (DgopService.cpuTemperature > 69)
                            return Theme.warning;
                        return Theme.primary;
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.iconSizeSmall

                KaskadIcon {
                    name: "device_thermostat"
                    size: Theme.iconSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    color: {
                        if (DgopService.cpuTemperature > 85)
                            return Theme.error;
                        if (DgopService.cpuTemperature > 69)
                            return Theme.warning;
                        return Theme.primary;
                    }
                }
            }
        }

        // RAM Bar
        Column {
            width: (parent.width - 2 * parent.spacing) / 3
            height: parent.height
            spacing: Theme.spacingXXS

            StyledText {
                width: parent.width
                height: Theme.fontSizeSmall
                text: Math.round(DgopService.memoryUsage || 0)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                width: 8
                height: parent.height - Theme.fontSizeSmall - Theme.iconSizeSmall - parent.spacing * 2
                radius: 4
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.outlineHeavy

                Rectangle {
                    width: parent.width
                    height: parent.height * Math.min((DgopService.memoryUsage || 42) / 100, 1)
                    radius: parent.radius
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: {
                        if (DgopService.memoryUsage > 90)
                            return Theme.error;
                        if (DgopService.memoryUsage > 75)
                            return Theme.warning;
                        return Theme.primary;
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.iconSizeSmall

                KaskadIcon {
                    name: "developer_board"
                    size: Theme.iconSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    color: {
                        if (DgopService.memoryUsage > 90)
                            return Theme.error;
                        if (DgopService.memoryUsage > 75)
                            return Theme.warning;
                        return Theme.primary;
                    }
                }
            }
        }
    }
}

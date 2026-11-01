// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: pane

    required property string title
    required property string subtitle
    required property var scheme
    required property bool kernora
    property real sliderValue: 0.62

    signal sliderMoved(real value)

    radius: 28
    color: scheme.surface
    border.width: 1
    border.color: scheme.outlineVariant
    implicitHeight: content.implicitHeight + 48

    function colorRoles() {
        return [
            { name: "Primary", value: scheme.primary },
            { name: "Primary container", value: scheme.primaryContainer },
            { name: "Surface", value: scheme.surface },
            { name: "Container", value: scheme.surfaceContainer },
            { name: "Container high", value: scheme.surfaceContainerHigh },
            { name: "Container highest", value: scheme.surfaceContainerHighest },
            { name: "Secondary container", value: scheme.secondaryContainer },
            { name: "Outline", value: scheme.outline }
        ];
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 14
                color: pane.scheme.primaryContainer

                Text {
                    anchors.centerIn: parent
                    text: pane.kernora ? "K" : "K"
                    color: pane.scheme.onPrimaryContainer
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: pane.title
                    color: pane.scheme.onSurface
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    text: pane.subtitle
                    color: pane.scheme.onSurfaceVariant
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
        }

        Text {
            text: "Панель и быстрые настройки"
            color: pane.scheme.onSurface
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: pane.kernora ? 26 : 14
            color: pane.kernora ? pane.scheme.surfaceContainer : pane.scheme.surface
            border.width: pane.kernora ? 0 : 1
            border.color: pane.scheme.outlineVariant

            RowLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 6

                Repeater {
                    model: ["⌘", "●", "Wi-Fi", "78%"]

                    Rectangle {
                        required property string modelData
                        required property int index
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: modelData.length > 2 ? 76 : 40
                        radius: pane.kernora ? 20 : 12
                        color: index === 0 ? pane.scheme.primaryContainer : pane.scheme.surfaceContainerHigh

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: index === 0 ? pane.scheme.onPrimaryContainer : pane.scheme.onSurface
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "12:42"
                    color: pane.scheme.onSurface
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    Layout.rightMargin: 8
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 214
            radius: pane.kernora ? 28 : 16
            color: pane.scheme.surfaceContainer

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Быстрые настройки"
                            color: pane.scheme.onSurface
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: pane.kernora ? "Точные роли Material 3" : "Текущая палитра KaskadOS"
                            color: pane.scheme.onSurfaceVariant
                            font.pixelSize: 11
                        }
                    }
                    Item { Layout.fillWidth: true }
                    MaterialSwitch { scheme: pane.scheme; kernoraStyle: pane.kernora }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 8

                    Repeater {
                        model: [
                            { icon: "⌁", name: "Wi-Fi", detail: "KaskadOS" },
                            { icon: "ᛒ", name: "Bluetooth", detail: "Включено" },
                            { icon: "◐", name: "Тёмная тема", detail: "Активна" },
                            { icon: "☾", name: "Ночной свет", detail: "22:00" }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 62
                            radius: pane.kernora ? 20 : 12
                            color: index === 0 ? pane.scheme.secondaryContainer : pane.scheme.surfaceContainerHigh

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 38
                                    radius: pane.kernora ? 19 : 10
                                    color: index === 0 ? pane.scheme.primary : pane.scheme.surfaceContainerHighest
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        color: index === 0 ? pane.scheme.onPrimary : pane.scheme.onSurface
                                        font.pixelSize: 18
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text { text: modelData.name; color: pane.scheme.onSurface; font.pixelSize: 13; font.weight: Font.Medium }
                                    Text { text: modelData.detail; color: pane.scheme.onSurfaceVariant; font.pixelSize: 10 }
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: [
                    { label: "Основная", kind: 0 },
                    { label: "Тональная", kind: 1 },
                    { label: "Контур", kind: 2 }
                ]

                Rectangle {
                    required property var modelData
                    Layout.preferredHeight: 40
                    Layout.preferredWidth: buttonLabel.implicitWidth + 32
                    radius: pane.kernora ? 20 : 12
                    color: modelData.kind === 0 ? pane.scheme.primary
                           : modelData.kind === 1 ? pane.scheme.secondaryContainer : "transparent"
                    border.width: modelData.kind === 2 ? 1 : 0
                    border.color: pane.scheme.outline

                    Text {
                        id: buttonLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: modelData.kind === 0 ? pane.scheme.onPrimary
                               : modelData.kind === 1 ? pane.scheme.onSecondaryContainer : pane.scheme.primary
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Text { text: pane.kernora ? "Kernora MSlider" : "KaskadOS KaskadSlider"; color: pane.scheme.onSurface; font.pixelSize: 13; font.weight: Font.DemiBold }
                Item { Layout.fillWidth: true }
                Text { text: Math.round(pane.sliderValue * 100) + "%"; color: pane.scheme.onSurfaceVariant; font.pixelSize: 12 }
            }

            MaterialSlider {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                scheme: pane.scheme
                expressive: pane.kernora
                value: pane.sliderValue
                onMoved: value => pane.sliderMoved(value)
            }
        }

        Text {
            text: "Роли палитры"
            color: pane.scheme.onSurface
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            Repeater {
                model: pane.colorRoles()

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: 12
                    color: modelData.value
                    border.width: 1
                    border.color: pane.scheme.outlineVariant

                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.name
                            color: pane.scheme.onSurface
                            style: Text.Outline
                            styleColor: pane.scheme.surface
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: String(modelData.value).toUpperCase()
                            color: pane.scheme.onSurface
                            style: Text.Outline
                            styleColor: pane.scheme.surface
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }
    }
}

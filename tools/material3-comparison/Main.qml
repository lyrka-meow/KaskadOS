// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: window

    width: 1420
    height: 900
    minimumWidth: 1040
    minimumHeight: 720
    visible: true
    title: "KaskadOS — сравнение Material 3"
    color: activePalette.surfaceContainerLowest

    property bool lightMode: false
    property real sharedSliderValue: 0.62

    readonly property var kaskadosDark: ({
        primary: "#9FE0B4", onPrimary: "#102117",
        primaryContainer: "#284D36", onPrimaryContainer: "#E2E8E4",
        secondary: "#B4CCBA", secondaryContainer: "#374B3E", onSecondaryContainer: "#D0E8D6",
        surface: "#121411", onSurface: "#E2E3DD",
        surfaceContainerLowest: "#0C0F0C", surfaceContainerLow: "#1A1C19",
        surfaceContainer: "#1E201C", surfaceContainerHigh: "#282B27",
        surfaceContainerHighest: "#333531", surfaceVariant: "#424940",
        onSurfaceVariant: "#C2C8BD", outline: "#8C9388", outlineVariant: "#424940"
    })
    readonly property var kaskadosLight: ({
        primary: "#326A45", onPrimary: "#FFFFFF",
        primaryContainer: "#B9F3CA", onPrimaryContainer: "#171D19",
        secondary: "#506356", secondaryContainer: "#B0BBB3", onSecondaryContainer: "#171D19",
        surface: "#F6FBF6", onSurface: "#171D19",
        surfaceContainerLowest: "#FFFFFF", surfaceContainerLow: "#F0F5F0",
        surfaceContainer: "#EAEEEA", surfaceContainerHigh: "#E4E9E4",
        surfaceContainerHighest: "#DEE3DE", surfaceVariant: "#DDE5DE",
        onSurfaceVariant: "#414942", outline: "#717972", outlineVariant: "#C3CBC4"
    })

    // Hybrid preview: Kernora's green surface ladder with the KaskadOS accent family.
    readonly property var kernoraDark: ({
        primary: "#9FE0B4", onPrimary: "#102117",
        primaryContainer: "#284D36", onPrimaryContainer: "#E2E8E4",
        secondary: "#B4CCBA", secondaryContainer: "#374B3E", onSecondaryContainer: "#D0E8D6",
        surface: "#121411", onSurface: "#E2E3DD",
        surfaceContainerLowest: "#0C0F0C", surfaceContainerLow: "#1A1C19",
        surfaceContainer: "#1E201C", surfaceContainerHigh: "#282B27",
        surfaceContainerHighest: "#333531", surfaceVariant: "#424940",
        onSurfaceVariant: "#C2C8BD", outline: "#8C9388", outlineVariant: "#424940"
    })
    readonly property var kernoraLight: ({
        primary: "#326A45", onPrimary: "#FFFFFF",
        primaryContainer: "#B9F3CA", onPrimaryContainer: "#171D19",
        secondary: "#4E6355", secondaryContainer: "#D0E8D6", onSecondaryContainer: "#0B1F14",
        surface: "#F9FAF3", onSurface: "#1A1C19",
        surfaceContainerLowest: "#FFFFFF", surfaceContainerLow: "#F4F4EE",
        surfaceContainer: "#EEEFE8", surfaceContainerHigh: "#E8E9E3",
        surfaceContainerHighest: "#E2E3DD", surfaceVariant: "#DEE4D8",
        onSurfaceVariant: "#424940", outline: "#73796F", outlineVariant: "#C2C8BD"
    })

    readonly property var kaskadosPalette: lightMode ? kaskadosLight : kaskadosDark
    readonly property var kernoraPalette: lightMode ? kernoraLight : kernoraDark
    readonly property var activePalette: kaskadosPalette

    header: Rectangle {
        height: 76
        color: window.activePalette.surfaceContainer
        border.width: 0

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 28
            anchors.rightMargin: 28
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: "Material 3 · лаборатория палитр"
                    color: window.activePalette.onSurface
                    font.pixelSize: 21
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Одинаковые элементы, одинаковое значение — отличаются только система токенов и форма компонентов"
                    color: window.activePalette.onSurfaceVariant
                    font.pixelSize: 11
                }
            }

            Rectangle {
                Layout.preferredWidth: modeRow.implicitWidth + 12
                Layout.preferredHeight: 46
                radius: 23
                color: window.activePalette.surfaceContainerHigh

                RowLayout {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: [
                            { text: "Тёмная", light: false },
                            { text: "Светлая", light: true }
                        ]

                        Rectangle {
                            required property var modelData
                            readonly property bool selected: window.lightMode === modelData.light
                            Layout.preferredWidth: 86
                            Layout.preferredHeight: 36
                            radius: 18
                            color: selected ? window.activePalette.primary : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.text
                                color: parent.selected ? window.activePalette.onPrimary : window.activePalette.onSurface
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.lightMode = modelData.light
                            }
                        }
                    }
                }
            }
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        RowLayout {
            width: parent.width
            spacing: 20

            Item { Layout.preferredWidth: 8 }

            ComparisonPane {
                Layout.fillWidth: true
                Layout.minimumWidth: 480
                Layout.topMargin: 20
                Layout.bottomMargin: 24
                title: "KaskadOS"
                subtitle: "Текущая встроенная палитра StockThemes и форма компонентов QtkShell"
                scheme: window.kaskadosPalette
                kernora: false
                sliderValue: window.sharedSliderValue
                onSliderMoved: value => window.sharedSliderValue = value
            }

            ComparisonPane {
                Layout.fillWidth: true
                Layout.minimumWidth: 480
                Layout.topMargin: 20
                Layout.bottomMargin: 24
                title: "Kernora × KaskadOS"
                subtitle: "Фон Kernora и фирменный акцент KaskadOS #9FE0B4"
                scheme: window.kernoraPalette
                kernora: true
                sliderValue: window.sharedSliderValue
                onSliderMoved: value => window.sharedSliderValue = value
            }

            Item { Layout.preferredWidth: 8 }
        }
    }
}

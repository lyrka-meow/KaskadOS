pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true
    Component.onCompleted: NetworkService.addRef()
    Component.onDestruction: NetworkService.removeRef()

    KaskadFlickable {
        anchors.fill: parent
        clip: true
        contentHeight: mainColumn.height + Theme.spacingXL
        contentWidth: width

        Column {
            id: mainColumn
            topPadding: 4
            width: Math.min(600, parent.width - Theme.spacingL * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingL

            NetworkInternetCard { width: parent.width }

            NetworkHotspotCard { width: parent.width }

            SettingsCard {
                width: parent.width
                title: "Подключения"
                iconName: "lan"

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: [
                            {
                                name: "Кабель",
                                icon: "settings_ethernet",
                                detail: NetworkService.ethernetConnected ? (NetworkService.networkStatus === "ethernet" ? "Основное подключение" : "Подключён") : "Не подключён",
                                tab: "network_ethernet"
                            },
                            {
                                name: "Wi‑Fi",
                                icon: "wifi",
                                detail: NetworkService.wifiConnected ? NetworkService.currentWifiSSID : NetworkService.wifiEnabled ? "Не подключён" : "Выключен",
                                tab: "network_wifi"
                            }
                        ]

                        delegate: Rectangle {
                            id: connectionRow
                            required property var modelData
                            width: parent.width
                            height: 64
                            radius: Theme.cornerRadius
                            color: rowMouse.containsMouse ? Theme.surfacePressed : Theme.surfaceVariant

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                KaskadIcon {
                                    name: connectionRow.modelData.icon
                                    size: 24
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    width: parent.width - 48 - Theme.spacingM * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    StyledText {
                                        text: connectionRow.modelData.name
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: connectionRow.modelData.detail
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }
                                }

                                KaskadIcon {
                                    name: "chevron_right"
                                    size: 24
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: PopoutService.openSettingsWithTab(connectionRow.modelData.tab)
                            }
                        }
                    }
                }
            }
        }
    }
}

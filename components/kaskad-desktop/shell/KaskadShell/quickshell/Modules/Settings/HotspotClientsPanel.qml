pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root

    width: parent?.width ?? 400
    spacing: Theme.spacingS
    property string editingMac: ""
    property string editingName: ""

    function beginNameEdit(client) {
        editingMac = client.mac;
        editingName = client.name || client.autoName || "";
    }

    function cancelNameEdit() {
        editingMac = "";
        editingName = "";
    }

    function saveNameEdit(name) {
        if (!editingMac)
            return;
        const mac = editingMac;
        NetworkService.setHotspotClientName(mac, name.trim(), response => {
            if (!response.error && editingMac === mac)
                cancelNameEdit();
        });
    }

    function formatBytes(value, rate) {
        let size = Math.max(0, Number(value) || 0);
        const units = ["Б", "КиБ", "МиБ", "ГиБ"];
        let index = 0;
        while (size >= 1024 && index < units.length - 1) {
            size /= 1024;
            index++;
        }
        return (index === 0 ? Math.round(size) : size.toFixed(size < 10 ? 1 : 0)) + " " + units[index] + (rate ? "/с" : "");
    }

    function formatConnected(seconds) {
        const total = Math.max(0, Number(seconds) || 0);
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        return hours > 0 ? "%1 ч %2 мин".arg(hours).arg(minutes) : "%1 мин".arg(minutes);
    }

    Component.onCompleted: NetworkService.refreshHotspotClients()

    Timer {
        interval: 2000
        repeat: true
        running: root.visible && NetworkService.hotspotEnabled
        triggeredOnStart: true
        onTriggered: NetworkService.refreshHotspotClients()
    }

    StyledText {
        width: parent.width
        text: "Подключённые устройства (%1)".arg(NetworkService.hotspotClients.length)
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        visible: NetworkService.hotspotEnabled && NetworkService.hotspotClients.length === 0
        text: "Пока никто не подключён"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Repeater {
        model: NetworkService.hotspotClients

        delegate: Rectangle {
            required property var modelData
            width: root.width
            height: clientContent.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceVariant

            Column {
                id: clientContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width
                    text: modelData.name || modelData.autoName || (modelData.vendor ? "Устройство " + modelData.vendor : "Неизвестное устройство")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: {
                        const parts = [];
                        if (modelData.ip)
                            parts.push(modelData.ip);
                        parts.push(modelData.mac);
                        if (modelData.randomizedMAC)
                            parts.push("случайный MAC");
                        else if (modelData.vendor)
                            parts.push(modelData.vendor);
                        if (modelData.name && modelData.autoName && modelData.name !== modelData.autoName)
                            parts.push("имя устройства: " + modelData.autoName);
                        return parts.join("  •  ");
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: "Сигнал %1 dBm  •  подключено %2\n↓ %3 (%4)  ↑ %5 (%6)\nЛиния: ↓ %7  ↑ %8"
                        .arg(modelData.signal).arg(root.formatConnected(modelData.connectedSeconds))
                        .arg(root.formatBytes(modelData.txRate, true)).arg(root.formatBytes(modelData.txBytes, false))
                        .arg(root.formatBytes(modelData.rxRate, true)).arg(root.formatBytes(modelData.rxBytes, false))
                        .arg(modelData.txBitrate || "—").arg(modelData.rxBitrate || "—")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    KaskadButton {
                        text: modelData.name ? "Переименовать" : "Назвать"
                        iconName: "edit"
                        buttonHeight: 32
                        backgroundColor: Theme.surface
                        textColor: Theme.surfaceText
                        visible: NetworkService.hotspotClientNamesApiVersion <= KaskadService.apiVersion
                        onClicked: root.beginNameEdit(modelData)
                    }

                    KaskadButton {
                        text: "Отключить"
                        iconName: "link_off"
                        buttonHeight: 32
                        backgroundColor: Theme.surface
                        textColor: Theme.surfaceText
                        onClicked: NetworkService.disconnectHotspotClient(modelData.mac)
                    }

                    KaskadButton {
                        text: "Заблокировать"
                        iconName: "block"
                        buttonHeight: 32
                        backgroundColor: Theme.error
                        textColor: Theme.surface
                        onClicked: NetworkService.setHotspotClientBlocked(modelData.mac, true)
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.editingMac === modelData.mac

                    KaskadTextField {
                        width: parent.width
                        labelText: "Понятное имя устройства"
                        placeholderText: "Например, Мой POCO"
                        text: root.editingName
                        maximumLength: 64
                        showClearButton: true
                        onTextEdited: root.editingName = text
                        onAccepted: root.saveNameEdit(root.editingName)
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.spacingS

                        KaskadButton {
                            text: "Сохранить"
                            iconName: "save"
                            buttonHeight: 32
                            onClicked: root.saveNameEdit(root.editingName)
                        }

                        KaskadButton {
                            text: "Отмена"
                            buttonHeight: 32
                            backgroundColor: Theme.surface
                            textColor: Theme.surfaceText
                            onClicked: root.cancelNameEdit()
                        }

                        KaskadButton {
                            text: "Сбросить имя"
                            buttonHeight: 32
                            backgroundColor: Theme.surface
                            textColor: Theme.surfaceText
                            visible: Boolean(modelData.name)
                            onClicked: root.saveNameEdit("")
                        }
                    }
                }
            }
        }
    }

    StyledText {
        width: parent.width
        visible: NetworkService.hotspotBlockedClients.length > 0
        text: "Заблокированные устройства"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    Repeater {
        model: NetworkService.hotspotBlockedClients

        delegate: Rectangle {
            required property var modelData
            width: root.width
            height: 52
            radius: Theme.cornerRadius
            color: Theme.surfaceVariant

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.right: unblockButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            KaskadButton {
                id: unblockButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: "Разблокировать"
                buttonHeight: 34
                backgroundColor: Theme.surface
                textColor: Theme.surfaceText
                onClicked: NetworkService.setHotspotClientBlocked(modelData, false)
            }
        }
    }

    HotspotAnalyticsPanel {
        width: root.width
        visible: KaskadService.apiVersion >= NetworkService.hotspotAnalyticsApiVersion
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.Widgets

SettingsCard {
    id: root

    title: "Интернет"
    iconName: "public"
    settingKey: "networkStatus"
    tags: ["network", "internet", "source", "priority", "ethernet", "wifi"]

    readonly property string sourceName: {
        if (NetworkService.networkStatus === "ethernet")
            return "Кабель";
        if (NetworkService.networkStatus === "wifi")
            return NetworkService.currentWifiSSID ? "Wi‑Fi · " + NetworkService.currentWifiSSID : "Wi‑Fi";
        return NetworkService.primaryConnection || "Источник не подключён";
    }
    readonly property string statusText: {
        if (!KaskadService.isConnected)
            return "Нет связи с сетевой службой";
        if (!NetworkService.primaryDevice && !NetworkService.primaryConnection)
            return "Нет маршрута в интернет";
        switch (NetworkService.connectivity) {
        case "full": return "Интернет доступен";
        case "portal": return "Требуется вход в сеть";
        case "limited": return "Подключено · интернет недоступен";
        case "none": return "Нет доступа к сети";
        default: return "Подключено · доступ в интернет не проверен";
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM

        Row {
            width: parent.width
            spacing: Theme.spacingM

            KaskadIcon {
                name: NetworkService.networkStatus === "wifi" ? "wifi" : NetworkService.networkStatus === "ethernet" ? "settings_ethernet" : "public_off"
                size: 32
                color: NetworkService.connectivity === "full" ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                width: parent.width - 32 - Theme.spacingM
                spacing: Theme.spacingXS

                StyledText {
                    width: parent.width
                    text: root.sourceName
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: root.statusText
                    font.pixelSize: Theme.fontSizeSmall
                    color: NetworkService.connectivity === "full" ? Theme.primary : Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outlineStrong
        }

        StyledText {
            width: parent.width
            text: NetworkService.changingPreference ? "Меняем приоритет…" : "Предпочитать подключение"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }

        KaskadButtonGroup {
            model: ["Авто", "Кабель", "Wi‑Fi"]
            checkEnabled: false
            minButtonWidth: 100
            buttonPadding: Theme.spacingS
            maximumWidth: parent.width
            currentIndex: ["auto", "ethernet", "wifi"].indexOf(NetworkService.userPreference)
            enabled: KaskadService.isConnected && NetworkService.backend === "networkmanager" && !NetworkService.changingPreference
            onSelectionChanged: (index, selected) => {
                if (selected)
                    NetworkService.setNetworkPreference(["auto", "ethernet", "wifi"][index]);
            }
        }

        StyledText {
            width: parent.width
            text: {
                if (NetworkService.preferenceError)
                    return NetworkService.preferenceError;
                if (NetworkService.userPreference === "ethernet" && !NetworkService.ethernetConnected)
                    return "Кабель недоступен. Используется доступное подключение.";
                if (NetworkService.userPreference === "wifi" && !NetworkService.wifiConnected)
                    return "Wi‑Fi не подключён. Используется доступное подключение.";
                return "";
            }
            visible: text.length > 0
            font.pixelSize: Theme.fontSizeSmall
            color: NetworkService.preferenceError ? Theme.error : Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }
}

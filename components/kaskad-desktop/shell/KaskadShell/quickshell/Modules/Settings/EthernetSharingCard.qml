pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.Widgets

SettingsCard {
    id: root

    width: parent.width
    title: "Интернет через Ethernet"
    iconName: "lan"
    settingKey: "ethernetSharing"
    tags: ["ethernet", "sharing", "internet", "nat", "dhcp", "vpn", "regalia", "раздача", "кабель"]

    property string selectedDevice: NetworkService.ethernetSharingDevice
        || (NetworkService.ethernetDevices.length === 1 ? NetworkService.ethernetDevices[0].name : "")
    property bool shareThroughVPN: NetworkService.ethernetSharingUseVPN
    readonly property var selectedAdapter: {
        const devices = NetworkService.ethernetDevices || [];
        for (const adapter of devices) {
            if (adapter.name === selectedDevice)
                return adapter;
        }
        return null;
    }
    readonly property bool busy: NetworkService.ethernetSharingBusy || NetworkService.ethernetSharingActivating
    readonly property bool canEnable: NetworkService.ethernetSharingSupported
        && NetworkService.wifiConnected
        && selectedAdapter !== null
        && selectedAdapter.carrier === true
    readonly property bool toggleEnabled: !busy
        && (NetworkService.ethernetSharingEnabled || canEnable)

    function setSharing(enabled) {
        if (!toggleEnabled)
            return;
        NetworkService.setEthernetSharing(enabled, selectedDevice, shareThroughVPN);
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM

        Connections {
            target: NetworkService

            function onEthernetSharingDeviceChanged() {
                if (NetworkService.ethernetSharingDevice)
                    root.selectedDevice = NetworkService.ethernetSharingDevice;
            }

            function onEthernetSharingUseVPNChanged() {
                if (NetworkService.ethernetSharingEnabled)
                    root.shareThroughVPN = NetworkService.ethernetSharingUseVPN;
            }

            function onEthernetDevicesChanged() {
                const devices = NetworkService.ethernetDevices || [];
                if (devices.length === 1 && !root.selectedDevice)
                    root.selectedDevice = devices[0].name;
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingM

            Rectangle {
                width: 44
                height: 44
                radius: Theme.cornerRadius
                color: NetworkService.ethernetSharingEnabled
                    ? Theme.withAlpha(Theme.primary, 0.16)
                    : Theme.surfaceVariant

                KaskadIcon {
                    anchors.centerIn: parent
                    name: NetworkService.ethernetSharingEnabled ? "device_hub" : "lan"
                    size: 24
                    color: NetworkService.ethernetSharingEnabled ? Theme.primary : Theme.surfaceVariantText
                }
            }

            Column {
                width: parent.width - 44 - sharingToggle.width - Theme.spacingM * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                StyledText {
                    width: parent.width
                    text: {
                        if (!NetworkService.ethernetSharingSupported)
                            return "Недоступно для текущей сетевой службы";
                        if (root.busy)
                            return NetworkService.ethernetSharingStatus === "stopping" ? "Выключаем раздачу…" : "Включаем раздачу…";
                        if (NetworkService.ethernetSharingEnabled)
                            return "Раздача включена";
                        return "Раздавать интернет по кабелю";
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: NetworkService.ethernetSharingEnabled ? Theme.primary : Theme.surfaceText
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    width: parent.width
                    text: {
                        if (NetworkService.ethernetSharingEnabled) {
                            const address = NetworkService.ethernetSharingAddress
                                ? " · " + NetworkService.ethernetSharingAddress : "";
                            const route = NetworkService.ethernetSharingUseVPN ? " · Regalia VPN" : " · напрямую";
                            return "Wi‑Fi · %1 → %2%3%4".arg(NetworkService.currentWifiSSID).arg(NetworkService.ethernetSharingDevice).arg(route).arg(address);
                        }
                        return "Ноутбук получает интернет по Wi‑Fi, а подключённый компьютер — автоматически по DHCP.";
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            KaskadToggle {
                id: sharingToggle
                anchors.verticalCenter: parent.verticalCenter
                checked: NetworkService.ethernetSharingEnabled
                enabled: root.toggleEnabled
                toggling: root.busy
                onToggled: checked => root.setSharing(checked)
            }
        }

        KaskadDropdown {
            width: parent.width
            visible: NetworkService.ethernetDevices.length > 1
            enabled: !root.busy && !NetworkService.ethernetSharingEnabled
            text: "Ethernet-адаптер"
            currentValue: root.selectedDevice
            options: (NetworkService.ethernetDevices || []).map(device => device.name)
            onValueChanged: value => root.selectedDevice = value
        }

        Row {
            width: parent.width
            spacing: Theme.spacingM

            KaskadIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "vpn_lock"
                size: 22
                color: root.shareThroughVPN ? Theme.primary : Theme.surfaceVariantText
            }

            Column {
                width: parent.width - 22 - vpnToggle.width - Theme.spacingM * 2
                spacing: Theme.spacingXXS

                StyledText {
                    width: parent.width
                    text: "Передавать через Regalia VPN"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    width: parent.width
                    text: root.shareThroughVPN
                        ? "При отключении VPN интернет на подключённом ПК блокируется без утечки напрямую."
                        : "Обычная раздача через текущее интернет-подключение ноутбука."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            KaskadToggle {
                id: vpnToggle
                anchors.verticalCenter: parent.verticalCenter
                checked: root.shareThroughVPN
                enabled: !root.busy && !NetworkService.ethernetSharingEnabled
                onToggled: checked => root.shareThroughVPN = checked
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outlineStrong
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            KaskadIcon {
                name: {
                    if (NetworkService.ethernetSharingError)
                        return "error";
                    if (!NetworkService.wifiConnected)
                        return "wifi_off";
                    if (root.selectedAdapter === null || root.selectedAdapter.carrier !== true)
                        return "link_off";
                    return "check_circle";
                }
                size: 18
                color: NetworkService.ethernetSharingError ? Theme.error
                    : root.canEnable || NetworkService.ethernetSharingEnabled ? Theme.primary
                    : Theme.surfaceVariantText
            }

            StyledText {
                width: parent.width - 18 - Theme.spacingS
                text: {
                    if (NetworkService.ethernetSharingError)
                        return NetworkService.ethernetSharingError;
                    if (NetworkService.ethernetSharingEnabled)
                        return NetworkService.ethernetSharingUseVPN
                            ? "Трафик ПК идёт через Regalia; при обрыве VPN прямой выход блокируется."
                            : "На другом компьютере оставьте IPv4 в режиме «Автоматически (DHCP)».";
                    if (!NetworkService.wifiConnected)
                        return "Сначала подключитесь к Wi‑Fi.";
                    if (root.selectedAdapter === null)
                        return NetworkService.ethernetDevices.length > 1 ? "Выберите Ethernet-адаптер." : "Ethernet-адаптер не найден.";
                    if (root.selectedAdapter.carrier !== true)
                        return "Подключите Ethernet-кабель к другому компьютеру.";
                    return "Готово к включению. Обычные настройки Ethernet останутся без изменений.";
                }
                font.pixelSize: Theme.fontSizeSmall
                color: NetworkService.ethernetSharingError ? Theme.error : Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }
}

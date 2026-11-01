pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root

    width: parent?.width ?? 400
    spacing: Theme.spacingS
    property string expandedDeviceMac: ""
    property string expandedSessionId: ""
    property string confirmingDelete: ""
    readonly property var analytics: NetworkService.hotspotAnalytics ?? ({ enabled: false, devices: [] })

    function formatBytes(value) {
        let size = Math.max(0, Number(value) || 0);
        const units = ["Б", "КиБ", "МиБ", "ГиБ"];
        let index = 0;
        while (size >= 1024 && index < units.length - 1) {
            size /= 1024;
            index++;
        }
        return (index === 0 ? Math.round(size) : size.toFixed(size < 10 ? 1 : 0)) + " " + units[index];
    }

    function formatDuration(value) {
        const seconds = Math.max(0, Number(value) || 0);
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.max(seconds > 0 ? 1 : 0, Math.floor((seconds % 3600) / 60));
        return hours > 0 ? "%1 ч %2 мин".arg(hours).arg(minutes) : "%1 мин".arg(minutes);
    }

    function formatDate(value) {
        if (!value)
            return "—";
        return Qt.formatDateTime(new Date(Number(value)), "dd.MM.yyyy  HH:mm");
    }

    function deviceTitle(device) {
        return device.name || device.autoName || (device.vendor ? "Устройство " + device.vendor : "Неизвестное устройство");
    }

    function confirmDelete(key, action) {
        if (confirmingDelete === key) {
            confirmingDelete = "";
            confirmReset.stop();
            action();
            return;
        }
        confirmingDelete = key;
        confirmReset.restart();
    }

    Component.onCompleted: NetworkService.refreshHotspotAnalytics()

    Timer {
        interval: 5000
        repeat: true
        running: root.visible && root.analytics.enabled
        onTriggered: NetworkService.refreshHotspotAnalytics()
    }

    Timer {
        id: confirmReset
        interval: 4000
        onTriggered: root.confirmingDelete = ""
    }

    Rectangle {
        width: parent.width
        height: analyticsHeader.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceVariant

        Column {
            id: analyticsHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            KaskadToggle {
                width: parent.width
                text: "Сохранять аналитику устройств"
                checked: root.analytics.enabled === true
                onToggled: checked => NetworkService.setHotspotAnalyticsEnabled(checked)
            }

            StyledText {
                width: parent.width
                text: root.analytics.enabled
                    ? "Сохраняются домены, количество обращений, трафик и оценка активности по каждому подключению. Содержимое страниц, сообщения и пароли не читаются."
                    : "История не сохраняется. После включения будут учитываться только новые обращения."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                visible: root.analytics.enabled
                text: "Автоочистка: %1 дней • до %2 подключений на устройство • до %3 доменов на подключение • занято %4"
                    .arg(root.analytics.retentionDays || 30)
                    .arg(root.analytics.maxSessionsPerDevice || 60)
                    .arg(root.analytics.maxDomainsPerSession || 200)
                    .arg(root.formatBytes(root.analytics.storageBytes))
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                visible: root.analytics.enabled
                text: "Важно: время около домена является оценкой по DNS-активности. Private DNS, DoH и VPN могут скрыть домены."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
                wrapMode: Text.WordWrap
            }

            KaskadButton {
                text: root.confirmingDelete === "all" ? "Нажмите ещё раз" : "Удалить всю историю"
                iconName: "delete_sweep"
                buttonHeight: 32
                visible: (root.analytics.devices ?? []).length > 0
                backgroundColor: Theme.error
                textColor: Theme.surface
                onClicked: root.confirmDelete("all", () => {
                    root.expandedDeviceMac = "";
                    root.expandedSessionId = "";
                    NetworkService.clearAllHotspotAnalytics();
                })
            }
        }
    }

    StyledText {
        width: parent.width
        visible: root.analytics.enabled && (root.analytics.devices ?? []).length === 0
        text: "История пока пуста. Она появится после подключения устройства и сетевой активности."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.analytics.enabled ? (root.analytics.devices ?? []) : []

        delegate: Rectangle {
            required property var modelData
            width: root.width
            height: deviceContent.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceVariant

            Column {
                id: deviceContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width
                    text: root.deviceTitle(modelData)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: {
                        const details = [modelData.mac];
                        if (modelData.randomizedMAC)
                            details.push("случайный MAC");
                        else if (modelData.vendor)
                            details.push(modelData.vendor);
                        details.push("последний раз " + root.formatDate(modelData.lastSeen));
                        return details.join(" • ");
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: "%1 подключений • %2 DNS-запросов • около %3 активности\n↓ %4  ↑ %5"
                        .arg(modelData.sessionsCount)
                        .arg(modelData.queries)
                        .arg(root.formatDuration(modelData.estimatedActiveSeconds))
                        .arg(root.formatBytes(modelData.txBytes))
                        .arg(root.formatBytes(modelData.rxBytes))
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    KaskadButton {
                        text: root.expandedDeviceMac === modelData.mac ? "Скрыть подключения" : "Подключения"
                        iconName: root.expandedDeviceMac === modelData.mac ? "expand_less" : "expand_more"
                        buttonHeight: 32
                        backgroundColor: Theme.surface
                        textColor: Theme.surfaceText
                        onClicked: {
                            if (root.expandedDeviceMac === modelData.mac) {
                                root.expandedDeviceMac = "";
                                root.expandedSessionId = "";
                            } else {
                                root.expandedDeviceMac = modelData.mac;
                                root.expandedSessionId = "";
                            }
                        }
                    }

                    KaskadButton {
                        text: root.confirmingDelete === "device:" + modelData.mac ? "Нажмите ещё раз" : "Удалить историю устройства"
                        iconName: "delete"
                        buttonHeight: 32
                        backgroundColor: Theme.error
                        textColor: Theme.surface
                        onClicked: root.confirmDelete("device:" + modelData.mac, () => {
                            if (root.expandedDeviceMac === modelData.mac) {
                                root.expandedDeviceMac = "";
                                root.expandedSessionId = "";
                            }
                            NetworkService.clearHotspotAnalyticsDevice(modelData.mac);
                        })
                    }
                }

                Repeater {
                    model: root.expandedDeviceMac === modelData.mac ? (modelData.sessions ?? []) : []

                    delegate: Rectangle {
                        required property var modelData
                        width: deviceContent.width
                        height: sessionContent.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surface

                        Column {
                            id: sessionContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: modelData.endedAt
                                    ? "%1 — %2".arg(root.formatDate(modelData.startedAt)).arg(root.formatDate(modelData.endedAt))
                                    : "%1 — сейчас".arg(root.formatDate(modelData.startedAt))
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: modelData.endedAt ? Theme.surfaceText : Theme.primary
                                wrapMode: Text.WordWrap
                            }

                            StyledText {
                                width: parent.width
                                text: "%1 DNS-запросов • около %2 активности • %3 доменов\n↓ %4  ↑ %5"
                                    .arg(modelData.queries)
                                    .arg(root.formatDuration(modelData.estimatedActiveSeconds))
                                    .arg((modelData.domains ?? []).length)
                                    .arg(root.formatBytes(modelData.txBytes))
                                    .arg(root.formatBytes(modelData.rxBytes))
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }

                            Flow {
                                width: parent.width
                                spacing: Theme.spacingS

                                KaskadButton {
                                    text: root.expandedSessionId === modelData.id ? "Скрыть домены" : "Домены"
                                    iconName: root.expandedSessionId === modelData.id ? "expand_less" : "language"
                                    buttonHeight: 30
                                    enabled: (modelData.domains ?? []).length > 0
                                    backgroundColor: Theme.surfaceVariant
                                    textColor: Theme.surfaceText
                                    onClicked: root.expandedSessionId = root.expandedSessionId === modelData.id ? "" : modelData.id
                                }

                                KaskadButton {
                                    text: root.confirmingDelete === "session:" + modelData.id
                                        ? "Нажмите ещё раз"
                                        : (modelData.endedAt ? "Удалить подключение" : "Очистить текущее")
                                    iconName: "delete"
                                    buttonHeight: 30
                                    backgroundColor: Theme.error
                                    textColor: Theme.surface
                                    onClicked: root.confirmDelete("session:" + modelData.id, () => {
                                        root.expandedSessionId = "";
                                        if (modelData.endedAt)
                                            NetworkService.deleteHotspotAnalyticsSession(modelData.mac, modelData.id);
                                        else
                                            NetworkService.clearCurrentHotspotAnalytics(modelData.mac);
                                    })
                                }
                            }

                            Repeater {
                                model: root.expandedSessionId === modelData.id ? (modelData.domains ?? []) : []

                                delegate: Rectangle {
                                    required property var modelData
                                    width: sessionContent.width
                                    height: domainContent.implicitHeight + Theme.spacingS * 2
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceVariant

                                    Column {
                                        id: domainContent
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: Theme.spacingS
                                        spacing: 2

                                        StyledText {
                                            width: parent.width
                                            text: modelData.domain
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: "%1 обращений • около %2 • %3 — %4"
                                                .arg(modelData.queries)
                                                .arg(root.formatDuration(modelData.estimatedActiveSeconds))
                                                .arg(root.formatDate(modelData.firstSeen))
                                                .arg(root.formatDate(modelData.lastSeen))
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

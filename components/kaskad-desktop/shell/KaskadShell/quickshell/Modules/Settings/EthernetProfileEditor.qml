pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.Widgets

SettingsCard {
    id: editor

    property string profileUuid: ""
    property string macMode: "hardware"
    property string customMac: ""
    property string routeMode: "auto"
    property string gateway: ""
    property string metric: "100"
    property bool initialized: false
    readonly property bool profileSupported: KaskadService.isConnected
        && KaskadService.apiVersion >= 32
        && NetworkService.backend === "networkmanager"
    property var wiredProfile: null
    property bool wiredProfileBusy: false
    property string wiredProfileError: ""
    property string wiredCheckpointToken: ""
    property int wiredRollbackRemaining: 0

    signal closeRequested

    title: editor.wiredProfile?.name ? "Настройка: " + editor.wiredProfile.name : "Настройка проводного подключения"
    iconName: "settings_ethernet"
    width: parent?.width ?? 0
    visible: profileUuid.length > 0

    function macModeLabel(value) {
        switch (value) {
        case "custom": return "Пользовательский MAC";
        case "random": return "Случайный при подключении";
        case "stable": return "Стабильный случайный";
        default: return "Аппаратный MAC";
        }
    }

    function macModeValue(label) {
        switch (label) {
        case "Пользовательский MAC": return "custom";
        case "Случайный при подключении": return "random";
        case "Стабильный случайный": return "stable";
        default: return "hardware";
        }
    }

    function routeModeLabel(value) {
        return value === "manual" ? "Пользовательский шлюз" : "Автоматически через DHCP";
    }

    function customMacError(value) {
        const normalized = value.trim();
        if (!/^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/.test(normalized))
            return "Формат MAC: 00:11:22:33:44:55";
        const octets = normalized.split(":").map(part => parseInt(part, 16));
        if (octets.every(value => value === 0) || octets.every(value => value === 255) || (octets[0] & 1) !== 0)
            return "Нулевой, broadcast и multicast MAC использовать нельзя";
        return "";
    }

    function gatewayValid(value) {
        const parts = value.trim().split(".");
        return parts.length === 4 && parts.every(part => /^\d{1,3}$/.test(part) && Number(part) >= 0 && Number(part) <= 255);
    }

    function metricValid(value) {
        const parsed = Number(value);
        return /^\d+$/.test(value.trim()) && Number.isInteger(parsed) && parsed >= 0 && parsed <= 4294967295;
    }

    function syncProfile() {
        const profile = editor.wiredProfile;
        if (!profile || profile.uuid !== profileUuid)
            return;
        macMode = profile.macMode || "hardware";
        customMac = profile.customMac || "";
        routeMode = profile.defaultRouteMode || "auto";
        gateway = profile.manualGateway || profile.suggestedGateway || "";
        metric = String(profile.routeMetric === undefined ? 100 : profile.routeMetric);
        initialized = true;
    }

    function load() {
        initialized = false;
        wiredProfile = null;
        if (profileUuid)
            fetchWiredProfile(profileUuid, profile => {
                if (profile)
                    syncProfile();
            });
    }

    function fetchWiredProfile(uuid, callback = null) {
        if (!profileSupported || !uuid || wiredProfileBusy)
            return;
        wiredProfileBusy = true;
        wiredProfileError = "";
        KaskadService.sendRequest("network.ethernet.profile.get", {uuid: uuid}, response => {
            wiredProfileBusy = false;
            if (response.error) {
                wiredProfileError = response.error;
                ToastService.showError("Не удалось открыть настройки Ethernet", response.error);
                if (callback)
                    callback(null);
                return;
            }
            wiredProfile = response.result || null;
            if (callback)
                callback(wiredProfile);
        });
    }

    function applyWiredProfile(options, callback = null) {
        if (!profileSupported || wiredProfileBusy)
            return;
        wiredProfileBusy = true;
        wiredProfileError = "";
        const request = {
            uuid: options.uuid || "",
            macMode: options.macMode || "hardware",
            customMac: options.customMac || "",
            defaultRouteMode: options.defaultRouteMode || "auto",
            gateway: options.gateway || "",
            metric: options.metric === undefined ? 100 : options.metric,
            rollbackSeconds: 60
        };
        KaskadService.sendRequest("network.ethernet.profile.apply", request, response => {
            wiredProfileBusy = false;
            if (response.error) {
                wiredProfileError = response.error;
                ToastService.showError("Настройки Ethernet не применены", response.error);
                if (callback)
                    callback(false);
                return;
            }
            const result = response.result || {};
            wiredProfile = result.profile || wiredProfile;
            wiredCheckpointToken = result.checkpointToken || "";
            if (wiredCheckpointToken) {
                wiredRollbackRemaining = result.rollbackSeconds || 60;
                wiredRollbackTimer.restart();
                ToastService.showInfo("Проверьте интернет и подтвердите настройки");
            } else {
                wiredRollbackRemaining = 0;
                wiredRollbackTimer.stop();
                ToastService.showInfo("Настройки Ethernet сохранены и применятся после подключения кабеля");
            }
            if (callback)
                callback(true);
        });
    }

    function confirmWiredProfile(callback = null) {
        if (!wiredCheckpointToken || wiredProfileBusy)
            return;
        wiredProfileBusy = true;
        const token = wiredCheckpointToken;
        KaskadService.sendRequest("network.ethernet.profile.confirm", {checkpointToken: token}, response => {
            wiredProfileBusy = false;
            if (response.error) {
                wiredProfileError = response.error;
                ToastService.showError("Не удалось подтвердить настройки", response.error);
                if (callback)
                    callback(false);
                return;
            }
            wiredCheckpointToken = "";
            wiredRollbackRemaining = 0;
            wiredRollbackTimer.stop();
            ToastService.showInfo("Настройки Ethernet сохранены");
            if (callback)
                callback(true);
        });
    }

    function rollbackWiredProfile(callback = null) {
        if (!wiredCheckpointToken || wiredProfileBusy)
            return;
        wiredProfileBusy = true;
        const token = wiredCheckpointToken;
        const uuid = wiredProfile?.uuid || "";
        KaskadService.sendRequest("network.ethernet.profile.rollback", {checkpointToken: token}, response => {
            wiredProfileBusy = false;
            wiredCheckpointToken = "";
            wiredRollbackRemaining = 0;
            wiredRollbackTimer.stop();
            if (response.error) {
                wiredProfileError = response.error;
                ToastService.showError("Не удалось восстановить настройки", response.error);
                if (callback)
                    callback(false);
                return;
            }
            ToastService.showInfo("Предыдущие настройки восстановлены");
            if (uuid)
                fetchWiredProfile(uuid, profile => {
                    if (profile)
                        syncProfile();
                });
            if (callback)
                callback(true);
        });
    }

    function applyChanges() {
        const parsedMetric = Number(metric);
        editor.applyWiredProfile({
            uuid: profileUuid,
            macMode: macMode,
            customMac: customMac.trim(),
            defaultRouteMode: routeMode,
            gateway: gateway.trim(),
            metric: Number.isInteger(parsedMetric) ? parsedMetric : -1
        }, success => {
            if (success)
                syncProfile();
        });
    }

    onProfileUuidChanged: load()

    Component.onCompleted: {
        if (profileUuid && !initialized && !wiredProfileBusy)
            load();
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM

        Timer {
            id: wiredRollbackTimer
            interval: 1000
            repeat: true
            onTriggered: {
                if (editor.wiredRollbackRemaining > 0)
                    editor.wiredRollbackRemaining--;
                if (editor.wiredRollbackRemaining <= 0) {
                    stop();
                    const uuid = editor.wiredProfile?.uuid || "";
                    editor.wiredCheckpointToken = "";
                    ToastService.showWarning("Настройки Ethernet автоматически отменены");
                    if (uuid)
                        editor.fetchWiredProfile(uuid, profile => {
                            if (profile)
                                editor.syncProfile();
                        });
                }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            Column {
                width: Math.max(0, parent.width - closeButton.width - Theme.spacingS)
                spacing: Theme.spacingXXS

                StyledText {
                    width: parent.width
                    text: "Обычный безопасный режим — аппаратный MAC и автоматический маршрут через DHCP. Расширенные значения действуют только для этого профиля."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            KaskadActionButton {
                id: closeButton
                iconName: "close"
                tooltipText: "Закрыть"
                onClicked: editor.closeRequested()
            }
        }

        Item {
            width: parent.width
            height: editor.wiredProfileBusy && !editor.initialized ? 44 : 0
            visible: height > 0
            KaskadSpinner { anchors.centerIn: parent; size: 22 }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingM
            visible: editor.initialized

            Rectangle {
                width: parent.width
                height: adapterInfo.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: adapterInfo
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        width: parent.width
                        text: "Текущее состояние"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        width: parent.width
                        text: "Интерфейс: " + (editor.wiredProfile?.interface || "—")
                            + "  •  Аппаратный MAC: " + (editor.wiredProfile?.permanentMac || "—")
                            + "  •  Текущий MAC: " + (editor.wiredProfile?.currentMac || "—")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WrapAnywhere
                    }
                    StyledText {
                        width: parent.width
                        text: {
                            const ipv4 = editor.wiredProfile?.ipv4 || {};
                            const addresses = (ipv4.ips || []).join(", ") || "адрес не получен";
                            return "IPv4/маска: " + addresses + "  •  Шлюз: " + (ipv4.gateway || "отсутствует") + "  •  DNS: " + (ipv4.dns || "отсутствует");
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        width: parent.width
                        text: "MAC профиля: " + editor.macModeLabel(editor.wiredProfile?.macMode || "hardware")
                            + (editor.wiredProfile?.customMac ? " (" + editor.wiredProfile.customMac + ")" : "")
                            + "  •  Маршрут по умолчанию: " + (editor.wiredProfile?.ipv4?.hasDefaultRoute ? "есть" : "отсутствует")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WrapAnywhere
                    }
                    StyledText {
                        width: parent.width
                        text: {
                            if (!editor.wiredProfile?.internetCheckCompleted)
                                return "Проверка интернета ещё не выполнялась";
                            const gatewayState = editor.wiredProfile.gatewayReachable ? "шлюз отвечает" : "шлюз не ответил на ping";
                            const internetState = editor.wiredProfile.internetReachable ? "интернет работает" : "интернет не подтверждён";
                            return gatewayState + "  •  " + internetState;
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        color: editor.wiredProfile?.internetReachable ? Theme.primary : Theme.surfaceVariantText
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: missingRouteWarning.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.warning, 0.14)
                border.width: 1
                border.color: Theme.warning
                visible: editor.wiredProfile?.missingDefaultRoute ?? false

                StyledText {
                    id: missingRouteWarning
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.spacingM
                    text: "Провайдер передал неполную таблицу маршрутов. Адрес получен, но маршрута в интернет нет. Можно вручную указать шлюз по умолчанию."
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }

            KaskadDropdown {
                width: parent.width
                text: "MAC-адрес подключения"
                description: editor.macMode === "hardware" ? "Рекомендуется для обычных сетей" : "Изменяется только в выбранном профиле"
                currentValue: editor.macModeLabel(editor.macMode)
                options: ["Аппаратный MAC", "Пользовательский MAC", "Случайный при подключении", "Стабильный случайный"]
                enabled: !editor.wiredProfileBusy && editor.wiredCheckpointToken.length === 0
                onValueChanged: value => editor.macMode = editor.macModeValue(value)
            }

            Column {
                width: parent.width
                spacing: Theme.spacingXS
                visible: editor.macMode === "custom"

                KaskadTextField {
                    width: parent.width
                    labelText: "MAC-адрес провайдера"
                    placeholderText: "00:11:22:33:44:55"
                    text: editor.customMac
                    leftIconName: "lan"
                    enabled: !editor.wiredProfileBusy && editor.wiredCheckpointToken.length === 0
                    onTextEdited: editor.customMac = text
                }
                StyledText {
                    width: parent.width
                    text: editor.customMacError(editor.customMac) || "Не подключайте старый роутер с тем же MAC одновременно к этому кабелю — два одинаковых адреса вызовут конфликт."
                    color: Theme.warning
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }

            StyledText {
                width: parent.width
                visible: editor.routeMode === "manual" && (!editor.gatewayValid(editor.gateway) || !editor.metricValid(editor.metric))
                text: !editor.gatewayValid(editor.gateway) ? "Укажите корректный IPv4-адрес шлюза" : "Метрика должна быть целым числом от 0 до 4294967295"
                color: Theme.warning
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            KaskadDropdown {
                width: parent.width
                text: "Маршрут по умолчанию"
                description: editor.routeMode === "auto" ? "Подходит для обычных роутеров и большинства провайдеров" : "Используется, когда DHCP не передал default route"
                currentValue: editor.routeModeLabel(editor.routeMode)
                options: ["Автоматически через DHCP", "Пользовательский шлюз"]
                enabled: !editor.wiredProfileBusy && editor.wiredCheckpointToken.length === 0
                onValueChanged: value => editor.routeMode = value === "Пользовательский шлюз" ? "manual" : "auto"
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS
                visible: editor.routeMode === "manual"

                KaskadTextField {
                    width: Math.max(0, parent.width * 0.67 - parent.spacing / 2)
                    labelText: "Шлюз IPv4"
                    placeholderText: editor.wiredProfile?.suggestedGateway || "192.168.1.1"
                    text: editor.gateway
                    leftIconName: "route"
                    enabled: !editor.wiredProfileBusy && editor.wiredCheckpointToken.length === 0
                    onTextEdited: editor.gateway = text
                }
                KaskadTextField {
                    width: Math.max(0, parent.width * 0.33 - parent.spacing / 2)
                    labelText: "Метрика"
                    placeholderText: "100"
                    text: editor.metric
                    enabled: !editor.wiredProfileBusy && editor.wiredCheckpointToken.length === 0
                    onTextEdited: editor.metric = text
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingXS
                visible: (editor.wiredProfile?.ipv4?.routes || []).length > 0

                StyledText {
                    text: "Полученные маршруты"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
                Repeater {
                    model: editor.wiredProfile?.ipv4?.routes || []
                    delegate: StyledText {
                        required property var modelData
                        width: parent.width
                        text: modelData.destination + "/" + modelData.prefix
                            + (modelData.nextHop ? " via " + modelData.nextHop : "")
                            + (modelData.metric ? "  metric " + modelData.metric : "")
                        font.family: SettingsData.monoFontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: rollbackContent.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.warning, 0.14)
                border.width: 1
                border.color: Theme.warning
                visible: editor.wiredCheckpointToken.length > 0

                Column {
                    id: rollbackContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        text: "Интернет работает? Подтвердите изменения. Иначе предыдущие настройки восстановятся через " + editor.wiredRollbackRemaining + " с."
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        spacing: Theme.spacingS
                        KaskadButton {
                            text: "Оставить настройки"
                            iconName: "check"
                            enabled: !editor.wiredProfileBusy
                            onClicked: editor.confirmWiredProfile()
                        }
                        KaskadButton {
                            text: "Вернуть предыдущие"
                            iconName: "undo"
                            backgroundColor: Theme.surfaceVariant
                            textColor: Theme.surfaceText
                            enabled: !editor.wiredProfileBusy
                            onClicked: editor.rollbackWiredProfile()
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                Item { width: Math.max(0, parent.width - resetButton.width - applyButton.width - parent.spacing * 2); height: 1 }
                KaskadButton {
                    id: resetButton
                    text: "Обычный режим"
                    iconName: "restart_alt"
                    backgroundColor: Theme.surfaceVariant
                    textColor: Theme.surfaceText
                    enabled: !editor.wiredProfileBusy && editor.wiredCheckpointToken.length === 0
                    onClicked: {
                        editor.macMode = "hardware";
                        editor.customMac = "";
                        editor.routeMode = "auto";
                        editor.gateway = "";
                        editor.metric = "100";
                    }
                }
                KaskadButton {
                    id: applyButton
                    text: editor.wiredProfileBusy ? "Применение…" : "Применить безопасно"
                    iconName: "save"
                    enabled: !editor.wiredProfileBusy && editor.wiredCheckpointToken.length === 0
                        && (editor.macMode !== "custom" || editor.customMacError(editor.customMac).length === 0)
                        && (editor.routeMode !== "manual" || (editor.gatewayValid(editor.gateway) && editor.metricValid(editor.metric)))
                    onClicked: editor.applyChanges()
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Modals.Common
import qs.Services
import qs.Widgets

SettingsCard {
    id: root

    width: parent.width
    title: "Раздать интернет"
    iconName: "wifi_tethering"
    settingKey: "networkHotspot"
    tags: ["hotspot", "sharing", "wifi", "раздача", "точка доступа"]

    property string ssid: NetworkService.hotspotSSID || ""
    property string password: ""
    property string device: NetworkService.hotspotDevice || ""
    property string band: NetworkService.hotspotBand || ""
    property bool compatibility: NetworkService.hotspotConfigured ? NetworkService.hotspotCompatibility : true
    property bool editing: false
    property bool advanced: false
    property bool showClients: false
    property bool passwordLoading: false
    property bool passwordResolved: true
    property int passwordRequestId: 0
    property int passwordEditRevision: 0
    readonly property bool showForm: !NetworkService.hotspotConfigured || editing
    readonly property bool busy: NetworkService.hotspotBusy || NetworkService.hotspotActivating
    readonly property bool canConfigure: ssid.trim().length > 0 && (password.length === 0 || password.length >= 8) && passwordResolved && !passwordLoading && !busy && !NetworkService.hotspotEnabled
    property var startConfirm: ConfirmModal {}

    function confirmThenStart(startFn) {
        if (!NetworkService.hotspotTargetWouldDisconnectWifi(device, compatibility ? "bg" : band)) {
            startFn();
            return;
        }
        startConfirm.showWithOptions({
            title: "Запустить точку доступа?",
            message: "Подключение к «%1» будет разорвано: этот адаптер не может одновременно принимать и раздавать Wi‑Fi.".arg(NetworkService.currentWifiSSID),
            confirmText: "Запустить",
            onConfirm: startFn
        });
    }

    function beginEditing() {
        ssid = NetworkService.hotspotSSID || "";
        device = NetworkService.hotspotDevice || "";
        band = NetworkService.hotspotBand || "";
        compatibility = NetworkService.hotspotCompatibility;
        password = "";
        editing = true;
        const requestId = ++passwordRequestId;
        const editRevision = passwordEditRevision;
        passwordLoading = NetworkService.hotspotSecured;
        passwordResolved = !NetworkService.hotspotSecured;
        if (!passwordLoading)
            return;
        NetworkService.getHotspotSecrets(response => {
            if (!editing || requestId !== passwordRequestId)
                return;
            passwordLoading = false;
            const stored = response.result?.password ?? response.password ?? "";
            if (!response.error && stored) {
                passwordResolved = true;
                if (editRevision === passwordEditRevision)
                    password = stored;
            } else {
                ToastService.showError("Не удалось загрузить пароль", "Введите пароль перед сохранением.");
            }
        });
    }

    function stopEditing() {
        passwordRequestId++;
        editing = false;
        password = "";
        passwordLoading = false;
        passwordResolved = true;
    }

    function save(start) {
        if (!canConfigure)
            return;
        const completed = response => {
            if (!response.error)
                stopEditing();
        };
        if (start) {
            confirmThenStart(() => NetworkService.configureAndStartHotspot(ssid.trim(), password, device, compatibility ? "bg" : band, compatibility, completed));
        } else {
            NetworkService.configureHotspot(ssid.trim(), password, device, compatibility ? "bg" : band, compatibility, completed);
        }
    }

    function toggleSharing() {
        if (NetworkService.hotspotEnabled) {
            NetworkService.stopHotspot();
        } else if (showForm) {
            save(true);
        } else {
            device = NetworkService.hotspotDevice;
            band = NetworkService.hotspotBand;
            compatibility = NetworkService.hotspotCompatibility;
            confirmThenStart(() => NetworkService.startHotspot());
        }
    }

    property Timer clientRefreshTimer: Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root.visible && NetworkService.hotspotEnabled
        onTriggered: NetworkService.refreshHotspotClients()
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            width: parent.width
            text: {
                if (!NetworkService.hotspotSupported)
                    return "Раздача недоступна в этой сетевой службе";
                if (!NetworkService.hotspotAvailable)
                    return "Нет Wi‑Fi‑адаптера с поддержкой точки доступа";
                if (root.busy)
                    return NetworkService.hotspotActivating ? "Запускаем точку доступа…" : "Применяем…";
                if (NetworkService.hotspotStatus === "degraded")
                    return "Раздача требует внимания";
                if (NetworkService.hotspotEnabled)
                    return "Точка доступа включена · " + NetworkService.hotspotSSID;
                return NetworkService.hotspotConfigured ? NetworkService.hotspotSSID + " · выключена" : "Создайте Wi‑Fi-сеть для других устройств";
            }
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
        }

        StyledText {
            width: parent.width
            visible: NetworkService.hotspotAvailable
            text: {
                const source = NetworkService.networkStatus === "ethernet" ? "Кабель" : NetworkService.networkStatus === "wifi" ? "Wi‑Fi · " + NetworkService.currentWifiSSID : NetworkService.primaryConnection;
                if (!source)
                    return "Нет источника интернета. Подключите кабель или Wi‑Fi.";
                return source + " → " + (NetworkService.hotspotSSID || root.ssid || "Точка доступа");
            }
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        StyledText {
            width: parent.width
            text: NetworkService.hotspotStatusMessage || NetworkService.hotspotError
            visible: text.length > 0
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.WordWrap
        }

        Column {
            width: parent.width
            spacing: Theme.spacingM
            visible: NetworkService.hotspotAvailable && root.showForm

            KaskadTextField {
                width: parent.width
                labelText: "Название сети"
                placeholderText: "Например, Мой компьютер"
                text: root.ssid
                onTextEdited: root.ssid = text
            }

            KaskadTextField {
                width: parent.width
                labelText: "Пароль"
                placeholderText: root.passwordLoading ? "Загрузка…" : "Не менее 8 символов или пусто для открытой сети"
                text: root.password
                showPasswordToggle: true
                echoMode: passwordVisible ? TextInput.Normal : TextInput.Password
                onTextEdited: {
                    root.password = text;
                    root.passwordEditRevision++;
                    root.passwordResolved = true;
                }
            }

            KaskadButton {
                text: "Дополнительно"
                iconName: root.advanced ? "expand_less" : "expand_more"
                backgroundColor: Theme.surfaceVariant
                textColor: Theme.surfaceText
                buttonHeight: 32
                onClicked: root.advanced = !root.advanced
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM
                visible: root.advanced

                KaskadToggle {
                    width: parent.width
                    text: "Совместимость · 2,4 ГГц"
                    checked: root.compatibility
                    onToggled: checked => root.compatibility = checked
                }

                KaskadDropdown {
                    width: parent.width
                    text: "Адаптер для раздачи"
                    currentValue: root.device || "Авто"
                    options: ["Авто"].concat((NetworkService.wifiDevices || []).filter(d => d.apCapable).map(d => d.name))
                    onValueChanged: value => root.device = value === "Авто" ? "" : value
                }

                KaskadDropdown {
                    width: parent.width
                    text: "Диапазон"
                    currentValue: root.compatibility || root.band === "bg" ? "2,4 ГГц" : root.band === "a" ? "5 ГГц" : "Авто"
                    options: ["Авто", "2,4 ГГц", "5 ГГц"]
                    enabled: !root.compatibility
                    onValueChanged: value => root.band = value === "2,4 ГГц" ? "bg" : value === "5 ГГц" ? "a" : ""
                }
            }
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingS
            visible: NetworkService.hotspotAvailable

            KaskadButton {
                text: NetworkService.hotspotEnabled ? "Выключить раздачу" : root.busy ? "Запуск…" : root.showForm ? "Создать и включить" : "Включить раздачу"
                iconName: NetworkService.hotspotEnabled ? "stop" : "wifi_tethering"
                enabled: !root.busy && (NetworkService.hotspotEnabled || !root.showForm || root.canConfigure)
                onClicked: root.toggleSharing()
            }

            KaskadButton {
                text: root.showForm ? "Сохранить" : "Изменить"
                iconName: root.showForm ? "save" : "edit"
                visible: !NetworkService.hotspotEnabled
                enabled: root.showForm ? root.canConfigure : !root.busy
                backgroundColor: Theme.surfaceVariant
                textColor: Theme.surfaceText
                onClicked: root.showForm ? root.save(false) : root.beginEditing()
            }

            KaskadButton {
                text: "Отмена"
                visible: root.editing
                enabled: !root.busy
                backgroundColor: Theme.surfaceVariant
                textColor: Theme.surfaceText
                onClicked: root.stopEditing()
            }
        }

        StyledText {
            width: parent.width
            text: "Чтобы изменить название или пароль, выключите раздачу."
            visible: NetworkService.hotspotEnabled
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        KaskadButton {
            text: "Устройства · %1".arg(NetworkService.hotspotClients.length)
            iconName: root.showClients ? "expand_less" : "expand_more"
            visible: NetworkService.hotspotEnabled || NetworkService.hotspotBlockedClients.length > 0
            backgroundColor: Theme.surfaceVariant
            textColor: Theme.surfaceText
            onClicked: root.showClients = !root.showClients
        }

        Loader {
            width: parent.width
            active: root.showClients && root.visible
            source: active ? Qt.resolvedUrl("HotspotClientsPanel.qml") : ""
        }
    }
}

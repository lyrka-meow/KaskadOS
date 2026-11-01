pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("KaskadNetworkService")

    property bool networkAvailable: false
    property string backend: ""

    property string networkStatus: "disconnected"
    property string primaryConnection: ""
    property string primaryConnectionType: ""
    property string primaryDevice: ""
    property string connectivity: "unknown"

    property string ethernetIP: ""
    property string ethernetInterface: ""
    property bool ethernetConnected: false
    property string ethernetConnectionUuid: ""
    property var ethernetDevices: []

    readonly property int ethernetSharingApiVersion: 35
    property bool backendEthernetSharingSupported: false
    property bool ethernetSharingConfigured: false
    property bool ethernetSharingEnabled: false
    property bool ethernetSharingActivating: false
    property string ethernetSharingDevice: ""
    property string ethernetSharingAddress: ""
    property bool ethernetSharingUseVPN: false
    property string ethernetSharingStatus: "stopped"
    property string ethernetSharingError: ""
    property bool ethernetSharingBusy: false
    readonly property bool ethernetSharingSupported: KaskadService.isConnected
        && networkAvailable
        && KaskadService.apiVersion >= ethernetSharingApiVersion
        && backendEthernetSharingSupported

    property var wiredConnections: []

    property string wifiIP: ""
    property string wifiInterface: ""
    property bool wifiConnected: false
    property bool wifiEnabled: true
    property string wifiConnectionUuid: ""
    property string wifiDevicePath: ""
    property string activeAccessPointPath: ""
    property var wifiDevices: []
    property string wifiDeviceOverride: SessionData.wifiDeviceOverride || ""
    property string connectingDevice: ""

    property string currentWifiSSID: ""
    property int wifiSignalStrength: 0
    property var wifiNetworks: []
    property var savedConnections: []
    property var ssidToConnectionName: ({})
    property var wifiSignalIcon: {
        if (isConnecting) {
            return "wifi";
        }
        if (!wifiConnected) {
            return "wifi_off";
        }
        if (wifiSignalStrength >= 50) {
            return "wifi";
        }
        if (wifiSignalStrength >= 25) {
            return "wifi_2_bar";
        }
        return "wifi_1_bar";
    }

    property string userPreference: "auto"
    property bool isConnecting: false
    property string connectingSSID: ""
    property string connectionError: ""

    property bool isScanning: false
    property bool autoScan: false

    property bool wifiAvailable: true
    property bool wifiToggling: false
    property bool changingPreference: false
    property string targetPreference: ""
    property string preferenceError: ""
    property bool preferenceMigrationAttempted: false
    property var savedWifiNetworks: []
    readonly property int savedWifiStateApiVersion: 26
    readonly property int hotspotApiVersion: 28
    readonly property int hotspotClientsApiVersion: 29
    readonly property int hotspotClientNamesApiVersion: 30
    readonly property int hotspotAnalyticsApiVersion: 31
    property bool backendHotspotSupported: false
    property bool backendHotspotAvailable: false
    property bool backendHotspotConfigured: false
    property bool backendHotspotEnabled: false
    property bool backendHotspotActivating: false
    property bool backendHotspotSecured: false
    property string backendHotspotSSID: ""
    property string backendHotspotDevice: ""
    property string backendHotspotBand: ""
    property bool backendHotspotCompatibility: false
    property string backendHotspotLastError: ""
    property string hotspotStatus: "stopped"
    property string hotspotStatusMessage: ""
    readonly property bool hotspotSupported: KaskadService.isConnected && networkAvailable && KaskadService.apiVersion >= hotspotApiVersion && backendHotspotSupported
    readonly property bool hotspotAvailable: hotspotSupported && backendHotspotAvailable
    readonly property bool hotspotConfigured: hotspotSupported && backendHotspotConfigured
    readonly property bool hotspotEnabled: hotspotSupported && backendHotspotEnabled
    readonly property bool hotspotActivating: hotspotSupported && backendHotspotActivating
    readonly property bool hotspotSecured: hotspotSupported && backendHotspotSecured
    readonly property bool hotspotWouldDisconnectWifi: hotspotSupported && !hotspotEnabled && !hotspotActivating && hotspotTargetWouldDisconnectWifi(backendHotspotDevice, backendHotspotBand)
    readonly property string hotspotSSID: hotspotSupported ? backendHotspotSSID : ""
    readonly property string hotspotDevice: hotspotSupported ? backendHotspotDevice : ""
    readonly property string hotspotBand: hotspotSupported ? backendHotspotBand : ""
    readonly property bool hotspotCompatibility: hotspotSupported && backendHotspotCompatibility
    property bool hotspotBusy: false
    property string hotspotError: ""
    property var hotspotClients: []
    property var hotspotBlockedClients: []
    property var hotspotClientSamples: ({})
    property double hotspotClientSampleTime: 0
    property bool hotspotClientsBusy: false
    property var hotspotAnalytics: ({ enabled: false, retentionDays: 30, maxSessionsPerDevice: 60, maxDomainsPerSession: 200, storageBytes: 0, devices: [] })
    property bool hotspotAnalyticsBusy: false
    property string connectionStatus: ""
    property string lastConnectionError: ""
    property bool passwordDialogShouldReopen: false
    property bool autoRefreshEnabled: false
    property string wifiPassword: ""
    property string forgetSSID: ""

    property string networkInfoSSID: ""
    property string networkInfoDetails: ""
    property bool networkInfoLoading: false

    property string networkWiredInfoUUID: ""
    property string networkWiredInfoDetails: ""
    property bool networkWiredInfoLoading: false

    property int refCount: 0
    property bool stateInitialized: false

    property string credentialsToken: ""
    property string credentialsSSID: ""
    property string credentialsSetting: ""
    property var credentialsFields: []
    property var credentialsHints: []
    property string credentialsReason: ""
    property bool credentialsRequested: false

    property string pendingConnectionSSID: ""
    property var pendingConnectionStartTime: 0
    property bool wasConnecting: false

    signal networksUpdated
    signal connectionChanged
    signal credentialsNeeded(string token, string ssid, string setting, var fields, var hints, string reason, string connType, string connName, var fieldsInfo)

    readonly property string socketPath: Quickshell.env("KASKAD_SOCKET")

    readonly property string effectiveWifiDevice: {
        if (!wifiDeviceOverride)
            return "";
        const deviceExists = wifiDevices.some(d => d.name === wifiDeviceOverride);
        return deviceExists ? wifiDeviceOverride : "";
    }

    Component.onCompleted: {
        if (socketPath && socketPath.length > 0) {
            checkKaskadCapabilities();
        }
    }

    Connections {
        target: KaskadService

        function onNetworkStateUpdate(data) {
            const networksCount = data.wifiNetworks?.length ?? "null";
            log.debug("Subscription update received, networks:", networksCount);
            updateState(data);
        }
    }

    Connections {
        target: KaskadService

        function onConnectionStateChanged() {
            if (KaskadService.isConnected) {
                checkKaskadCapabilities();
            } else {
                stateInitialized = false;
                changingPreference = false;
                targetPreference = "";
                preferenceMigrationAttempted = false;
            }
        }
    }

    Connections {
        target: KaskadService
        enabled: KaskadService.isConnected

        function onCapabilitiesChanged() {
            checkKaskadCapabilities();
        }

        function onCredentialsRequest(data) {
            handleCredentialsRequest(data);
        }
    }

    function checkKaskadCapabilities() {
        if (!KaskadService.isConnected) {
            return;
        }

        if (KaskadService.capabilities.length === 0) {
            return;
        }

        networkAvailable = KaskadService.capabilities.includes("network");

        if (networkAvailable && !stateInitialized) {
            stateInitialized = true;
            getState();
        }
    }

    function handleCredentialsRequest(data) {
        credentialsToken = data.token || "";
        credentialsSSID = data.ssid || "";
        credentialsSetting = data.setting || "802-11-wireless-security";
        credentialsFields = data.fields || ["psk"];
        credentialsHints = data.hints || [];
        credentialsReason = data.reason || "Credentials required";
        credentialsRequested = true;

        const connType = data.connType || "";
        const connName = data.name || data.connectionId || "";
        const fInfo = data.fieldsInfo || [];

        credentialsNeeded(credentialsToken, credentialsSSID, credentialsSetting, credentialsFields, credentialsHints, credentialsReason, connType, connName, fInfo);
    }

    function addRef() {
        refCount++;
        if (refCount === 1 && networkAvailable) {
            startAutoScan();
        }
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
        if (refCount === 0) {
            stopAutoScan();
        }
    }

    property bool initialStateFetched: false

    function getState() {
        if (!networkAvailable)
            return;
        KaskadService.sendRequest("network.getState", null, response => {
            if (response.result) {
                updateState(response.result);
                if (!initialStateFetched && response.result.wifiEnabled && (!response.result.wifiNetworks || response.result.wifiNetworks.length === 0)) {
                    initialStateFetched = true;
                    Qt.callLater(() => scanWifi());
                }
            }
        });
    }

    function updateState(state) {
        const previousConnecting = isConnecting;
        const previousConnectingSSID = connectingSSID;

        backend = state.backend || "";
        networkStatus = state.networkStatus || "disconnected";
        primaryConnection = state.primaryConnectionName || state.primaryConnection || "";
        primaryConnectionType = state.primaryConnectionType || "";
        primaryDevice = state.primaryDevice || "";
        connectivity = state.connectivity || "unknown";

        // Display only backend-confirmed state. The old settings key is a
        // migration source, never a second authority over the active route.
        if (["auto", "ethernet", "wifi"].includes(state.preference)) {
            const savedPreference = SettingsData.networkPreference;
            userPreference = state.preference;
            if (state.preferenceInitialized === false && !preferenceMigrationAttempted) {
                preferenceMigrationAttempted = true;
                if (["ethernet", "wifi"].includes(savedPreference))
                    Qt.callLater(() => setNetworkPreference(savedPreference));
            } else if (state.preferenceInitialized === true && !changingPreference
                       && savedPreference !== state.preference) {
                SettingsData.set("networkPreference", state.preference);
            }
        }

        ethernetIP = state.ethernetIP || "";
        ethernetInterface = state.ethernetDevice || "";
        ethernetConnected = state.ethernetConnected || false;
        ethernetConnectionUuid = state.ethernetConnectionUuid || "";
        ethernetDevices = state.ethernetDevices || [];

        if (KaskadService.apiVersion >= ethernetSharingApiVersion) {
            backendEthernetSharingSupported = state.ethernetSharingSupported === true;
            ethernetSharingConfigured = state.ethernetSharingConfigured === true;
            ethernetSharingEnabled = state.ethernetSharingEnabled === true;
            ethernetSharingActivating = state.ethernetSharingActivating === true;
            ethernetSharingDevice = state.ethernetSharingDevice || "";
            ethernetSharingAddress = state.ethernetSharingAddress || "";
            ethernetSharingUseVPN = state.ethernetSharingUseVPN === true;
            ethernetSharingStatus = state.ethernetSharingStatus || (ethernetSharingEnabled ? "active" : "stopped");
            ethernetSharingError = state.ethernetSharingLastError || "";
        } else {
            backendEthernetSharingSupported = false;
            ethernetSharingConfigured = false;
            ethernetSharingEnabled = false;
            ethernetSharingActivating = false;
            ethernetSharingDevice = "";
            ethernetSharingAddress = "";
            ethernetSharingUseVPN = false;
            ethernetSharingStatus = "stopped";
            ethernetSharingError = "";
        }

        wiredConnections = state.wiredConnections || [];

        wifiIP = state.wifiIP || "";
        wifiInterface = state.wifiDevice || "";
        wifiConnected = state.wifiConnected || false;
        wifiEnabled = state.wifiEnabled !== undefined ? state.wifiEnabled : true;
        wifiConnectionUuid = state.wifiConnectionUuid || "";
        wifiDevicePath = state.wifiDevicePath || "";
        activeAccessPointPath = state.activeAccessPointPath || "";
        wifiDevices = state.wifiDevices || [];
        connectingDevice = state.connectingDevice || "";

        if (KaskadService.apiVersion >= hotspotApiVersion) {
            const supportsHotspot = state.hotspotSupported === true;
            const wasHotspotEnabled = backendHotspotEnabled;
            const wasHotspotActivating = backendHotspotActivating;
            backendHotspotSupported = supportsHotspot;
            backendHotspotAvailable = state.hotspotAvailable === true;
            backendHotspotConfigured = state.hotspotConfigured === true;
            backendHotspotEnabled = state.hotspotEnabled === true;
            backendHotspotActivating = state.hotspotActivating === true;
            backendHotspotSecured = state.hotspotSecured === true;
            backendHotspotSSID = state.hotspotSSID || "";
            backendHotspotDevice = state.hotspotDevice || "";
            backendHotspotBand = state.hotspotBand || "";
            backendHotspotCompatibility = state.hotspotCompatibility === true;
            backendHotspotLastError = state.hotspotLastError || "";
            hotspotStatus = state.hotspotStatus || (backendHotspotEnabled ? "active" : backendHotspotActivating ? "starting" : "stopped");
            hotspotStatusMessage = state.hotspotStatusMessage || "";
            if (backendHotspotLastError)
                hotspotError = hotspotErrorMessage(backendHotspotLastError);
            else if (backendHotspotEnabled && hotspotStatus === "active")
                hotspotError = "";
            if (!backendHotspotEnabled)
                hotspotClients = [];

            // Activation is asynchronous: only toast outcomes of starts we watched
            // begin, so restoring state after a shell restart stays silent.
            const watchedStart = wasHotspotActivating || hotspotBusy;
            if (watchedStart && !wasHotspotEnabled && backendHotspotEnabled) {
                ToastService.showInfo(I18n.tr("Hotspot started", "hotspot start success message"));
            } else if (wasHotspotActivating && !backendHotspotActivating && !backendHotspotEnabled && backendHotspotLastError) {
                hotspotError = backendHotspotLastError;
                ToastService.showError(I18n.tr("Failed to start hotspot", "hotspot start error title"), hotspotErrorMessage(backendHotspotLastError));
            }
        } else {
            backendHotspotSupported = false;
            backendHotspotAvailable = false;
            backendHotspotConfigured = false;
            backendHotspotEnabled = false;
            backendHotspotActivating = false;
            backendHotspotSecured = false;
            backendHotspotSSID = "";
            backendHotspotDevice = "";
            backendHotspotBand = "";
            backendHotspotCompatibility = false;
            backendHotspotLastError = "";
            hotspotStatus = "stopped";
            hotspotStatusMessage = "";
        }

        currentWifiSSID = state.wifiSSID || "";
        wifiSignalStrength = state.wifiSignal || 0;

        if (state.wifiNetworks) {
            wifiNetworks = state.wifiNetworks;
        }

        if (state.wifiNetworks || state.savedWifiNetworks) {
            const hasSavedWifiState = KaskadService.apiVersion >= savedWifiStateApiVersion && Array.isArray(state.savedWifiNetworks);
            const sourceSavedNetworks = hasSavedWifiState ? state.savedWifiNetworks : (state.wifiNetworks || []).filter(network => network.saved);
            const saved = [];
            const mapping = {};
            for (const network of sourceSavedNetworks) {
                const normalized = Object.assign({}, network, {
                    saved: true,
                    outOfRange: hasSavedWifiState ? network.outOfRange === true : false
                });
                saved.push(normalized);
                if (network?.ssid)
                    mapping[network.ssid] = network.ssid;
            }
            savedConnections = saved;
            savedWifiNetworks = saved;
            ssidToConnectionName = mapping;

            networksUpdated();
        }

        isConnecting = state.isConnecting || false;
        connectingSSID = state.connectingSSID || "";
        connectionError = state.lastError || "";
        lastConnectionError = state.lastError || "";

        if (pendingConnectionSSID) {
            if (wifiConnected && currentWifiSSID === pendingConnectionSSID && wifiIP) {
                const elapsed = Date.now() - pendingConnectionStartTime;
                log.info("Successfully connected to", pendingConnectionSSID, "in", elapsed, "ms");
                ToastService.showInfo(I18n.tr("Connected to %1").arg(pendingConnectionSSID));

                pendingConnectionSSID = "";
                connectionStatus = "connected";
            } else if (previousConnecting && !isConnecting && !wifiConnected) {
                const isCancellationError = connectionError === "user-canceled";
                const isBadCredentials = connectionError === "bad-credentials";

                if (isCancellationError) {
                    connectionStatus = "cancelled";
                    pendingConnectionSSID = "";
                } else if (isBadCredentials) {
                    connectionStatus = "invalid_password";
                    pendingConnectionSSID = "";
                } else {
                    if (connectionError) {
                        ToastService.showError(I18n.tr("Failed to connect to %1").arg(pendingConnectionSSID));
                    }
                    connectionStatus = "failed";
                    pendingConnectionSSID = "";
                }
            }
        }

        wasConnecting = isConnecting;

        connectionChanged();
    }

    function connectToSpecificWiredConfig(uuid) {
        if (!networkAvailable || isConnecting)
            return;
        isConnecting = true;
        connectionError = "";
        connectionStatus = "connecting";

        const params = {
            uuid: uuid
        };

        KaskadService.sendRequest("network.ethernet.connect.config", params, response => {
            if (response.error) {
                connectionError = response.error;
                lastConnectionError = response.error;
                connectionStatus = "failed";
                ToastService.showError(I18n.tr("Failed to activate configuration"), response.error);
            } else {
                connectionError = "";
                connectionStatus = "connected";
                ToastService.showInfo(I18n.tr("Configuration activated"));
            }

            isConnecting = false;
        });
    }

    function scanWifi() {
        if (!networkAvailable || isScanning || !wifiEnabled)
            return;
        isScanning = true;
        const params = effectiveWifiDevice ? {
            device: effectiveWifiDevice
        } : null;
        KaskadService.sendRequest("network.wifi.scan", params, response => {
            isScanning = false;
            if (response.error) {
                log.warn("WiFi scan failed:", response.error);
            } else {
                Qt.callLater(() => getState());
            }
        });
    }

    function scanWifiNetworks() {
        scanWifi();
    }

    function connectToWifi(ssid, password = "", username = "", anonymousIdentity = "", domainSuffixMatch = "", hidden = false) {
        if (!networkAvailable || isConnecting)
            return;
        pendingConnectionSSID = ssid;
        pendingConnectionStartTime = Date.now();
        isConnecting = true;
        connectingSSID = ssid;
        connectionError = "";
        connectionStatus = "connecting";
        credentialsRequested = false;

        const params = {
            ssid: ssid
        };
        if (effectiveWifiDevice)
            params.device = effectiveWifiDevice;
        if (hidden)
            params.hidden = true;

        if (KaskadService.apiVersion >= 7) {
            if (password || username) {
                params.password = password;
                if (username)
                    params.username = username;
                if (anonymousIdentity)
                    params.anonymousIdentity = anonymousIdentity;
                if (domainSuffixMatch)
                    params.domainSuffixMatch = domainSuffixMatch;
                params.interactive = false;
            } else {
                params.interactive = true;
            }
        } else {
            if (password)
                params.password = password;
            if (username)
                params.username = username;
            if (anonymousIdentity)
                params.anonymousIdentity = anonymousIdentity;
            if (domainSuffixMatch)
                params.domainSuffixMatch = domainSuffixMatch;
        }

        KaskadService.sendRequest("network.wifi.connect", params, response => {
            if (response.error) {
                if (connectionStatus === "cancelled")
                    return;
                connectionError = response.error;
                lastConnectionError = response.error;
                pendingConnectionSSID = "";
                isConnecting = false;
                connectingSSID = "";
                connectionStatus = "failed";
                ToastService.showError(I18n.tr("Failed to start connection to %1").arg(ssid));
            }
        });
    }

    function disconnectWifi() {
        if (!networkAvailable || !wifiInterface)
            return;
        const params = effectiveWifiDevice ? {
            device: effectiveWifiDevice
        } : null;
        KaskadService.sendRequest("network.wifi.disconnect", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to disconnect WiFi"), response.error);
            } else {
                ToastService.showInfo(I18n.tr("Disconnected from WiFi"));
                currentWifiSSID = "";
                connectionStatus = "";
            }
        });
    }

    function submitCredentials(token, secrets, save) {
        log.debug("submitCredentials: networkAvailable=" + networkAvailable + " apiVersion=" + KaskadService.apiVersion);

        if (!networkAvailable || KaskadService.apiVersion < 7) {
            log.warn("submitCredentials: Aborting - networkAvailable=" + networkAvailable + " apiVersion=" + KaskadService.apiVersion);
            return;
        }

        const params = {
            token: token,
            secrets: secrets,
            save: save || false
        };

        credentialsRequested = false;

        if (credentialsReason === "wrong-password" && credentialsSSID && credentialsSetting === "802-11-wireless-security") {
            pendingConnectionSSID = credentialsSSID;
            pendingConnectionStartTime = Date.now();
            connectionStatus = "connecting";
        }

        KaskadService.sendRequest("network.credentials.submit", params, response => {
            if (response.error) {
                log.warn("Failed to submit credentials:", response.error);
            }
        });
    }

    function cancelCredentials(token) {
        if (!networkAvailable || KaskadService.apiVersion < 7)
            return;
        const params = {
            token: token
        };

        credentialsRequested = false;
        pendingConnectionSSID = "";
        connectionStatus = "cancelled";

        KaskadService.sendRequest("network.credentials.cancel", params, response => {
            if (response.error) {
                log.warn("Failed to cancel credentials:", response.error);
            }
        });
    }

    function forgetWifiNetwork(ssid) {
        if (!networkAvailable)
            return;
        forgetSSID = ssid;
        KaskadService.sendRequest("network.wifi.forget", {
            ssid: ssid
        }, response => {
            if (response.error) {
                log.warn("Failed to forget network:", response.error);
            } else {
                ToastService.showInfo(I18n.tr("Forgot network %1").arg(ssid));

                savedConnections = savedConnections.filter(s => s.ssid !== ssid);
                savedWifiNetworks = savedWifiNetworks.filter(s => s.ssid !== ssid);

                const updated = [...wifiNetworks];
                for (const network of updated) {
                    if (network.ssid === ssid) {
                        network.saved = false;
                        if (network.connected) {
                            network.connected = false;
                            currentWifiSSID = "";
                        }
                    }
                }
                wifiNetworks = updated;
                networksUpdated();
                Qt.callLater(() => refreshSavedWifiNetworks());
            }
            forgetSSID = "";
        });
    }

    function toggleWifiRadio() {
        if (!networkAvailable || wifiToggling)
            return;
        wifiToggling = true;
        KaskadService.sendRequest("network.wifi.toggle", null, response => {
            wifiToggling = false;

            if (response.error) {
                log.warn("Failed to toggle WiFi:", response.error);
            } else if (response.result) {
                wifiEnabled = response.result.enabled;
                ToastService.showInfo(wifiEnabled ? I18n.tr("WiFi enabled") : I18n.tr("WiFi disabled"));
            }
        });
    }

    function enableWifiDevice() {
        if (!networkAvailable)
            return;
        KaskadService.sendRequest("network.wifi.enable", null, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to enable WiFi"), response.error);
            } else {
                ToastService.showInfo(I18n.tr("WiFi enabled"));
            }
        });
    }

    function setNetworkPreference(preference) {
        if (!networkAvailable || changingPreference || !["auto", "ethernet", "wifi"].includes(preference))
            return;
        changingPreference = true;
        targetPreference = preference;
        preferenceError = "";

        KaskadService.sendRequest("network.preference.set", {
            preference: preference
        }, response => {
            changingPreference = false;
            targetPreference = "";

            if (response.error) {
                log.warn("Failed to set network preference:", response.error);
                preferenceError = response.error.message || String(response.error);
                ToastService.showError("Не удалось сменить источник интернета", preferenceError);
            } else {
                userPreference = preference;
                SettingsData.set("networkPreference", preference);
            }
            getState();
        });
    }

    function setConnectionPriority(type) {
        if (type === "wifi") {
            setNetworkPreference("wifi");
        } else if (type === "ethernet") {
            setNetworkPreference("ethernet");
        }
    }

    function connectToWifiAndSetPreference(ssid, password, username = "", anonymousIdentity = "", domainSuffixMatch = "", hidden = false) {
        connectToWifi(ssid, password, username, anonymousIdentity, domainSuffixMatch, hidden);
        setNetworkPreference("wifi");
    }

    function toggleNetworkConnection(type) {
        if (!networkAvailable)
            return;
        if (type === "ethernet") {
            if (ethernetConnected) {
                KaskadService.sendRequest("network.ethernet.disconnect", null, null);
            } else {
                KaskadService.sendRequest("network.ethernet.connect", null, null);
            }
        }
    }

    function disconnectEthernetDevice(deviceName) {
        if (!networkAvailable)
            return;
        KaskadService.sendRequest("network.ethernet.disconnect", {
            device: deviceName
        }, null);
    }

    function setEthernetSharing(enabled, deviceName = "", useVPN = false, callback = null) {
        if (!ethernetSharingSupported || ethernetSharingBusy)
            return false;

        ethernetSharingBusy = true;
        ethernetSharingError = "";
        KaskadService.sendRequest("network.ethernet.sharing.set", {
            enabled: enabled,
            device: deviceName || "",
            useVPN: useVPN === true
        }, response => {
            ethernetSharingBusy = false;
            if (response.error) {
                ethernetSharingError = response.error.message || String(response.error);
                ToastService.showError(enabled ? "Не удалось включить раздачу" : "Не удалось выключить раздачу", ethernetSharingError);
            } else {
                ToastService.showInfo(enabled ? "Интернет раздаётся через Ethernet" : "Раздача через Ethernet выключена");
                Qt.callLater(() => getState());
            }
            if (callback)
                callback(response);
        });
        return true;
    }

    function startAutoScan() {
        autoScan = true;
        autoRefreshEnabled = true;
        if (networkAvailable && wifiEnabled) {
            scanWifi();
        }
    }

    function stopAutoScan() {
        autoScan = false;
        autoRefreshEnabled = false;
    }

    function fetchWiredNetworkInfo(uuid) {
        if (!networkAvailable)
            return;
        networkWiredInfoUUID = uuid;
        networkWiredInfoLoading = true;
        networkWiredInfoDetails = "Loading network information...";

        KaskadService.sendRequest("network.ethernet.info", {
            uuid: uuid
        }, response => {
            networkWiredInfoLoading = false;

            if (response.error) {
                networkWiredInfoDetails = "Failed to fetch network information";
            } else if (response.result) {
                formatWiredNetworkInfo(response.result);
            }
        });
    }

    function formatWiredNetworkInfo(info) {
        let details = "";

        if (!info) {
            details = "Network information not found or network not available.";
        } else {
            details += "Interface: " + info.iface + "\\n";
            details += "Driver: " + info.driver + "\\n";
            details += "MAC Addr: " + info.hwAddr + "\\n";
            details += "Speed: " + info.speed + " Mb/s\\n\\n";

            details += "IPv4 information:\\n";

            for (const ip4 of info.IPv4s.ips) {
                details += "    IPv4 address: " + ip4 + "\\n";
            }
            details += "    Gateway: " + info.IPv4s.gateway + "\\n";
            details += "    DNS: " + info.IPv4s.dns + "\\n";

            if (info.IPv6s.ips) {
                details += "\\nIPv6 information:\\n";

                for (const ip6 of info.IPv6s.ips) {
                    details += "    IPv6 address: " + ip6 + "\\n";
                }
                if (info.IPv6s.gateway.length > 0) {
                    details += "    Gateway: " + info.IPv6s.gateway + "\\n";
                }
                if (info.IPv6s.dns.length > 0) {
                    details += "    DNS: " + info.IPv6s.dns + "\\n";
                }
            }
        }

        networkWiredInfoDetails = details;
    }

    function fetchNetworkInfo(ssid) {
        if (!networkAvailable)
            return;
        networkInfoSSID = ssid;
        networkInfoLoading = true;
        networkInfoDetails = "Loading network information...";

        KaskadService.sendRequest("network.info", {
            ssid: ssid
        }, response => {
            networkInfoLoading = false;

            if (response.error) {
                networkInfoDetails = "Failed to fetch network information";
            } else if (response.result) {
                formatNetworkInfo(response.result);
            }
        });
    }

    function formatNetworkInfo(info) {
        let details = "";

        if (!info || !info.bands || info.bands.length === 0) {
            details = "Network information not found or network not available.";
        } else {
            for (const band of info.bands) {
                const freqGHz = band.frequency / 1000;
                let bandName = "Unknown";
                if (band.frequency >= 2400 && band.frequency <= 2500) {
                    bandName = "2.4 GHz";
                } else if (band.frequency >= 5000 && band.frequency <= 6000) {
                    bandName = "5 GHz";
                } else if (band.frequency >= 6000) {
                    bandName = "6 GHz";
                }

                const statusPrefix = band.connected ? "● " : "  ";
                const statusSuffix = band.connected ? " (Connected)" : "";

                details += statusPrefix + bandName + statusSuffix + " - " + band.signal + "%\\n";
                details += "  Channel " + band.channel + " (" + freqGHz.toFixed(1) + " GHz) • " + band.rate + " Mbit/s\\n";
                details += "  BSSID: " + band.bssid + "\\n";
                details += "  Mode: " + band.mode + "\\n";
                details += "  Security: " + (band.secured ? "Secured" : "Open") + "\\n";
                if (band.saved) {
                    details += "  Status: Saved network\\n";
                }
                details += "\\n";
            }
        }

        networkInfoDetails = details;
    }

    function getNetworkInfo(ssid) {
        const network = wifiNetworks.find(n => n.ssid === ssid);
        if (!network) {
            return null;
        }

        return {
            "ssid": network.ssid,
            "signal": network.signal,
            "secured": network.secured,
            "saved": network.saved,
            "connected": network.connected,
            "bssid": network.bssid
        };
    }

    function getWiredNetworkInfo(uuid) {
        const network = wiredConnections.find(n => n.uuid === uuid);
        if (!network) {
            return null;
        }

        return {
            "uuid": uuid
        };
    }

    function refreshNetworkState() {
        if (networkAvailable) {
            getState();
        }
    }

    function setWifiDeviceOverride(deviceName) {
        SessionData.setWifiDeviceOverride(deviceName || "");
        if (networkAvailable && wifiEnabled) {
            scanWifi();
        }
    }

    function setWifiAutoconnect(ssid, autoconnect) {
        if (!networkAvailable || KaskadService.apiVersion <= 13)
            return;
        const params = {
            ssid: ssid,
            autoconnect: autoconnect
        };

        KaskadService.sendRequest("network.wifi.setAutoconnect", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to update autoconnect"), response.error);
            } else {
                ToastService.showInfo(autoconnect ? I18n.tr("Autoconnect enabled") : I18n.tr("Autoconnect disabled"));
                Qt.callLater(() => getState());
            }
        });
    }

    function configureHotspot(ssid, password = "", device = "", band = "", compatibility = false, callback = null) {
        if (!hotspotSupported || hotspotBusy)
            return false;

        const params = {
            ssid: ssid
        };
        if (password)
            params.password = password;
        if (device)
            params.device = device;
        if (band)
            params.band = band;
        params.compatibility = compatibility;

        hotspotBusy = true;
        hotspotError = "";

        KaskadService.sendRequest("network.hotspot.configure", params, response => {
            hotspotBusy = false;
            if (response.error) {
                hotspotError = response.error;
                ToastService.showError(I18n.tr("Failed to configure hotspot", "hotspot configuration error title"), response.error);
            } else {
                Qt.callLater(() => getState());
            }
            if (callback)
                callback(response);
        });

        return true;
    }

    function startHotspot(callback = null) {
        if (!hotspotAvailable || hotspotBusy)
            return false;

        hotspotBusy = true;
        hotspotError = "";

        KaskadService.sendRequest("network.hotspot.start", null, response => {
            hotspotBusy = false;
            if (response.error) {
                hotspotError = response.error;
                ToastService.showError(I18n.tr("Failed to start hotspot", "hotspot start error title"), response.error);
            } else {
                Qt.callLater(() => getState());
            }
            if (callback)
                callback(response);
        });

        return true;
    }

    function stopHotspot(callback = null) {
        if (!hotspotSupported || hotspotBusy)
            return false;

        hotspotBusy = true;
        hotspotError = "";

        KaskadService.sendRequest("network.hotspot.stop", null, response => {
            hotspotBusy = false;
            if (response.error) {
                hotspotError = response.error;
                ToastService.showError(I18n.tr("Failed to stop hotspot", "hotspot stop error title"), response.error);
            } else {
                Qt.callLater(() => getState());
            }
            if (callback)
                callback(response);
        });

        return true;
    }

    function configureAndStartHotspot(ssid, password = "", device = "", band = "", compatibility = false, callback = null) {
        return configureHotspot(ssid, password, device, band, compatibility, configureResponse => {
            if (configureResponse.error) {
                if (callback)
                    callback(configureResponse);
                return;
            }
            startHotspot(callback);
        });
    }

    function getHotspotSecrets(callback) {
        if (!hotspotSupported) {
            if (callback)
                callback({
                    error: "hotspot not supported"
                });
            return false;
        }

        KaskadService.sendRequest("network.hotspot.getSecrets", null, response => {
            if (callback)
                callback(response);
        });

        return true;
    }

    function refreshHotspotClients(callback = null) {
        if (!hotspotSupported || KaskadService.apiVersion < hotspotClientsApiVersion) {
            hotspotClients = [];
            if (callback) callback({ error: "hotspot client monitoring not supported" });
            return false;
        }
        if (hotspotClientsBusy)
            return false;
        hotspotClientsBusy = true;
        KaskadService.sendRequest("network.hotspot.clients", null, response => {
            hotspotClientsBusy = false;
            if (!response.error) {
                const result = response.result ?? response;
                const now = Date.now();
                const elapsed = hotspotClientSampleTime > 0 ? Math.max(0.2, (now - hotspotClientSampleTime) / 1000) : 0;
                const nextSamples = {};
                hotspotClients = (result.clients ?? []).map(client => {
                    const previous = hotspotClientSamples[client.mac];
                    const rxRate = elapsed > 0 && previous ? Math.max(0, (client.rxBytes - previous.rxBytes) / elapsed) : 0;
                    const txRate = elapsed > 0 && previous ? Math.max(0, (client.txBytes - previous.txBytes) / elapsed) : 0;
                    nextSamples[client.mac] = { rxBytes: client.rxBytes, txBytes: client.txBytes };
                    return Object.assign({}, client, { rxRate: rxRate, txRate: txRate });
                });
                hotspotBlockedClients = result.blocked ?? [];
                hotspotClientSamples = nextSamples;
                hotspotClientSampleTime = now;
            }
            if (callback) callback(response);
        });
        return true;
    }

    function disconnectHotspotClient(mac, callback = null) {
        KaskadService.sendRequest("network.hotspot.client.disconnect", { mac: mac }, response => {
            if (response.error)
                ToastService.showError("Не удалось отключить устройство", response.error);
            else
                Qt.callLater(() => refreshHotspotClients());
            if (callback) callback(response);
        });
    }

    function setHotspotClientBlocked(mac, blocked, callback = null) {
        const method = blocked ? "network.hotspot.client.block" : "network.hotspot.client.unblock";
        KaskadService.sendRequest(method, { mac: mac }, response => {
            if (response.error)
                ToastService.showError(blocked ? "Не удалось заблокировать устройство" : "Не удалось разблокировать устройство", response.error);
            else
                Qt.callLater(() => refreshHotspotClients());
            if (callback) callback(response);
        });
    }

    function setHotspotClientName(mac, name, callback = null) {
        if (KaskadService.apiVersion < hotspotClientNamesApiVersion) {
            const response = { error: "Имена устройств не поддерживаются установленной версией службы" };
            ToastService.showError("Не удалось сохранить имя устройства", response.error);
            if (callback) callback(response);
            return false;
        }
        KaskadService.sendRequest("network.hotspot.client.setName", { mac: mac, name: name }, response => {
            if (response.error)
                ToastService.showError("Не удалось сохранить имя устройства", response.error);
            else
                Qt.callLater(() => refreshHotspotClients());
            if (callback) callback(response);
        });
        return true;
    }

    function refreshHotspotAnalytics(callback = null) {
        if (KaskadService.apiVersion < hotspotAnalyticsApiVersion || hotspotAnalyticsBusy)
            return false;
        hotspotAnalyticsBusy = true;
        KaskadService.sendRequest("network.hotspot.analytics.get", null, response => {
            hotspotAnalyticsBusy = false;
            if (!response.error)
                hotspotAnalytics = response.result ?? response;
            if (callback) callback(response);
        });
        return true;
    }

    function setHotspotAnalyticsEnabled(enabled, callback = null) {
        KaskadService.sendRequest("network.hotspot.analytics.setEnabled", { enabled: enabled }, response => {
            if (response.error)
                ToastService.showError("Не удалось изменить сбор аналитики", response.error);
            else
                Qt.callLater(() => refreshHotspotAnalytics());
            if (callback) callback(response);
        });
    }

    function deleteHotspotAnalyticsSession(mac, sessionId, callback = null) {
        hotspotAnalyticsRequest("network.hotspot.analytics.deleteSession", { mac: mac, sessionId: sessionId }, callback);
    }

    function clearCurrentHotspotAnalytics(mac, callback = null) {
        hotspotAnalyticsRequest("network.hotspot.analytics.clearCurrent", { mac: mac }, callback);
    }

    function clearHotspotAnalyticsDevice(mac, callback = null) {
        hotspotAnalyticsRequest("network.hotspot.analytics.clearDevice", { mac: mac }, callback);
    }

    function clearAllHotspotAnalytics(callback = null) {
        hotspotAnalyticsRequest("network.hotspot.analytics.clearAll", {}, callback);
    }

    function hotspotAnalyticsRequest(method, params, callback) {
        KaskadService.sendRequest(method, params, response => {
            if (response.error)
                ToastService.showError("Не удалось очистить аналитику", response.error);
            else
                Qt.callLater(() => refreshHotspotAnalytics());
            if (callback) callback(response);
        });
    }

    function hotspotTargetWouldDisconnectWifi(device, band = "") {
        // The backend uses a second virtual interface when the selected radio
        // is already receiving Wi-Fi. It either starts concurrent sharing or
        // returns a capability error; it never silently drops the client link.
        return false;
    }

    function hotspotErrorMessage(code) {
        switch (code) {
        case "hotspot-ip-config-failed":
            return I18n.tr("IP sharing setup failed. Check that dnsmasq is installed.", "hotspot IP configuration failure message");
        case "hotspot-supplicant-failed":
            return I18n.tr("The WiFi adapter could not start access point mode.", "hotspot adapter failure message");
        default:
            return I18n.tr("Hotspot activation failed.", "generic hotspot activation failure message");
        }
    }

    function refreshSavedWifiNetworks() {
        if (!networkAvailable)
            return;

        getState();
    }
}

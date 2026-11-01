pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("NetworkService")

    property bool networkAvailable: activeService !== null
    property string backend: activeService?.backend ?? ""
    property string networkStatus: activeService?.networkStatus ?? "disconnected"
    property string primaryConnection: activeService?.primaryConnection ?? ""
    property string primaryConnectionType: activeService?.primaryConnectionType ?? ""
    property string primaryDevice: activeService?.primaryDevice ?? ""
    property string connectivity: activeService?.connectivity ?? "unknown"

    property string ethernetIP: activeService?.ethernetIP ?? ""
    property string ethernetInterface: activeService?.ethernetInterface ?? ""
    property bool ethernetConnected: activeService?.ethernetConnected ?? false
    property string ethernetConnectionUuid: activeService?.ethernetConnectionUuid ?? ""
    property var ethernetDevices: activeService?.ethernetDevices ?? []
    readonly property int ethernetSharingApiVersion: activeService?.ethernetSharingApiVersion ?? 35
    property bool ethernetSharingSupported: activeService?.ethernetSharingSupported ?? false
    property bool ethernetSharingConfigured: activeService?.ethernetSharingConfigured ?? false
    property bool ethernetSharingEnabled: activeService?.ethernetSharingEnabled ?? false
    property bool ethernetSharingActivating: activeService?.ethernetSharingActivating ?? false
    property string ethernetSharingDevice: activeService?.ethernetSharingDevice ?? ""
    property string ethernetSharingAddress: activeService?.ethernetSharingAddress ?? ""
    property string ethernetSharingStatus: activeService?.ethernetSharingStatus ?? "stopped"
    property string ethernetSharingError: activeService?.ethernetSharingError ?? ""
    property bool ethernetSharingBusy: activeService?.ethernetSharingBusy ?? false

    property var wiredConnections: activeService?.wiredConnections ?? []

    property string wifiIP: activeService?.wifiIP ?? ""
    property string wifiInterface: activeService?.wifiInterface ?? ""
    property bool wifiConnected: activeService?.wifiConnected ?? false
    property bool wifiEnabled: activeService?.wifiEnabled ?? true
    property string wifiConnectionUuid: activeService?.wifiConnectionUuid ?? ""
    property string wifiDevicePath: activeService?.wifiDevicePath ?? ""
    property string activeAccessPointPath: activeService?.activeAccessPointPath ?? ""
    property var wifiDevices: activeService?.wifiDevices ?? []
    property string wifiDeviceOverride: activeService?.wifiDeviceOverride ?? ""
    property string connectingDevice: activeService?.connectingDevice ?? ""

    property string currentWifiSSID: activeService?.currentWifiSSID ?? ""
    property int wifiSignalStrength: activeService?.wifiSignalStrength ?? 0
    property var wifiNetworks: activeService?.wifiNetworks ?? []
    property var savedConnections: activeService?.savedConnections ?? []
    property var ssidToConnectionName: activeService?.ssidToConnectionName ?? ({})
    property var wifiSignalIcon: activeService?.wifiSignalIcon ?? "wifi_off"

    property string userPreference: activeService?.userPreference ?? "auto"
    property bool isConnecting: activeService?.isConnecting ?? false
    readonly property bool isWifiConnecting: isConnecting && !ethernetConnected && !wifiToggling
    property string connectingSSID: activeService?.connectingSSID ?? ""
    property string connectionError: activeService?.connectionError ?? ""

    property bool isScanning: activeService?.isScanning ?? false
    property bool autoScan: activeService?.autoScan ?? false

    property bool wifiAvailable: activeService?.wifiAvailable ?? true
    property bool wifiToggling: activeService?.wifiToggling ?? false
    property bool changingPreference: activeService?.changingPreference ?? false
    property string targetPreference: activeService?.targetPreference ?? ""
    property string preferenceError: activeService?.preferenceError ?? ""
    property var savedWifiNetworks: activeService?.savedWifiNetworks ?? []
    readonly property int savedWifiStateApiVersion: activeService?.savedWifiStateApiVersion ?? 26
    readonly property int hotspotApiVersion: activeService?.hotspotApiVersion ?? 28
    readonly property int hotspotClientsApiVersion: activeService?.hotspotClientsApiVersion ?? 29
    readonly property int hotspotClientNamesApiVersion: activeService?.hotspotClientNamesApiVersion ?? 30
    readonly property int hotspotAnalyticsApiVersion: activeService?.hotspotAnalyticsApiVersion ?? 31
    property bool hotspotSupported: activeService?.hotspotSupported ?? false
    property bool hotspotAvailable: activeService?.hotspotAvailable ?? false
    property bool hotspotConfigured: activeService?.hotspotConfigured ?? false
    property bool hotspotEnabled: activeService?.hotspotEnabled ?? false
    property bool hotspotActivating: activeService?.hotspotActivating ?? false
    property bool hotspotSecured: activeService?.hotspotSecured ?? false
    property bool hotspotWouldDisconnectWifi: activeService?.hotspotWouldDisconnectWifi ?? false
    property string hotspotSSID: activeService?.hotspotSSID ?? ""
    property string hotspotDevice: activeService?.hotspotDevice ?? ""
    property string hotspotBand: activeService?.hotspotBand ?? ""
    property bool hotspotCompatibility: activeService?.hotspotCompatibility ?? false
    property bool hotspotBusy: activeService?.hotspotBusy ?? false
    property string hotspotError: activeService?.hotspotError ?? ""
    property string hotspotStatus: activeService?.hotspotStatus ?? "stopped"
    property string hotspotStatusMessage: activeService?.hotspotStatusMessage ?? ""
    property var hotspotClients: activeService?.hotspotClients ?? []
    property var hotspotBlockedClients: activeService?.hotspotBlockedClients ?? []
    property var hotspotAnalytics: activeService?.hotspotAnalytics ?? ({ enabled: false, devices: [] })
    property bool hotspotAnalyticsBusy: activeService?.hotspotAnalyticsBusy ?? false
    property string connectionStatus: activeService?.connectionStatus ?? ""
    property string lastConnectionError: activeService?.lastConnectionError ?? ""
    property bool passwordDialogShouldReopen: activeService?.passwordDialogShouldReopen ?? false
    property bool autoRefreshEnabled: activeService?.autoRefreshEnabled ?? false
    property string wifiPassword: activeService?.wifiPassword ?? ""
    property string forgetSSID: activeService?.forgetSSID ?? ""

    property string networkInfoSSID: activeService?.networkInfoSSID ?? ""
    property string networkInfoDetails: activeService?.networkInfoDetails ?? ""
    property bool networkInfoLoading: activeService?.networkInfoLoading ?? false

    property string networkWiredInfoUUID: activeService?.networkWiredInfoUUID ?? ""
    property string networkWiredInfoDetails: activeService?.networkWiredInfoDetails ?? ""
    property bool networkWiredInfoLoading: activeService?.networkWiredInfoLoading ?? false

    property int refCount: activeService?.refCount ?? 0
    property bool stateInitialized: activeService?.stateInitialized ?? false

    property bool subscriptionConnected: activeService?.subscriptionConnected ?? false

    property string credentialsToken: activeService?.credentialsToken ?? ""
    property string credentialsSSID: activeService?.credentialsSSID ?? ""
    property string credentialsSetting: activeService?.credentialsSetting ?? ""
    property var credentialsFields: activeService?.credentialsFields ?? []
    property var credentialsHints: activeService?.credentialsHints ?? []
    property string credentialsReason: activeService?.credentialsReason ?? ""
    property bool credentialsRequested: activeService?.credentialsRequested ?? false

    signal networksUpdated
    signal connectionChanged
    signal credentialsNeeded(string token, string ssid, string setting, var fields, var hints, string reason, string connType, string connName, var fieldsInfo)

    property var activeService: null

    readonly property string socketPath: Quickshell.env("KASKAD_SOCKET")

    // Backend adoption must be state-checked here, not only edge-triggered below:
    // with staged shell loading this singleton can be instantiated after
    // KaskadNetworkService already resolved its capabilities, so the change signal
    // may never fire again.
    Component.onCompleted: {
        log.info("Initializing...");
        if (!socketPath || socketPath.length === 0) {
            log.info("KASKAD_SOCKET not set, network backend unavailable");
            return;
        }
        if (KaskadNetworkService.networkAvailable) {
            log.info("Network capability already available, using KaskadNetworkService");
            useKaskadService();
            return;
        }
        log.debug("KASKAD_SOCKET found, waiting for capabilities...");
    }

    Connections {
        target: KaskadNetworkService

        function onNetworkAvailableChanged() {
            if (!activeService && KaskadNetworkService.networkAvailable) {
                log.info("Network capability detected, using KaskadNetworkService");
                useKaskadService();
            }
        }
    }

    function useKaskadService() {
        activeService = KaskadNetworkService;
        log.info("Switched to KaskadNetworkService, networkAvailable:", networkAvailable);
        connectSignals();
    }

    function connectSignals() {
        if (activeService) {
            if (activeService.networksUpdated) {
                activeService.networksUpdated.connect(root.networksUpdated);
            }
            if (activeService.connectionChanged) {
                activeService.connectionChanged.connect(root.connectionChanged);
            }
            if (activeService.credentialsNeeded) {
                activeService.credentialsNeeded.connect(root.credentialsNeeded);
            }
        }
    }

    function addRef() {
        if (activeService && activeService.addRef) {
            activeService.addRef();
        }
    }

    function removeRef() {
        if (activeService && activeService.removeRef) {
            activeService.removeRef();
        }
    }

    function getState() {
        if (activeService && activeService.getState) {
            activeService.getState();
        }
    }

    function scanWifi() {
        if (activeService && activeService.scanWifi) {
            activeService.scanWifi();
        }
    }

    function scanWifiNetworks() {
        if (activeService && activeService.scanWifiNetworks) {
            activeService.scanWifiNetworks();
        }
    }

    function refreshSavedWifiNetworks() {
        if (activeService && activeService.refreshSavedWifiNetworks) {
            activeService.refreshSavedWifiNetworks();
        }
    }

    function connectToWifi(ssid, password = "", username = "", anonymousIdentity = "", domainSuffixMatch = "") {
        if (activeService && activeService.connectToWifi) {
            activeService.connectToWifi(ssid, password, username, anonymousIdentity, domainSuffixMatch);
        }
    }

    function disconnectWifi() {
        if (activeService && activeService.disconnectWifi) {
            activeService.disconnectWifi();
        }
    }

    function forgetWifiNetwork(ssid) {
        if (activeService && activeService.forgetWifiNetwork) {
            activeService.forgetWifiNetwork(ssid);
        }
    }

    function toggleWifiRadio() {
        if (activeService && activeService.toggleWifiRadio) {
            activeService.toggleWifiRadio();
        }
    }

    function enableWifiDevice() {
        if (activeService && activeService.enableWifiDevice) {
            activeService.enableWifiDevice();
        }
    }

    function setNetworkPreference(preference) {
        if (activeService && activeService.setNetworkPreference) {
            activeService.setNetworkPreference(preference);
        }
    }

    function setConnectionPriority(type) {
        if (activeService && activeService.setConnectionPriority) {
            activeService.setConnectionPriority(type);
        }
    }

    function connectToWifiAndSetPreference(ssid, password, username = "", anonymousIdentity = "", domainSuffixMatch = "") {
        if (activeService && activeService.connectToWifiAndSetPreference) {
            activeService.connectToWifiAndSetPreference(ssid, password, username, anonymousIdentity, domainSuffixMatch);
        }
    }

    function toggleNetworkConnection(type) {
        if (activeService && activeService.toggleNetworkConnection) {
            activeService.toggleNetworkConnection(type);
        }
    }

    function disconnectEthernetDevice(deviceName) {
        if (activeService && activeService.disconnectEthernetDevice) {
            activeService.disconnectEthernetDevice(deviceName);
        }
    }

    function setEthernetSharing(enabled, deviceName = "", useVPN = false, callback = null) {
        if (activeService && activeService.setEthernetSharing) {
            return activeService.setEthernetSharing(enabled, deviceName, useVPN, callback);
        }
        return false;
    }

    function startAutoScan() {
        if (activeService && activeService.startAutoScan) {
            activeService.startAutoScan();
        }
    }

    function stopAutoScan() {
        if (activeService && activeService.stopAutoScan) {
            activeService.stopAutoScan();
        }
    }

    function fetchNetworkInfo(ssid) {
        if (activeService && activeService.fetchNetworkInfo) {
            activeService.fetchNetworkInfo(ssid);
        }
    }

    function fetchWiredNetworkInfo(uuid) {
        if (activeService && activeService.fetchWiredNetworkInfo) {
            activeService.fetchWiredNetworkInfo(uuid);
        }
    }

    function getNetworkInfo(ssid) {
        if (activeService && activeService.getNetworkInfo) {
            return activeService.getNetworkInfo(ssid);
        }
        return null;
    }

    function getWiredNetworkInfo(uuid) {
        if (activeService && activeService.getWiredNetworkInfo) {
            return activeService.getWiredNetworkInfo(uuid);
        }
        return null;
    }

    function refreshNetworkState() {
        if (activeService && activeService.refreshNetworkState) {
            activeService.refreshNetworkState();
        }
    }

    function connectToSpecificWiredConfig(uuid) {
        if (activeService && activeService.connectToSpecificWiredConfig) {
            activeService.connectToSpecificWiredConfig(uuid);
        }
    }

    function submitCredentials(token, secrets, save) {
        if (activeService && activeService.submitCredentials) {
            activeService.submitCredentials(token, secrets, save);
        }
    }

    function cancelCredentials(token) {
        if (activeService && activeService.cancelCredentials) {
            activeService.cancelCredentials(token);
        }
    }

    function setWifiAutoconnect(ssid, autoconnect) {
        if (activeService && activeService.setWifiAutoconnect) {
            activeService.setWifiAutoconnect(ssid, autoconnect);
        }
    }

    function configureHotspot(ssid, password = "", device = "", band = "", compatibility = false, callback = null) {
        if (activeService && activeService.configureHotspot) {
            return activeService.configureHotspot(ssid, password, device, band, compatibility, callback);
        }
        return false;
    }

    function startHotspot(callback = null) {
        if (activeService && activeService.startHotspot) {
            return activeService.startHotspot(callback);
        }
        return false;
    }

    function stopHotspot(callback = null) {
        if (activeService && activeService.stopHotspot) {
            return activeService.stopHotspot(callback);
        }
        return false;
    }

    function refreshHotspotClients(callback = null) {
        return activeService?.refreshHotspotClients ? activeService.refreshHotspotClients(callback) : false;
    }

    function disconnectHotspotClient(mac, callback = null) {
        return activeService?.disconnectHotspotClient ? activeService.disconnectHotspotClient(mac, callback) : false;
    }

    function setHotspotClientBlocked(mac, blocked, callback = null) {
        return activeService?.setHotspotClientBlocked ? activeService.setHotspotClientBlocked(mac, blocked, callback) : false;
    }

    function setHotspotClientName(mac, name, callback = null) {
        return activeService?.setHotspotClientName ? activeService.setHotspotClientName(mac, name, callback) : false;
    }

    function refreshHotspotAnalytics(callback = null) {
        return activeService?.refreshHotspotAnalytics ? activeService.refreshHotspotAnalytics(callback) : false;
    }

    function setHotspotAnalyticsEnabled(enabled, callback = null) {
        return activeService?.setHotspotAnalyticsEnabled ? activeService.setHotspotAnalyticsEnabled(enabled, callback) : false;
    }

    function deleteHotspotAnalyticsSession(mac, sessionId, callback = null) {
        return activeService?.deleteHotspotAnalyticsSession ? activeService.deleteHotspotAnalyticsSession(mac, sessionId, callback) : false;
    }

    function clearCurrentHotspotAnalytics(mac, callback = null) {
        return activeService?.clearCurrentHotspotAnalytics ? activeService.clearCurrentHotspotAnalytics(mac, callback) : false;
    }

    function clearHotspotAnalyticsDevice(mac, callback = null) {
        return activeService?.clearHotspotAnalyticsDevice ? activeService.clearHotspotAnalyticsDevice(mac, callback) : false;
    }

    function clearAllHotspotAnalytics(callback = null) {
        return activeService?.clearAllHotspotAnalytics ? activeService.clearAllHotspotAnalytics(callback) : false;
    }

    function configureAndStartHotspot(ssid, password = "", device = "", band = "", compatibility = false, callback = null) {
        if (activeService && activeService.configureAndStartHotspot) {
            return activeService.configureAndStartHotspot(ssid, password, device, band, compatibility, callback);
        }
        return false;
    }

    function getHotspotSecrets(callback) {
        if (activeService && activeService.getHotspotSecrets) {
            return activeService.getHotspotSecrets(callback);
        }
        return false;
    }

    function hotspotTargetWouldDisconnectWifi(device, band = "") {
        if (activeService && activeService.hotspotTargetWouldDisconnectWifi) {
            return activeService.hotspotTargetWouldDisconnectWifi(device, band);
        }
        return false;
    }

    function setWifiDeviceOverride(deviceName) {
        if (activeService && activeService.setWifiDeviceOverride) {
            activeService.setWifiDeviceOverride(deviceName);
        }
    }
}

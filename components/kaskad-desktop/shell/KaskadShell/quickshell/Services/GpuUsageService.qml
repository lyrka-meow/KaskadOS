pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("GpuUsageService")

    property int refCount: 0
    property bool updating: false
    property var devices: []
    readonly property bool available: devices.some(device => device.usageAvailable)

    function addRef() {
        refCount++;
        if (refCount === 1)
            refresh();
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
    }

    function metadataFor(address) {
        const metadata = DgopService.availableGpus || [];
        return metadata.find(gpu => gpu.address === address) || null;
    }

    function normalizedDevices(source) {
        return (source || []).map(device => {
            const metadata = metadataFor(device.id);
            return Object.assign({}, device, {
                "name": device.name || metadata?.fullName || metadata?.displayName || device.driver?.toUpperCase() || device.id,
                "displayName": metadata?.displayName || device.name || device.driver?.toUpperCase() || device.id
            });
        });
    }

    function refresh() {
        if (updating || refCount <= 0 || !KaskadService.isConnected)
            return;
        updating = true;
        KaskadService.sendRequest("gpu.getState", null, response => {
            updating = false;
            if (response.result) {
                devices = normalizedDevices(response.result.devices);
            } else if (response.error && response.error !== "not connected to Kaskad socket") {
                log.warn("GPU metrics request failed:", response.error);
            }
        });
    }

    Connections {
        target: KaskadService
        function onConnectionStateChanged() {
            if (KaskadService.isConnected && root.refCount > 0)
                root.refresh();
        }
    }

    Connections {
        target: DgopService
        function onAvailableGpusChanged() {
            root.devices = root.normalizedDevices(root.devices);
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.refCount > 0
        onTriggered: root.refresh()
    }
}

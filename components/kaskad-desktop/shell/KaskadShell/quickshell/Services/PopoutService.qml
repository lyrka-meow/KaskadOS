pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Kaskad.Ipc
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Singleton {
    id: root

    Connections {
        target: Kaskad
        ignoreUnknownSignals: true
        function onLauncherRequested(kind) {
            if (kind === "default")
                root.toggleKaskadLauncherV2();
            else if (kind === "spotlight")
                root.toggleSpotlightBar();
        }
    }

    property var controlCenterPopout: null
    property var controlCenterLoader: null
    property var notificationCenterPopout: null
    property var notificationCenterLoader: null
    property var appDrawerPopout: null
    property var appDrawerLoader: null
    property var processListPopout: null
    property var processListPopoutLoader: null
    property var kaskadDashPopout: null
    property var kaskadDashPopoutLoader: null
    property var batteryPopout: null
    property var batteryPopoutLoader: null
    property var vpnPopout: null
    property var vpnPopoutLoader: null
    property var systemUpdatePopout: null
    property var systemUpdateLoader: null
    property var layoutPopout: null
    property var layoutPopoutLoader: null
    property var clipboardHistoryPopout: null
    property var clipboardHistoryPopoutLoader: null

    property var settingsModal: null
    property var settingsModalLoader: null
    property var clipboardHistoryModal: null
    property var kaskadLauncherV2Modal: null
    property var kaskadLauncherV2ModalLoader: null
    property var spotlightBarModal: null
    property var spotlightBarModalLoader: null
    property var powerMenuModal: null
    property var powerMenuModalLoader: null
    property var processListModal: null
    property var processListModalLoader: null
    property var colorPickerModal: null
    property var notificationModal: null
    property var wifiPasswordModal: null
    property var wifiPasswordModalLoader: null
    property var wifiQRCodeModal: null
    property var wifiQRCodeModalLoader: null
    property var polkitAuthModal: null
    property var polkitAuthModalLoader: null
    property var bluetoothPairingModal: null
    property var networkInfoModal: null
    property var windowRuleModalLoader: null
    property var powerProfileModal: null
    property var powerProfileModalLoader: null

    property var notepadSlideouts: []


    // Deferred unload: keep popouts warm while the session is active and reclaim them on lock/monitors-off.
    property var _pendingUnloads: ({})

    Connections {
        target: SessionService
        function onSessionLocked() {
            root._flushPendingUnloads();
        }
    }

    Connections {
        target: IdleService
        function onMonitorsOffChanged() {
            if (IdleService.monitorsOff)
                root._flushPendingUnloads();
        }
    }

    function _scheduleUnload(key) {
        _pendingUnloads[key] = true;
    }

    function _flushPendingUnloads() {
        const keys = Object.keys(_pendingUnloads);
        _pendingUnloads = ({});
        for (let i = 0; i < keys.length; i++) {
            const unload = _deferredUnloaders[keys[i]];
            if (unload)
                unload();
        }
    }

    function _popoutStillPresented(popout) {
        return !!popout && (popout.shouldBeVisible === true || popout.isClosing === true);
    }

    function _unloadPopoutNow(popoutName, loaderName) {
        const loader = root[loaderName];
        if (!loader)
            return;
        if (_popoutStillPresented(root[popoutName]))
            return;
        root[popoutName] = null;
        loader.active = false;
    }

    readonly property var _deferredUnloaders: ({
            "controlCenter": () => _unloadPopoutNow("controlCenterPopout", "controlCenterLoader"),
            "notificationCenter": () => _unloadPopoutNow("notificationCenterPopout", "notificationCenterLoader"),
            "appDrawer": () => _unloadPopoutNow("appDrawerPopout", "appDrawerLoader"),
            "processList": () => _unloadPopoutNow("processListPopout", "processListPopoutLoader"),
            "battery": () => _unloadPopoutNow("batteryPopout", "batteryPopoutLoader"),
            "vpn": () => _unloadPopoutNow("vpnPopout", "vpnPopoutLoader"),
            "systemUpdate": () => _unloadPopoutNow("systemUpdatePopout", "systemUpdateLoader"),
            "layout": () => _unloadPopoutNow("layoutPopout", "layoutPopoutLoader"),
            "clipboardHistory": () => _unloadPopoutNow("clipboardHistoryPopout", "clipboardHistoryPopoutLoader"),
            "settings": () => _unloadSettingsNow()
        })

    function setPosition(popout, x, y, width, section, screen) {
        if (popout && popout.setTriggerPosition && arguments.length >= 6) {
            popout.setTriggerPosition(x, y, width, section, screen);
        }
    }

    function openControlCenter(x, y, width, section, screen) {
        if (controlCenterPopout) {
            setPosition(controlCenterPopout, x, y, width, section, screen);
            controlCenterPopout.open();
        }
    }

    function closeControlCenter() {
        controlCenterPopout?.close();
    }

    function unloadControlCenter() {
        _scheduleUnload("controlCenter");
    }

    function toggleControlCenter(x, y, width, section, screen) {
        if (controlCenterPopout) {
            setPosition(controlCenterPopout, x, y, width, section, screen);
            controlCenterPopout.toggle();
        }
    }

    function openNotificationCenter(x, y, width, section, screen) {
        if (notificationCenterPopout) {
            setPosition(notificationCenterPopout, x, y, width, section, screen);
            notificationCenterPopout.open();
        }
    }

    function closeNotificationCenter() {
        notificationCenterPopout?.close();
    }

    function unloadNotificationCenter() {
        _scheduleUnload("notificationCenter");
    }

    function toggleNotificationCenter(x, y, width, section, screen) {
        if (notificationCenterPopout) {
            setPosition(notificationCenterPopout, x, y, width, section, screen);
            notificationCenterPopout.toggle();
        }
    }

    function openAppDrawer(x, y, width, section, screen) {
        if (appDrawerPopout) {
            setPosition(appDrawerPopout, x, y, width, section, screen);
            appDrawerPopout.open();
        }
    }

    function closeAppDrawer() {
        appDrawerPopout?.close();
    }

    function unloadAppDrawer() {
        _scheduleUnload("appDrawer");
    }

    function toggleAppDrawer(x, y, width, section, screen) {
        if (appDrawerPopout) {
            setPosition(appDrawerPopout, x, y, width, section, screen);
            appDrawerPopout.toggle();
        }
    }

    function openProcessList(x, y, width, section, screen) {
        if (processListPopout) {
            setPosition(processListPopout, x, y, width, section, screen);
            processListPopout.open();
        }
    }

    function closeProcessList() {
        processListPopout?.close();
    }

    function unloadProcessListPopout() {
        _scheduleUnload("processList");
    }

    function toggleProcessList(x, y, width, section, screen) {
        if (processListPopout) {
            setPosition(processListPopout, x, y, width, section, screen);
            processListPopout.toggle();
        }
    }

    property bool _kaskadDashWantsOpen: false
    property bool _kaskadDashWantsToggle: false
    property var _kaskadDashPendingTab: 0
    property real _kaskadDashPendingX: 0
    property real _kaskadDashPendingY: 0
    property real _kaskadDashPendingWidth: 0
    property string _kaskadDashPendingSection: ""
    property var _kaskadDashPendingScreen: null
    property bool _kaskadDashHasPosition: false

    function _storeKaskadDashPosition(x, y, width, section, screen, hasPos) {
        _kaskadDashPendingX = x;
        _kaskadDashPendingY = y;
        _kaskadDashPendingWidth = width;
        _kaskadDashPendingSection = section;
        _kaskadDashPendingScreen = screen;
        _kaskadDashHasPosition = hasPos;
    }

    // `tab` is a view id ("weather"); numeric indices remain accepted for
    // callers that still use the older API.
    function _kaskadDashTabId(tab) {
        if (typeof tab === "string" && tab !== "")
            return tab;
        const ids = SettingsData.visibleDashTabIds();
        return ids[typeof tab === "number" ? tab : 0] ?? "overview";
    }

    function openKaskadDash(tab, x, y, width, section, screen) {
        _kaskadDashPendingTab = tab || 0;
        if (kaskadDashPopout) {
            if (arguments.length >= 6)
                setPosition(kaskadDashPopout, x, y, width, section, screen);
            kaskadDashPopout.requestTab(_kaskadDashTabId(_kaskadDashPendingTab));
            kaskadDashPopout.dashVisible = true;
            return;
        }
        if (!kaskadDashPopoutLoader)
            return;
        _storeKaskadDashPosition(x, y, width, section, screen, arguments.length >= 6);
        _kaskadDashWantsOpen = true;
        _kaskadDashWantsToggle = false;
        kaskadDashPopoutLoader.active = true;
    }

    function closeKaskadDash() {
        if (kaskadDashPopout)
            kaskadDashPopout.dashVisible = false;
    }

    function unloadKaskadDash() {
        // KaskadDash is intentionally kept alive after first use. Destroying this
        // lazy popout during its close signal can invalidate connected overlay
        // bindings while Qt is still unwinding the signal stack.
    }

    function toggleKaskadDash(tab, x, y, width, section, screen) {
        _kaskadDashPendingTab = tab || 0;
        if (kaskadDashPopout) {
            if (arguments.length >= 6)
                setPosition(kaskadDashPopout, x, y, width, section, screen);
            if (kaskadDashPopout.dashVisible) {
                kaskadDashPopout.dashVisible = false;
            } else {
                kaskadDashPopout.requestTab(_kaskadDashTabId(_kaskadDashPendingTab));
                kaskadDashPopout.dashVisible = true;
            }
            return;
        }
        if (!kaskadDashPopoutLoader)
            return;
        _storeKaskadDashPosition(x, y, width, section, screen, arguments.length >= 6);
        _kaskadDashWantsToggle = true;
        _kaskadDashWantsOpen = false;
        kaskadDashPopoutLoader.active = true;
    }

    function _onKaskadDashPopoutLoaded() {
        if (!kaskadDashPopout)
            return;

        if (_kaskadDashHasPosition)
            setPosition(kaskadDashPopout, _kaskadDashPendingX, _kaskadDashPendingY, _kaskadDashPendingWidth, _kaskadDashPendingSection, _kaskadDashPendingScreen);

        if (_kaskadDashWantsOpen) {
            _kaskadDashWantsOpen = false;
            kaskadDashPopout.requestTab(_kaskadDashTabId(_kaskadDashPendingTab));
            kaskadDashPopout.dashVisible = true;
            return;
        }
        if (_kaskadDashWantsToggle) {
            _kaskadDashWantsToggle = false;
            if (kaskadDashPopout.dashVisible) {
                kaskadDashPopout.dashVisible = false;
            } else {
                kaskadDashPopout.requestTab(_kaskadDashTabId(_kaskadDashPendingTab));
                kaskadDashPopout.dashVisible = true;
            }
        }
    }

    function openBattery(x, y, width, section, screen) {
        if (batteryPopout) {
            setPosition(batteryPopout, x, y, width, section, screen);
            batteryPopout.open();
        }
    }

    function closeBattery() {
        batteryPopout?.close();
    }

    function unloadBattery() {
        _scheduleUnload("battery");
    }

    function toggleBattery(x, y, width, section, screen) {
        if (batteryPopout) {
            setPosition(batteryPopout, x, y, width, section, screen);
            batteryPopout.toggle();
        }
    }

    function openVpn(x, y, width, section, screen) {
        if (vpnPopout) {
            setPosition(vpnPopout, x, y, width, section, screen);
            vpnPopout.open();
        }
    }

    function closeVpn() {
        vpnPopout?.close();
    }

    function unloadVpn() {
        _scheduleUnload("vpn");
    }

    function toggleVpn(x, y, width, section, screen) {
        if (vpnPopout) {
            setPosition(vpnPopout, x, y, width, section, screen);
            vpnPopout.toggle();
        }
    }

    function openSystemUpdate(x, y, width, section, screen) {
        if (systemUpdatePopout) {
            if (arguments.length >= 5)
                setPosition(systemUpdatePopout, x, y, width, section, screen);
            systemUpdatePopout.open();
        }
    }

    function closeSystemUpdate() {
        systemUpdatePopout?.close();
    }

    function unloadSystemUpdate() {
        _scheduleUnload("systemUpdate");
    }

    function toggleSystemUpdate(x, y, width, section, screen) {
        if (systemUpdatePopout) {
            if (arguments.length >= 5)
                setPosition(systemUpdatePopout, x, y, width, section, screen);
            systemUpdatePopout.toggle();
        }
    }

    property bool _settingsWantsOpen: false
    property bool _settingsWantsToggle: false

    property string _settingsPendingTab: ""
    property int _settingsPendingTabIndex: -1

    function openSettings() {
        if (settingsModal) {
            settingsModal.show();
        } else if (settingsModalLoader) {
            _settingsWantsOpen = true;
            _settingsWantsToggle = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    function openSettingsWithTab(tabName: string) {
        if (settingsModal) {
            settingsModal.showWithTabName(tabName);
            return;
        }
        if (settingsModalLoader) {
            _settingsPendingTab = tabName;
            _settingsWantsOpen = true;
            _settingsWantsToggle = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    function openSettingsWithTabIndex(tabIndex: int) {
        if (settingsModal) {
            settingsModal.showWithTab(tabIndex);
            return;
        }
        if (settingsModalLoader) {
            _settingsPendingTabIndex = tabIndex;
            _settingsWantsOpen = true;
            _settingsWantsToggle = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    function closeSettings() {
        settingsModal?.close();
    }

    function toggleSettings() {
        if (settingsModal) {
            settingsModal.toggle();
        } else if (settingsModalLoader) {
            _settingsWantsToggle = true;
            _settingsWantsOpen = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    function toggleSettingsWithTab(tabName: string) {
        if (settingsModal) {
            var idx = settingsModal.resolveTabIndex(tabName);
            settingsModal.setTabIndex(idx);
            settingsModal.toggle();
            return;
        }
        if (settingsModalLoader) {
            _settingsPendingTab = tabName;
            _settingsWantsToggle = true;
            _settingsWantsOpen = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    function focusOrToggleSettings() {
        if (settingsModal?.visible) {
            const settingsTitle = I18n.tr("Settings", "settings window title");
            if (CompositorService.activateWindowByTitle(["Settings", settingsTitle]))
                return;
        }
        openSettings();
    }

    function focusOrToggleSettingsWithTab(tabName: string) {
        if (settingsModal?.visible) {
            const settingsTitle = I18n.tr("Settings", "settings window title");
            var idx = settingsModal.resolveTabIndex(tabName);
            settingsModal.setTabIndex(idx);
            if (CompositorService.activateWindowByTitle(["Settings", settingsTitle]))
                return;
        }
        openSettingsWithTab(tabName);
    }

    function unloadSettings() {
        _scheduleUnload("settings");
    }

    function _unloadSettingsNow() {
        if (!settingsModalLoader)
            return;
        if (settingsModal && settingsModal.visible)
            return;
        settingsModal = null;
        settingsModalLoader.active = false;
    }

    function _onSettingsModalLoaded() {
        if (_settingsWantsOpen) {
            _settingsWantsOpen = false;
            if (_settingsPendingTabIndex >= 0) {
                settingsModal?.showWithTab(_settingsPendingTabIndex);
                _settingsPendingTabIndex = -1;
            } else if (_settingsPendingTab) {
                settingsModal?.showWithTabName(_settingsPendingTab);
                _settingsPendingTab = "";
            } else {
                settingsModal?.show();
            }
            return;
        }
        if (_settingsWantsToggle) {
            _settingsWantsToggle = false;
            if (_settingsPendingTabIndex >= 0) {
                settingsModal?.setTabIndex(_settingsPendingTabIndex);
                _settingsPendingTabIndex = -1;
            } else if (_settingsPendingTab) {
                var idx = settingsModal?.resolveTabIndex(_settingsPendingTab) ?? -1;
                settingsModal?.setTabIndex(idx);
                _settingsPendingTab = "";
            }
            settingsModal?.toggle();
        }
    }

    function openClipboardHistory() {
        clipboardHistoryModal?.show();
    }

    function closeClipboardHistory() {
        clipboardHistoryModal?.hide();
    }

    function unloadClipboardHistoryPopout() {
        _scheduleUnload("clipboardHistory");
    }

    function unloadLayoutPopout() {
        _scheduleUnload("layout");
    }

    property bool _kaskadLauncherV2WantsOpen: false
    property bool _kaskadLauncherV2WantsToggle: false
    property string _kaskadLauncherV2PendingQuery: ""
    property string _kaskadLauncherV2PendingMode: ""
    property bool _kaskadLauncherV2TriggerUsesOverlayLayer: false
    property bool _kaskadLauncherV2EdgeHoverManaged: false

    function _setKaskadLauncherV2TriggerUsesOverlayLayer(value) {
        _kaskadLauncherV2TriggerUsesOverlayLayer = value === true;
        // Disable edge-hover by default on every open/toggle path unless explicitly enabled.
        _setKaskadLauncherV2EdgeHoverManaged(false);
        if (kaskadLauncherV2Modal)
            kaskadLauncherV2Modal.triggerUsesOverlayLayer = _kaskadLauncherV2TriggerUsesOverlayLayer;
    }

    // Set edgeHoverManaged to enable hover retraction for edge-hover triggered launcher sessions.
    function _setKaskadLauncherV2EdgeHoverManaged(value) {
        _kaskadLauncherV2EdgeHoverManaged = value === true;
        if (kaskadLauncherV2Modal)
            kaskadLauncherV2Modal.edgeHoverManaged = _kaskadLauncherV2EdgeHoverManaged;
    }

    function openKaskadLauncherV2(triggerUsesOverlayLayer, edgeHoverManaged) {
        _setKaskadLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        _setKaskadLauncherV2EdgeHoverManaged(edgeHoverManaged);
        if (kaskadLauncherV2Modal) {
            kaskadLauncherV2Modal.show();
        } else if (kaskadLauncherV2ModalLoader) {
            _kaskadLauncherV2WantsOpen = true;
            _kaskadLauncherV2WantsToggle = false;
            kaskadLauncherV2ModalLoader.active = true;
        }
    }

    function openKaskadLauncherV2WithQuery(query: string, triggerUsesOverlayLayer) {
        _setKaskadLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (kaskadLauncherV2Modal) {
            kaskadLauncherV2Modal.showWithQuery(query);
        } else if (kaskadLauncherV2ModalLoader) {
            _kaskadLauncherV2PendingQuery = query;
            _kaskadLauncherV2WantsOpen = true;
            _kaskadLauncherV2WantsToggle = false;
            kaskadLauncherV2ModalLoader.active = true;
        }
    }

    function openKaskadLauncherV2WithMode(mode: string, triggerUsesOverlayLayer) {
        _setKaskadLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (kaskadLauncherV2Modal) {
            kaskadLauncherV2Modal.showWithMode(mode);
        } else if (kaskadLauncherV2ModalLoader) {
            _kaskadLauncherV2PendingMode = mode;
            _kaskadLauncherV2WantsOpen = true;
            _kaskadLauncherV2WantsToggle = false;
            kaskadLauncherV2ModalLoader.active = true;
        }
    }

    function closeKaskadLauncherV2() {
        kaskadLauncherV2Modal?.hide();
    }

    function unloadKaskadLauncherV2() {
        if (kaskadLauncherV2ModalLoader) {
            kaskadLauncherV2Modal = null;
            kaskadLauncherV2ModalLoader.active = false;
        }
    }

    function toggleKaskadLauncherV2(triggerUsesOverlayLayer) {
        _setKaskadLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (kaskadLauncherV2Modal) {
            kaskadLauncherV2Modal.toggle();
        } else if (kaskadLauncherV2ModalLoader) {
            _kaskadLauncherV2WantsToggle = true;
            _kaskadLauncherV2WantsOpen = false;
            kaskadLauncherV2ModalLoader.active = true;
        }
    }

    function toggleKaskadLauncherV2WithMode(mode: string, triggerUsesOverlayLayer) {
        _setKaskadLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (kaskadLauncherV2Modal) {
            kaskadLauncherV2Modal.toggleWithMode(mode);
        } else if (kaskadLauncherV2ModalLoader) {
            _kaskadLauncherV2PendingMode = mode;
            _kaskadLauncherV2WantsToggle = true;
            _kaskadLauncherV2WantsOpen = false;
            kaskadLauncherV2ModalLoader.active = true;
        }
    }

    function toggleKaskadLauncherV2WithQuery(query: string, triggerUsesOverlayLayer) {
        _setKaskadLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (kaskadLauncherV2Modal) {
            kaskadLauncherV2Modal.toggleWithQuery(query);
        } else if (kaskadLauncherV2ModalLoader) {
            _kaskadLauncherV2PendingQuery = query;
            _kaskadLauncherV2WantsOpen = true;
            _kaskadLauncherV2WantsToggle = false;
            kaskadLauncherV2ModalLoader.active = true;
        }
    }

    function _onKaskadLauncherV2ModalLoaded() {
        if (kaskadLauncherV2Modal) {
            kaskadLauncherV2Modal.triggerUsesOverlayLayer = _kaskadLauncherV2TriggerUsesOverlayLayer;
            kaskadLauncherV2Modal.edgeHoverManaged = _kaskadLauncherV2EdgeHoverManaged;
        }
        if (_kaskadLauncherV2WantsOpen) {
            _kaskadLauncherV2WantsOpen = false;
            if (_kaskadLauncherV2PendingQuery) {
                kaskadLauncherV2Modal?.showWithQuery(_kaskadLauncherV2PendingQuery);
                _kaskadLauncherV2PendingQuery = "";
            } else if (_kaskadLauncherV2PendingMode) {
                kaskadLauncherV2Modal?.showWithMode(_kaskadLauncherV2PendingMode);
                _kaskadLauncherV2PendingMode = "";
            } else {
                kaskadLauncherV2Modal?.show();
            }
            return;
        }
        if (_kaskadLauncherV2WantsToggle) {
            _kaskadLauncherV2WantsToggle = false;
            if (_kaskadLauncherV2PendingMode) {
                kaskadLauncherV2Modal?.toggleWithMode(_kaskadLauncherV2PendingMode);
                _kaskadLauncherV2PendingMode = "";
            } else {
                kaskadLauncherV2Modal?.toggle();
            }
        }
    }

    property bool _spotlightBarWantsOpen: false
    property bool _spotlightBarWantsToggle: false
    property string _spotlightBarPendingQuery: ""
    property string _spotlightBarPendingMode: ""

    function openSpotlightBar() {
        if (spotlightBarModal) {
            spotlightBarModal.show();
        } else if (spotlightBarModalLoader) {
            _spotlightBarWantsOpen = true;
            _spotlightBarWantsToggle = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function openSpotlightBarWithQuery(query: string) {
        if (spotlightBarModal) {
            spotlightBarModal.showWithQuery(query);
        } else if (spotlightBarModalLoader) {
            _spotlightBarPendingQuery = query;
            _spotlightBarWantsOpen = true;
            _spotlightBarWantsToggle = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function openSpotlightBarWithMode(mode: string) {
        if (spotlightBarModal) {
            spotlightBarModal.showWithMode(mode);
        } else if (spotlightBarModalLoader) {
            _spotlightBarPendingMode = mode;
            _spotlightBarWantsOpen = true;
            _spotlightBarWantsToggle = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function closeSpotlightBar() {
        spotlightBarModal?.hide();
    }

    function toggleSpotlightBar() {
        if (spotlightBarModal) {
            spotlightBarModal.toggle();
        } else if (spotlightBarModalLoader) {
            _spotlightBarWantsToggle = true;
            _spotlightBarWantsOpen = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function toggleSpotlightBarWithMode(mode: string) {
        if (spotlightBarModal) {
            spotlightBarModal.toggleWithMode(mode);
        } else if (spotlightBarModalLoader) {
            _spotlightBarPendingMode = mode;
            _spotlightBarWantsToggle = true;
            _spotlightBarWantsOpen = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function toggleSpotlightBarWithQuery(query: string) {
        if (spotlightBarModal) {
            spotlightBarModal.toggleWithQuery(query);
        } else if (spotlightBarModalLoader) {
            _spotlightBarPendingQuery = query;
            _spotlightBarWantsOpen = true;
            _spotlightBarWantsToggle = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function _onSpotlightBarModalLoaded() {
        if (_spotlightBarWantsOpen) {
            _spotlightBarWantsOpen = false;
            if (_spotlightBarPendingQuery) {
                spotlightBarModal?.showWithQuery(_spotlightBarPendingQuery);
                _spotlightBarPendingQuery = "";
            } else if (_spotlightBarPendingMode) {
                spotlightBarModal?.showWithMode(_spotlightBarPendingMode);
                _spotlightBarPendingMode = "";
            } else {
                spotlightBarModal?.show();
            }
            return;
        }
        if (_spotlightBarWantsToggle) {
            _spotlightBarWantsToggle = false;
            if (_spotlightBarPendingMode) {
                spotlightBarModal?.toggleWithMode(_spotlightBarPendingMode);
                _spotlightBarPendingMode = "";
            } else {
                spotlightBarModal?.toggle();
            }
        }
    }

    function openPowerMenu() {
        powerMenuModal?.openCentered();
    }

    function closePowerMenu() {
        powerMenuModal?.close();
    }

    function togglePowerMenu() {
        if (powerMenuModal) {
            if (powerMenuModal.shouldBeVisible) {
                powerMenuModal.close();
            } else {
                powerMenuModal.openCentered();
            }
        }
    }

    function openPowerProfileModal() {
        if (powerProfileModal) {
            powerProfileModal.openCentered();
        } else if (powerProfileModalLoader) {
            powerProfileModalLoader.active = true;
            Qt.callLater(() => powerProfileModal?.openCentered());
        }
    }

    function closePowerProfileModal() {
        powerProfileModal?.close();
    }

    function togglePowerProfileModal() {
        if (powerProfileModal) {
            if (powerProfileModal.shouldBeVisible) {
                powerProfileModal.close();
            } else {
                powerProfileModal.openCentered();
            }
        } else if (powerProfileModalLoader) {
            powerProfileModalLoader.active = true;
            Qt.callLater(() => {
                if (powerProfileModal) {
                    if (powerProfileModal.shouldBeVisible) {
                        powerProfileModal.close();
                    } else {
                        powerProfileModal.openCentered();
                    }
                }
            });
        }
    }

    function showProcessListModal() {
        if (processListModal) {
            processListModal.show();
        } else if (processListModalLoader) {
            processListModalLoader.active = true;
            Qt.callLater(() => processListModal?.show());
        }
    }

    function hideProcessListModal() {
        processListModal?.hide();
    }

    function unloadProcessListModal() {
        if (processListModalLoader) {
            processListModal = null;
            processListModalLoader.active = false;
        }
    }

    function toggleProcessListModal() {
        if (processListModal) {
            processListModal.toggle();
        } else if (processListModalLoader) {
            processListModalLoader.active = true;
            Qt.callLater(() => processListModal?.show());
        }
    }

    function showColorPicker() {
        colorPickerModal?.show();
    }

    function hideColorPicker() {
        colorPickerModal?.close();
    }

    function showNotificationModal() {
        notificationModal?.show();
    }

    function hideNotificationModal() {
        notificationModal?.close();
    }

    function showWifiPasswordModal(ssid) {
        if (wifiPasswordModalLoader)
            wifiPasswordModalLoader.active = true;
        if (wifiPasswordModal) {
            wifiPasswordModal.show(ssid);
        } else {
            Qt.callLater(() => wifiPasswordModal?.show(ssid));
        }
    }

    function showWifiQRCodeModal(ssid) {
        if (wifiQRCodeModalLoader)
            wifiQRCodeModalLoader.active = true;
        if (wifiQRCodeModal)
            wifiQRCodeModal.show(ssid);
    }

    function showHiddenNetworkModal() {
        if (wifiPasswordModalLoader)
            wifiPasswordModalLoader.active = true;
        if (wifiPasswordModal) {
            wifiPasswordModal.showHidden();
        } else {
            Qt.callLater(() => wifiPasswordModal?.showHidden());
        }
    }

    function hideWifiPasswordModal() {
        wifiPasswordModal?.hide();
    }

    function showNetworkInfoModal() {
        networkInfoModal?.show();
    }

    function hideNetworkInfoModal() {
        networkInfoModal?.close();
    }

    function closeNotepadSlideouts() {
        for (var i = 0; i < notepadSlideouts.length; i++) {
            if (notepadSlideouts[i] && notepadSlideouts[i].isVisible)
                notepadSlideouts[i].hide();
        }
    }

    function notepadSlideoutForFocusedScreen() {
        if (!notepadSlideouts || notepadSlideouts.length === 0)
            return null;
        const focused = BarWidgetService.getFocusedScreenName();
        if (focused) {
            for (var i = 0; i < notepadSlideouts.length; i++) {
                if (notepadSlideouts[i]?.modelData?.name === focused)
                    return notepadSlideouts[i];
            }
        }
        return notepadSlideouts[0];
    }

    // Remembered presentation wins over the configured default until the user
    // changes the default in settings (handled below).
    readonly property string notepadResolvedMode: SessionData.notepadLastMode || SettingsData.notepadDefaultMode

    function openNotepadSlideout() {
        SessionData.setNotepadLastMode("slideout");
        notepadPopout?.hide();
        if (notepadSlideouts.length > 0) {
            notepadSlideoutForFocusedScreen()?.show();
        }
    }

    // Keep the notepad in a single presentation for default modes
    Connections {
        target: SettingsData
        function onNotepadDefaultModeChanged() {
            SessionData.setNotepadLastMode(SettingsData.notepadDefaultMode);
            if (SettingsData.notepadDefaultMode === "popout") {
                var hadSlideout = false;
                for (var i = 0; i < root.notepadSlideouts.length; i++) {
                    if (root.notepadSlideouts[i] && root.notepadSlideouts[i].isVisible) {
                        hadSlideout = true;
                        root.notepadSlideouts[i].hide();
                    }
                }
                if (hadSlideout)
                    root.openNotepadPopout();
            } else if (root.notepadPopout && root.notepadPopout.visible) {
                root.notepadPopout.hide();
                root.openNotepadSlideout();
            }
        }
    }

    function openNotepad() {
        if (notepadResolvedMode === "popout") {
            openNotepadPopout();
            return;
        }
        openNotepadSlideout();
    }

    function closeNotepad() {
        if (notepadResolvedMode === "popout") {
            notepadPopout?.hide();
            return;
        }
        if (notepadSlideouts.length > 0) {
            notepadSlideoutForFocusedScreen()?.hide();
        }
    }

    function toggleNotepad() {
        if (notepadResolvedMode === "popout") {
            toggleNotepadPopout();
            return;
        }
        if (notepadSlideouts.length > 0) {
            notepadSlideoutForFocusedScreen()?.toggle();
        }
    }

    property var notepadPopout: null
    property var notepadPopoutLoader: null
    property bool _notepadPopoutWantsOpen: false
    property string _notepadPendingOpenFilePath: ""

    function openNotepadPopout() {
        SessionData.setNotepadLastMode("popout");
        closeNotepadSlideouts();
        if (notepadPopout) {
            notepadPopout.show();
        } else if (notepadPopoutLoader) {
            _notepadPopoutWantsOpen = true;
            notepadPopoutLoader.active = true;
        }
    }

    function openNotepadPopoutWithFile(path) {
        closeNotepadSlideouts();
        if (notepadPopout) {
            notepadPopout.show();
            notepadPopout.notepad?.openExternalFile(path);
        } else if (notepadPopoutLoader) {
            _notepadPendingOpenFilePath = path;
            _notepadPopoutWantsOpen = true;
            notepadPopoutLoader.active = true;
        }
    }

    function _onNotepadPopoutLoaded() {
        if (_notepadPopoutWantsOpen && notepadPopout) {
            _notepadPopoutWantsOpen = false;
            notepadPopout.show();
            if (_notepadPendingOpenFilePath) {
                const pendingPath = _notepadPendingOpenFilePath;
                _notepadPendingOpenFilePath = "";
                notepadPopout.notepad?.openExternalFile(pendingPath);
            }
        }
    }

    function toggleNotepadPopout() {
        if (notepadPopout) {
            if (!notepadPopout.visible)
                closeNotepadSlideouts();
            notepadPopout.toggle();
        } else {
            openNotepadPopout();
        }
    }
}

pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import Kaskad.Ipc 1.0
import qs.Common
import qs.Services
import "settings/SessionSpec.js" as Spec
import "settings/SessionStore.js" as Store

Singleton {
    id: root
    readonly property var log: Log.scoped("SessionData")

    readonly property int sessionConfigVersion: 11

    property bool _parseError: false
    property bool _hasLoaded: false
    property bool _isReadOnly: false
    property bool _hasUnsavedChanges: false
    property var _loadedSessionSnapshot: null
    readonly property var _hooks: ({
            "updateLocale": updateLocale
        })
    readonly property string _stateUrl: StandardPaths.writableLocation(StandardPaths.GenericStateLocation)
    readonly property string _stateDir: Paths.strip(_stateUrl)

    property bool isLightMode: false
    property bool doNotDisturb: false
    property real doNotDisturbUntil: 0
    property string terminalOverride: ""
    property bool isSwitchingMode: false
    property bool suppressOSD: true

    readonly property var terminalOptions: ["ghostty", "kitty", "foot", "alacritty", "wezterm", "konsole", "gnome-terminal", "xterm"]
    property var installedTerminals: []

    function resolveTerminal() {
        if (terminalOverride && terminalOverride.length > 0) {
            return terminalOverride;
        }
        const env = Quickshell.env("TERMINAL");
        if (env && env.length > 0) {
            return env;
        }
        return "";
    }

    Process {
        id: terminalProbe
        running: true
        command: ["sh", "-c", "for t in ghostty kitty foot alacritty wezterm konsole gnome-terminal xterm; do command -v \"$t\" >/dev/null 2>&1 && echo \"$t\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.trim().split("\n").filter(line => line.length > 0);
                root.installedTerminals = found;
            }
        }
    }

    Timer {
        id: dndExpireTimer
        repeat: false
        running: false
        onTriggered: root.setDoNotDisturb(false)
    }

    function _armDndExpireTimer() {
        dndExpireTimer.stop();
        if (!doNotDisturb || doNotDisturbUntil <= 0)
            return;
        const remaining = doNotDisturbUntil - Date.now();
        if (remaining <= 0) {
            setDoNotDisturb(false);
            return;
        }
        dndExpireTimer.interval = remaining;
        dndExpireTimer.start();
    }

    onDoNotDisturbChanged: _armDndExpireTimer()
    onDoNotDisturbUntilChanged: _armDndExpireTimer()

    Timer {
        id: osdSuppressTimer
        interval: 2000
        running: true
        onTriggered: root.suppressOSD = false
    }

    Timer {
        id: shellSurfaceContextInitTimer
        interval: 100
        repeat: false
        onTriggered: root.ensureWorkspaceOutputAssignments()
    }

    function suppressOSDTemporarily() {
        suppressOSD = true;
        osdSuppressTimer.restart();
    }

    Connections {
        target: SessionService
        function onSessionResumed() {
            root.suppressOSD = true;
            osdSuppressTimer.restart();
            root._applyDndExpirySanity();
        }
    }

    property string wallpaperPath: ""
    property bool perMonitorWallpaper: false
    property var monitorWallpapers: ({})
    property bool perModeWallpaper: false
    property string wallpaperPathLight: ""
    property string wallpaperPathDark: ""
    property var monitorWallpapersLight: ({})
    property var monitorWallpapersDark: ({})
    property var monitorWallpaperFillModes: ({})

    // Map: screenName -> { scrollX, scrollY } (0-100 range, like workspace percentage)
    property var monitorScrollPositions: ({})

    function setMonitorScrollPosition(screenName, scrollX, scrollY) {
        var newPositions = Object.assign({}, monitorScrollPositions);
        newPositions[screenName] = {
            scrollX: scrollX,
            scrollY: scrollY
        };
        monitorScrollPositions = newPositions;
    }

    function getMonitorScrollPosition(screenName) {
        return monitorScrollPositions[screenName] || {
            scrollX: 50,
            scrollY: 50
        };
    }

    function clearMonitorScrollPosition(screenName) {
        var newPositions = Object.assign({}, monitorScrollPositions);
        delete newPositions[screenName];
        monitorScrollPositions = newPositions;
    }

    property string wallpaperTransition: "fade"
    readonly property var availableWallpaperTransitions: ["none", "fade", "wipe", "disc", "stripes", "iris bloom", "pixelate", "portal"]
    property var includedTransitions: availableWallpaperTransitions.filter(t => t !== "none")

    property bool wallpaperCyclingEnabled: false
    property string wallpaperCyclingMode: "interval"
    property int wallpaperCyclingInterval: 300
    property string wallpaperCyclingTime: "06:00"
    property var monitorCyclingSettings: ({})

    property bool nightModeEnabled: false
    property int nightModeTemperature: 4500
    property int nightModeHighTemperature: 6500
    property bool nightModeAutoEnabled: false
    property string nightModeAutoMode: "time"
    property int nightModeStartHour: 18
    property int nightModeStartMinute: 0
    property int nightModeEndHour: 6
    property int nightModeEndMinute: 0
    property real latitude: 0.0
    property real longitude: 0.0
    property bool nightModeUseIPLocation: false
    property string nightModeLocationProvider: ""

    property bool themeModeAutoEnabled: false
    property string themeModeAutoMode: "time"
    property int themeModeStartHour: 18
    property int themeModeStartMinute: 0
    property int themeModeEndHour: 6
    property int themeModeEndMinute: 0
    property bool themeModeShareGammaSettings: true
    property string themeModeNextTransition: ""

    property var pinnedApps: []
    property var barPinnedApps: []
    property var pinnedAppsByWorkspace: ({})
    property var barPinnedAppsByWorkspace: ({})
    property var workspaceOutputAssignments: ({})
    // Shell surfaces belong to a monitor/workspace pair, just like pins.
    // A disconnected monitor keeps its workspace ids, so its layout returns
    // unchanged when the monitor is connected again.
    property var barWorkspaceContexts: ({})
    property var dockWorkspaceContexts: []
    property bool shellSurfaceContextsInitialized: false
    // Compatibility container for snapshots written by session format 6.
    // They are folded once into the stable numbered context maps below.
    property var workspaceContextSnapshots: ({})
    property bool stableWorkspaceContextMigrationDone: false
    // Alpha.63 could save a standalone dock only against a temporary or
    // disconnected output because Kaskad compositor detection failed.
    property bool dockContextRecoveryDone: false
    // Builds through alpha.65 could run the virtual shell smoke test against
    // the developer's real XDG_STATE_HOME. Recover all shell surfaces after
    // test-only output contexts have been isolated from the user profile.
    property bool shellSurfaceContextRecoveryDone: true
    // Version 11 makes the output role part of the stable surface address.
    // `primary::1` follows the selected primary monitor, `all::1` applies to
    // every monitor, while `HDMI-A-1::1` remains tied to one physical output.
    property bool surfaceContextScopeMigrationDone: true
    property int dockLauncherPosition: 0
    property var hiddenTrayIds: []
    property var trayItemOrder: []
    property var recentColors: []
    property string launchPrefix: ""
    property string lastBrightnessDevice: ""
    property var brightnessExponentialDevices: ({})
    property var brightnessUserSetValues: ({})
    property var brightnessExponentValues: ({})

    property int selectedGpuIndex: 0
    property bool nvidiaGpuTempEnabled: false
    property bool nonNvidiaGpuTempEnabled: false
    property var enabledGpuPciIds: []

    property string wifiDeviceOverride: ""
    property bool weatherHourlyDetailed: true

    property string weatherLocation: "New York, NY"
    property string weatherCoordinates: "40.7128,-74.0060"

    property var hiddenApps: []
    property var appOverrides: ({})
    property bool searchAppActions: true

    property string lastPlayerIdentity: ""

    property var deviceMaxVolumes: ({})
    property var hiddenOutputDeviceNames: []
    property var hiddenInputDeviceNames: []
    property bool microphoneShortcutEnabled: true
    property string microphoneShortcutMode: "toggle"

    property string locale: ""
    property string timeLocale: ""

    property string notepadLastMode: ""

    property string launcherLastMode: "all"
    property string launcherLastFileSearchType: "all"
    property string launcherLastQuery: ""
    property var launcherQueryHistory: []
    property string appDrawerLastMode: "apps"
    property string niriOverviewLastMode: "apps"
    property string settingsSidebarExpandedIds: ","
    property string settingsSidebarCollapsedIds: ","
    property bool showConfigReloadToast: true

    Component.onCompleted: {
        loadSettings();
        Qt.callLater(ensureWorkspaceOutputAssignments);
    }

    Connections {
        target: Kaskad
        function onAvailableChanged() {
            root.ensureWorkspaceOutputAssignments();
        }
        function onOutputsChanged() {
            root.ensureWorkspaceOutputAssignments();
        }
        function onWorkspacesChanged() {
            root.ensureWorkspaceOutputAssignments();
        }
    }

    property var _pendingMigration: null

    function loadSettings() {
        _hasUnsavedChanges = false;
        _pendingMigration = null;

        try {
            const txt = settingsFile.text();
            let obj = (txt && txt.trim()) ? JSON.parse(txt) : null;

            if (obj?.brightnessLogarithmicDevices && !obj?.brightnessExponentialDevices)
                obj.brightnessExponentialDevices = obj.brightnessLogarithmicDevices;

            if (obj?.nightModeStartTime !== undefined) {
                const parts = obj.nightModeStartTime.split(":");
                obj.nightModeStartHour = parseInt(parts[0]) || 18;
                obj.nightModeStartMinute = parseInt(parts[1]) || 0;
            }
            if (obj?.nightModeEndTime !== undefined) {
                const parts = obj.nightModeEndTime.split(":");
                obj.nightModeEndHour = parseInt(parts[0]) || 6;
                obj.nightModeEndMinute = parseInt(parts[1]) || 0;
            }

            const oldVersion = obj?.configVersion ?? 0;
            if (obj && oldVersion === 0)
                migrateFromUndefinedToV1(obj);

            if (obj && oldVersion < sessionConfigVersion) {
                const settingsDataRef = (typeof SettingsData !== "undefined") ? SettingsData : null;
                const migrated = Store.migrateToVersion(obj, sessionConfigVersion, settingsDataRef);
                if (migrated) {
                    _pendingMigration = migrated;
                    obj = migrated;
                }
            }

            Store.parse(root, obj);
            _applyDndExpirySanity();

            _loadedSessionSnapshot = getCurrentSessionJson();
            _hasLoaded = true;

            if (typeof Theme !== "undefined")
                Theme.generateSystemThemesFromCurrentTheme();

            if (typeof WallpaperCyclingService !== "undefined")
                WallpaperCyclingService.updateCyclingState();

            _checkSessionWritable();
        } catch (e) {
            _parseError = true;
            const msg = e.message;
            log.error("Failed to parse session.json - file will not be overwritten.");
            Qt.callLater(() => ToastService.showError(I18n.tr("Failed to parse %1").arg("session.json"), msg));
        }
    }

    function _checkSessionWritable() {
        sessionWritableCheckProcess.running = true;
    }

    function _onWritableCheckComplete(writable) {
        const wasReadOnly = _isReadOnly;
        _isReadOnly = !writable;
        if (_isReadOnly) {
            _hasUnsavedChanges = _checkForUnsavedChanges();
        } else {
            _loadedSessionSnapshot = getCurrentSessionJson();
            _hasUnsavedChanges = false;
            if (wasReadOnly && _pendingMigration)
                settingsFile.setText(JSON.stringify(_pendingMigration, null, 2));
        }
        _pendingMigration = null;
    }

    function _checkForUnsavedChanges() {
        if (!_hasLoaded || !_loadedSessionSnapshot)
            return false;
        const current = getCurrentSessionJson();
        return current !== _loadedSessionSnapshot;
    }

    function getCurrentSessionJson() {
        return JSON.stringify(Store.toJson(root), null, 2);
    }

    function parseSettings(content) {
        _parseError = false;
        try {
            let obj = (content && content.trim()) ? JSON.parse(content) : null;

            if (obj?.brightnessLogarithmicDevices && !obj?.brightnessExponentialDevices)
                obj.brightnessExponentialDevices = obj.brightnessLogarithmicDevices;

            if (obj?.nightModeStartTime !== undefined) {
                const parts = obj.nightModeStartTime.split(":");
                obj.nightModeStartHour = parseInt(parts[0]) || 18;
                obj.nightModeStartMinute = parseInt(parts[1]) || 0;
            }
            if (obj?.nightModeEndTime !== undefined) {
                const parts = obj.nightModeEndTime.split(":");
                obj.nightModeEndHour = parseInt(parts[0]) || 6;
                obj.nightModeEndMinute = parseInt(parts[1]) || 0;
            }

            const oldVersion = obj?.configVersion ?? 0;
            if (obj && oldVersion === 0)
                migrateFromUndefinedToV1(obj);

            if (obj && oldVersion < sessionConfigVersion) {
                const settingsDataRef = (typeof SettingsData !== "undefined") ? SettingsData : null;
                const migrated = Store.migrateToVersion(obj, sessionConfigVersion, settingsDataRef);
                if (migrated) {
                    _pendingMigration = migrated;
                    obj = migrated;
                }
            }

            Store.parse(root, obj);
            _applyDndExpirySanity();

            _loadedSessionSnapshot = getCurrentSessionJson();
            _hasLoaded = true;

            if (typeof Theme !== "undefined")
                Theme.generateSystemThemesFromCurrentTheme();

            if (typeof WallpaperCyclingService !== "undefined")
                WallpaperCyclingService.updateCyclingState();
        } catch (e) {
            _parseError = true;
            const msg = e.message;
            log.error("Failed to parse session.json - file will not be overwritten.");
            Qt.callLater(() => ToastService.showError(I18n.tr("Failed to parse %1").arg("session.json"), msg));
        }
    }

    function _applyDndExpirySanity() {
        if (doNotDisturb && doNotDisturbUntil > 0 && Date.now() >= doNotDisturbUntil) {
            doNotDisturb = false;
            doNotDisturbUntil = 0;
        } else if (!doNotDisturb && doNotDisturbUntil !== 0) {
            doNotDisturbUntil = 0;
        }
        _armDndExpireTimer();
    }

    property bool _lastSaveFailed: false
    property bool _retryingSessionWrite: false

    function saveSettings(waitForCompletion) {
        if (_parseError || !_hasLoaded)
            return false;
        // Finish the queued write before reporting success to editors.
        // blockWrites alone does not guarantee a completed write at setText().
        if (waitForCompletion && _lastSaveFailed) {
            _retryingSessionWrite = true;
            settingsFile.reload();
            settingsFile.waitForJob();
            _retryingSessionWrite = false;
        }
        _lastSaveFailed = false;
        settingsFile.setText(getCurrentSessionJson());
        if (waitForCompletion)
            settingsFile.waitForJob();
        if (_isReadOnly)
            _checkSessionWritable();
        return !_lastSaveFailed;
    }

    function set(key, value) {
        Spec.set(root, key, value, saveSettings, _hooks);
    }

    function migrateFromUndefinedToV1(settings) {
        if (typeof SettingsData !== "undefined") {
            if (settings.acMonitorTimeout !== undefined) {
                SettingsData.set("acMonitorTimeout", settings.acMonitorTimeout);
            }
            if (settings.acLockTimeout !== undefined) {
                SettingsData.set("acLockTimeout", settings.acLockTimeout);
            }
            if (settings.acSuspendTimeout !== undefined) {
                SettingsData.set("acSuspendTimeout", settings.acSuspendTimeout);
            }
            if (settings.acHibernateTimeout !== undefined) {
                SettingsData.set("acHibernateTimeout", settings.acHibernateTimeout);
            }
            if (settings.batteryMonitorTimeout !== undefined) {
                SettingsData.set("batteryMonitorTimeout", settings.batteryMonitorTimeout);
            }
            if (settings.batteryLockTimeout !== undefined) {
                SettingsData.set("batteryLockTimeout", settings.batteryLockTimeout);
            }
            if (settings.batterySuspendTimeout !== undefined) {
                SettingsData.set("batterySuspendTimeout", settings.batterySuspendTimeout);
            }
            if (settings.batteryHibernateTimeout !== undefined) {
                SettingsData.set("batteryHibernateTimeout", settings.batteryHibernateTimeout);
            }
            if (settings.lockBeforeSuspend !== undefined) {
                SettingsData.set("lockBeforeSuspend", settings.lockBeforeSuspend);
            }
            if (settings.loginctlLockIntegration !== undefined) {
                SettingsData.set("loginctlLockIntegration", settings.loginctlLockIntegration);
            }
            if (settings.launchPrefix !== undefined) {
                SettingsData.set("launchPrefix", settings.launchPrefix);
            }
        }
        if (typeof CacheData !== "undefined") {
            if (settings.wallpaperLastPath !== undefined) {
                CacheData.wallpaperLastPath = settings.wallpaperLastPath;
            }
            if (settings.profileLastPath !== undefined) {
                CacheData.profileLastPath = settings.profileLastPath;
            }
            CacheData.saveCache();
        }
    }

    function setLightMode(lightMode) {
        isSwitchingMode = true;
        syncWallpaperForCurrentMode(lightMode);
        isLightMode = lightMode;
        saveSettings();
        Qt.callLater(() => {
            isSwitchingMode = false;
        });
    }

    function setDoNotDisturb(enabled, durationMinutes) {
        const minutes = Number(durationMinutes) || 0;
        doNotDisturb = enabled;
        doNotDisturbUntil = (enabled && minutes > 0) ? Date.now() + minutes * 60 * 1000 : 0;
        saveSettings();
    }

    function setDoNotDisturbUntilTimestamp(timestampMs) {
        const target = Number(timestampMs) || 0;
        if (target <= Date.now()) {
            setDoNotDisturb(false);
            return;
        }
        doNotDisturb = true;
        doNotDisturbUntil = target;
        saveSettings();
    }

    function setWallpaperPath(path) {
        wallpaperPath = path;
        saveSettings();
    }

    function setWallpaper(imagePath) {
        wallpaperPath = imagePath;
        if (perModeWallpaper) {
            if (isLightMode) {
                wallpaperPathLight = imagePath;
            } else {
                wallpaperPathDark = imagePath;
            }
        }
        saveSettings();

        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function setWallpaperColor(color) {
        wallpaperPath = color;
        if (perModeWallpaper) {
            if (isLightMode) {
                wallpaperPathLight = color;
            } else {
                wallpaperPathDark = color;
            }
        }
        saveSettings();

        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function clearWallpaper() {
        wallpaperPath = "";
        saveSettings();

        if (typeof Theme !== "undefined") {
            if (typeof SettingsData !== "undefined" && SettingsData.theme) {
                Theme.switchTheme(SettingsData.theme);
            } else {
                Theme.switchTheme("kaskados");
            }
        }
    }

    function setPerMonitorWallpaper(enabled) {
        perMonitorWallpaper = enabled;
        if (enabled && perModeWallpaper) {
            syncWallpaperForCurrentMode();
        }
        saveSettings();

        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function setPerModeWallpaper(enabled) {
        if (enabled && wallpaperCyclingEnabled) {
            setWallpaperCyclingEnabled(false);
        }
        if (enabled && perMonitorWallpaper) {
            var monitorCyclingAny = false;
            for (var key in monitorCyclingSettings) {
                if (monitorCyclingSettings[key].enabled) {
                    monitorCyclingAny = true;
                    break;
                }
            }
            if (monitorCyclingAny) {
                var newSettings = Object.assign({}, monitorCyclingSettings);
                for (var screenName in newSettings) {
                    newSettings[screenName].enabled = false;
                }
                monitorCyclingSettings = newSettings;
            }
        }

        perModeWallpaper = enabled;
        if (enabled) {
            if (perMonitorWallpaper) {
                monitorWallpapersLight = Object.assign({}, monitorWallpapers);
                monitorWallpapersDark = Object.assign({}, monitorWallpapers);
            } else {
                wallpaperPathLight = wallpaperPath;
                wallpaperPathDark = wallpaperPath;
            }
        } else {
            syncWallpaperForCurrentMode();
        }
        saveSettings();

        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function setMonitorWallpaper(screenName, path) {
        var screen = null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }

        if (!screen) {
            log.warn("Screen not found");
            return;
        }

        var identifier = typeof SettingsData !== "undefined" ? SettingsData.getScreenDisplayName(screen) : screen.name;

        var newMonitorWallpapers = {};
        for (var key in monitorWallpapers) {
            var isThisScreen = key === screen.name || (screen.model && key === screen.model);
            if (!isThisScreen) {
                newMonitorWallpapers[key] = monitorWallpapers[key];
            }
        }

        if (path && path !== "") {
            newMonitorWallpapers[identifier] = path;
        }

        monitorWallpapers = newMonitorWallpapers;

        if (perModeWallpaper) {
            if (isLightMode) {
                var newLight = {};
                for (var key in monitorWallpapersLight) {
                    var isThisScreen = key === screen.name || (screen.model && key === screen.model);
                    if (!isThisScreen) {
                        newLight[key] = monitorWallpapersLight[key];
                    }
                }
                if (path && path !== "") {
                    newLight[identifier] = path;
                }
                monitorWallpapersLight = newLight;
            } else {
                var newDark = {};
                for (var key in monitorWallpapersDark) {
                    var isThisScreen = key === screen.name || (screen.model && key === screen.model);
                    if (!isThisScreen) {
                        newDark[key] = monitorWallpapersDark[key];
                    }
                }
                if (path && path !== "") {
                    newDark[identifier] = path;
                }
                monitorWallpapersDark = newDark;
            }
        }

        saveSettings();

        if (typeof Theme !== "undefined" && typeof Quickshell !== "undefined" && typeof SettingsData !== "undefined") {
            var screens = Quickshell.screens;
            if (screens.length > 0) {
                var targetMonitor = (SettingsData.matugenTargetMonitor && SettingsData.matugenTargetMonitor !== "") ? SettingsData.matugenTargetMonitor : screens[0].name;
                if (screenName === targetMonitor) {
                    Theme.generateSystemThemesFromCurrentTheme();
                }
            }
        }
    }

    function setWallpaperTransition(transition) {
        wallpaperTransition = transition;
        saveSettings();
    }

    function setWallpaperCyclingEnabled(enabled) {
        wallpaperCyclingEnabled = enabled;
        saveSettings();
    }

    function setWallpaperCyclingMode(mode) {
        wallpaperCyclingMode = mode;
        saveSettings();
    }

    function setWallpaperCyclingInterval(interval) {
        wallpaperCyclingInterval = interval;
        saveSettings();
    }

    function setWallpaperCyclingTime(time) {
        wallpaperCyclingTime = time;
        saveSettings();
    }

    function setMonitorCyclingEnabled(screenName, enabled) {
        var screen = null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }

        if (!screen) {
            log.warn("Screen not found");
            return;
        }

        var identifier = typeof SettingsData !== "undefined" ? SettingsData.getScreenDisplayName(screen) : screen.name;

        var newSettings = {};
        for (var key in monitorCyclingSettings) {
            var isThisScreen = key === screen.name || (screen.model && key === screen.model);
            if (!isThisScreen) {
                newSettings[key] = monitorCyclingSettings[key];
            }
        }

        newSettings[identifier] = getMonitorCyclingSettings(screenName);
        newSettings[identifier].enabled = enabled;
        monitorCyclingSettings = newSettings;
        saveSettings();
    }

    function setMonitorCyclingMode(screenName, mode) {
        var screen = null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }

        if (!screen) {
            log.warn("Screen not found");
            return;
        }

        var identifier = typeof SettingsData !== "undefined" ? SettingsData.getScreenDisplayName(screen) : screen.name;

        var newSettings = {};
        for (var key in monitorCyclingSettings) {
            var isThisScreen = key === screen.name || (screen.model && key === screen.model);
            if (!isThisScreen) {
                newSettings[key] = monitorCyclingSettings[key];
            }
        }

        newSettings[identifier] = getMonitorCyclingSettings(screenName);
        newSettings[identifier].mode = mode;
        monitorCyclingSettings = newSettings;
        saveSettings();
    }

    function setMonitorCyclingInterval(screenName, interval) {
        var screen = null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }

        if (!screen) {
            log.warn("Screen not found");
            return;
        }

        var identifier = typeof SettingsData !== "undefined" ? SettingsData.getScreenDisplayName(screen) : screen.name;

        var newSettings = {};
        for (var key in monitorCyclingSettings) {
            var isThisScreen = key === screen.name || (screen.model && key === screen.model);
            if (!isThisScreen) {
                newSettings[key] = monitorCyclingSettings[key];
            }
        }

        newSettings[identifier] = getMonitorCyclingSettings(screenName);
        newSettings[identifier].interval = interval;
        monitorCyclingSettings = newSettings;
        saveSettings();
    }

    function setMonitorCyclingTime(screenName, time) {
        var screen = null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }

        if (!screen) {
            log.warn("Screen not found");
            return;
        }

        var identifier = typeof SettingsData !== "undefined" ? SettingsData.getScreenDisplayName(screen) : screen.name;

        var newSettings = {};
        for (var key in monitorCyclingSettings) {
            var isThisScreen = key === screen.name || (screen.model && key === screen.model);
            if (!isThisScreen) {
                newSettings[key] = monitorCyclingSettings[key];
            }
        }

        newSettings[identifier] = getMonitorCyclingSettings(screenName);
        newSettings[identifier].time = time;
        monitorCyclingSettings = newSettings;
        saveSettings();
    }

    function setNightModeEnabled(enabled) {
        nightModeEnabled = enabled;
        saveSettings();
    }

    function setNightModeTemperature(temperature) {
        nightModeTemperature = temperature;
        saveSettings();
    }

    function setNightModeHighTemperature(temperature) {
        nightModeHighTemperature = temperature;
        saveSettings();
    }

    function setNightModeAutoEnabled(enabled) {
        nightModeAutoEnabled = enabled;
        saveSettings();
    }

    function setNightModeAutoMode(mode) {
        nightModeAutoMode = mode;
        saveSettings();
    }

    function setNightModeStartHour(hour) {
        nightModeStartHour = hour;
        saveSettings();
    }

    function setNightModeStartMinute(minute) {
        nightModeStartMinute = minute;
        saveSettings();
    }

    function setNightModeEndHour(hour) {
        nightModeEndHour = hour;
        saveSettings();
    }

    function setNightModeEndMinute(minute) {
        nightModeEndMinute = minute;
        saveSettings();
    }

    function setNightModeUseIPLocation(use) {
        nightModeUseIPLocation = use;
        saveSettings();
    }

    function setLatitude(lat) {
        latitude = lat;
        saveSettings();
    }

    function setLongitude(lng) {
        longitude = lng;
        saveSettings();
    }

    function setNightModeLocationProvider(provider) {
        nightModeLocationProvider = provider;
        saveSettings();
    }

    function setThemeModeAutoEnabled(enabled) {
        themeModeAutoEnabled = enabled;
        saveSettings();
    }

    function setThemeModeAutoMode(mode) {
        themeModeAutoMode = mode;
        saveSettings();
    }

    function setThemeModeStartHour(hour) {
        themeModeStartHour = hour;
        saveSettings();
    }

    function setThemeModeStartMinute(minute) {
        themeModeStartMinute = minute;
        saveSettings();
    }

    function setThemeModeEndHour(hour) {
        themeModeEndHour = hour;
        saveSettings();
    }

    function setThemeModeEndMinute(minute) {
        themeModeEndMinute = minute;
        saveSettings();
    }

    function setThemeModeShareGammaSettings(share) {
        themeModeShareGammaSettings = share;
        saveSettings();
    }

    function _pinScreenName(screenName) {
        if (screenName)
            return screenName;
        const screen = CompositorService.getInteractionScreen();
        return screen?.name || "primary";
    }

    function _contextSlot(key) {
        const separator = String(key || "").indexOf("::");
        if (separator < 1)
            return 0;
        const slot = Number(String(key).slice(separator + 2));
        return Number.isInteger(slot) && slot > 0 ? slot : 0;
    }

    function _isPrimaryOnlyPreference(preferences) {
        const prefs = Array.from(preferences || []);
        return prefs.length === 1 && prefs[0] === "primary";
    }

    function _isAllScreensPreference(preferences) {
        const prefs = Array.from(preferences || []);
        return prefs.length === 0 || prefs.includes("all");
    }

    function _barContextScope(barId, outputName) {
        const bar = SettingsData.getBarConfig(barId);
        const preferences = bar?.screenPreferences || ["all"];
        if (_isPrimaryOnlyPreference(preferences))
            return "primary";
        if (_isAllScreensPreference(preferences))
            return "all";
        return outputName;
    }

    function _dockContextScope(outputName) {
        const preferences = SettingsData.screenPreferences?.dock || ["primary"];
        if (_isPrimaryOnlyPreference(preferences))
            return "primary";
        if (_isAllScreensPreference(preferences))
            return "all";
        return outputName;
    }

    function _scopedContextKey(physicalKey, scope) {
        const slot = _contextSlot(physicalKey);
        return slot > 0 && scope ? scope + "::" + slot : "";
    }

    function _contextListContains(contexts, outputName, physicalKey) {
        const slot = _contextSlot(physicalKey);
        if (!slot)
            return false;
        const values = Array.from(contexts || []);
        if (values.includes(outputName + "::" + slot) || values.includes("all::" + slot))
            return true;
        const primary = CompositorService.getPrimaryScreen();
        return !!primary && primary.name === outputName && values.includes("primary::" + slot);
    }

    function contextListsOverlap(leftContexts, rightContexts) {
        const primaryName = CompositorService.getPrimaryScreen()?.name || "";
        function resolvedScope(key) {
            const separator = String(key || "").indexOf("::");
            const scope = separator > 0 ? String(key).slice(0, separator) : "";
            return scope === "primary" ? primaryName : scope;
        }
        for (const left of Array.from(leftContexts || [])) {
            const leftSlot = _contextSlot(left);
            if (!leftSlot)
                continue;
            const leftScope = resolvedScope(left);
            for (const right of Array.from(rightContexts || [])) {
                if (_contextSlot(right) !== leftSlot)
                    continue;
                const rightScope = resolvedScope(right);
                if (leftScope === "all" || rightScope === "all" || (leftScope && leftScope === rightScope))
                    return true;
            }
        }
        return false;
    }

    function _contextScopesForPreferences(preferences) {
        const prefs = Array.from(preferences || []);
        if (_isPrimaryOnlyPreference(prefs))
            return ["primary"];
        if (_isAllScreensPreference(prefs))
            return ["all"];

        const scopes = [];
        for (const preference of prefs) {
            let name = typeof preference === "string" ? preference : (preference?.name || "");
            if (typeof preference === "string") {
                const connected = Array.from(Quickshell.screens || []).find(screen =>
                    screen?.name === preference
                        || SettingsData.getScreenDisplayName(screen) === preference
                        || screen?.model === preference);
                const remembered = Array.from(SettingsData.rememberedMonitors || []).find(monitor =>
                    monitor?.name === preference || monitor?.model === preference);
                name = connected?.name || remembered?.name || preference;
            } else if (preference) {
                const connected = Array.from(Quickshell.screens || []).find(screen =>
                    SettingsData.isScreenInPreferences(screen, [preference]));
                name = connected?.name || preference.name || "";
            }
            if (name && name !== "primary" && name !== "all" && !scopes.includes(name))
                scopes.push(name);
        }
        // A monitor identified by model may return through a different port.
        // Resolve it to the connector currently exposed by the compositor,
        // while retaining the remembered connector for a disconnected screen.
        for (const screen of Array.from(Quickshell.screens || [])) {
            if (SettingsData.isScreenInPreferences(screen, prefs) && !scopes.includes(screen.name))
                scopes.push(screen.name);
        }
        return scopes;
    }

    function _reconcileContextScopes(contexts, preferences) {
        const current = Array.from(contexts || []);
        const scopes = _contextScopesForPreferences(preferences);
        if (scopes.length === 0)
            return [];

        const allSlots = Array.from(new Set(current.map(_contextSlot).filter(slot => slot > 0)));
        const fallbackSlots = allSlots.length > 0 ? allSlots : [1];

        // A role applies the same local workspace number to whichever output
        // currently fulfils that role. Collapsing different physical scopes
        // must therefore select one slot, never create a Cartesian product.
        if (scopes.length === 1 && (scopes[0] === "primary" || scopes[0] === "all")) {
            const role = scopes[0];
            const existingRoleSlot = current
                .filter(key => String(key).startsWith(role + "::"))
                .map(_contextSlot)
                .find(slot => slot > 0);
            const preferredOutput = CompositorService.getPrimaryScreen()?.name || interactionScreenName();
            const preferredSlot = current
                .filter(key => String(key).startsWith(preferredOutput + "::"))
                .map(_contextSlot)
                .find(slot => slot > 0);
            return [role + "::" + (existingRoleSlot || preferredSlot || fallbackSlots[0])];
        }

        const next = [];
        for (const scope of scopes) {
            let slots = current
                .filter(key => String(key).startsWith(scope + "::"))
                .map(_contextSlot)
                .filter(slot => slot > 0);
            if (slots.length === 0 && scope !== "primary" && scope !== "all") {
                const physical = currentWorkspaceContext(scope);
                const currentSlot = _contextSlot(physical);
                if (currentSlot > 0)
                    slots = [currentSlot];
            }
            if (slots.length === 0)
                slots = fallbackSlots;
            for (const slot of Array.from(new Set(slots)))
                next.push(scope + "::" + slot);
        }
        return Array.from(new Set(next));
    }

    function reconcileBarScreenPreferences(barId, preferences) {
        if (!barId)
            return;
        const next = JSON.parse(JSON.stringify(barWorkspaceContexts || {}));
        const contexts = _reconcileContextScopes(next[barId] || [], preferences);
        if (contexts.length > 0)
            next[barId] = contexts;
        else
            delete next[barId];
        barWorkspaceContexts = next;
        saveSettings();
    }

    function reconcileDockScreenPreferences(preferences) {
        dockWorkspaceContexts = _reconcileContextScopes(dockWorkspaceContexts || [], preferences);
        saveSettings();
    }

    function ensureWorkspaceOutputAssignments() {
        if (!_hasLoaded || !Kaskad.available)
            return;
        const outputs = Array.from(Kaskad.outputs || [])
            .filter(output => output && output.enabled !== false)
            .map(output => output.name)
            .filter(name => !!name);
        const workspaces = Array.from(Kaskad.workspaces || []).sort((a, b) => a.position - b.position);
        if (outputs.length === 0 || workspaces.length === 0)
            return;

        const validIds = new Set(workspaces.map(workspace => workspace.id));

        // The compositor is the source of truth. The session copy only
        // migrates installations created before output ownership was stored
        // by VirtualDesktopManager itself.
        const next = {};
        for (const workspace of workspaces) {
            if (workspace.output)
                next[workspace.id] = workspace.output;
        }
        for (const workspaceId in workspaceOutputAssignments || {}) {
            if (validIds.has(workspaceId) && !next[workspaceId])
                next[workspaceId] = workspaceOutputAssignments[workspaceId];
        }

        const assignedIds = new Set(Object.keys(next));
        const outputsWithWorkspace = new Set(Object.values(next));

        // Existing windows are the strongest ownership signal during the
        // one-time migration from the old global workspace list.
        for (const workspace of workspaces) {
            if (assignedIds.has(workspace.id))
                continue;
            const windowOutputs = new Set(Array.from(Kaskad.windows || [])
                .filter(window => Array.from(window.workspaces || []).includes(workspace.id) && !!window.output)
                .map(window => window.output));
            if (windowOutputs.size === 1) {
                const owner = Array.from(windowOutputs)[0];
                next[workspace.id] = owner;
                assignedIds.add(workspace.id);
                outputsWithWorkspace.add(owner);
            }
        }

        // Preserve the desktop each output was showing before the migration.
        for (const outputName of outputs) {
            const current = workspaces.find(workspace =>
                !assignedIds.has(workspace.id)
                    && Array.from(workspace.currentOutputs || []).includes(outputName));
            if (current) {
                next[current.id] = outputName;
                assignedIds.add(current.id);
                outputsWithWorkspace.add(outputName);
            }
        }

        // Give every connected output at least one of the remaining desktops.
        for (const outputName of outputs) {
            if (outputsWithWorkspace.has(outputName))
                continue;
            const available = workspaces.find(workspace => !assignedIds.has(workspace.id));
            if (!available)
                break;
            next[available.id] = outputName;
            assignedIds.add(available.id);
            outputsWithWorkspace.add(outputName);
        }

        // Legacy surplus desktops stay with the primary display.
        const primaryName = CompositorService.getPrimaryScreen()?.name || outputs[0];
        for (const workspace of workspaces) {
            if (!assignedIds.has(workspace.id))
                next[workspace.id] = primaryName;
        }

        // Surface and pin configuration uses stable local workspace numbers
        // (output::1, output::2, ...), never compositor UUIDs. Dynamic
        // workspaces may be destroyed and recreated with a different UUID,
        // while their numbered configuration must survive unchanged.
        function canonicalContextKey(key) {
            const separator = String(key || "").indexOf("::");
            if (separator < 1)
                return "";
            const storedOutput = key.slice(0, separator);
            const suffix = key.slice(separator + 2);
            if (/^[1-9][0-9]*$/.test(suffix))
                return storedOutput + "::" + Number(suffix);
            if (!validIds.has(suffix))
                return "";
            const owner = next[suffix] || storedOutput;
            const local = workspaces
                .filter(workspace => next[workspace.id] === owner)
                .sort((a, b) => a.position - b.position);
            const index = local.findIndex(workspace => workspace.id === suffix);
            return index >= 0 ? owner + "::" + (index + 1) : "";
        }
        function canonicalPinMap(source) {
            const result = {};
            for (const key in source || {}) {
                const canonical = canonicalContextKey(key);
                if (!canonical)
                    continue;
                result[canonical] = Array.from(new Set([...(result[canonical] || []), ...(source[key] || [])]));
            }
            return result;
        }
        function canonicalContextList(source) {
            return Array.from(new Set(Array.from(source || []).map(canonicalContextKey).filter(key => !!key)));
        }

        const canonicalDockPins = canonicalPinMap(pinnedAppsByWorkspace);
        const canonicalBarPins = canonicalPinMap(barPinnedAppsByWorkspace);
        const canonicalDockContexts = canonicalContextList(dockWorkspaceContexts);
        const canonicalBarContexts = {};
        for (const barId in barWorkspaceContexts || {}) {
            const contexts = canonicalContextList(barWorkspaceContexts[barId]);
            if (contexts.length > 0)
                canonicalBarContexts[barId] = contexts;
        }
        // Fold snapshots created by version 6 into the stable numbered store.
        for (const snapshotKey in workspaceContextSnapshots || {}) {
            const canonical = canonicalContextKey(snapshotKey);
            const snapshot = workspaceContextSnapshots[snapshotKey] || {};
            if (!canonical)
                continue;
            for (const barId of Array.from(snapshot.barIds || [])) {
                const contexts = Array.from(canonicalBarContexts[barId] || []);
                if (!contexts.includes(canonical))
                    contexts.push(canonical);
                canonicalBarContexts[barId] = contexts;
            }
            if (snapshot.dock && !canonicalDockContexts.includes(canonical))
                canonicalDockContexts.push(canonical);
            canonicalDockPins[canonical] = Array.from(new Set([
                ...(canonicalDockPins[canonical] || []), ...(snapshot.pinnedApps || [])]));
            canonicalBarPins[canonical] = Array.from(new Set([
                ...(canonicalBarPins[canonical] || []), ...(snapshot.barPinnedApps || [])]));
        }

        let pinScopesChanged = false;

        // Output roles and physical outputs used to be two independent
        // filters. A primary-only panel could therefore be allowed on HDMI
        // by screenPreferences while its workspace context still allowed
        // only eDP, producing no panel at all. Fold those two dimensions into
        // one stable address. Hotplug now only resolves the role; it never
        // mutates the saved placement.
        if (!surfaceContextScopeMigrationDone) {
            if (!SettingsData._hasLoaded) {
                shellSurfaceContextInitTimer.restart();
            } else {
                for (const bar of SettingsData.barConfigs || []) {
                    if (!bar?.id)
                        continue;
                    let scope = "";
                    if (_isPrimaryOnlyPreference(bar.screenPreferences || ["all"]))
                        scope = "primary";
                    else if (_isAllScreensPreference(bar.screenPreferences || ["all"]))
                        scope = "all";
                    if (!scope)
                        continue;
                    const scoped = Array.from(new Set(Array.from(canonicalBarContexts[bar.id] || [])
                        .map(context => _scopedContextKey(context, scope))
                        .filter(context => !!context)));
                    if (scoped.length > 0)
                        canonicalBarContexts[bar.id] = scoped;
                }

                const dockPreferences = SettingsData.screenPreferences?.dock || ["primary"];
                let dockScope = "";
                if (_isPrimaryOnlyPreference(dockPreferences))
                    dockScope = "primary";
                else if (_isAllScreensPreference(dockPreferences))
                    dockScope = "all";
                if (dockScope) {
                    const scopedDock = Array.from(new Set(canonicalDockContexts
                        .map(context => _scopedContextKey(context, dockScope))
                        .filter(context => !!context)));
                    if (scopedDock.length > 0) {
                        canonicalDockContexts.length = 0;
                        canonicalDockContexts.push(...scopedDock);
                    }
                }
                surfaceContextScopeMigrationDone = true;
                pinScopesChanged = true;
            }
        }

        // One-time repair for profiles contaminated by a virtual compositor
        // smoke or nested development session. Do not infer test outputs by
        // their names: compare saved placements with the real compositor
        // topology. Disconnected placements are deliberately retained.
        if (!shellSurfaceContextRecoveryDone) {
            if (!SettingsData._hasLoaded) {
                shellSurfaceContextInitTimer.restart();
            } else {
                const rememberedOutputs = Array.from(new Set(Object.values(workspaceOutputAssignments || {})
                    .filter(outputName => !!outputName)));
                const outputsReady = rememberedOutputs.length === 0
                    || outputs.some(outputName => rememberedOutputs.includes(outputName));

                if (!outputsReady) {
                    shellSurfaceContextInitTimer.restart();
                } else {
                    const connectedScreens = Array.from(Quickshell.screens || [])
                        .filter(screen => screen?.name && outputs.includes(screen.name));
                    const preferredOutputs = Array.from(new Set([
                        CompositorService.getFocusedScreen()?.name || "",
                        CompositorService.getPrimaryScreen()?.name || "",
                        ...rememberedOutputs,
                        ...outputs
                    ].filter(outputName => outputs.includes(outputName))));

                    function contextForOutput(outputName) {
                        const local = workspaces
                            .filter(workspace => next[workspace.id] === outputName)
                            .sort((a, b) => a.position - b.position);
                        if (local.length === 0)
                            return "";
                        const current = local.find(workspace =>
                            Array.from(workspace.currentOutputs || []).includes(outputName));
                        const index = current ? local.indexOf(current) : 0;
                        return outputName + "::" + (index + 1);
                    }

                    let recoveryComplete = true;
                    for (const bar of SettingsData.barConfigs || []) {
                        if (!bar?.id || !(bar.enabled ?? false))
                            continue;
                        const saved = Array.from(canonicalBarContexts[bar.id] || []);
                        const hasConnectedContext = saved.some(context => {
                            const slot = _contextSlot(context);
                            return slot > 0 && outputs.some(outputName =>
                                _contextListContains([context], outputName, outputName + "::" + slot));
                        });
                        if (hasConnectedContext)
                            continue;

                        let candidates = connectedScreens
                            .filter(screen => SettingsData.isScreenInPreferences(
                                screen, bar.screenPreferences || ["all"]))
                            .map(screen => screen.name);
                        if (candidates.length === 0)
                            candidates = preferredOutputs.slice(0, 1);
                        const targetOutput = candidates.find(outputName => !!contextForOutput(outputName)) || "";
                        const physicalContext = contextForOutput(targetOutput);
                        const targetContext = _scopedContextKey(
                            physicalContext, _barContextScope(bar.id, targetOutput));
                        if (!targetContext) {
                            recoveryComplete = false;
                            continue;
                        }
                        canonicalBarContexts[bar.id] = Array.from(new Set([...saved, targetContext]));
                    }

                    const hasConnectedDock = canonicalDockContexts.some(context => {
                        const slot = _contextSlot(context);
                        return slot > 0 && outputs.some(outputName =>
                            _contextListContains([context], outputName, outputName + "::" + slot));
                    });
                    if (SettingsData.showDock && !hasConnectedDock) {
                        const dockScreens = Array.from(SettingsData.getFilteredScreens("dock") || [])
                            .map(screen => screen?.name || "")
                            .filter(outputName => outputs.includes(outputName));
                        const candidates = dockScreens.length > 0 ? dockScreens : preferredOutputs;
                        const targetOutput = candidates.find(outputName => !!contextForOutput(outputName)) || "";
                        const physicalContext = contextForOutput(targetOutput);
                        const targetContext = _scopedContextKey(
                            physicalContext, _dockContextScope(targetOutput));
                        if (targetContext)
                            canonicalDockContexts.push(targetContext);
                        else
                            recoveryComplete = false;
                    }

                    shellSurfaceContextRecoveryDone = recoveryComplete;
                    dockContextRecoveryDone = recoveryComplete;
                    pinScopesChanged = recoveryComplete;
                    if (!recoveryComplete)
                        shellSurfaceContextInitTimer.restart();
                }
            }
        }

        // Version 6 could leave a bar config alive after losing its UUID
        // context. Preserve every such user-created panel by assigning it the
        // next free logical slot on its selected output. This is a one-time
        // recovery; normal edits always write their stable slot immediately.
        if (!stableWorkspaceContextMigrationDone) {
            if (!SettingsData._hasLoaded) {
                shellSurfaceContextInitTimer.restart();
            } else {
                for (const bar of SettingsData.barConfigs || []) {
                    if (!bar?.id || !(bar.enabled ?? false) || canonicalBarContexts[bar.id]?.length > 0)
                        continue;
                    const selectedScreens = Array.from(Quickshell.screens || []).filter(screen =>
                        SettingsData.isScreenInPreferences(screen, bar.screenPreferences || ["all"]));
                    for (const screen of selectedScreens) {
                        const prefix = screen.name + "::";
                        const used = new Set();
                        for (const existingBarId in canonicalBarContexts) {
                            for (const context of canonicalBarContexts[existingBarId] || []) {
                                if (context.startsWith(prefix))
                                    used.add(Number(context.slice(prefix.length)));
                            }
                        }
                        let slot = 1;
                        while (used.has(slot))
                            slot++;
                        canonicalBarContexts[bar.id] = [
                            _scopedContextKey(prefix + slot, _barContextScope(bar.id, screen.name))
                        ];
                    }
                }
                stableWorkspaceContextMigrationDone = true;
                pinScopesChanged = true;
            }
        }

        if (JSON.stringify(canonicalDockPins) !== JSON.stringify(pinnedAppsByWorkspace || {})) {
            pinnedAppsByWorkspace = canonicalDockPins;
            pinScopesChanged = true;
        }
        if (JSON.stringify(canonicalBarPins) !== JSON.stringify(barPinnedAppsByWorkspace || {})) {
            barPinnedAppsByWorkspace = canonicalBarPins;
            pinScopesChanged = true;
        }
        if (shellSurfaceContextsInitialized
                && JSON.stringify(canonicalDockContexts) !== JSON.stringify(dockWorkspaceContexts || [])) {
            dockWorkspaceContexts = canonicalDockContexts;
            pinScopesChanged = true;
        }
        if (shellSurfaceContextsInitialized
                && JSON.stringify(canonicalBarContexts) !== JSON.stringify(barWorkspaceContexts || {})) {
            barWorkspaceContexts = canonicalBarContexts;
            pinScopesChanged = true;
        }
        if (Object.keys(workspaceContextSnapshots || {}).length > 0) {
            workspaceContextSnapshots = {};
            pinScopesChanged = true;
        }

        if (JSON.stringify(next) !== JSON.stringify(workspaceOutputAssignments || {})) {
            workspaceOutputAssignments = next;
            saveSettings();
        } else if (pinScopesChanged)
            saveSettings();

        // Mirror ownership into the compositor. This keeps global shortcuts,
        // touchpad gestures and the shell switcher on the same per-output list.
        for (const workspace of workspaces) {
            const owner = next[workspace.id] || "";
            if (owner && workspace.output !== owner)
                Kaskad.assignWorkspaceToOutput(workspace.id, owner);
        }

        // If two outputs previously shared one global current desktop, move
        // each output to the first desktop that now belongs to it.
        for (const outputName of outputs) {
            const ownsCurrent = workspaces.some(workspace =>
                next[workspace.id] === outputName
                    && Array.from(workspace.currentOutputs || []).includes(outputName));
            if (ownsCurrent)
                continue;
            const target = workspaces.find(workspace => next[workspace.id] === outputName);
            if (target)
                Kaskad.activateWorkspaceOnOutput(target.id, outputName);
        }
        ensureShellSurfaceContexts(outputs, workspaces, next);
        migrateLegacyPinScopes();
    }

    function _workspaceContextKey(outputName, workspaceId) {
        if (!outputName || !workspaceId)
            return "";
        const workspaces = Array.from(Kaskad.workspaces || [])
            .filter(workspace => {
                const assignedOutput = (workspaceOutputAssignments || {})[workspace.id] || workspace.output || "";
                return assignedOutput === outputName;
            })
            .sort((a, b) => a.position - b.position);
        const index = workspaces.findIndex(workspace => workspace.id === workspaceId);
        if (index < 0)
            return "";
        return outputName + "::" + (index + 1);
    }

    function currentWorkspaceIdForOutput(outputName) {
        if (!outputName)
            return "";
        const workspace = Array.from(Kaskad.workspaces || []).find(item =>
            Array.from(item.currentOutputs || []).includes(outputName));
        return workspace?.id || "";
    }

    function currentWorkspaceContext(outputName) {
        return _workspaceContextKey(outputName, currentWorkspaceIdForOutput(outputName));
    }

    function ensureShellSurfaceContexts(outputs, workspaces, assignments) {
        if (!_hasLoaded || shellSurfaceContextsInitialized)
            return;
        if (!SettingsData._hasLoaded) {
            shellSurfaceContextInitTimer.restart();
            return;
        }
        const primaryName = CompositorService.getPrimaryScreen()?.name || outputs[0] || "";
        const nextBars = {};
        const bars = SettingsData.barConfigs || [];

        for (const bar of bars) {
            if (!bar || !bar.id || !(bar.enabled ?? false))
                continue;
            const contexts = [];
            for (const outputName of outputs) {
                const screen = Array.from(Quickshell.screens || []).find(item => item.name === outputName);
                if (!screen || !SettingsData.isScreenInPreferences(screen, bar.screenPreferences || ["all"]))
                    continue;
                const workspace = workspaces.find(item =>
                    assignments[item.id] === outputName
                        && Array.from(item.currentOutputs || []).includes(outputName));
                const physicalKey = _workspaceContextKey(outputName, workspace?.id || "");
                const key = _scopedContextKey(physicalKey, _barContextScope(bar.id, outputName));
                if (key)
                    contexts.push(key);
            }
            if (contexts.length > 0)
                nextBars[bar.id] = Array.from(new Set(contexts));
        }

        const nextDock = [];
        if (SettingsData.showDock) {
            const dockScreens = SettingsData.getFilteredScreens("dock") || [];
            for (const screen of dockScreens) {
                // The factory layout exists only on workspace 01 of the
                // primary monitor. Other monitor/workspace layouts begin
                // empty and are enabled explicitly by the user.
                if (screen.name !== primaryName)
                    continue;
                const physicalKey = currentWorkspaceContext(screen.name);
                const key = _scopedContextKey(physicalKey, _dockContextScope(screen.name));
                if (key)
                    nextDock.push(key);
            }
        }

        barWorkspaceContexts = nextBars;
        dockWorkspaceContexts = nextDock;
        shellSurfaceContextsInitialized = true;
        saveSettings();
    }

    function isBarVisibleInContext(barId, outputName, workspaceId) {
        if (!CompositorService.isKaskad || !Kaskad.available)
            return true;
        if (!shellSurfaceContextsInitialized)
            return false;
        // A migration must never leave the desktop without navigation while
        // physical outputs are still replacing the startup placeholder.
        if (!shellSurfaceContextRecoveryDone)
            return true;
        const key = _workspaceContextKey(outputName, workspaceId || currentWorkspaceIdForOutput(outputName));
        return !!key && _contextListContains((barWorkspaceContexts || {})[barId] || [], outputName, key);
    }

    function setBarVisibleInContext(barId, outputName, workspaceId, visible) {
        if (!CompositorService.isKaskad || !Kaskad.available)
            return;
        const physicalKey = _workspaceContextKey(outputName, workspaceId || currentWorkspaceIdForOutput(outputName));
        const key = _scopedContextKey(physicalKey, _barContextScope(barId, outputName));
        if (!barId || !key)
            return;
        const next = JSON.parse(JSON.stringify(barWorkspaceContexts || {}));
        const contexts = Array.from(next[barId] || []).filter(item => item !== key);
        if (visible)
            contexts.push(key);
        if (contexts.length > 0)
            next[barId] = contexts;
        else
            delete next[barId];
        barWorkspaceContexts = next;
        saveSettings();
    }

    function forgetBarContexts(barId) {
        if (!barId)
            return;
        const next = Object.assign({}, barWorkspaceContexts || {});
        delete next[barId];
        barWorkspaceContexts = next;
        const nextSnapshots = JSON.parse(JSON.stringify(workspaceContextSnapshots || {}));
        for (const key in nextSnapshots) {
            nextSnapshots[key].barIds = Array.from(nextSnapshots[key].barIds || [])
                .filter(id => id !== barId);
        }
        workspaceContextSnapshots = nextSnapshots;
        saveSettings();
    }

    function removeBarOutputContexts(barId, outputName) {
        if (!barId || !outputName)
            return;
        const next = JSON.parse(JSON.stringify(barWorkspaceContexts || {}));
        const contexts = Array.from(next[barId] || [])
            .filter(key => !key.startsWith(outputName + "::"));
        if (contexts.length > 0)
            next[barId] = contexts;
        else
            delete next[barId];
        barWorkspaceContexts = next;
        const nextSnapshots = JSON.parse(JSON.stringify(workspaceContextSnapshots || {}));
        for (const key in nextSnapshots) {
            if (!key.startsWith(outputName + "::"))
                continue;
            nextSnapshots[key].barIds = Array.from(nextSnapshots[key].barIds || [])
                .filter(id => id !== barId);
        }
        workspaceContextSnapshots = nextSnapshots;
        saveSettings();
    }

    function isDockVisibleInContext(outputName, workspaceId) {
        if (!CompositorService.isKaskad || !Kaskad.available)
            return SettingsData.showDock;
        if (!SettingsData.showDock || !shellSurfaceContextsInitialized)
            return false;
        if (!shellSurfaceContextRecoveryDone) {
            return Array.from(SettingsData.getFilteredScreens("dock") || [])
                .some(screen => screen?.name === outputName);
        }
        const key = _workspaceContextKey(outputName, workspaceId || currentWorkspaceIdForOutput(outputName));
        return !!key && _contextListContains(dockWorkspaceContexts || [], outputName, key);
    }

    function isDockVisibleInSlot(outputName, slot) {
        const number = Number(slot);
        if (!outputName || !Number.isInteger(number) || number < 1)
            return false;
        return SettingsData.showDock
            && _contextListContains(dockWorkspaceContexts || [], outputName, outputName + "::" + number);
    }

    function setDockVisibleInContext(outputName, workspaceId, visible) {
        if (!CompositorService.isKaskad || !Kaskad.available)
            return;
        const physicalKey = _workspaceContextKey(outputName, workspaceId || currentWorkspaceIdForOutput(outputName));
        const key = _scopedContextKey(physicalKey, _dockContextScope(outputName));
        if (!key)
            return;
        const contexts = Array.from(dockWorkspaceContexts || []).filter(item => item !== key);
        if (visible)
            contexts.push(key);
        dockWorkspaceContexts = contexts;
        saveSettings();
    }

    function setDockVisibleInSlot(outputName, slot, visible) {
        const number = Number(slot);
        if (!outputName || !Number.isInteger(number) || number < 1)
            return;
        const key = _scopedContextKey(outputName + "::" + number, _dockContextScope(outputName));
        const contexts = Array.from(dockWorkspaceContexts || []).filter(item => item !== key);
        if (visible)
            contexts.push(key);
        dockWorkspaceContexts = contexts;
        if (visible && !SettingsData.showDock)
            SettingsData.setShowDock(true);
        saveSettings();
    }

    function interactionScreenName() {
        return CompositorService.getInteractionScreen()?.name
            || CompositorService.getPrimaryScreen()?.name
            || Array.from(Quickshell.screens || [])[0]?.name
            || "";
    }

    function isDockVisibleOnInteractionWorkspace(outputName) {
        return isDockVisibleInContext(outputName || interactionScreenName());
    }

    function setDockVisibleOnInteractionWorkspace(visible, requestedOutputName) {
        const outputName = requestedOutputName || interactionScreenName();
        if (!outputName)
            return;
        if (visible && !SettingsData.showDock)
            SettingsData.setShowDock(true);
        setDockVisibleInContext(outputName, "", visible);
    }

    function removeDockOutputContexts(outputName) {
        if (!outputName)
            return;
        dockWorkspaceContexts = Array.from(dockWorkspaceContexts || [])
            .filter(key => !key.startsWith(outputName + "::"));
        const nextSnapshots = JSON.parse(JSON.stringify(workspaceContextSnapshots || {}));
        for (const key in nextSnapshots) {
            if (key.startsWith(outputName + "::"))
                nextSnapshots[key].dock = false;
        }
        workspaceContextSnapshots = nextSnapshots;
        saveSettings();
    }

    function migrateLegacyPinScopes() {
        const primary = CompositorService.getPrimaryScreen();
        if (!primary)
            return;
        const workspace = Array.from(Kaskad.workspaces || []).find(item =>
            Array.from(item.currentOutputs || []).includes(primary.name));
        if (!workspace)
            return;
        const key = _workspaceContextKey(primary.name, workspace.id);
        let changed = false;
        if (Object.keys(pinnedAppsByWorkspace || {}).length === 0 && (pinnedApps || []).length > 0) {
            const nextDockPins = {};
            nextDockPins[key] = [...pinnedApps];
            pinnedAppsByWorkspace = nextDockPins;
            changed = true;
        }
        if (Object.keys(barPinnedAppsByWorkspace || {}).length === 0 && (barPinnedApps || []).length > 0) {
            const nextBarPins = {};
            nextBarPins[key] = [...barPinnedApps];
            barPinnedAppsByWorkspace = nextBarPins;
            changed = true;
        }
        if (changed)
            saveSettings();
    }

    function workspaceOutput(workspaceId) {
        return (workspaceOutputAssignments || {})[workspaceId] || "";
    }

    function workspacesForOutput(outputName) {
        ensureWorkspaceOutputAssignments();
        return Array.from(Kaskad.workspaces || []).filter(workspace => workspaceOutput(workspace.id) === outputName);
    }

    function setWorkspaceOutput(workspaceId, outputName) {
        if (!workspaceId || !outputName)
            return;
        const next = Object.assign({}, workspaceOutputAssignments || {});
        next[workspaceId] = outputName;
        workspaceOutputAssignments = next;
        if (Kaskad.available)
            Kaskad.assignWorkspaceToOutput(workspaceId, outputName);
        saveSettings();
    }

    function forgetWorkspaceOutput(workspaceId) {
        if (!workspaceId || !Object.prototype.hasOwnProperty.call(workspaceOutputAssignments || {}, workspaceId))
            return;
        const next = Object.assign({}, workspaceOutputAssignments || {});
        delete next[workspaceId];
        workspaceOutputAssignments = next;
        saveSettings();
    }

    function forgetOutputContexts(outputName) {
        if (!outputName)
            return;
        const nextAssignments = {};
        for (const workspaceId in workspaceOutputAssignments || {}) {
            if (workspaceOutputAssignments[workspaceId] !== outputName)
                nextAssignments[workspaceId] = workspaceOutputAssignments[workspaceId];
        }
        function withoutOutput(source) {
            const next = {};
            const prefix = outputName + "::";
            for (const key in source || {}) {
                if (!key.startsWith(prefix))
                    next[key] = source[key];
            }
            return next;
        }
        workspaceOutputAssignments = nextAssignments;
        pinnedAppsByWorkspace = withoutOutput(pinnedAppsByWorkspace);
        barPinnedAppsByWorkspace = withoutOutput(barPinnedAppsByWorkspace);
        dockWorkspaceContexts = Array.from(dockWorkspaceContexts || [])
            .filter(key => !key.startsWith(outputName + "::"));
        const nextBarContexts = {};
        for (const barId in barWorkspaceContexts || {}) {
            const contexts = Array.from(barWorkspaceContexts[barId] || [])
                .filter(key => !key.startsWith(outputName + "::"));
            if (contexts.length > 0)
                nextBarContexts[barId] = contexts;
        }
        barWorkspaceContexts = nextBarContexts;
        const nextSnapshots = {};
        for (const key in workspaceContextSnapshots || {}) {
            if (!key.startsWith(outputName + "::"))
                nextSnapshots[key] = workspaceContextSnapshots[key];
        }
        workspaceContextSnapshots = nextSnapshots;
        saveSettings();
    }

    function _pinWorkspaceId(screenName, workspaceId) {
        if (workspaceId)
            return workspaceId;
        const targetScreen = _pinScreenName(screenName);
        const workspace = Array.from(Kaskad.workspaces || []).find(item =>
            Array.from(item.currentOutputs || []).includes(targetScreen))
            || Array.from(Kaskad.workspaces || []).find(item => item.current);
        return workspace?.id || "default";
    }

    function _pinScopeKey(screenName, workspaceId) {
        const outputName = _pinScreenName(screenName);
        const resolvedWorkspaceId = _pinWorkspaceId(outputName, workspaceId);
        // Pins use the same stable local slot as panels and the standalone
        // dock. Compositor workspace UUIDs are transient: an empty dynamic
        // workspace can disappear and later be recreated with another UUID.
        // Storing that UUID made a freshly pinned app vanish as soon as the
        // workspace list was reconciled.
        return _workspaceContextKey(outputName, resolvedWorkspaceId)
            || currentWorkspaceContext(outputName)
            || outputName + "::1";
    }

    function _legacyPinsForScope(screenName, workspaceId, legacyPins, scopedPins) {
        const key = _pinScopeKey(screenName, workspaceId);
        if (Object.prototype.hasOwnProperty.call(scopedPins || {}, key))
            return [...(scopedPins[key] || [])];
        const primary = CompositorService.getPrimaryScreen();
        const targetScreen = _pinScreenName(screenName);
        if (Object.keys(scopedPins || {}).length === 0 && (!primary || primary.name === targetScreen))
            return [...(legacyPins || [])];
        return [];
    }

    function pinnedAppsForContext(screenName, workspaceId) {
        return _legacyPinsForScope(screenName, workspaceId, pinnedApps, pinnedAppsByWorkspace);
    }

    function barPinnedAppsForContext(screenName, workspaceId) {
        return _legacyPinsForScope(screenName, workspaceId, barPinnedApps, barPinnedAppsByWorkspace);
    }

    function setPinnedApps(apps, screenName, workspaceId) {
        const key = _pinScopeKey(screenName, workspaceId);
        const next = Object.assign({}, pinnedAppsByWorkspace || {});
        next[key] = [...(apps || [])];
        pinnedAppsByWorkspace = next;
        saveSettings();
    }

    function setDockLauncherPosition(position) {
        dockLauncherPosition = position;
        saveSettings();
    }

    function addPinnedApp(appId, screenName, workspaceId) {
        if (!appId)
            return;
        var currentPinned = pinnedAppsForContext(screenName, workspaceId);
        if (currentPinned.indexOf(appId) === -1) {
            currentPinned.push(appId);
            setPinnedApps(currentPinned, screenName, workspaceId);
        }
    }

    function removePinnedApp(appId, screenName, workspaceId) {
        if (!appId)
            return;
        var currentPinned = pinnedAppsForContext(screenName, workspaceId).filter(id => id !== appId);
        setPinnedApps(currentPinned, screenName, workspaceId);
    }

    function isPinnedApp(appId, screenName, workspaceId) {
        return appId && pinnedAppsForContext(screenName, workspaceId).indexOf(appId) !== -1;
    }

    function setBarPinnedApps(apps, screenName, workspaceId) {
        const key = _pinScopeKey(screenName, workspaceId);
        const next = Object.assign({}, barPinnedAppsByWorkspace || {});
        next[key] = [...(apps || [])];
        barPinnedAppsByWorkspace = next;
        saveSettings();
    }

    function addBarPinnedApp(appId, screenName, workspaceId) {
        if (!appId)
            return;
        var currentPinned = barPinnedAppsForContext(screenName, workspaceId);
        if (currentPinned.indexOf(appId) === -1) {
            currentPinned.push(appId);
            setBarPinnedApps(currentPinned, screenName, workspaceId);
        }
    }

    function removeBarPinnedApp(appId, screenName, workspaceId) {
        if (!appId)
            return;
        var currentPinned = barPinnedAppsForContext(screenName, workspaceId).filter(id => id !== appId);
        setBarPinnedApps(currentPinned, screenName, workspaceId);
    }

    function isBarPinnedApp(appId, screenName, workspaceId) {
        return appId && barPinnedAppsForContext(screenName, workspaceId).indexOf(appId) !== -1;
    }

    function hideTrayId(trayId) {
        if (!trayId)
            return;
        const current = [...hiddenTrayIds];
        if (current.indexOf(trayId) === -1) {
            current.push(trayId);
            hiddenTrayIds = current;
            saveSettings();
        }
    }

    function showTrayId(trayId) {
        if (!trayId)
            return;
        hiddenTrayIds = hiddenTrayIds.filter(id => id !== trayId);
        saveSettings();
    }

    function isHiddenTrayId(trayId) {
        return trayId && hiddenTrayIds.indexOf(trayId) !== -1;
    }

    function setTrayItemOrder(order) {
        trayItemOrder = order;
        saveSettings();
    }

    function addRecentColor(color) {
        const colorStr = color.toString();
        let recent = recentColors.slice();
        recent = recent.filter(c => c !== colorStr);
        recent.unshift(colorStr);
        if (recent.length > 5)
            recent = recent.slice(0, 5);
        recentColors = recent;
        saveSettings();
    }

    function setLaunchPrefix(prefix) {
        launchPrefix = prefix;
        saveSettings();
    }

    function setLastBrightnessDevice(device) {
        lastBrightnessDevice = device;
        saveSettings();
    }

    function setBrightnessExponential(deviceName, enabled) {
        var newSettings = Object.assign({}, brightnessExponentialDevices);
        if (enabled) {
            newSettings[deviceName] = true;
        } else {
            delete newSettings[deviceName];
        }
        brightnessExponentialDevices = newSettings;
        saveSettings();

        if (typeof DisplayService !== "undefined") {
            DisplayService.updateDeviceBrightnessDisplay(deviceName);
        }
    }

    function getBrightnessExponential(deviceName) {
        return brightnessExponentialDevices[deviceName] === true;
    }

    function setBrightnessUserSetValue(deviceName, value) {
        var newValues = Object.assign({}, brightnessUserSetValues);
        newValues[deviceName] = value;
        brightnessUserSetValues = newValues;
        saveSettings();
    }

    function getBrightnessUserSetValue(deviceName) {
        return brightnessUserSetValues[deviceName];
    }

    function clearBrightnessUserSetValue(deviceName) {
        var newValues = Object.assign({}, brightnessUserSetValues);
        delete newValues[deviceName];
        brightnessUserSetValues = newValues;
        saveSettings();
    }

    function setBrightnessExponent(deviceName, exponent) {
        var newValues = Object.assign({}, brightnessExponentValues);
        if (exponent !== undefined && exponent !== null) {
            newValues[deviceName] = exponent;
        } else {
            delete newValues[deviceName];
        }
        brightnessExponentValues = newValues;
        saveSettings();
    }

    function getBrightnessExponent(deviceName) {
        const value = brightnessExponentValues[deviceName];
        return value !== undefined ? value : 1.2;
    }

    function setSelectedGpuIndex(index) {
        selectedGpuIndex = index;
        saveSettings();
    }

    function setNvidiaGpuTempEnabled(enabled) {
        nvidiaGpuTempEnabled = enabled;
        saveSettings();
    }

    function setNonNvidiaGpuTempEnabled(enabled) {
        nonNvidiaGpuTempEnabled = enabled;
        saveSettings();
    }

    function setEnabledGpuPciIds(pciIds) {
        enabledGpuPciIds = pciIds;
        saveSettings();
    }

    function setWifiDeviceOverride(device) {
        wifiDeviceOverride = device || "";
        saveSettings();
    }

    function setWeatherHourlyDetailed(detailed) {
        weatherHourlyDetailed = detailed;
        saveSettings();
    }

    function setWeatherLocation(displayName, coordinates) {
        weatherLocation = displayName;
        weatherCoordinates = coordinates;
        saveSettings();
    }

    function hideApp(appId) {
        if (!appId)
            return;
        const current = [...hiddenApps];
        if (current.indexOf(appId) === -1) {
            current.push(appId);
            hiddenApps = current;
            saveSettings();
        }
    }

    function showApp(appId) {
        if (!appId)
            return;
        hiddenApps = hiddenApps.filter(id => id !== appId);
        saveSettings();
    }

    function isAppHidden(appId) {
        return appId && hiddenApps.indexOf(appId) !== -1;
    }

    function setAppOverride(appId, overrides) {
        if (!appId)
            return false;
        const previousOverrides = appOverrides;
        const newOverrides = Object.assign({}, appOverrides);
        if (!overrides || Object.keys(overrides).length === 0) {
            delete newOverrides[appId];
        } else {
            newOverrides[appId] = overrides;
        }
        appOverrides = newOverrides;
        if (!saveSettings(true)) {
            appOverrides = previousOverrides;
            return false;
        }
        return true;
    }

    function getAppOverride(appId) {
        if (!appId)
            return null;
        return appOverrides[appId] || null;
    }

    function clearAppOverride(appId) {
        if (!appId)
            return false;
        const previousOverrides = appOverrides;
        const newOverrides = Object.assign({}, appOverrides);
        delete newOverrides[appId];
        appOverrides = newOverrides;
        if (!saveSettings(true)) {
            appOverrides = previousOverrides;
            return false;
        }
        return true;
    }

    function setSearchAppActions(enabled) {
        searchAppActions = enabled;
        saveSettings();
    }

    function setDeviceMaxVolume(nodeName, maxPercent) {
        if (!nodeName)
            return;
        const updated = Object.assign({}, deviceMaxVolumes);
        const clamped = Math.max(100, Math.min(200, Math.round(maxPercent)));
        if (clamped === 100) {
            delete updated[nodeName];
        } else {
            updated[nodeName] = clamped;
        }
        deviceMaxVolumes = updated;
        saveSettings();
    }

    function setHiddenOutputDeviceNames(deviceNames) {
        if (!Array.isArray(deviceNames))
            return;
        hiddenOutputDeviceNames = deviceNames;
        saveSettings();
    }

    function setHiddenInputDeviceNames(deviceNames) {
        if (!Array.isArray(deviceNames))
            return;
        hiddenInputDeviceNames = deviceNames;
        saveSettings();
    }

    function getDeviceMaxVolume(nodeName) {
        if (!nodeName)
            return 100;
        return deviceMaxVolumes[nodeName] ?? 100;
    }

    function removeDeviceMaxVolume(nodeName) {
        if (!nodeName)
            return;
        const updated = Object.assign({}, deviceMaxVolumes);
        delete updated[nodeName];
        deviceMaxVolumes = updated;
        saveSettings();
    }

    function updateLocale() {
        if (!locale) {
            I18n._pickTranslation();
            return;
        }
        I18n.useLocale(locale, locale.startsWith("en") ? "" : I18n.folder + "/" + locale + ".json");
    }

    function setNotepadLastMode(mode) {
        if (notepadLastMode === mode)
            return;
        notepadLastMode = mode;
        saveSettings();
    }

    function setLauncherLastMode(mode) {
        launcherLastMode = mode;
        saveSettings();
    }

    function getLauncherRestoreMode() {
        if (!SettingsData.rememberLastMode)
            return "all";
        return launcherLastMode || "all";
    }

    function setLauncherLastFileSearchType(type) {
        launcherLastFileSearchType = type;
        saveSettings();
    }

    function setLauncherLastQuery(query) {
        launcherLastQuery = query;
        saveSettings();
    }

    function addLauncherHistory(query, skipLastQuery) {
        let q = query.trim();

        if (!skipLastQuery)
            setLauncherLastQuery(q);

        if (!q)
            return;

        if (launcherQueryHistory.length > 0 && launcherQueryHistory[0] === q) {
            return;
        }

        let history = [...launcherQueryHistory];

        let idx = history.indexOf(q);
        if (idx !== -1)
            history.splice(idx, 1);

        history.unshift(q);
        if (history.length > 50)
            history = history.slice(0, 50);

        launcherQueryHistory = history;
        saveSettings();
    }

    function clearLauncherHistory() {
        launcherLastQuery = "";
        launcherSearchHistory = [];
        saveSettings();
    }

    function setAppDrawerLastMode(mode) {
        appDrawerLastMode = mode;
        saveSettings();
    }

    function setNiriOverviewLastMode(mode) {
        niriOverviewLastMode = mode;
        saveSettings();
    }

    function setSettingsSidebarState(expandedIds, collapsedIds) {
        settingsSidebarExpandedIds = expandedIds;
        settingsSidebarCollapsedIds = collapsedIds;
        saveSettings();
    }

    function syncWallpaperForCurrentMode(mode) {
        if (!perModeWallpaper)
            return;
        var light = (mode !== undefined) ? mode : isLightMode;
        if (perMonitorWallpaper) {
            monitorWallpapers = light ? Object.assign({}, monitorWallpapersLight) : Object.assign({}, monitorWallpapersDark);
            return;
        }

        wallpaperPath = light ? wallpaperPathLight : wallpaperPathDark;
    }

    function _findMonitorValue(map, screenName) {
        var screen = null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }

        if (!screen)
            return map[screenName];

        if (map[screen.name] !== undefined)
            return map[screen.name];
        if (screen.model && map[screen.model] !== undefined)
            return map[screen.model];
        if (typeof SettingsData !== "undefined") {
            var displayName = SettingsData.getScreenDisplayName(screen);
            if (displayName && map[displayName] !== undefined)
                return map[displayName];
        }
        return undefined;
    }

    function getMonitorWallpaper(screenName) {
        if (!perMonitorWallpaper)
            return wallpaperPath;
        var value = _findMonitorValue(monitorWallpapers, screenName);
        return value !== undefined ? value : wallpaperPath;
    }

    function getMonitorWallpaperFillMode(screenName) {
        var globalFillMode = (typeof SettingsData !== "undefined") ? SettingsData.wallpaperFillMode : "Fill";
        if (!perMonitorWallpaper)
            return globalFillMode;
        var value = _findMonitorValue(monitorWallpaperFillModes, screenName);
        return value !== undefined ? value : globalFillMode;
    }

    function setMonitorWallpaperFillMode(screenName, mode) {
        var screen = null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }

        if (!screen)
            return;

        var identifier = typeof SettingsData !== "undefined" ? SettingsData.getScreenDisplayName(screen) : screen.name;

        var newModes = {};
        for (var key in monitorWallpaperFillModes) {
            var isThisScreen = key === screen.name || (screen.model && key === screen.model);
            if (!isThisScreen)
                newModes[key] = monitorWallpaperFillModes[key];
        }

        newModes[identifier] = mode;
        monitorWallpaperFillModes = newModes;
        saveSettings();
    }

    function getMonitorCyclingSettings(screenName) {
        var defaults = {
            "enabled": false,
            "mode": "interval",
            "interval": 300,
            "time": "06:00"
        };
        var value = _findMonitorValue(monitorCyclingSettings, screenName);
        return Object.assign({}, defaults, value !== undefined ? value : {});
    }

    FileView {
        id: settingsFile

        path: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/KaskadShell/session.json"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            if (root._retryingSessionWrite)
                return;
            _hasUnsavedChanges = false;
            parseSettings(settingsFile.text());
        }
        onSaveFailed: error => {
            root._lastSaveFailed = true;
            root._isReadOnly = true;
            root._hasUnsavedChanges = root._checkForUnsavedChanges();
        }
    }

    Process {
        id: sessionWritableCheckProcess

        property string sessionPath: Paths.strip(settingsFile.path)

        command: ["sh", "-c", "[ ! -f \"" + sessionPath + "\" ] || [ -w \"" + sessionPath + "\" ] && echo 'writable' || echo 'readonly'"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim();
                root._onWritableCheckComplete(result === "writable");
            }
        }
    }

    IpcHandler {
        target: "wallpaper"

        function get(): string {
            if (root.perMonitorWallpaper) {
                return "ERROR: Per-monitor mode enabled. Use getFor(screenName) instead.";
            }
            return root.wallpaperPath || "";
        }

        function set(path: string): string {
            if (root.perMonitorWallpaper) {
                return "ERROR: Per-monitor mode enabled. Use setFor(screenName, path) instead.";
            }

            if (!path) {
                return "ERROR: No path provided";
            }

            var absolutePath = path.startsWith("/") ? path : StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/" + path;

            try {
                root.setWallpaper(absolutePath);
                return "SUCCESS: Wallpaper set to " + absolutePath;
            } catch (e) {
                return "ERROR: Failed to set wallpaper: " + e.toString();
            }
        }

        function clear(): string {
            root.setWallpaper("");
            root.setPerMonitorWallpaper(false);
            root.monitorWallpapers = {};
            root.saveSettings();
            return "SUCCESS: All wallpapers cleared";
        }

        function next(): string {
            if (root.perMonitorWallpaper) {
                return "ERROR: Per-monitor mode enabled. Use nextFor(screenName) instead.";
            }

            if (!root.wallpaperPath) {
                return "ERROR: No wallpaper set";
            }

            try {
                WallpaperCyclingService.cycleNextManually();
                return "SUCCESS: Cycling to next wallpaper";
            } catch (e) {
                return "ERROR: Failed to cycle wallpaper: " + e.toString();
            }
        }

        function prev(): string {
            if (root.perMonitorWallpaper) {
                return "ERROR: Per-monitor mode enabled. Use prevFor(screenName) instead.";
            }

            if (!root.wallpaperPath) {
                return "ERROR: No wallpaper set";
            }

            try {
                WallpaperCyclingService.cyclePrevManually();
                return "SUCCESS: Cycling to previous wallpaper";
            } catch (e) {
                return "ERROR: Failed to cycle wallpaper: " + e.toString();
            }
        }

        function getFor(screenName: string): string {
            if (!screenName) {
                return "ERROR: No screen name provided";
            }
            return root.getMonitorWallpaper(screenName) || "";
        }

        function setFor(screenName: string, path: string): string {
            if (!screenName) {
                return "ERROR: No screen name provided";
            }

            if (!path) {
                return "ERROR: No path provided";
            }

            var absolutePath = path.startsWith("/") ? path : StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/" + path;

            try {
                if (!root.perMonitorWallpaper) {
                    root.setPerMonitorWallpaper(true);
                }
                root.setMonitorWallpaper(screenName, absolutePath);
                return "SUCCESS: Wallpaper set for " + screenName + " to " + absolutePath;
            } catch (e) {
                return "ERROR: Failed to set wallpaper for " + screenName + ": " + e.toString();
            }
        }

        function nextFor(screenName: string): string {
            if (!screenName) {
                return "ERROR: No screen name provided";
            }

            var currentWallpaper = root.getMonitorWallpaper(screenName);
            if (!currentWallpaper) {
                return "ERROR: No wallpaper set for " + screenName;
            }

            try {
                WallpaperCyclingService.cycleNextForMonitor(screenName);
                return "SUCCESS: Cycling to next wallpaper for " + screenName;
            } catch (e) {
                return "ERROR: Failed to cycle wallpaper for " + screenName + ": " + e.toString();
            }
        }

        function prevFor(screenName: string): string {
            if (!screenName) {
                return "ERROR: No screen name provided";
            }

            var currentWallpaper = root.getMonitorWallpaper(screenName);
            if (!currentWallpaper) {
                return "ERROR: No wallpaper set for " + screenName;
            }

            try {
                WallpaperCyclingService.cyclePrevForMonitor(screenName);
                return "SUCCESS: Cycling to previous wallpaper for " + screenName;
            } catch (e) {
                return "ERROR: Failed to cycle wallpaper for " + screenName + ": " + e.toString();
            }
        }
    }
}

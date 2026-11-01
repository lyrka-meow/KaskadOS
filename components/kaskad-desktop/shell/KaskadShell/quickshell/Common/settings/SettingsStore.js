.pragma library

    .import "./SettingsSpec.js" as SpecModule

function parse(root, jsonObj) {
    var SPEC = SpecModule.SPEC;

    if (!jsonObj) return;

    for (var k in SPEC) {
        // Runtime-only keys are never in the JSON; resetting them here
        // would wipe values set by detection processes on every reload.
        if (SPEC[k].persist === false) continue;
        if (!(k in jsonObj)) {
            root[k] = SPEC[k].def;
        }
    }

    for (var k in jsonObj) {
        if (!SPEC[k]) continue;
        var raw = jsonObj[k];
        var spec = SPEC[k];
        var coerce = spec.coerce;
        root[k] = coerce ? (coerce(raw) !== undefined ? coerce(raw) : root[k]) : raw;
    }
}

function toJson(root) {
    var SPEC = SpecModule.SPEC;
    var out = {};
    for (var k in SPEC) {
        if (SPEC[k].persist === false) continue;
        out[k] = root[k];
    }
    out.configVersion = root.settingsConfigVersion;
    return out;
}

function migrateToVersion(obj, targetVersion) {
    if (!obj) return null;

    var settings = JSON.parse(JSON.stringify(obj));
    var currentVersion = settings.configVersion || 0;

    if (currentVersion >= targetVersion) {
        return null;
    }

    if (currentVersion < 18 && settings.screenshotProfiles === undefined) {
        settings.screenshotProfiles = SpecModule.SPEC.screenshotProfiles.def;
    }

    if (currentVersion < 2) {
        console.info("Migrating settings from version", currentVersion, "to version 2");

        if (settings.barConfigs === undefined) {
            var position = 0;
            if (settings.kaskadBarAtBottom !== undefined || settings.topBarAtBottom !== undefined) {
                var atBottom = settings.kaskadBarAtBottom !== undefined ? settings.kaskadBarAtBottom : settings.topBarAtBottom;
                position = atBottom ? 1 : 0;
            } else if (settings.kaskadBarPosition !== undefined) {
                position = settings.kaskadBarPosition;
            }

            var defaultConfig = {
                id: "default",
                name: "Main Bar",
                enabled: true,
                position: position,
                screenPreferences: ["all"],
                showOnLastDisplay: true,
                leftWidgets: settings.kaskadBarLeftWidgets || ["launcherButton", "workspaceSwitcher", "focusedWindow"],
                centerWidgets: settings.kaskadBarCenterWidgets || [{ id: "music", enabled: true, instanceId: "bw_media_default" }, "clock", "weather"],
                rightWidgets: settings.kaskadBarRightWidgets || ["systemTray", "clipboard", "cpuUsage", "memUsage", "notificationButton", "battery", "controlCenterButton"],
                spacing: settings.kaskadBarSpacing !== undefined ? settings.kaskadBarSpacing : 4,
                innerPadding: settings.kaskadBarInnerPadding !== undefined ? settings.kaskadBarInnerPadding : 4,
                bottomGap: settings.kaskadBarBottomGap !== undefined ? settings.kaskadBarBottomGap : 0,
                transparency: settings.kaskadBarTransparency !== undefined ? settings.kaskadBarTransparency : 1.0,
                widgetTransparency: settings.kaskadBarWidgetTransparency !== undefined ? settings.kaskadBarWidgetTransparency : 1.0,
                squareCorners: settings.kaskadBarSquareCorners !== undefined ? settings.kaskadBarSquareCorners : false,
                noBackground: settings.kaskadBarNoBackground !== undefined ? settings.kaskadBarNoBackground : false,
                gothCornersEnabled: settings.kaskadBarGothCornersEnabled !== undefined ? settings.kaskadBarGothCornersEnabled : false,
                gothCornerRadiusOverride: settings.kaskadBarGothCornerRadiusOverride !== undefined ? settings.kaskadBarGothCornerRadiusOverride : false,
                gothCornerRadiusValue: settings.kaskadBarGothCornerRadiusValue !== undefined ? settings.kaskadBarGothCornerRadiusValue : 12,
                borderEnabled: settings.kaskadBarBorderEnabled !== undefined ? settings.kaskadBarBorderEnabled : false,
                borderColor: settings.kaskadBarBorderColor || "surfaceText",
                borderOpacity: settings.kaskadBarBorderOpacity !== undefined ? settings.kaskadBarBorderOpacity : 1.0,
                borderThickness: settings.kaskadBarBorderThickness !== undefined ? settings.kaskadBarBorderThickness : 1,
                fontScale: settings.kaskadBarFontScale !== undefined ? settings.kaskadBarFontScale : 1.0,
                autoHide: settings.kaskadBarAutoHide !== undefined ? settings.kaskadBarAutoHide : false,
                autoHideDelay: settings.kaskadBarAutoHideDelay !== undefined ? settings.kaskadBarAutoHideDelay : 250,
                openOnOverview: settings.kaskadBarOpenOnOverview !== undefined ? settings.kaskadBarOpenOnOverview : false,
                visible: settings.kaskadBarVisible !== undefined ? settings.kaskadBarVisible : true,
                popupGapsAuto: settings.popupGapsAuto !== undefined ? settings.popupGapsAuto : true,
                popupGapsManual: settings.popupGapsManual !== undefined ? settings.popupGapsManual : 4
            };

            settings.barConfigs = [defaultConfig];

            var legacyKeys = [
                "kaskadBarLeftWidgets", "kaskadBarCenterWidgets", "kaskadBarRightWidgets",
                "kaskadBarWidgetOrder", "kaskadBarAutoHide", "kaskadBarAutoHideDelay",
                "kaskadBarOpenOnOverview", "kaskadBarVisible", "kaskadBarSpacing",
                "kaskadBarBottomGap", "kaskadBarInnerPadding", "kaskadBarPosition",
                "kaskadBarSquareCorners", "kaskadBarNoBackground", "kaskadBarGothCornersEnabled",
                "kaskadBarGothCornerRadiusOverride", "kaskadBarGothCornerRadiusValue",
                "kaskadBarBorderEnabled", "kaskadBarBorderColor", "kaskadBarBorderOpacity",
                "kaskadBarBorderThickness", "popupGapsAuto", "popupGapsManual",
                "kaskadBarAtBottom", "topBarAtBottom", "kaskadBarTransparency", "kaskadBarWidgetTransparency"
            ];

            for (var i = 0; i < legacyKeys.length; i++) {
                delete settings[legacyKeys[i]];
            }

            console.info("Migrated single bar settings to barConfigs");
        }

        settings.configVersion = 2;
    }

    if (currentVersion < 3) {
        console.info("Migrating settings from version", currentVersion, "to version 3");
        console.info("Per-widget controlCenterButton config now supported via widgetData properties");
        settings.configVersion = 3;
    }

    if (currentVersion < 4) {
        console.info("Migrating settings from version", currentVersion, "to version 4");
        console.info("Migrating desktop widgets to unified desktopWidgetInstances");

        var instances = [];

        if (settings.desktopClockEnabled) {
            var clockPositions = {};
            if (settings.desktopClockX !== undefined && settings.desktopClockX >= 0) {
                clockPositions["default"] = {
                    x: settings.desktopClockX,
                    y: settings.desktopClockY,
                    width: settings.desktopClockWidth || 280,
                    height: settings.desktopClockHeight || 180
                };
            }

            instances.push({
                id: "dw_clock_primary",
                widgetType: "desktopClock",
                name: "Desktop Clock",
                enabled: true,
                config: {
                    style: settings.desktopClockStyle || "analog",
                    transparency: settings.desktopClockTransparency !== undefined ? settings.desktopClockTransparency : 0.8,
                    colorMode: settings.desktopClockColorMode || "primary",
                    customColor: settings.desktopClockCustomColor || "#ffffff",
                    showDate: settings.desktopClockShowDate !== false,
                    showAnalogNumbers: settings.desktopClockShowAnalogNumbers || false,
                    showAnalogSeconds: settings.desktopClockShowAnalogSeconds !== false,
                    displayPreferences: settings.desktopClockDisplayPreferences || ["all"]
                },
                positions: clockPositions
            });
        }

        if (settings.systemMonitorEnabled) {
            var sysmonPositions = {};
            if (settings.systemMonitorX !== undefined && settings.systemMonitorX >= 0) {
                sysmonPositions["default"] = {
                    x: settings.systemMonitorX,
                    y: settings.systemMonitorY,
                    width: settings.systemMonitorWidth || 320,
                    height: settings.systemMonitorHeight || 480
                };
            }

            instances.push({
                id: "dw_sysmon_primary",
                widgetType: "systemMonitor",
                name: "System Monitor",
                enabled: true,
                config: {
                    showHeader: settings.systemMonitorShowHeader !== false,
                    transparency: settings.systemMonitorTransparency !== undefined ? settings.systemMonitorTransparency : 0.8,
                    colorMode: settings.systemMonitorColorMode || "primary",
                    customColor: settings.systemMonitorCustomColor || "#ffffff",
                    showCpu: settings.systemMonitorShowCpu !== false,
                    showCpuGraph: settings.systemMonitorShowCpuGraph !== false,
                    showCpuTemp: settings.systemMonitorShowCpuTemp !== false,
                    showGpuTemp: settings.systemMonitorShowGpuTemp || false,
                    gpuPciId: settings.systemMonitorGpuPciId || "",
                    showMemory: settings.systemMonitorShowMemory !== false,
                    showMemoryGraph: settings.systemMonitorShowMemoryGraph !== false,
                    showNetwork: settings.systemMonitorShowNetwork !== false,
                    showNetworkGraph: settings.systemMonitorShowNetworkGraph !== false,
                    showDisk: settings.systemMonitorShowDisk !== false,
                    showTopProcesses: settings.systemMonitorShowTopProcesses || false,
                    topProcessCount: settings.systemMonitorTopProcessCount || 3,
                    topProcessSortBy: settings.systemMonitorTopProcessSortBy || "cpu",
                    layoutMode: settings.systemMonitorLayoutMode || "auto",
                    graphInterval: settings.systemMonitorGraphInterval || 60,
                    displayPreferences: settings.systemMonitorDisplayPreferences || ["all"]
                },
                positions: sysmonPositions
            });
        }

        var variants = settings.systemMonitorVariants || [];
        for (var i = 0; i < variants.length; i++) {
            var v = variants[i];
            instances.push({
                id: v.id,
                widgetType: "systemMonitor",
                name: v.name || ("System Monitor " + (i + 2)),
                enabled: true,
                config: v.config || {},
                positions: v.positions || {}
            });
        }

        settings.desktopWidgetInstances = instances;
        settings.configVersion = 4;
    }

    if (currentVersion < 5) {
        console.info("Migrating settings from version", currentVersion, "to version 5");
        console.info("Moving sensitive data (weather location, coordinates) to session.json");

        delete settings.weatherLocation;
        delete settings.weatherCoordinates;

        settings.configVersion = 5;
    }

    if (currentVersion < 6) {
        console.info("Migrating settings from version", currentVersion, "to version 6");

        if (settings.barElevationEnabled === undefined) {
            var legacyBars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
            var hadLegacyBarShadowEnabled = false;
            for (var j = 0; j < legacyBars.length; j++) {
                var legacyIntensity = Number(legacyBars[j] && legacyBars[j].shadowIntensity);
                if (!isNaN(legacyIntensity) && legacyIntensity > 0) {
                    hadLegacyBarShadowEnabled = true;
                    break;
                }
            }
            settings.barElevationEnabled = hadLegacyBarShadowEnabled;
        }

        settings.configVersion = 6;
    }

    if (currentVersion < 11) {
        settings.configVersion = 11;
    }

    if (currentVersion < 12) {
        console.info("Migrating settings from version", currentVersion, "to version 12");
        if (settings.batteryNotificationType !== undefined) {
            settings.batteryChargeLimitNotificationType = settings.batteryNotificationType;
            settings.batteryLowNotificationType = settings.batteryNotificationType;
            settings.batteryCriticalNotificationType = settings.batteryNotificationType;
            delete settings.batteryNotificationType;
        }
        settings.configVersion = 12;
    }

    if (currentVersion < 13) {
        console.info("Migrating settings from version", currentVersion, "to version 13");

        var bars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        var targetBar = null;
        for (var barIndex = 0; barIndex < bars.length; barIndex++) {
            if (bars[barIndex] && bars[barIndex].id === "default") {
                targetBar = bars[barIndex];
                break;
            }
        }
        if (!targetBar && bars.length > 0)
            targetBar = bars[0];

        if (targetBar) {
            var rightWidgets = Array.isArray(targetBar.rightWidgets)
                ? targetBar.rightWidgets.slice()
                : [];
            var hasSystemUpdate = rightWidgets.some(function(widget) {
                return (typeof widget === "string" ? widget : widget && widget.id) === "systemUpdate";
            });
            if (!hasSystemUpdate) {
                var notificationIndex = rightWidgets.findIndex(function(widget) {
                    return (typeof widget === "string" ? widget : widget && widget.id) === "notificationButton";
                });
                var insertIndex = notificationIndex >= 0 ? notificationIndex : rightWidgets.length;
                rightWidgets.splice(insertIndex, 0, "systemUpdate");
                targetBar.rightWidgets = rightWidgets;
            }
        }

        settings.configVersion = 13;
    }

    if (currentVersion < 14) {
        console.info("Migrating settings from version", currentVersion, "to version 14");
        if (settings.screenPreferences && typeof settings.screenPreferences === "object")
            delete settings.screenPreferences.wallpaper;
        settings.configVersion = 14;
    }

    if (currentVersion < 15) {
        console.info("Migrating settings from version", currentVersion, "to version 15");

        // The original single main bar and dock were implicitly cloned to all
        // outputs.  Bind them to the primary-display role instead.  Explicit
        // per-output bars and any additional bars are preserved unchanged.
        var primaryBars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        for (var primaryBarIndex = 0; primaryBarIndex < primaryBars.length; primaryBarIndex++) {
            var primaryBar = primaryBars[primaryBarIndex];
            if (!primaryBar || primaryBar.id !== "default")
                continue;
            var primaryBarPrefs = Array.isArray(primaryBar.screenPreferences) ? primaryBar.screenPreferences : ["all"];
            if (primaryBarPrefs.length === 0 || primaryBarPrefs.indexOf("all") >= 0)
                primaryBar.screenPreferences = ["primary"];
            break;
        }

        if (!settings.screenPreferences || typeof settings.screenPreferences !== "object")
            settings.screenPreferences = {};
        var dockPrefs = settings.screenPreferences.dock;
        if (!Array.isArray(dockPrefs) || dockPrefs.length === 0 || dockPrefs.indexOf("all") >= 0)
            settings.screenPreferences.dock = ["primary"];

        // Cursor-following was experimental and can leak private popups onto a
        // shared screen.  Version 15 intentionally moves the safe default to
        // the user-selected primary display.
        if (!settings.primaryMonitorPreference || typeof settings.primaryMonitorPreference !== "object")
            settings.primaryMonitorPreference = {};
        delete settings.notificationMonitorMode;
        delete settings.notificationMonitorName;
        delete settings.interactionMonitorMode;
        delete settings.interactionMonitorName;
        delete settings.primaryMonitorName;
        settings.configVersion = 15;
    }

    if (currentVersion < 16) {
        console.info("Migrating settings to a single system tray widget");
        var trayFound = false;
        var trayBars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        for (var trayBarIndex = 0; trayBarIndex < trayBars.length; trayBarIndex++) {
            var trayBar = trayBars[trayBarIndex];
            if (!trayBar)
                continue;
            var traySections = ["leftWidgets", "centerWidgets", "rightWidgets"];
            for (var traySectionIndex = 0; traySectionIndex < traySections.length; traySectionIndex++) {
                var traySection = traySections[traySectionIndex];
                var trayWidgets = Array.isArray(trayBar[traySection]) ? trayBar[traySection] : [];
                var uniqueTrayWidgets = [];
                for (var trayWidgetIndex = 0; trayWidgetIndex < trayWidgets.length; trayWidgetIndex++) {
                    var trayWidget = trayWidgets[trayWidgetIndex];
                    var trayWidgetId = typeof trayWidget === "string" ? trayWidget : (trayWidget && (trayWidget.id || trayWidget.widgetId));
                    if (trayWidgetId !== "systemTray") {
                        uniqueTrayWidgets.push(trayWidget);
                    } else if (!trayFound) {
                        uniqueTrayWidgets.push(trayWidget);
                        trayFound = true;
                    }
                }
                trayBar[traySection] = uniqueTrayWidgets;
            }
        }
        settings.configVersion = 16;
    }

    if (currentVersion < 17) {
        console.info("Removing the retired Tailscale control-center widget");
        if (Array.isArray(settings.controlCenterWidgets)) {
            settings.controlCenterWidgets = settings.controlCenterWidgets.filter(function(widget) {
                return widget && widget.id !== "builtin_tailscale";
            });
        }
        settings.configVersion = 17;
    }

    if (currentVersion < 18) {
        console.info("Adding configurable Kaskad screenshot profiles");
        settings.configVersion = 18;
    }

    if (currentVersion < 19) {
        var instanceCounter = 0;
        var mediaBars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        var mediaSections = ["leftWidgets", "centerWidgets", "rightWidgets"];
        for (var barIndex = 0; barIndex < mediaBars.length; barIndex++) {
            for (var sectionIndex = 0; sectionIndex < mediaSections.length; sectionIndex++) {
                var sectionKey = mediaSections[sectionIndex];
                var widgets = Array.isArray(mediaBars[barIndex][sectionKey]) ? mediaBars[barIndex][sectionKey] : [];
                for (var widgetIndex = 0; widgetIndex < widgets.length; widgetIndex++) {
                    var rawWidget = widgets[widgetIndex];
                    var mediaId = typeof rawWidget === "string" ? rawWidget : rawWidget && rawWidget.id;
                    if (mediaId !== "music")
                        continue;
                    var normalized = typeof rawWidget === "string" ? { id: rawWidget, enabled: true } : rawWidget;
                    if (!normalized.instanceId)
                        normalized.instanceId = "bw_media_" + Date.now() + "_" + (++instanceCounter);
                    widgets[widgetIndex] = normalized;
                }
                mediaBars[barIndex][sectionKey] = widgets;
            }
        }
        settings.barConfigs = mediaBars;
        settings.configVersion = 19;
    }

    return settings;
}

function cleanup(fileText) {
    var getValidKeys = SpecModule.getValidKeys;
    if (!fileText || !fileText.trim()) return;

    try {
        var settings = JSON.parse(fileText);
        var validKeys = getValidKeys();
        var needsSave = false;

        for (var key in settings) {
            if (validKeys.indexOf(key) < 0) {
                delete settings[key];
                needsSave = true;
            }
        }

        return needsSave ? JSON.stringify(settings, null, 2) : null;
    } catch (e) {
        console.warn("SettingsData: Failed to cleanup unused keys:", e.message);
        return null;
    }
}

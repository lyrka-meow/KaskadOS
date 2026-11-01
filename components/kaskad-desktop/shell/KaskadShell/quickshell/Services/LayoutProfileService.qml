pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

QtObject {
    id: root

    readonly property int formatVersion: 2
    property string pendingPath: ""
    property var pendingProfile: null
    property string error: ""

    signal previewReady(var profile)
    signal imported(string name)
    signal exported(string path)

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function cleanPath(url) {
        return decodeURIComponent(String(url || "").replace(/^file:\/\//, ""));
    }

    function sanitizedInstances() {
        const result = clone(SettingsData.desktopWidgetInstances || []);
        for (let i = 0; i < result.length; i++) {
            const config = result[i].config || {};
            delete config.localMusicFolder;
            delete config.videoPath;
            delete config.customCommand;
            delete config.customPath;
            result[i].config = config;
            result[i].positions = normalizedPositions(result[i].positions || {});
        }
        return result;
    }

    function scrubPrivateFields(value) {
        if (Array.isArray(value))
            return value.map(item => scrubPrivateFields(item));
        if (!value || typeof value !== "object")
            return value;
        const output = {};
        for (const key in value) {
            const normalized = key.toLowerCase();
            if (normalized.includes("password") || normalized.includes("token")
                    || normalized.includes("secret") || normalized.includes("command")
                    || normalized.includes("folder") || normalized.endsWith("path")
                    || normalized.includes("ssid") || normalized.includes("vpn"))
                continue;
            output[key] = scrubPrivateFields(value[key]);
        }
        return output;
    }

    function screenForKey(key) {
        const screens = Array.from(Quickshell.screens || []);
        return screens.find(screen => SettingsData.getScreenDisplayName(screen) === key || screen.name === key) || screens[0] || null;
    }

    function normalizedPositions(positions) {
        const output = {};
        for (const key in positions) {
            const position = clone(positions[key]);
            if (key !== "_synced") {
                const screen = screenForKey(key);
                if (screen) {
                    if (position.x !== undefined)
                        position.x = position.x / Math.max(1, screen.width);
                    if (position.y !== undefined)
                        position.y = position.y / Math.max(1, screen.height);
                    position.normalized = true;
                }
            }
            output[key] = position;
        }
        return output;
    }

    function denormalizedPositions(positions) {
        const output = {};
        const screens = Array.from(Quickshell.screens || []);
        for (const key in positions) {
            const position = clone(positions[key]);
            const screen = screenForKey(key) || screens[0] || null;
            const targetKey = key === "_synced" ? key
                            : (screen ? SettingsData.getScreenDisplayName(screen) : key);
            if (position.normalized && screen) {
                if (position.x !== undefined)
                    position.x = position.x * screen.width;
                if (position.y !== undefined)
                    position.y = position.y * screen.height;
            }
            delete position.normalized;
            output[targetKey] = position;
        }
        return output;
    }

    function createProfile(name) {
        return {
            kind: "org.kaskados.layout",
            version: formatVersion,
            name: name || "KaskadOS layout",
            createdAt: new Date().toISOString(),
            screens: Array.from(Quickshell.screens || []).map(screen => ({
                name: SettingsData.getScreenDisplayName(screen),
                width: screen.width,
                height: screen.height
            })),
            layout: {
                bars: scrubPrivateFields(clone(SettingsData.barConfigs || [])),
                barWorkspaceContexts: clone(SessionData.barWorkspaceContexts || {}),
                desktopWidgets: scrubPrivateFields(sanitizedInstances()),
                desktopWidgetGroups: clone(SettingsData.desktopWidgetGroups || []),
                dock: {
                    position: SettingsData.dockPosition,
                    spacing: SettingsData.dockSpacing,
                    margin: SettingsData.dockMargin,
                    iconSize: SettingsData.dockIconSize,
                    autoHide: SettingsData.dockAutoHide,
                    screenPreferences: clone(SettingsData.screenPreferences?.dock || ["primary"]),
                    workspaceContexts: clone(SessionData.dockWorkspaceContexts || [])
                },
                appearance: {
                    themeName: SettingsData.currentThemeName,
                    themeCategory: SettingsData.currentThemeCategory,
                    wallpaperFillMode: SettingsData.wallpaperFillMode
                }
            },
            assets: []
        };
    }

    function exportTo(url, name) {
        let path = cleanPath(url);
        if (!path.endsWith(".kaskadlayout"))
            path += ".kaskadlayout";
        error = "";
        pendingPath = path;
        writer.path = path;
        writer.setText(JSON.stringify(createProfile(name), null, 2));
    }

    function loadPreview(url) {
        error = "";
        pendingProfile = null;
        pendingPath = cleanPath(url);
        reader.path = pendingPath;
        reader.reload();
    }

    function validate(profile) {
        if (!profile || profile.kind !== "org.kaskados.layout")
            return I18n.tr("This is not a KaskadOS layout file");
        if (profile.version !== 1 && profile.version !== formatVersion)
            return I18n.tr("Unsupported layout format version");
        if (!profile.layout || !Array.isArray(profile.layout.bars) || !Array.isArray(profile.layout.desktopWidgets))
            return I18n.tr("The layout file is incomplete");
        if (profile.layout.bars.length > 32 || profile.layout.desktopWidgets.length > 512)
            return I18n.tr("The layout contains too many objects");
        return "";
    }

    function sanitizedContextList(value) {
        if (!Array.isArray(value))
            return [];
        return Array.from(new Set(value
            .map(item => String(item || ""))
            .filter(item => /^(primary|all|[A-Za-z0-9_.:-]+)::[1-9][0-9]*$/.test(item))));
    }

    function sanitizedBarContexts(value, bars) {
        const source = value && typeof value === "object" && !Array.isArray(value) ? value : {};
        const allowed = new Set(Array.from(bars || []).map(bar => String(bar?.id || "")));
        const output = {};
        for (const barId in source) {
            if (!allowed.has(barId))
                continue;
            const contexts = sanitizedContextList(source[barId]);
            if (contexts.length > 0)
                output[barId] = contexts;
        }
        return output;
    }

    function applyPending() {
        if (!pendingProfile)
            return false;
        const profile = pendingProfile;
        LayoutEditService.checkpoint();
        const widgets = scrubPrivateFields(clone(profile.layout.desktopWidgets || []));
        for (let i = 0; i < widgets.length; i++)
            widgets[i].positions = denormalizedPositions(widgets[i].positions || {});
        const bars = scrubPrivateFields(clone(profile.layout.bars || []));
        SettingsData.barConfigs = bars;
        SessionData.barWorkspaceContexts = sanitizedBarContexts(
            profile.layout.barWorkspaceContexts, bars);
        SettingsData.desktopWidgetInstances = widgets;
        SettingsData.desktopWidgetGroups = clone(profile.layout.desktopWidgetGroups || []);
        const dock = profile.layout.dock || {};
        if (dock.position !== undefined) SettingsData.dockPosition = dock.position;
        if (dock.spacing !== undefined) SettingsData.dockSpacing = dock.spacing;
        if (dock.margin !== undefined) SettingsData.dockMargin = dock.margin;
        if (dock.iconSize !== undefined) SettingsData.dockIconSize = dock.iconSize;
        if (dock.autoHide !== undefined) SettingsData.dockAutoHide = dock.autoHide;
        if (dock.screenPreferences !== undefined) {
            const preferences = clone(SettingsData.screenPreferences || {});
            preferences.dock = clone(dock.screenPreferences);
            SettingsData.screenPreferences = preferences;
        }
        SessionData.dockWorkspaceContexts = sanitizedContextList(dock.workspaceContexts);
        for (const bar of bars)
            SessionData.reconcileBarScreenPreferences(bar.id, bar.screenPreferences || ["all"]);
        SessionData.reconcileDockScreenPreferences(
            SettingsData.screenPreferences?.dock || ["primary"]);
        const appearance = profile.layout.appearance || {};
        if (appearance.themeName && /^[A-Za-z0-9._-]+$/.test(appearance.themeName)
                && !appearance.themeName.includes(".."))
            SettingsData.currentThemeName = appearance.themeName;
        if (appearance.themeCategory && /^[A-Za-z0-9._-]+$/.test(appearance.themeCategory))
            SettingsData.currentThemeCategory = appearance.themeCategory;
        if (["Fill", "Fit", "Stretch", "Center", "Tile", "Scrolling"].includes(appearance.wallpaperFillMode))
            SettingsData.wallpaperFillMode = appearance.wallpaperFillMode;
        SettingsData.applyStoredTheme();
        SettingsData.updateBarConfigs();
        SettingsData.saveSettings();
        SessionData.saveSettings();
        imported(profile.name || "KaskadOS layout");
        pendingProfile = null;
        return true;
    }

    property FileView writer: FileView {
        id: writer
        preload: false
        blockWrites: true
        atomicWrites: true
        printErrors: true
        onSaved: root.exported(root.pendingPath)
        onSaveFailed: message => root.error = String(message)
    }

    property FileView reader: FileView {
        id: reader
        preload: false
        blockLoading: true
        printErrors: true
        onLoaded: {
            try {
                const contents = reader.text();
                if (contents.length > 5 * 1024 * 1024) {
                    root.error = I18n.tr("The layout file is too large");
                    return;
                }
                const profile = JSON.parse(contents);
                const validationError = root.validate(profile);
                if (validationError) {
                    root.error = validationError;
                    return;
                }
                root.pendingProfile = profile;
                root.previewReady(profile);
            } catch (exception) {
                root.error = I18n.tr("The layout file is damaged");
            }
        }
        onLoadFailed: message => root.error = String(message)
    }
}

pragma Singleton

import QtQuick
import qs.Common

QtObject {
    id: root

    property bool active: false
    property string mode: "desktop"
    property string screenName: ""
    property string selectedKind: ""
    property string selectedId: ""
    property string selectedBarId: ""
    property string selectedBarSection: "centerWidgets"
    property int selectedBarIndex: -1
    property string settingsTargetId: ""
    property var baseline: null
    property var undoStack: []
    property var redoStack: []

    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0

    signal opened
    signal closed(bool committed)

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function snapshot() {
        return {
            barConfigs: clone(SettingsData.barConfigs || []),
            desktopWidgetInstances: clone(SettingsData.desktopWidgetInstances || []),
            desktopWidgetGroups: clone(SettingsData.desktopWidgetGroups || []),
            desktopWidgetGridSettings: clone(SettingsData.desktopWidgetGridSettings || {}),
            dockPosition: SettingsData.dockPosition,
            dockSpacing: SettingsData.dockSpacing,
            dockMargin: SettingsData.dockMargin,
            dockIconSize: SettingsData.dockIconSize,
            showDock: SettingsData.showDock,
            dockAutoHide: SettingsData.dockAutoHide,
            dockSmartAutoHide: SettingsData.dockSmartAutoHide,
            screenPreferences: clone(SettingsData.screenPreferences || {}),
            currentThemeName: SettingsData.currentThemeName,
            currentThemeCategory: SettingsData.currentThemeCategory,
            wallpaperFillMode: SettingsData.wallpaperFillMode,
            barWorkspaceContexts: clone(SessionData.barWorkspaceContexts || {}),
            dockWorkspaceContexts: clone(SessionData.dockWorkspaceContexts || [])
        };
    }

    function applySnapshot(value) {
        if (!value)
            return;
        SettingsData.barConfigs = clone(value.barConfigs || []);
        SettingsData.desktopWidgetInstances = clone(value.desktopWidgetInstances || []);
        SettingsData.desktopWidgetGroups = clone(value.desktopWidgetGroups || []);
        SettingsData.desktopWidgetGridSettings = clone(value.desktopWidgetGridSettings || {});
        const appearanceChanged = (value.currentThemeName !== undefined && value.currentThemeName !== SettingsData.currentThemeName)
                               || (value.currentThemeCategory !== undefined && value.currentThemeCategory !== SettingsData.currentThemeCategory);
        if (value.dockPosition !== undefined) SettingsData.dockPosition = value.dockPosition;
        if (value.dockSpacing !== undefined) SettingsData.dockSpacing = value.dockSpacing;
        if (value.dockMargin !== undefined) SettingsData.dockMargin = value.dockMargin;
        if (value.dockIconSize !== undefined) SettingsData.dockIconSize = value.dockIconSize;
        if (value.showDock !== undefined) SettingsData.showDock = value.showDock;
        if (value.dockAutoHide !== undefined) SettingsData.dockAutoHide = value.dockAutoHide;
        if (value.dockSmartAutoHide !== undefined) SettingsData.dockSmartAutoHide = value.dockSmartAutoHide;
        if (value.screenPreferences !== undefined) SettingsData.screenPreferences = clone(value.screenPreferences);
        if (value.currentThemeName !== undefined) SettingsData.currentThemeName = value.currentThemeName;
        if (value.currentThemeCategory !== undefined) SettingsData.currentThemeCategory = value.currentThemeCategory;
        if (value.wallpaperFillMode !== undefined) SettingsData.wallpaperFillMode = value.wallpaperFillMode;
        if (value.barWorkspaceContexts !== undefined)
            SessionData.barWorkspaceContexts = clone(value.barWorkspaceContexts);
        if (value.dockWorkspaceContexts !== undefined)
            SessionData.dockWorkspaceContexts = clone(value.dockWorkspaceContexts);
        SettingsData.updateBarConfigs();
        if (appearanceChanged)
            SettingsData.applyStoredTheme();
        SettingsData.saveSettings();
        SessionData.saveSettings();
    }

    function begin(editMode, targetScreen) {
        if (!active) {
            baseline = snapshot();
            undoStack = [];
            redoStack = [];
        }
        mode = ["desktop", "panel", "dock"].includes(editMode) ? editMode : "desktop";
        screenName = targetScreen || "";
        selectedKind = "";
        selectedId = "";
        selectedBarIndex = -1;
        active = true;
        opened();
    }

    function checkpoint() {
        if (!active)
            return;
        const current = snapshot();
        if (undoStack.length > 0 && JSON.stringify(undoStack[undoStack.length - 1]) === JSON.stringify(current))
            return;
        const next = undoStack.slice();
        next.push(current);
        if (next.length > 50)
            next.shift();
        undoStack = next;
        redoStack = [];
    }

    function undo() {
        if (!canUndo)
            return;
        const previous = undoStack[undoStack.length - 1];
        const nextUndo = undoStack.slice(0, -1);
        const nextRedo = redoStack.slice();
        nextRedo.push(snapshot());
        undoStack = nextUndo;
        redoStack = nextRedo;
        applySnapshot(previous);
    }

    function redo() {
        if (!canRedo)
            return;
        const next = redoStack[redoStack.length - 1];
        const nextRedo = redoStack.slice(0, -1);
        const nextUndo = undoStack.slice();
        nextUndo.push(snapshot());
        undoStack = nextUndo;
        redoStack = nextRedo;
        applySnapshot(next);
    }

    function commit() {
        if (!active)
            return;
        active = false;
        baseline = null;
        undoStack = [];
        redoStack = [];
        clearSelection();
        closed(true);
    }

    function cancel() {
        if (!active)
            return;
        applySnapshot(baseline);
        active = false;
        baseline = null;
        undoStack = [];
        redoStack = [];
        clearSelection();
        closed(false);
    }

    function selectDesktopWidget(instanceId) {
        selectedKind = "desktopWidget";
        selectedId = instanceId || "";
        selectedBarId = "";
        selectedBarIndex = -1;
    }

    function selectBarWidget(barId, section, index) {
        selectedKind = "barWidget";
        selectedId = "";
        selectedBarId = barId || "";
        selectedBarSection = section || "centerWidgets";
        selectedBarIndex = index;
    }

    function selectBar(barId) {
        selectedKind = "bar";
        selectedId = "";
        selectedBarId = barId || "";
        selectedBarSection = "centerWidgets";
        selectedBarIndex = -1;
    }

    function clearSelection() {
        selectedKind = "";
        selectedId = "";
        selectedBarId = "";
        selectedBarIndex = -1;
    }

    function requestDesktopWidgetSettings(instanceId) {
        settingsTargetId = instanceId || "";
    }

    function addDesktopWidget(widgetType) {
        const definition = DesktopWidgetRegistry.getWidget(widgetType);
        if (!definition)
            return null;
        checkpoint();
        const created = SettingsData.createDesktopWidgetInstance(widgetType, definition.name,
                                                                  clone(DesktopWidgetRegistry.getDefaultConfig(widgetType)));
        selectDesktopWidget(created.id);
        return created;
    }

    function duplicateSelected() {
        if (selectedKind !== "desktopWidget" || !selectedId)
            return;
        const source = SettingsData.getDesktopWidgetInstance(selectedId);
        if (!source)
            return;
        checkpoint();
        const created = SettingsData.duplicateDesktopWidgetInstance(selectedId);
        if (!created)
            return;
        const positions = clone(source.positions || {});
        for (const key in positions) {
            if (positions[key].x !== undefined)
                positions[key].x += key === "_synced" ? 0.02 : 24;
            if (positions[key].y !== undefined)
                positions[key].y += key === "_synced" ? 0.02 : 24;
        }
        SettingsData.updateDesktopWidgetInstance(created.id, { positions: positions });
        selectDesktopWidget(created.id);
    }

    function removeSelected() {
        if (selectedKind !== "desktopWidget" || !selectedId)
            return;
        checkpoint();
        SettingsData.removeDesktopWidgetInstance(selectedId);
        clearSelection();
    }

    function setBarEdge(barId, position) {
        if (!barId)
            return;
        checkpoint();
        SettingsData.updateBarConfig(barId, { position: position });
    }

    function createBar(screen) {
        if ((SettingsData.barConfigs || []).length >= 32) {
            ToastService.showWarning(I18n.tr("The panel limit has been reached"));
            return;
        }
        const source = SettingsData.getBarConfig("default") || SettingsData.barConfigs[0];
        if (!source)
            return;
        checkpoint();
        const copy = clone(source);
        copy.id = "bar_" + Date.now() + "_" + Math.random().toString(36).substr(2, 6);
        copy.name = I18n.tr("New panel");
        copy.enabled = true;
        copy.leftWidgets = [];
        copy.centerWidgets = [];
        copy.rightWidgets = [];
        copy.screenPreferences = screen ? [SettingsData.getScreenDisplayName(screen)] : ["all"];
        SettingsData.addBarConfig(copy);
        selectBar(copy.id);
    }

    function duplicateBar(barId, screen) {
        if ((SettingsData.barConfigs || []).length >= 32) {
            ToastService.showWarning(I18n.tr("The panel limit has been reached"));
            return;
        }
        const source = SettingsData.getBarConfig(barId);
        if (!source)
            return;
        checkpoint();
        const copy = clone(source);
        copy.id = "bar_" + Date.now() + "_" + Math.random().toString(36).substr(2, 6);
        copy.name = (source.name || I18n.tr("Panel")) + " — " + I18n.tr("copy");
        copy.screenPreferences = screen ? [SettingsData.getScreenDisplayName(screen)] : clone(source.screenPreferences || ["all"]);
        const sections = ["leftWidgets", "centerWidgets", "rightWidgets"];
        for (const section of sections) {
            copy[section] = (copy[section] || []).filter(widget => {
                return (typeof widget === "string" ? widget : widget?.id) !== "systemTray";
            }).map(widget => {
                if (typeof widget === "string")
                    return widget;
                const item = clone(widget);
                item.instanceId = "bw_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9);
                return item;
            });
        }
        SettingsData.addBarConfig(copy);
        selectBar(copy.id);
    }

    function removeBar(barId) {
        if (!barId || barId === "default" || SettingsData.barConfigs.length <= 1) {
            ToastService.showWarning(I18n.tr("The main panel cannot be removed"));
            return;
        }
        checkpoint();
        SettingsData.deleteBarConfig(barId);
        const fallback = SettingsData.getEnabledBarConfigs()[0] || SettingsData.barConfigs[0];
        selectBar(fallback?.id || "");
    }

    function setBarScreenScope(barId, screen, allScreens) {
        if (!barId || !screen)
            return;
        checkpoint();
        const key = SettingsData.getScreenDisplayName(screen);
        SettingsData.updateBarConfig(barId, {
            screenPreferences: allScreens ? ["all"] : [key]
        });
    }

    function moveBarToScreen(barId, screen) {
        setBarScreenScope(barId, screen, false);
        if (screen)
            screenName = SettingsData.getScreenDisplayName(screen);
    }

    function selectAdjacentBar(currentBarId, delta) {
        const bars = SettingsData.getEnabledBarConfigs();
        if (bars.length === 0) {
            clearSelection();
            return;
        }
        let index = bars.findIndex(bar => bar.id === currentBarId);
        if (index < 0)
            index = 0;
        else
            index = (index + delta + bars.length) % bars.length;
        selectBar(bars[index].id);
    }

    function toggleBarCurrentWorkspace(barId, screen) {
        if (!barId || !screen || !CompositorService.isKaskad)
            return;
        checkpoint();
        const visible = SessionData.isBarVisibleInContext(barId, screen.name, "");
        SessionData.setBarVisibleInContext(barId, screen.name, "", !visible);
    }

    function moveSelectedBarWidget(delta) {
        if (selectedKind !== "barWidget" || !selectedBarId || selectedBarIndex < 0)
            return;
        const config = SettingsData.getBarConfig(selectedBarId);
        if (!config)
            return;
        const list = clone(config[selectedBarSection] || []);
        const target = selectedBarIndex + delta;
        if (target < 0 || target >= list.length)
            return;
        checkpoint();
        const item = list.splice(selectedBarIndex, 1)[0];
        list.splice(target, 0, item);
        const update = {};
        update[selectedBarSection] = list;
        SettingsData.updateBarConfig(selectedBarId, update);
        selectedBarIndex = target;
    }

    function moveSelectedBarWidgetToSection(direction) {
        if (selectedKind !== "barWidget" || !selectedBarId || selectedBarIndex < 0)
            return;
        const sections = ["leftWidgets", "centerWidgets", "rightWidgets"];
        const sourceSectionIndex = sections.indexOf(selectedBarSection);
        const targetSectionIndex = sourceSectionIndex + direction;
        if (sourceSectionIndex < 0 || targetSectionIndex < 0 || targetSectionIndex >= sections.length)
            return;
        const config = SettingsData.getBarConfig(selectedBarId);
        if (!config)
            return;
        const source = clone(config[selectedBarSection] || []);
        const targetSection = sections[targetSectionIndex];
        const target = clone(config[targetSection] || []);
        if (selectedBarIndex >= source.length)
            return;
        checkpoint();
        const item = source.splice(selectedBarIndex, 1)[0];
        target.push(item);
        const update = {};
        update[selectedBarSection] = source;
        update[targetSection] = target;
        SettingsData.updateBarConfig(selectedBarId, update);
        selectedBarSection = targetSection;
        selectedBarIndex = target.length - 1;
    }

    function removeSelectedBarWidget() {
        if (selectedKind !== "barWidget" || !selectedBarId || selectedBarIndex < 0)
            return;
        const config = SettingsData.getBarConfig(selectedBarId);
        if (!config)
            return;
        const list = clone(config[selectedBarSection] || []);
        if (selectedBarIndex >= list.length)
            return;
        checkpoint();
        list.splice(selectedBarIndex, 1);
        const update = {};
        update[selectedBarSection] = list;
        SettingsData.updateBarConfig(selectedBarId, update);
        clearSelection();
    }

    function toggleSelectedBarWidgetEnabled() {
        if (selectedKind !== "barWidget" || !selectedBarId || selectedBarIndex < 0)
            return;
        const config = SettingsData.getBarConfig(selectedBarId);
        if (!config)
            return;
        const list = clone(config[selectedBarSection] || []);
        if (selectedBarIndex >= list.length)
            return;
        const current = list[selectedBarIndex];
        checkpoint();
        if (typeof current === "string") {
            list[selectedBarIndex] = {
                id: current,
                enabled: false,
                instanceId: "bw_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9)
            };
        } else {
            current.enabled = current.enabled === false;
        }
        const update = {};
        update[selectedBarSection] = list;
        SettingsData.updateBarConfig(selectedBarId, update);
    }

    function resizeSelectedSpacer(delta) {
        if (selectedKind !== "barWidget" || !selectedBarId || selectedBarIndex < 0)
            return;
        const config = SettingsData.getBarConfig(selectedBarId);
        const list = clone(config?.[selectedBarSection] || []);
        if (selectedBarIndex >= list.length)
            return;
        const current = list[selectedBarIndex];
        const widgetId = typeof current === "string" ? current : current?.id;
        if (widgetId !== "spacer")
            return;
        checkpoint();
        const item = typeof current === "string" ? { id: current, enabled: true } : current;
        item.size = Math.max(5, Math.min(5000, (item.size || 20) + delta));
        if (!item.instanceId)
            item.instanceId = "bw_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9);
        list[selectedBarIndex] = item;
        const update = {};
        update[selectedBarSection] = list;
        SettingsData.updateBarConfig(selectedBarId, update);
    }

    function toggleCenteringMode() {
        checkpoint();
        SettingsData.set("centeringMode", SettingsData.centeringMode === "geometric" ? "index" : "geometric");
    }

    function toggleDockOnWorkspace(screen) {
        if (!screen)
            return;
        checkpoint();
        const visible = SessionData.isDockVisibleInContext(screen.name, "");
        if (!SettingsData.showDock)
            SettingsData.setShowDock(true);
        SessionData.setDockVisibleInContext(screen.name, "", !visible);
    }

    function setDockEnabled(enabled, screen) {
        checkpoint();
        SettingsData.setShowDock(enabled);
        if (enabled && screen && CompositorService.isKaskad
                && !SessionData.isDockVisibleInContext(screen.name, ""))
            SessionData.setDockVisibleInContext(screen.name, "", true);
    }

    function setDockEdge(position) {
        checkpoint();
        SettingsData.setDockPosition(position);
    }

    function toggleDockAutoHide() {
        checkpoint();
        const enabled = !SettingsData.dockAutoHide;
        if (enabled && SettingsData.dockSmartAutoHide)
            SettingsData.set("dockSmartAutoHide", false);
        SettingsData.set("dockAutoHide", enabled);
    }

    function addBarWidget(barId, section, widgetId) {
        if (!barId || !widgetId)
            return;
        const config = SettingsData.getBarConfig(barId);
        if (!config)
            return;
        if (widgetId === "systemTray" && SettingsData.hasConfiguredSystemTray()) {
            ToastService.showWarning(I18n.tr("The system tray can only be used once"));
            return;
        }
        const key = section || "centerWidgets";
        const list = clone(config[key] || []);
        checkpoint();
        const item = {
            id: widgetId,
            enabled: true,
            instanceId: "bw_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9)
        };
        if (widgetId === "spacer")
            item.size = 20;
        list.push(item);
        const update = {};
        update[key] = list;
        SettingsData.updateBarConfig(barId, update);
        selectBarWidget(barId, key, list.length - 1);
    }
}

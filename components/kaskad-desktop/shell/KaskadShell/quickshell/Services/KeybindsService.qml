pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import Kaskad.Ipc
import qs.Common
import qs.Services
import "../Common/ConfigIncludeResolve.js" as ConfigIncludeResolve
import "../Common/KeybindActions.js" as Actions

Singleton {
    id: root
    readonly property var log: Log.scoped("KeybindsService")

    property bool available: CompositorService.isNiri || CompositorService.isHyprland || CompositorService.isMango || (CompositorService.isKaskad && Kaskad.protocolVersion >= 4)
    property string currentProvider: {
        if (CompositorService.isNiri)
            return "niri";
        if (CompositorService.isHyprland)
            return "hyprland";
        if (CompositorService.isMango)
            return "mangowc";
        if (CompositorService.isKaskad)
            return "kaskad";
        return "";
    }

    readonly property string cheatsheetProvider: {
        if (CompositorService.isNiri)
            return "niri";
        if (CompositorService.isHyprland)
            return "hyprland";
        if (CompositorService.isMango)
            return "mangowc";
        return "";
    }
    property bool cheatsheetAvailable: cheatsheetProvider !== ""
    property bool cheatsheetLoading: false
    property var cheatsheet: ({})

    property bool loading: false
    property bool saving: false
    property bool fixing: false
    property string lastError: ""
    property string modKey: "Super"
    property bool kaskadShellBindsIncluded: true

    property var kaskadShellStatus: ({
            "exists": true,
            "included": true,
            "includePosition": -1,
            "totalIncludes": 0,
            "bindsAfterKaskad": 0,
            "effective": true,
            "overriddenBy": 0,
            "statusMessage": "",
            "configFormat": "",
            "readOnly": false
        })

    property var _rawData: null
    property var keybinds: ({})
    property var _allBinds: ({})
    property var _categories: []
    property var _flatCache: []
    property var displayList: []
    property int _dataVersion: 0
    property string _pendingSavedKey: ""

    readonly property var categoryOrder: Actions.getCategoryOrder()
    readonly property string configDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation))
    readonly property string compositorConfigDir: {
        switch (currentProvider) {
        case "niri":
            return configDir + "/niri";
        case "hyprland":
            return configDir + "/hypr";
        case "mangowc":
            return configDir + "/mango";
        default:
            return "";
        }
    }
    readonly property string kaskadShellBindsPath: {
        switch (currentProvider) {
        case "niri":
            return compositorConfigDir + "/kaskad-shell/binds.kdl";
        case "hyprland":
            return compositorConfigDir + "/kaskad-shell/binds.lua";
        case "mangowc":
            return compositorConfigDir + "/kaskad-shell/binds.conf";
        default:
            return "";
        }
    }
    readonly property string mainConfigPath: {
        switch (currentProvider) {
        case "niri":
            return compositorConfigDir + "/config.kdl";
        case "hyprland":
            return compositorConfigDir + "/hyprland.lua";
        case "mangowc":
            return compositorConfigDir + "/config.conf";
        default:
            return "";
        }
    }
    readonly property bool readOnly: currentProvider === "hyprland" && kaskadShellStatus.readOnly === true
    readonly property var actionTypes: Actions.getActionTypes()
    readonly property var kaskadShellActions: getKaskadActions()

    signal bindsLoaded
    signal bindSaved(string key)
    signal bindSaveCompleted(bool success)
    signal bindRemoved(string key)
    signal kaskadShellBindsFixed
    signal cheatsheetLoaded

    Connections {
        target: CompositorService
        function onCompositorChanged() {
            if (!CompositorService.isNiri && !CompositorService.isMango)
                return;
            Qt.callLater(root.loadBinds);
        }
    }

    Connections {
        target: NiriService
        enabled: CompositorService.isNiri
        function onConfigReloaded() {
            Qt.callLater(root.loadBinds, false);
        }
    }

    Process {
        id: cheatsheetProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.cheatsheet = JSON.parse(text);
                } catch (e) {
                    log.error("Failed to parse cheatsheet:", e);
                    root.cheatsheet = {};
                }
                root.cheatsheetLoading = false;
                root.cheatsheetLoaded();
            }
        }

        onExited: exitCode => {
            if (exitCode === 0)
                return;
            log.warn("Cheatsheet load failed with code:", exitCode);
            root.cheatsheetLoading = false;
        }
    }

    Process {
        id: loadProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._rawData = JSON.parse(text);
                    root._processData();
                } catch (e) {
                    log.error("Failed to parse binds:", e);
                }
                root.loading = false;
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                log.warn("Load process failed with code:", exitCode);
                root.loading = false;
            }
        }
    }

    Process {
        id: saveProcess
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;
                root.lastError = text.trim();
                ToastService.showError(I18n.tr("Failed to save keybind"), "", root.lastError, "keybinds");
            }
        }

        onExited: exitCode => {
            root.saving = false;
            if (exitCode !== 0) {
                log.error("Save failed with code:", exitCode);
                root.bindSaveCompleted(false);
                return;
            }
            root.lastError = "";
            root.bindSaveCompleted(true);
            if (CompositorService.isMango)
                MangoService.reloadConfig();
            root.loadBinds(false);
        }
    }

    Process {
        id: removeProcess
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;
                root.lastError = text.trim();
                ToastService.showError(I18n.tr("Failed to remove keybind"), "", root.lastError, "keybinds");
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                log.error("Remove failed with code:", exitCode);
                return;
            }
            root.lastError = "";
            if (CompositorService.isMango)
                MangoService.reloadConfig();
            root.loadBinds(false);
        }
    }

    Process {
        id: fixProcess
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;
                root.lastError = text.trim();
                ToastService.showError(I18n.tr("Failed to add binds include"), "", root.lastError, "keybinds");
            }
        }

        onExited: exitCode => {
            root.fixing = false;
            if (exitCode !== 0) {
                log.error("Fix failed with code:", exitCode);
                return;
            }
            root.lastError = "";
            root.kaskadShellBindsIncluded = true;
            root.kaskadShellBindsFixed();
            const bindsRel = root.currentProvider === "niri" ? "kaskad-shell/binds.kdl" : root.currentProvider === "hyprland" ? "kaskad-shell/binds.lua" : "kaskad-shell/binds.conf";
            ToastService.showInfo(I18n.tr("Binds include added"), I18n.tr("%1 is now included in config").arg(bindsRel), "", "keybinds");
            if (CompositorService.isMango)
                MangoService.reloadConfig();
            Qt.callLater(root.forceReload);
        }
    }

    function fixKaskadBindsInclude() {
        if (fixing || kaskadShellBindsIncluded || !compositorConfigDir)
            return;
        if (readOnly) {
            showHyprlandReadOnlyWarning();
            return;
        }
        fixing = true;
        const timestamp = Math.floor(Date.now() / 1000);
        const backupPath = `${mainConfigPath}.kaskadShellbackup${timestamp}`;
        let script;
        switch (currentProvider) {
        case "niri":
            script = ConfigIncludeResolve.buildRepairScript({
                configFile: mainConfigPath,
                backupFile: backupPath,
                fragmentFile: compositorConfigDir + "/kaskad-shell/binds.kdl",
                grepPattern: 'include.*"kaskad-shell/binds.kdl"',
                includeLine: 'include "kaskad-shell/binds.kdl"'
            });
            break;
        case "hyprland":
            script = ConfigIncludeResolve.buildRepairScript({
                configFile: mainConfigPath,
                backupFile: backupPath,
                fragmentFiles: [compositorConfigDir + "/kaskad-shell/binds.lua", compositorConfigDir + "/kaskad-shell/binds-user.lua"],
                includes: [
                    {
                        grepPattern: "kaskad-shell.binds",
                        includeLine: "require(\"kaskad-shell.binds\")"
                    },
                    {
                        grepPattern: "kaskad-shell.binds-user",
                        includeLine: "require(\"kaskad-shell.binds-user\")"
                    }
                ]
            });
            break;
        case "mangowc":
            script = ConfigIncludeResolve.buildRepairScript({
                configFile: mainConfigPath,
                backupFile: backupPath,
                fragmentFile: compositorConfigDir + "/kaskad-shell/binds.conf",
                grepPattern: "source.*kaskad-shell/binds.conf",
                includeLine: "source = ./kaskad-shell/binds.conf"
            });
            break;
        default:
            fixing = false;
            return;
        }
        fixProcess.command = ["sh", "-c", script];
        fixProcess.running = true;
    }

    function forceReload() {
        _allBinds = {};
        _flatCache = [];
        _categories = [];
        loadBinds(true);
    }

    function loadCheatsheet(provider) {
        if (cheatsheetProcess.running)
            return;
        const target = provider || cheatsheetProvider;
        if (!target)
            return;
        cheatsheetLoading = true;
        cheatsheetProcess.command = ["kaskad-shell", "keybinds", "show", target];
        cheatsheetProcess.running = true;
    }

    function loadBinds(showLoading) {
        if (loadProcess.running || !available)
            return;
        const hasData = Object.keys(_allBinds).length > 0;
        loading = showLoading !== false && !hasData;
        if (currentProvider === "kaskad") {
            _rawData = {
                "provider": "kaskad",
                "binds": {
                    "Screenshot": [{
                        "key": Kaskad.screenshotShortcut,
                        "action": "spawn kaskad-shell ipc call screenshot capture quick-region",
                        "desc": "Kaskad Screenshot: Quick Region",
                        "source": "kaskad-shell-default",
                        "hasDefault": true
                    }]
                }
            };
            _processData();
            loading = false;
            return;
        }
        loadProcess.command = ["kaskad-shell", "keybinds", "show", currentProvider];
        loadProcess.running = true;
    }

    function _processData() {
        keybinds = _rawData || {};
        modKey = currentProvider === "niri" ? (_rawData?.modKey || "Super") : "Super";
        kaskadShellBindsIncluded = _rawData?.kaskadShellBindsIncluded ?? true;
        const status = _rawData?.kaskadShellStatus;
        if (status) {
            kaskadShellStatus = {
                "exists": status.exists ?? true,
                "included": status.included ?? true,
                "includePosition": status.includePosition ?? -1,
                "totalIncludes": status.totalIncludes ?? 0,
                "bindsAfterKaskad": status.bindsAfterKaskad ?? 0,
                "effective": status.effective ?? true,
                "overriddenBy": status.overriddenBy ?? 0,
                "statusMessage": status.statusMessage ?? "",
                "configFormat": status.configFormat ?? "",
                "readOnly": status.readOnly === true
            };
        }
        _maybeWarnHyprlandLegacyConf();

        if (!_rawData?.binds) {
            _allBinds = {};
            _categories = [];
            _flatCache = [];
            displayList = [];
            _dataVersion++;
            bindsLoaded();
            if (_pendingSavedKey) {
                bindSaved(_pendingSavedKey);
                _pendingSavedKey = "";
            }
            return;
        }

        const processed = {};
        const bindsData = _rawData.binds;
        for (const cat in bindsData) {
            const binds = bindsData[cat];
            for (var i = 0; i < binds.length; i++) {
                const bind = binds[i];
                const targetCat = Actions.isKaskadAction(bind.action) ? "Kaskad" : cat;
                if (!processed[targetCat])
                    processed[targetCat] = [];
                processed[targetCat].push(bind);
            }
        }

        const sortedCats = Object.keys(processed).sort((a, b) => {
            const ai = categoryOrder.indexOf(a);
            const bi = categoryOrder.indexOf(b);
            return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
        });

        const grouped = [];
        const actionMap = {};
        for (var ci = 0; ci < sortedCats.length; ci++) {
            const category = sortedCats[ci];
            const binds = processed[category];
            if (!binds)
                continue;
            for (var i = 0; i < binds.length; i++) {
                const bind = binds[i];
                const action = bind.action || "";
                const sourceStr = bind.source || "config";
                const keyData = {
                    "key": bind.key || "",
                    "desc": bind.desc || "",
                    "source": sourceStr,
                    "isOverride": sourceStr === "kaskad-shell",
                    "isKaskadManaged": sourceStr === "kaskad-shell" || sourceStr === "kaskad-shell-default",
                    "hasDefault": bind.hasDefault === true,
                    "cooldownMs": bind.cooldownMs || 0,
                    "flags": bind.flags || "",
                    "allowWhenLocked": bind.allowWhenLocked || false,
                    "allowInhibiting": bind.allowInhibiting,
                    "repeat": bind.repeat
                };
                if (actionMap[action]) {
                    actionMap[action].keys.push(keyData);
                    if (!actionMap[action].desc && bind.desc)
                        actionMap[action].desc = bind.desc;
                    if (!actionMap[action].conflict && bind.conflict)
                        actionMap[action].conflict = bind.conflict;
                } else {
                    const entry = {
                        "category": category,
                        "action": action,
                        "desc": bind.desc || "",
                        "keys": [keyData],
                        "conflict": bind.conflict || null
                    };
                    actionMap[action] = entry;
                    grouped.push(entry);
                }
            }
        }

        const list = [];
        for (const cat of sortedCats) {
            list.push({
                "id": "cat:" + cat,
                "type": "category",
                "name": cat
            });
            const binds = processed[cat];
            if (!binds)
                continue;
            for (const bind of binds)
                list.push({
                    "id": "bind:" + bind.key,
                    "type": "bind",
                    "key": bind.key,
                    "desc": bind.desc
                });
        }

        _allBinds = processed;
        _categories = sortedCats;
        _flatCache = grouped;
        displayList = list;
        _dataVersion++;
        bindsLoaded();
        if (_pendingSavedKey) {
            bindSaved(_pendingSavedKey);
            _pendingSavedKey = "";
        }
    }

    function getCategories() {
        return _categories;
    }

    function getFlatBinds() {
        return _flatCache;
    }

    function keysForAction(actionId) {
        if (!actionId)
            return [];
        for (let i = 0; i < _flatCache.length; i++) {
            const group = _flatCache[i];
            if (!group || group.action !== actionId || !Array.isArray(group.keys))
                continue;
            const keys = [];
            for (let k = 0; k < group.keys.length; k++) {
                const key = group.keys[k]?.key || "";
                if (key)
                    keys.push(key);
            }
            return keys;
        }
        return [];
    }

    function saveBind(originalKey, bindData) {
        if (readOnly) {
            showHyprlandReadOnlyWarning();
            return;
        }
        if (!bindData.key || !Actions.isValidAction(bindData.action))
            return;
        if (currentProvider === "kaskad") {
            const saved = Kaskad.setScreenshotShortcut(bindData.key);
            bindSaveCompleted(saved);
            if (saved) {
                _pendingSavedKey = bindData.key;
                loadBinds(false);
            }
            return;
        }
        saving = true;
        const cmd = ["kaskad-shell", "keybinds", "set", currentProvider, bindData.key, bindData.action, "--desc", bindData.desc || ""];
        if (originalKey && originalKey !== bindData.key)
            cmd.push("--replace-key", originalKey);
        if (bindData.cooldownMs > 0)
            cmd.push("--cooldown-ms", String(bindData.cooldownMs));
        if (bindData.allowWhenLocked)
            cmd.push("--allow-when-locked");
        if (bindData.repeat === false)
            cmd.push("--no-repeat");
        if (bindData.allowInhibiting === false)
            cmd.push("--no-inhibiting");
        if (bindData.flags)
            cmd.push("--flags", bindData.flags);
        saveProcess.command = cmd;
        saveProcess.running = true;
        _pendingSavedKey = bindData.key;
    }

    property bool _hyprlandLegacyWarnShown: false

    function _maybeWarnHyprlandLegacyConf() {
        if (_hyprlandLegacyWarnShown)
            return;
        if (currentProvider !== "hyprland")
            return;
        if (readOnly) {
            _hyprlandLegacyWarnShown = true;
            showHyprlandReadOnlyWarning();
            return;
        }
        if (!kaskadShellStatus.exists || kaskadShellStatus.included)
            return;
        _hyprlandLegacyWarnShown = true;
        ToastService.showWarning(I18n.tr("Hyprland config include missing"), I18n.tr("Kaskad Settings writes Lua keybinds. Add the Kaskad include so edits apply."), "kaskad-shell setup", "hyprland-migration");
    }

    function showHyprlandReadOnlyWarning() {
        ToastService.showWarning(I18n.tr("Hyprland conf mode"), I18n.tr("This install is still using hyprland.conf. Run kaskad-shell setup to migrate before changing these settings."), "kaskad-shell setup", "hyprland-migration");
    }

    function removeBind(key) {
        if (readOnly) {
            showHyprlandReadOnlyWarning();
            return;
        }
        if (!key)
            return;
        if (currentProvider === "kaskad") {
            if (Kaskad.setScreenshotShortcut("")) {
                bindRemoved(key);
                loadBinds(false);
            }
            return;
        }
        removeProcess.command = ["kaskad-shell", "keybinds", "remove", currentProvider, key];
        removeProcess.running = true;
        bindRemoved(key);
    }

    function resetBind(key) {
        if (readOnly) {
            showHyprlandReadOnlyWarning();
            return;
        }
        if (!key)
            return;
        if (currentProvider === "kaskad") {
            if (Kaskad.setScreenshotShortcut("Super+Shift+S")) {
                bindRemoved(key);
                loadBinds(false);
            }
            return;
        }
        removeProcess.command = ["kaskad-shell", "keybinds", "reset", currentProvider, key];
        removeProcess.running = true;
        bindRemoved(key);
    }

    function isKaskadAction(action) {
        return Actions.isKaskadAction(action);
    }

    function isValidAction(action) {
        return Actions.isValidAction(action);
    }

    function getActionType(action) {
        return Actions.getActionType(action);
    }

    function getActionLabel(action) {
        return Actions.getActionLabel(action, currentProvider);
    }

    function getCompositorCategories() {
        return Actions.getCompositorCategories(currentProvider);
    }

    function getCompositorActions(category) {
        return Actions.getCompositorActions(currentProvider, category);
    }

    function getKaskadActions() {
        return Actions.getKaskadActions(CompositorService.isNiri, CompositorService.isHyprland, CompositorService.isKaskad);
    }

    function buildSpawnAction(command, args) {
        return Actions.buildSpawnAction(command, args);
    }

    function buildShellAction(shellCmd, shell) {
        return Actions.buildShellAction(currentProvider, shellCmd, shell);
    }

    function getShellFromAction(action) {
        return Actions.getShellFromAction(action);
    }

    function parseSpawnCommand(action) {
        return Actions.parseSpawnCommand(action);
    }

    function parseShellCommand(action) {
        return Actions.parseShellCommand(action);
    }
}

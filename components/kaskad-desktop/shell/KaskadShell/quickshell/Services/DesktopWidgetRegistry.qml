pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root

    property var registeredWidgets: ({})
    property var registeredWidgetsList: []

    signal registryChanged

    Component.onCompleted: {
        registerBuiltins();
    }

    function registerBuiltins() {
        registerWidget({
            id: "desktopClock",
            name: I18n.tr("Desktop Clock", "Desktop clock widget name"),
            icon: "schedule",
            description: I18n.tr("Analog, digital, or stacked clock display", "Desktop clock widget description"),
            type: "builtin",
            component: "qs.Modules.BuiltinDesktopPlugins.DesktopClockWidget",
            settingsComponent: "qs.Modules.Settings.DesktopWidgetSettings.ClockSettings",
            defaultConfig: getDefaultClockConfig(),
            defaultSize: {
                width: 280,
                height: 180
            }
        });

        registerWidget({
            id: "systemMonitor",
            name: I18n.tr("System Monitor", "System monitor widget name"),
            icon: "monitoring",
            description: I18n.tr("CPU, memory, network, and disk monitoring", "System monitor widget description"),
            type: "builtin",
            component: "qs.Modules.BuiltinDesktopPlugins.SystemMonitorWidget",
            settingsComponent: "qs.Modules.Settings.DesktopWidgetSettings.SystemMonitorSettings",
            defaultConfig: getDefaultSystemMonitorConfig(),
            defaultSize: {
                width: 320,
                height: 480
            }
        });

        registerWidget({
            id: "video",
            name: I18n.tr("Video Widget", "Desktop video widget name"),
            icon: "movie",
            description: I18n.tr("Loop a local video on your desktop", "Desktop video widget description"),
            type: "builtin",
            component: "qs.Modules.BuiltinDesktopPlugins.VideoWidget",
            settingsComponent: "qs.Modules.Settings.DesktopWidgetSettings.VideoSettings",
            defaultConfig: getDefaultVideoConfig(),
            defaultSize: {
                width: 480,
                height: 270
            }
        });

        registerWidget({
            id: "audioPlayer",
            name: I18n.tr("Audio Player", "Desktop audio player widget name"),
            icon: "library_music",
            description: I18n.tr("Play an independent local music folder", "Desktop audio player widget description"),
            type: "builtin",
            component: "qs.Modules.BuiltinDesktopPlugins.AudioPlayerWidget",
            settingsComponent: "",
            defaultConfig: getDefaultAudioPlayerConfig(),
            defaultSize: {
                width: 440,
                height: 520
            }
        });

        registerWidget({
            id: "desktopLyrics",
            name: I18n.tr("Synchronized Lyrics", "Desktop lyrics widget name"),
            icon: "lyrics",
            description: I18n.tr("Live lyrics from the local player, Telegram, browsers and other media apps", "Desktop lyrics widget description"),
            type: "builtin",
            component: "qs.Modules.BuiltinDesktopPlugins.DesktopLyricsWidget",
            settingsComponent: "",
            defaultConfig: getDefaultLyricsConfig(),
            defaultSize: {
                width: 620,
                height: 230
            }
        });

        registerWidget({
            id: "taskNotes",
            name: I18n.tr("Tasks & Notes", "Desktop tasks widget name"),
            icon: "checklist",
            description: I18n.tr("Quick notes and tasks from the local planner", "Desktop tasks widget description"),
            type: "builtin",
            component: "qs.Modules.BuiltinDesktopPlugins.TasksWidget",
            settingsComponent: "",
            defaultConfig: getDefaultTaskNotesConfig(),
            defaultSize: {
                width: 380,
                height: 430
            }
        });
    }

    function getDefaultClockConfig() {
        return {
            style: "analog",
            transparency: 0.8,
            colorMode: "primary",
            customColor: "#ffffff",
            showDate: true,
            showAnalogNumbers: false,
            showAnalogSeconds: true,
            displayPreferences: ["all"]
        };
    }

    function getDefaultSystemMonitorConfig() {
        return {
            showHeader: true,
            transparency: 0.8,
            colorMode: "primary",
            customColor: "#ffffff",
            showCpu: true,
            showCpuGraph: true,
            showCpuTemp: true,
            showGpuTemp: false,
            gpuPciId: "",
            showMemory: true,
            showMemoryGraph: true,
            showNetwork: true,
            showNetworkGraph: true,
            showDisk: true,
            showTopProcesses: false,
            topProcessCount: 3,
            topProcessSortBy: "cpu",
            layoutMode: "auto",
            graphInterval: 60,
            displayPreferences: ["all"]
        };
    }

    function getDefaultVideoConfig() {
        return {
            videoPath: "",
            muted: true,
            volume: 1.0,
            opacity: 1.0,
            cornerRadius: 12,
            fillMode: "crop",
            displayPreferences: ["all"]
        };
    }

    function getDefaultAudioPlayerConfig() {
        return {
            localMusicFolder: "",
            localMusicRecursive: false,
            localMusicRepeatMode: "none",
            localMusicShuffle: false,
            localMusicVolume: 0.8,
            transparency: 0.96,
            displayPreferences: ["all"]
        };
    }

    function getDefaultLyricsConfig() {
        return {
            sourceMode: "auto",
            localInstanceId: "",
            mprisIdentity: "",
            syncOffsetMs: 0,
            transparency: 0.58,
            showBorder: true,
            displayPreferences: ["all"]
        };
    }

    function getDefaultTaskNotesConfig() {
        return {
            transparency: 0.94,
            showCompleted: false,
            maxItems: 8,
            displayPreferences: ["all"]
        };
    }

    function registerWidget(widgetDef) {
        if (!widgetDef?.id)
            return;

        const newMap = Object.assign({}, registeredWidgets);
        newMap[widgetDef.id] = widgetDef;
        registeredWidgets = newMap;
        _updateWidgetsList();
        registryChanged();
    }

    function unregisterWidget(widgetId) {
        if (!registeredWidgets[widgetId])
            return;

        const newMap = Object.assign({}, registeredWidgets);
        delete newMap[widgetId];
        registeredWidgets = newMap;
        _updateWidgetsList();
        registryChanged();
    }

    function getWidget(widgetType) {
        return registeredWidgets[widgetType] ?? null;
    }

    function getDefaultConfig(widgetType) {
        const widget = getWidget(widgetType);
        if (!widget)
            return {};

        if (widget.type === "builtin") {
            switch (widgetType) {
            case "desktopClock":
                return getDefaultClockConfig();
            case "systemMonitor":
                return getDefaultSystemMonitorConfig();
            case "video":
                return getDefaultVideoConfig();
            case "audioPlayer":
                return getDefaultAudioPlayerConfig();
            case "desktopLyrics":
                return getDefaultLyricsConfig();
            case "taskNotes":
                return getDefaultTaskNotesConfig();
            default:
                return widget.defaultConfig ?? {};
            }
        }

        return widget.defaultConfig ?? {};
    }

    function getDefaultSize(widgetType) {
        const widget = getWidget(widgetType);
        return widget?.defaultSize ?? {
            width: 200,
            height: 200
        };
    }

    function _updateWidgetsList() {
        const result = [];
        for (const key in registeredWidgets) {
            result.push(registeredWidgets[key]);
        }
        result.sort((a, b) => {
            if (a.type === "builtin" && b.type !== "builtin")
                return -1;
            if (a.type !== "builtin" && b.type === "builtin")
                return 1;
            return (a.name || "").localeCompare(b.name || "");
        });
        registeredWidgetsList = result;
    }

    function getBuiltinWidgets() {
        return registeredWidgetsList.filter(w => w.type === "builtin");
    }

    function getAllWidgets() {
        return registeredWidgetsList;
    }
}

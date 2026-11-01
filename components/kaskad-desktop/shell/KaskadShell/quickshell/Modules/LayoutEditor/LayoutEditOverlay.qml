import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

Variants {
    model: Quickshell.screens

    delegate: Scope {
        id: surface
        required property var modelData

        readonly property string screenKey: SettingsData.getScreenDisplayName(modelData)
        readonly property bool targetsThisScreen: !LayoutEditService.screenName
                                                  || LayoutEditService.screenName === screenKey
                                                  || LayoutEditService.screenName === modelData.name
        property bool catalogOpen: false

        readonly property var desktopCatalog: {
            const widgets = Array.from(DesktopWidgetRegistry.registeredWidgetsList || []);
            return widgets.sort((left, right) => {
                if (left.id === "taskNotes") return -1;
                if (right.id === "taskNotes") return 1;
                return String(left.name || "").localeCompare(String(right.name || ""));
            });
        }

        readonly property bool dockVisibleHere: {
            SessionData.dockWorkspaceContexts;
            return SessionData.isDockVisibleInContext(modelData.name, "");
        }

        readonly property var activeBar: {
            const bars = SettingsData.getEnabledBarConfigs();
            if (LayoutEditService.selectedBarId) {
                const selected = bars.find(bar => bar.id === LayoutEditService.selectedBarId);
                if (selected)
                    return selected;
            }
            return bars.find(bar => CompositorService.isKaskad
                       ? SessionData.isBarVisibleInContext(bar.id, modelData.name)
                       : SettingsData.isScreenInPreferences(modelData, bar.screenPreferences || ["all"]))
                   || bars[0] || null;
        }

        readonly property var panelCatalog: [
            { id: "launcherButton", title: "Меню приложений", icon: "apps" },
            { id: "appsDock", title: "Приложения", icon: "dock_to_bottom" },
            { id: "runningApps", title: "Запущенные приложения", icon: "apps" },
            { id: "workspaceSwitcher", title: "Рабочие столы", icon: "workspaces" },
            { id: "focusedWindow", title: "Активное окно", icon: "web_asset" },
            { id: "music", title: "Музыка", icon: "music_note" },
            { id: "clock", title: "Часы", icon: "schedule" },
            { id: "weather", title: "Погода", icon: "partly_cloudy_day" },
            { id: "systemTray", title: "Системный лоток", icon: "system_tray" },
            { id: "privacyIndicator", title: "Приватность", icon: "privacy_tip" },
            { id: "clipboard", title: "Буфер обмена", icon: "content_paste" },
            { id: "notificationButton", title: "Уведомления", icon: "notifications" },
            { id: "controlCenterButton", title: "Быстрые настройки", icon: "tune" },
            { id: "battery", title: "Батарея", icon: "battery_full" },
            { id: "vpn", title: "VPN", icon: "vpn_lock" },
            { id: "idleInhibitor", title: "Не выключать экран", icon: "motion_sensor_active" },
            { id: "capsLockIndicator", title: "Caps Lock", icon: "keyboard_capslock" },
            { id: "keyboard_layout_name", title: "Раскладка", icon: "keyboard" },
            { id: "network_speed_monitor", title: "Скорость сети", icon: "network_check" },
            { id: "cpuUsage", title: "Процессор", icon: "memory" },
            { id: "memUsage", title: "Память", icon: "developer_board" },
            { id: "diskUsage", title: "Диск", icon: "storage" },
            { id: "cpuTemp", title: "Температура CPU", icon: "device_thermostat" },
            { id: "gpuTemp", title: "Температура GPU", icon: "device_thermostat" },
            { id: "gpuUsage", title: "Нагрузка GPU", icon: "speed" },
            { id: "systemUpdate", title: "Обновления", icon: "system_update" },
            { id: "powerMenuButton", title: "Питание", icon: "power_settings_new" },
            { id: "notepadButton", title: "Заметки", icon: "edit_note" },
            { id: "colorPicker", title: "Пипетка", icon: "colorize" },
            { id: "layout", title: "Раскладка Mango", icon: "view_quilt" },
            { id: "separator", title: "Линия", icon: "horizontal_rule" },
            { id: "spacer", title: "Разделитель", icon: "space_bar" }
        ]

        readonly property int barPosition: LayoutEditService.mode === "dock"
                                                   ? SettingsData.dockPosition
                                                   : (activeBar?.position ?? SettingsData.Position.Top)
        readonly property real activeBarInnerPadding: activeBar?.innerPadding ?? 4
        readonly property real activeBarThickness: Math.max(26 + activeBarInnerPadding * 0.6,
                                                            Theme.barHeight - 4 - (8 - activeBarInnerPadding))
        readonly property real activeBarOuterSize: activeBarThickness
                                                    + (activeBar?.spacing ?? 4)
                                                    + (activeBar?.bottomGap ?? 0)
        readonly property bool editorFromBottom: barPosition === SettingsData.Position.Bottom
        readonly property real editorEdgeOffset: LayoutEditService.mode === "dock"
                                                  ? Math.max(Theme.spacingM,
                                                             SettingsData.dockIconSize
                                                             + SettingsData.dockMargin * 2
                                                             + Theme.spacingS)
                                                  : ((barPosition === SettingsData.Position.Top
                                                      || barPosition === SettingsData.Position.Bottom)
                                                     ? activeBarOuterSize + Theme.spacingS
                                                     : Theme.spacingM)
        readonly property real commandRailHeight: 52
        readonly property real contextRailOffset: editorEdgeOffset + commandRailHeight + Theme.spacingXS

        function moveActiveBarToNextScreen() {
            const screens = Array.from(Quickshell.screens || []);
            if (!activeBar || screens.length < 2)
                return;
            const preferences = activeBar.screenPreferences || ["all"];
            let currentIndex = screens.findIndex(candidate =>
                preferences.includes(SettingsData.getScreenDisplayName(candidate)));
            if (currentIndex < 0)
                currentIndex = screens.findIndex(candidate => candidate.name === modelData.name);
            const target = screens[(currentIndex + 1) % screens.length];
            LayoutEditService.moveBarToScreen(activeBar.id, target);
        }

        PanelWindow {
            id: commandWindow
            screen: surface.modelData
            visible: LayoutEditService.active && surface.targetsThisScreen
            color: "transparent"
            anchors.left: true
            anchors.right: true
            anchors.top: !surface.editorFromBottom
            anchors.bottom: surface.editorFromBottom
            implicitHeight: surface.commandRailHeight

            WlrLayershell.namespace: "kaskados:layout-editor:commands"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            WlrLayershell.margins.top: !surface.editorFromBottom ? surface.editorEdgeOffset : 0
            WlrLayershell.margins.bottom: surface.editorFromBottom ? surface.editorEdgeOffset : 0

            Rectangle {
                id: commandRail
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: commandRow.implicitWidth + Theme.spacingS * 2
                height: 50
                radius: height / 2
                color: Theme.withAlpha(Theme.surfaceContainer, 0.82)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.9)

                Row {
                    id: commandRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    EditButton {
                        iconName: "dashboard_customize"
                        label: "Рабочий стол"
                        emphasized: LayoutEditService.mode === "desktop"
                        onActivated: surface.selectMode("desktop")
                    }
                    EditButton {
                        iconName: "view_day"
                        label: "Панель"
                        emphasized: LayoutEditService.mode === "panel"
                        onActivated: surface.selectMode("panel")
                    }
                    EditButton {
                        iconName: "dock_to_bottom"
                        label: "Док"
                        emphasized: LayoutEditService.mode === "dock"
                        onActivated: surface.selectMode("dock")
                    }
                    EditButton {
                        visible: LayoutEditService.mode !== "dock"
                        iconName: "add"
                        label: LayoutEditService.mode === "desktop" ? "Добавить виджет" : "Добавить в панель"
                        onActivated: surface.catalogOpen = !surface.catalogOpen
                    }
                    EditButton { iconName: "undo"; label: "Отменить"; compact: true; enabled: LayoutEditService.canUndo; onActivated: LayoutEditService.undo() }
                    EditButton { iconName: "redo"; label: "Повторить"; compact: true; enabled: LayoutEditService.canRedo; onActivated: LayoutEditService.redo() }
                    EditButton { iconName: "file_open"; label: "Импорт"; compact: true; onActivated: importDialog.open() }
                    EditButton { iconName: "save"; label: "Экспорт"; compact: true; onActivated: exportDialog.open() }
                    EditButton { iconName: "close"; label: "Не сохранять"; danger: true; onActivated: LayoutEditService.cancel() }
                    EditButton { iconName: "check"; label: "Готово"; emphasized: true; onActivated: LayoutEditService.commit() }
                }
            }

            FileDialog {
                id: importDialog
                title: "Импорт макета KaskadOS"
                fileMode: FileDialog.OpenFile
                nameFilters: ["Макеты KaskadOS (*.kaskadlayout)", "Все файлы (*)"]
                currentFolder: Paths.home
                onAccepted: LayoutProfileService.loadPreview(selectedFile)
            }

            FileDialog {
                id: exportDialog
                title: "Экспорт макета KaskadOS"
                fileMode: FileDialog.SaveFile
                nameFilters: ["Макеты KaskadOS (*.kaskadlayout)"]
                currentFolder: Paths.home
                currentFile: Paths.toFileUrl(Paths.strip(Paths.home) + "/my-layout.kaskadlayout")
                onAccepted: LayoutProfileService.exportTo(selectedFile, "KaskadOS layout")
            }

            Connections {
                target: LayoutProfileService
                function onPreviewReady(profile) {
                    previewTitle.text = profile.name || "Макет KaskadOS";
                    previewSummary.text = profile.layout.bars.length + " панелей · "
                                          + profile.layout.desktopWidgets.length + " виджетов";
                    previewPopup.open();
                }
                function onExported(path) { ToastService.showInfo("Макет экспортирован", path); }
                function onImported(name) { ToastService.showInfo("Макет импортирован", name); }
                function onErrorChanged() {
                    if (LayoutProfileService.error)
                        ToastService.showError("Не удалось открыть макет", LayoutProfileService.error);
                }
            }

            Popup {
                id: previewPopup
                anchors.centerIn: parent
                width: 440
                height: 210
                modal: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                background: Rectangle {
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainer
                    border.width: 1
                    border.color: Theme.outline
                }
                contentItem: Column {
                    spacing: Theme.spacingM
                    StyledText { id: previewTitle; width: parent.width - Theme.spacingL * 2; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold; elide: Text.ElideRight }
                    StyledText { id: previewSummary; width: parent.width - Theme.spacingL * 2; color: Theme.surfaceVariantText }
                    StyledText { width: parent.width - Theme.spacingL * 2; text: "Сети, аккаунты, пароли, локальные папки и параметры устройств не импортируются."; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap }
                    Row {
                        spacing: Theme.spacingS
                        EditButton { iconName: "close"; label: "Отмена"; onActivated: previewPopup.close() }
                        EditButton { iconName: "check"; label: "Применить"; emphasized: true; onActivated: { LayoutProfileService.applyPending(); previewPopup.close(); } }
                    }
                }
            }
        }

        function selectMode(nextMode) {
            surface.catalogOpen = false;
            LayoutEditService.clearSelection();
            LayoutEditService.mode = nextMode;
        }

        PanelWindow {
            id: panelTools
            screen: surface.modelData
            visible: LayoutEditService.active && surface.targetsThisScreen
                     && LayoutEditService.mode === "panel" && surface.activeBar !== null
            color: "transparent"
            anchors.left: true
            anchors.right: true
            anchors.top: !surface.editorFromBottom
            anchors.bottom: surface.editorFromBottom
            implicitHeight: 52

            WlrLayershell.namespace: "kaskados:layout-editor:panel-context"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.margins.top: !surface.editorFromBottom ? surface.contextRailOffset : 0
            WlrLayershell.margins.bottom: surface.editorFromBottom ? surface.contextRailOffset : 0

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(contextRow.implicitWidth + Theme.spacingS * 2,
                                surface.modelData.width - Theme.spacingL * 2)
                height: 50
                radius: height / 2
                color: Theme.withAlpha(Theme.surfaceContainer, 0.82)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.9)

                Row {
                    id: contextRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                EditButton { iconName: "add"; label: "Новая панель"; compact: true; onActivated: LayoutEditService.createBar(surface.modelData) }
                EditButton {
                    iconName: "swap_horiz"
                    label: surface.activeBar?.name || "Панель"
                    maxWidth: 190
                    onActivated: LayoutEditService.selectAdjacentBar(surface.activeBar?.id || "", 1)
                }
                EditButton { iconName: "content_copy"; label: "Создать копию"; compact: true; onActivated: LayoutEditService.duplicateBar(surface.activeBar?.id || "", surface.modelData) }
                EditButton {
                    iconName: "delete"
                    label: "Удалить панель"
                    compact: true
                    danger: true
                    enabled: surface.activeBar?.id !== "default" && (SettingsData.barConfigs || []).length > 1
                    onActivated: LayoutEditService.removeBar(surface.activeBar?.id || "")
                }
                EditButton { iconName: "add_box"; label: "Добавить элемент"; compact: true; onActivated: surface.catalogOpen = !surface.catalogOpen }
                EditButton {
                    iconName: (surface.activeBar?.screenPreferences || ["all"]).includes("all") ? "desktop_windows" : "desktop_mac"
                    label: (surface.activeBar?.screenPreferences || ["all"]).includes("all") ? "Все экраны" : "Этот экран"
                    compact: true
                    onActivated: {
                        const all = (surface.activeBar?.screenPreferences || ["all"]).includes("all");
                        LayoutEditService.setBarScreenScope(surface.activeBar?.id || "", surface.modelData, !all);
                    }
                }
                EditButton { visible: Quickshell.screens.length > 1; iconName: "screen_share"; label: "На следующий экран"; compact: true; onActivated: surface.moveActiveBarToNextScreen() }
                EditButton { visible: CompositorService.isKaskad; iconName: "visibility"; label: "Текущий стол"; compact: true; onActivated: LayoutEditService.toggleBarCurrentWorkspace(surface.activeBar?.id || "", surface.modelData) }
                    EditButton {
                        iconName: SettingsData.centeringMode === "geometric" ? "center_focus_weak" : "format_list_numbered"
                        label: SettingsData.centeringMode === "geometric" ? "Геометрический центр" : "Центр по порядку"
                        compact: true
                        onActivated: LayoutEditService.toggleCenteringMode()
                    }
                    Rectangle { width: 1; height: 28; anchors.verticalCenter: parent.verticalCenter; color: Theme.outline; opacity: 0.7 }
                    Repeater {
                        model: [
                            { icon: "vertical_align_top", value: SettingsData.Position.Top, tip: "Сверху" },
                            { icon: "vertical_align_bottom", value: SettingsData.Position.Bottom, tip: "Снизу" },
                            { icon: "align_horizontal_left", value: SettingsData.Position.Left, tip: "Слева" },
                            { icon: "align_horizontal_right", value: SettingsData.Position.Right, tip: "Справа" }
                        ]
                        EditButton {
                            required property var modelData
                            iconName: modelData.icon
                            label: modelData.tip
                            compact: true
                            emphasized: surface.barPosition === modelData.value
                            onActivated: LayoutEditService.setBarEdge(surface.activeBar?.id || "", modelData.value)
                        }
                    }
                }
            }
        }

        PanelWindow {
            id: dockTools
            screen: surface.modelData
            visible: LayoutEditService.active && surface.targetsThisScreen
                     && LayoutEditService.mode === "dock"
            color: "transparent"
            anchors.left: true
            anchors.right: true
            anchors.top: !surface.editorFromBottom
            anchors.bottom: surface.editorFromBottom
            implicitHeight: 52

            WlrLayershell.namespace: "kaskados:layout-editor:dock-context"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.margins.top: !surface.editorFromBottom ? surface.contextRailOffset : 0
            WlrLayershell.margins.bottom: surface.editorFromBottom ? surface.contextRailOffset : 0

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(dockContextRow.implicitWidth + Theme.spacingS * 2,
                                surface.modelData.width - Theme.spacingL * 2)
                height: 50
                radius: height / 2
                color: Theme.withAlpha(Theme.surfaceContainer, 0.82)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.9)

                Row {
                    id: dockContextRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    EditButton {
                        iconName: SettingsData.showDock ? "visibility" : "visibility_off"
                        label: SettingsData.showDock ? "Док включён" : "Док выключен"
                        emphasized: SettingsData.showDock
                        onActivated: LayoutEditService.setDockEnabled(!SettingsData.showDock, surface.modelData)
                    }
                    EditButton {
                        visible: CompositorService.isKaskad
                        iconName: surface.dockVisibleHere ? "desktop_windows" : "add_to_home_screen"
                        label: surface.dockVisibleHere ? "На этом столе" : "Показать здесь"
                        emphasized: surface.dockVisibleHere
                        onActivated: LayoutEditService.toggleDockOnWorkspace(surface.modelData)
                    }
                    EditButton {
                        iconName: SettingsData.dockAutoHide ? "keyboard_arrow_down" : "keep"
                        label: SettingsData.dockAutoHide ? "Автоскрытие" : "Всегда виден"
                        onActivated: LayoutEditService.toggleDockAutoHide()
                    }
                    Rectangle { width: 1; height: 28; anchors.verticalCenter: parent.verticalCenter; color: Theme.outline; opacity: 0.7 }
                    Repeater {
                        model: [
                            { icon: "vertical_align_top", value: SettingsData.Position.Top, tip: "Сверху" },
                            { icon: "vertical_align_bottom", value: SettingsData.Position.Bottom, tip: "Снизу" },
                            { icon: "align_horizontal_left", value: SettingsData.Position.Left, tip: "Слева" },
                            { icon: "align_horizontal_right", value: SettingsData.Position.Right, tip: "Справа" }
                        ]
                        EditButton {
                            required property var modelData
                            iconName: modelData.icon
                            label: modelData.tip
                            compact: true
                            emphasized: SettingsData.dockPosition === modelData.value
                            onActivated: LayoutEditService.setDockEdge(modelData.value)
                        }
                    }
                }
            }
        }

        PanelWindow {
            id: catalogWindow
            screen: surface.modelData
            visible: LayoutEditService.active && surface.targetsThisScreen && surface.catalogOpen
                     && LayoutEditService.mode !== "dock"
            color: "transparent"
            anchors.left: true
            anchors.top: !surface.editorFromBottom
            anchors.bottom: surface.editorFromBottom
            implicitWidth: Math.min(900, surface.modelData.width - Theme.spacingL * 2)
            implicitHeight: 82

            WlrLayershell.namespace: "kaskados:layout-editor:catalog"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.margins.left: Math.max(Theme.spacingM, (surface.modelData.width - implicitWidth) / 2)
            WlrLayershell.margins.top: !surface.editorFromBottom
                                       ? (LayoutEditService.mode === "panel"
                                          ? surface.contextRailOffset + 56
                                          : surface.editorEdgeOffset + surface.commandRailHeight + Theme.spacingS)
                                       : 0
            WlrLayershell.margins.bottom: surface.editorFromBottom
                                          ? (LayoutEditService.mode === "panel"
                                             ? surface.contextRailOffset + 56
                                             : surface.editorEdgeOffset + surface.commandRailHeight + Theme.spacingS)
                                          : 0

            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                radius: height / 2
                color: Theme.withAlpha(Theme.surfaceContainer, 0.96)
                border.width: 1
                border.color: Theme.outline

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    StyledText {
                        width: 120
                        anchors.verticalCenter: parent.verticalCenter
                        text: LayoutEditService.mode === "desktop" ? "Добавить на стол" : "Добавить в панель"
                        color: Theme.surfaceText
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    ListView {
                        width: parent.width - 120 - 42 - Theme.spacingS * 2
                        height: parent.height
                        orientation: ListView.Horizontal
                        spacing: Theme.spacingS
                        model: LayoutEditService.mode === "desktop" ? surface.desktopCatalog : surface.panelCatalog

                        delegate: Rectangle {
                            required property var modelData
                            width: 132
                            height: 50
                            anchors.verticalCenter: parent?.verticalCenter
                            radius: height / 2
                            color: catalogArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: catalogArea.containsMouse ? Theme.primary : Theme.outline
                            Row {
                                anchors.centerIn: parent
                                width: parent.width - Theme.spacingM * 2
                                spacing: Theme.spacingXS
                                KaskadIcon { anchors.verticalCenter: parent.verticalCenter; name: modelData.icon || "widgets"; size: 20; color: Theme.primary }
                                StyledText { width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter; text: modelData.name || modelData.title; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            }
                            MouseArea {
                                id: catalogArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (LayoutEditService.mode === "desktop")
                                        LayoutEditService.addDesktopWidget(modelData.id);
                                    else
                                        LayoutEditService.addBarWidget(surface.activeBar?.id || "", LayoutEditService.selectedBarSection || "centerWidgets", modelData.id);
                                    surface.catalogOpen = false;
                                }
                            }
                        }
                    }
                    EditButton { anchors.verticalCenter: parent.verticalCenter; iconName: "close"; label: "Закрыть"; compact: true; onActivated: surface.catalogOpen = false }
                }
            }
        }

        component EditButton: Rectangle {
            id: button
            property string iconName: ""
            property string label: ""
            property bool emphasized: false
            property bool danger: false
            property bool compact: false
            property real maxWidth: 10000
            signal activated

            width: compact && !area.containsMouse
                   ? 38
                   : Math.min(maxWidth, buttonRow.implicitWidth + Theme.spacingM * 2)
            height: 38
            radius: 19
            opacity: enabled ? 1 : 0.4
            color: danger ? Theme.withAlpha(Theme.error, area.containsMouse ? 0.28 : 0.17)
                          : emphasized ? Theme.primary
                          : area.containsMouse ? Theme.withAlpha(Theme.surfaceContainerHighest, 0.9) : "transparent"
            border.width: danger ? 1 : 0
            border.color: danger ? Theme.withAlpha(Theme.error, 0.55) : Theme.outline
            Row {
                id: buttonRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                KaskadIcon { name: button.iconName; size: 18; color: button.emphasized ? Theme.primaryText : (button.danger ? Theme.error : Theme.surfaceText) }
                StyledText { visible: !button.compact || area.containsMouse; width: Math.min(implicitWidth, button.maxWidth - 38); text: button.label; elide: Text.ElideRight; color: button.emphasized ? Theme.primaryText : (button.danger ? Theme.error : Theme.surfaceText); font.pixelSize: Theme.fontSizeSmall }
            }
            MouseArea { id: area; anchors.fill: parent; enabled: button.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.activated() }
            Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        }
    }
}

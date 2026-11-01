import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets

Loader {
    id: root

    property string widgetId: ""
    property var widgetData: null
    property int spacerSize: 20
    property var components: null
    property bool isInColumn: false
    property var axis: null
    property string section: "center"
    property int configIndex: -1
    property var parentScreen: null
    property real widgetThickness: 30
    property real barThickness: 48
    property real barSpacing: 4
    property var barConfig: null
    property var blurBarWindow: null
    property real sectionAvailablePrimarySize: 0
    property bool isFirst: false
    property bool isLast: false
    property real sectionSpacing: 0
    property bool isLeftBarEdge: false
    property bool isRightBarEdge: false
    property bool isTopBarEdge: false
    property bool isBottomBarEdge: false
    property string _registeredScreenName: ""
    property var _registeredItem: null

    asynchronous: false

    readonly property bool orientationMatches: (axis?.isVertical ?? false) === isInColumn

    readonly property bool widgetEnabled: widgetData?.enabled !== false

    active: orientationMatches && getWidgetVisible(widgetId, DgopService.dgopAvailable)
            && (widgetId !== "music" || MprisController.activePlayer !== null || editActive)
    sourceComponent: getWidgetComponent(widgetId, components)

    signal contentItemReady(var item)

    readonly property string editSection: section === "left" ? "leftWidgets"
                                                : section === "right" ? "rightWidgets" : "centerWidgets"
    readonly property bool editActive: LayoutEditService.active && LayoutEditService.mode === "panel"
    readonly property bool editSelected: editActive
                                             && LayoutEditService.selectedKind === "barWidget"
                                             && LayoutEditService.selectedBarId === (barConfig?.id || "")
                                             && LayoutEditService.selectedBarSection === editSection
                                             && LayoutEditService.selectedBarIndex === configIndex

    Binding {
        target: root.item
        when: root.item && !root.widgetEnabled
        property: "visible"
        value: false
        restoreMode: Binding.RestoreBinding
    }

    Binding {
        target: root.item
        when: root.item && "parentScreen" in root.item
        property: "parentScreen"
        value: root.parentScreen
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "section" in root.item
        property: "section"
        value: root.section
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "widgetThickness" in root.item
        property: "widgetThickness"
        value: root.widgetThickness
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "barThickness" in root.item
        property: "barThickness"
        value: root.barThickness
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "barSpacing" in root.item
        property: "barSpacing"
        value: root.barSpacing
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "barConfig" in root.item
        property: "barConfig"
        value: root.barConfig
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "blurBarWindow" in root.item
        property: "blurBarWindow"
        value: root.blurBarWindow
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "axis" in root.item
        property: "axis"
        value: root.axis
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "widgetData" in root.item
        property: "widgetData"
        value: root.widgetData
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "isFirst" in root.item
        property: "isFirst"
        value: root.isFirst
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "isLast" in root.item
        property: "isLast"
        value: root.isLast
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "sectionSpacing" in root.item
        property: "sectionSpacing"
        value: root.sectionSpacing
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "sectionAvailablePrimarySize" in root.item
        property: "sectionAvailablePrimarySize"
        value: root.sectionAvailablePrimarySize
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "isLeftBarEdge" in root.item
        property: "isLeftBarEdge"
        value: root.isLeftBarEdge
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "isRightBarEdge" in root.item
        property: "isRightBarEdge"
        value: root.isRightBarEdge
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "isTopBarEdge" in root.item
        property: "isTopBarEdge"
        value: root.isTopBarEdge
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "isBottomBarEdge" in root.item
        property: "isBottomBarEdge"
        value: root.isBottomBarEdge
        restoreMode: Binding.RestoreNone
    }

    onLoaded: {
        if (!item)
            return;

        contentItemReady(item);

        if (axis && "isVertical" in item) {
            try {
                item.isVertical = axis.isVertical;
            } catch (e) {}
        }

        if (item.popoutService !== undefined)
            item.popoutService = PopoutService;

        registerWidgetIfEligible();
    }

    Component.onDestruction: {
        unregisterWidget();
    }

    function registerWidgetIfEligible() {
        if (!item || !widgetId || !parentScreen?.name)
            return;

        const hasPopout = item.popoutTarget !== undefined || typeof item.triggerPopout === "function" || typeof item.clicked === "function";
        if (!hasPopout)
            return;

        _registeredScreenName = parentScreen.name;
        _registeredItem = item;
        BarWidgetService.registerWidget(widgetId, _registeredScreenName, _registeredItem);
    }

    function unregisterWidget() {
        if (!widgetId || !_registeredScreenName)
            return;

        BarWidgetService.unregisterWidget(widgetId, _registeredScreenName, _registeredItem);
        _registeredScreenName = "";
        _registeredItem = null;
    }

    function getWidgetComponent(widgetId, components) {
        const componentMap = {
            "launcherButton": components.launcherButtonComponent,
            "workspaceSwitcher": components.workspaceSwitcherComponent,
            "focusedWindow": components.focusedWindowComponent,
            "runningApps": components.runningAppsComponent,
            "clock": components.clockComponent,
            "music": components.mediaComponent,
            "weather": components.weatherComponent,
            "systemTray": components.systemTrayComponent,
            "privacyIndicator": components.privacyIndicatorComponent,
            "clipboard": components.clipboardComponent,
            "cpuUsage": components.cpuUsageComponent,
            "memUsage": components.memUsageComponent,
            "diskUsage": components.diskUsageComponent,
            "cpuTemp": components.cpuTempComponent,
            "gpuTemp": components.gpuTempComponent,
			"gpuUsage": components.gpuUsageComponent,
            "notificationButton": components.notificationButtonComponent,
            "battery": components.batteryComponent,
            "controlCenterButton": components.controlCenterButtonComponent,
            "capsLockIndicator": components.capsLockIndicatorComponent,
            "idleInhibitor": components.idleInhibitorComponent,
            "spacer": components.spacerComponent,
            "separator": components.separatorComponent,
            "network_speed_monitor": components.networkComponent,
            "keyboard_layout_name": components.keyboardLayoutNameComponent,
            "vpn": components.vpnComponent,
            "notepadButton": components.notepadButtonComponent,
            "colorPicker": components.colorPickerComponent,
            "systemUpdate": components.systemUpdateComponent,
            "layout": components.layoutComponent,
            "powerMenuButton": components.powerMenuButtonComponent,
            "appsDock": components.appsDockComponent
        };

        if (componentMap[widgetId]) {
            return componentMap[widgetId];
        }

        return null;
    }

    function getWidgetVisible(widgetId, dgopAvailable) {
        const widgetVisibility = {
            "cpuUsage": dgopAvailable,
            "memUsage": dgopAvailable,
            "cpuTemp": dgopAvailable,
            "gpuTemp": dgopAvailable,
			"gpuUsage": true,
            "network_speed_monitor": dgopAvailable,
            "layout": CompositorService.isMango && MangoService.available
        };

        return widgetVisibility[widgetId] ?? true;
    }

    Rectangle {
        anchors.fill: parent
        z: 10000
        visible: root.editActive
        radius: Theme.cornerRadius
        color: root.editSelected ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
        border.width: root.editSelected ? 2 : 1
        border.color: root.editSelected ? Theme.primary : Theme.withAlpha(Theme.primary, 0.55)

        MouseArea {
            id: selectionArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: LayoutEditService.selectBarWidget(root.barConfig?.id || "", root.editSection, root.configIndex)
        }

        Grid {
            id: localActions
            z: 2
            visible: root.editSelected
            spacing: 3
            columns: root.isInColumn ? 1 : (root.widgetId === "spacer" ? 8 : 6)
            rows: root.isInColumn ? (root.widgetId === "spacer" ? 8 : 6) : 1
            anchors.centerIn: parent

            LocalAction { iconName: root.isInColumn ? "arrow_upward" : "arrow_back"; tip: "Раньше"; onTriggered: LayoutEditService.moveSelectedBarWidget(-1) }
            LocalAction { iconName: root.isInColumn ? "arrow_downward" : "arrow_forward"; tip: "Позже"; onTriggered: LayoutEditService.moveSelectedBarWidget(1) }
            LocalAction { iconName: "keyboard_double_arrow_left"; tip: "В предыдущую область"; onTriggered: LayoutEditService.moveSelectedBarWidgetToSection(-1) }
            LocalAction { iconName: "keyboard_double_arrow_right"; tip: "В следующую область"; onTriggered: LayoutEditService.moveSelectedBarWidgetToSection(1) }
            LocalAction { visible: root.widgetId === "spacer"; iconName: "remove"; tip: "Уменьшить промежуток"; onTriggered: LayoutEditService.resizeSelectedSpacer(-5) }
            LocalAction { visible: root.widgetId === "spacer"; iconName: "add"; tip: "Увеличить промежуток"; onTriggered: LayoutEditService.resizeSelectedSpacer(5) }
            LocalAction { iconName: root.widgetEnabled ? "visibility_off" : "visibility"; tip: root.widgetEnabled ? "Скрыть" : "Показать"; onTriggered: LayoutEditService.toggleSelectedBarWidgetEnabled() }
            LocalAction { iconName: "delete"; tip: "Удалить"; danger: true; onTriggered: LayoutEditService.removeSelectedBarWidget() }
        }
    }

    component LocalAction: Rectangle {
        id: action
        property string iconName: ""
        property string tip: ""
        property bool danger: false
        signal triggered
        width: 30
        height: 30
        radius: 15
        color: danger ? Theme.withAlpha(Theme.error, actionArea.containsMouse ? 0.32 : 0.2)
                      : Theme.withAlpha(actionArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer, 0.97)
        border.width: 1
        border.color: danger ? Theme.error : Theme.outline
        KaskadIcon { anchors.centerIn: parent; name: action.iconName; size: 16; color: action.danger ? Theme.error : Theme.surfaceText }
        MouseArea { id: actionArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: action.triggered() }
    }
}

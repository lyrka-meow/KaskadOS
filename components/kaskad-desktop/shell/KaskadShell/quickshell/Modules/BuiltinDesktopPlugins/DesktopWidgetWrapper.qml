import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    required property string widgetType
    required property var screen

    property var builtinComponent: null
    property string instanceId: ""
    property var instanceData: null
    property bool widgetEnabled: true

    readonly property var activeComponent: builtinComponent

    readonly property bool showOnOverlay: instanceData?.config?.showOnOverlay ?? false
    readonly property bool showOnOverview: instanceData?.config?.showOnOverview ?? false
    readonly property bool showOnOverviewOnly: instanceData?.config?.showOnOverviewOnly ?? false
    readonly property bool overviewActive: CompositorService.isNiri && NiriService.inOverview
    readonly property bool clickThrough: instanceData?.config?.clickThrough ?? false
    readonly property bool syncPositionAcrossScreens: instanceData?.config?.syncPositionAcrossScreens ?? false


    readonly property bool isInstance: instanceId !== "" && instanceData !== null
    readonly property bool layoutEditActive: LayoutEditService.active
                                                   && LayoutEditService.mode === "desktop"
                                                   && (!LayoutEditService.screenName
                                                       || LayoutEditService.screenName === screenKey
                                                       || LayoutEditService.screenName === screen?.name)
    readonly property bool layoutSelected: layoutEditActive
                                               && LayoutEditService.selectedKind === "desktopWidget"
                                               && LayoutEditService.selectedId === instanceId


    readonly property string screenKey: SettingsData.getScreenDisplayName(screen)
    readonly property string positionKey: syncPositionAcrossScreens ? "_synced" : screenKey

    readonly property int screenWidth: screen?.width ?? 1920
    readonly property int screenHeight: screen?.height ?? 1080

    readonly property bool useGhostPreview: !CompositorService.isNiri

    property real previewX: widgetX
    property real previewY: widgetY
    property real previewWidth: widgetWidth
    property real previewHeight: widgetHeight

    readonly property bool hasSavedPosition: {
        if (isInstance)
            return instanceData?.positions?.[positionKey]?.x !== undefined;
        return SettingsData.getDesktopWidgetPosition(widgetType, positionKey, "x", null) !== null;
    }

    readonly property bool hasSavedSize: {
        if (isInstance)
            return instanceData?.positions?.[positionKey]?.width !== undefined;
        return SettingsData.getDesktopWidgetPosition(widgetType, positionKey, "width", null) !== null;
    }

    property real savedX: {
        if (isInstance) {
            const val = instanceData?.positions?.[positionKey]?.x;
            if (val === undefined)
                return screenWidth / 2 - savedWidth / 2;
            return syncPositionAcrossScreens ? val * screenWidth : val;
        }
        const val = SettingsData.getDesktopWidgetPosition(widgetType, positionKey, "x", null);
        if (val === null)
            return screenWidth / 2 - savedWidth / 2;
        return syncPositionAcrossScreens ? val * screenWidth : val;
    }
    property real savedY: {
        if (isInstance) {
            const val = instanceData?.positions?.[positionKey]?.y;
            if (val === undefined)
                return screenHeight / 2 - savedHeight / 2;
            return syncPositionAcrossScreens ? val * screenHeight : val;
        }
        const val = SettingsData.getDesktopWidgetPosition(widgetType, positionKey, "y", null);
        if (val === null)
            return screenHeight / 2 - savedHeight / 2;
        return syncPositionAcrossScreens ? val * screenHeight : val;
    }
    property real savedWidth: {
        if (isInstance) {
            const val = instanceData?.positions?.[positionKey]?.width;
            if (val === undefined)
                return 280;
            return val;
        }
        const val = SettingsData.getDesktopWidgetPosition(widgetType, positionKey, "width", null);
        if (val === null)
            return 280;
        return val;
    }
    property real savedHeight: {
        if (isInstance) {
            const val = instanceData?.positions?.[positionKey]?.height;
            if (val === undefined)
                return forceSquare ? savedWidth : 180;
            return forceSquare ? savedWidth : val;
        }
        const val = SettingsData.getDesktopWidgetPosition(widgetType, positionKey, "height", null);
        if (val === null)
            return forceSquare ? savedWidth : 180;
        return forceSquare ? savedWidth : val;
    }

    property real dragOverrideX: -1
    property real dragOverrideY: -1
    property real dragOverrideW: -1
    property real dragOverrideH: -1

    readonly property real effectiveX: dragOverrideX >= 0 ? dragOverrideX : savedX
    readonly property real effectiveY: dragOverrideY >= 0 ? dragOverrideY : savedY
    readonly property real effectiveW: dragOverrideW >= 0 ? dragOverrideW : savedWidth
    readonly property real effectiveH: dragOverrideH >= 0 ? dragOverrideH : savedHeight

    readonly property real widgetX: Math.max(0, Math.min(effectiveX, screenWidth - widgetWidth))
    readonly property real widgetY: Math.max(0, Math.min(effectiveY, screenHeight - widgetHeight))
    readonly property real widgetWidth: Math.max(minWidth, Math.min(effectiveW, screenWidth))
    readonly property real widgetHeight: Math.max(minHeight, Math.min(effectiveH, screenHeight))

    function clearDragOverrides() {
        dragOverrideX = -1;
        dragOverrideY = -1;
        dragOverrideW = -1;
        dragOverrideH = -1;
    }

    property real minWidth: contentLoader.item?.minWidth ?? 100
    property real minHeight: contentLoader.item?.minHeight ?? 100
    property bool forceSquare: contentLoader.item?.forceSquare ?? false
    property bool acceptsKeyboardFocus: contentLoader.item?.acceptsKeyboardFocus ?? false
    property bool isInteracting: dragArea.pressed || resizeArea.pressed

    property var _gridSettingsTrigger: SettingsData.desktopWidgetGridSettings
    readonly property int gridSize: {
        void _gridSettingsTrigger;
        return SettingsData.getDesktopWidgetGridSetting(screenKey, "size", 40);
    }
    readonly property bool gridEnabled: {
        void _gridSettingsTrigger;
        return SettingsData.getDesktopWidgetGridSetting(screenKey, "enabled", false);
    }

    function snapToGrid(value) {
        return Math.round(value / gridSize) * gridSize;
    }

    function savePosition(finalX, finalY) {
        const xVal = syncPositionAcrossScreens ? finalX / screenWidth : finalX;
        const yVal = syncPositionAcrossScreens ? finalY / screenHeight : finalY;
        if (isInstance && instanceData) {
            SettingsData.updateDesktopWidgetInstancePosition(instanceId, positionKey, {
                x: xVal,
                y: yVal
            });
            return;
        }
        SettingsData.updateDesktopWidgetPosition(widgetType, positionKey, {
            x: xVal,
            y: yVal
        });
    }

    function saveSize(finalW, finalH) {
        const sizeVal = forceSquare ? Math.max(finalW, finalH) : finalW;
        const heightVal = forceSquare ? sizeVal : finalH;
        if (isInstance && instanceData) {
            SettingsData.updateDesktopWidgetInstancePosition(instanceId, positionKey, {
                width: sizeVal,
                height: heightVal
            });
            return;
        }
        SettingsData.updateDesktopWidgetPosition(widgetType, positionKey, {
            width: sizeVal,
            height: heightVal
        });
    }

    PanelWindow {
        id: widgetWindow
        screen: root.screen
        visible: {
            if (!root.widgetEnabled || root.activeComponent === null)
                return false;
            if (root.showOnOverviewOnly)
                return root.overviewActive;
            return true;
        }
        color: "transparent"

        Region {
            id: emptyMask
        }

        mask: root.clickThrough && !root.layoutEditActive ? emptyMask : null

        WlrLayershell.namespace: "kaskad-shell:desktop-widget:" + root.widgetType + (root.instanceId ? ":" + root.instanceId : "")
        WlrLayershell.layer: {
            if (root.layoutEditActive || (root.isInteracting && !CompositorService.useHyprlandFocusGrab))
                return WlrLayer.Overlay;
            if (root.showOnOverlay)
                return WlrLayer.Overlay;
            if (root.overviewActive && (root.showOnOverview || root.showOnOverviewOnly))
                return WlrLayer.Overlay;
            return WlrLayer.Bottom;
        }
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: {
            if (PopoutManager.screenshotActive)
                return WlrKeyboardFocus.None;
            if (root.isInteracting) {
                if (CompositorService.useHyprlandFocusGrab)
                    return WlrKeyboardFocus.OnDemand;
                return WlrKeyboardFocus.Exclusive;
            }
            if (root.acceptsKeyboardFocus)
                return WlrKeyboardFocus.OnDemand;
            return WlrKeyboardFocus.None;
        }

        HyprlandFocusGrab {
            active: CompositorService.isHyprland && root.isInteracting
            windows: [widgetWindow]
        }

        Item {
            anchors.fill: parent
            focus: root.isInteracting

            Keys.onPressed: event => {
                if (!root.isInteracting)
                    return;
                switch (event.key) {
                case Qt.Key_G:
                    SettingsData.setDesktopWidgetGridSetting(root.screenKey, "enabled", !root.gridEnabled);
                    event.accepted = true;
                    break;
                case Qt.Key_Z:
                    SettingsData.setDesktopWidgetGridSetting(root.screenKey, "size", Math.max(10, root.gridSize - 10));
                    event.accepted = true;
                    break;
                case Qt.Key_X:
                    SettingsData.setDesktopWidgetGridSetting(root.screenKey, "size", Math.min(200, root.gridSize + 10));
                    event.accepted = true;
                    break;
                }
            }
        }

        anchors {
            left: true
            top: true
        }

        WlrLayershell.margins {
            left: root.widgetX
            top: root.widgetY
        }

        implicitWidth: root.widgetWidth
        implicitHeight: root.widgetHeight

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: root.widgetEnabled && root.activeComponent !== null
            sourceComponent: root.activeComponent
            opacity: 0

            NumberAnimation {
                id: revealFade
                target: contentLoader
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.mediumDuration
                easing.type: Theme.standardEasing
            }

            function reloadComponent() {
                active = false;
                active = true;
            }

            function updateInstanceData() {
                if (!item || item.instanceData === undefined)
                    return;
                item.instanceData = root.instanceData;
            }

            Connections {
                target: root
                enabled: contentLoader.item !== null

                function onInstanceDataChanged() {
                    contentLoader.updateInstanceData();
                }
            }

            onLoaded: {
                if (!item)
                    return;

                revealFade.restart();

                if (item.instanceId !== undefined)
                    item.instanceId = root.instanceId;
                if (item.instanceData !== undefined)
                    item.instanceData = root.instanceData;
                if (!root.hasSavedSize) {
                    const defW = item.defaultWidth ?? item.widgetWidth ?? 280;
                    const defH = item.defaultHeight ?? item.widgetHeight ?? 180;
                    const finalW = Math.max(root.minWidth, Math.min(defW, root.screenWidth));
                    const finalH = Math.max(root.minHeight, Math.min(defH, root.screenHeight));
                    root.saveSize(finalW, finalH);
                }
                if (!root.hasSavedPosition) {
                    const finalX = Math.max(0, Math.min(root.screenWidth / 2 - root.widgetWidth / 2, root.screenWidth - root.widgetWidth));
                    const finalY = Math.max(0, Math.min(root.screenHeight / 2 - root.widgetHeight / 2, root.screenHeight - root.widgetHeight));
                    root.savePosition(finalX, finalY);
                }
                if (item.widgetWidth !== undefined)
                    item.widgetWidth = Qt.binding(() => contentLoader.width);
                if (item.widgetHeight !== undefined)
                    item.widgetHeight = Qt.binding(() => contentLoader.height);
                if (item.screen !== undefined)
                    item.screen = Qt.binding(() => root.screen);
            }
        }

        Rectangle {
            id: interactionBorder
            anchors.fill: parent
            color: "transparent"
            border.color: Theme.primary
            border.width: 2
            radius: Theme.cornerRadius
            visible: root.layoutEditActive && (!root.useGhostPreview || !root.isInteracting)
            opacity: 0.8

            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 28
                height: 28
                topLeftRadius: Theme.cornerRadius
                bottomRightRadius: Theme.cornerRadius
                color: Theme.primary
                opacity: root.layoutSelected ? (resizeArea.pressed ? 1 : 0.72) : 0

                KaskadIcon {
                    anchors.centerIn: parent
                    name: "open_in_full"
                    size: 16
                    color: Theme.primaryText
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 6
                width: selectedLabel.implicitWidth + Theme.spacingM
                height: 26
                radius: 13
                color: Theme.primary
                visible: root.layoutSelected

                StyledText {
                    id: selectedLabel
                    anchors.centerIn: parent
                    text: root.instanceData?.name || root.widgetType
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primaryText
                }
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            enabled: root.layoutEditActive
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor

            property point startPos
            property real startX
            property real startY

            onPressed: mouse => {
                LayoutEditService.selectDesktopWidget(root.instanceId);
                LayoutEditService.checkpoint();
                startPos = root.useGhostPreview ? Qt.point(mouse.x, mouse.y) : mapToGlobal(mouse.x, mouse.y);
                startX = root.widgetX;
                startY = root.widgetY;
                root.previewX = root.widgetX;
                root.previewY = root.widgetY;
                root.dragOverrideX = root.widgetX;
                root.dragOverrideY = root.widgetY;
            }

            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const currentPos = root.useGhostPreview ? Qt.point(mouse.x, mouse.y) : mapToGlobal(mouse.x, mouse.y);
                let newX = Math.max(0, Math.min(startX + currentPos.x - startPos.x, root.screenWidth - root.widgetWidth));
                let newY = Math.max(0, Math.min(startY + currentPos.y - startPos.y, root.screenHeight - root.widgetHeight));
                if (root.gridEnabled) {
                    newX = Math.max(0, Math.min(root.snapToGrid(newX), root.screenWidth - root.widgetWidth));
                    newY = Math.max(0, Math.min(root.snapToGrid(newY), root.screenHeight - root.widgetHeight));
                }
                if (root.useGhostPreview) {
                    root.previewX = newX;
                    root.previewY = newY;
                    return;
                }
                root.dragOverrideX = newX;
                root.dragOverrideY = newY;
            }

            onReleased: {
                const finalX = root.useGhostPreview ? root.previewX : root.dragOverrideX;
                const finalY = root.useGhostPreview ? root.previewY : root.dragOverrideY;
                root.savePosition(finalX, finalY);
                root.clearDragOverrides();
            }
        }

        MouseArea {
            id: resizeArea
            width: 48
            height: 48
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            acceptedButtons: Qt.LeftButton
            enabled: root.layoutEditActive && root.layoutSelected
            cursorShape: pressed ? Qt.SizeFDiagCursor : Qt.ArrowCursor

            property point startPos
            property real startWidth
            property real startHeight

            onPressed: mouse => {
                LayoutEditService.checkpoint();
                startPos = root.useGhostPreview ? Qt.point(mouse.x, mouse.y) : mapToGlobal(mouse.x, mouse.y);
                startWidth = root.widgetWidth;
                startHeight = root.widgetHeight;
                root.previewWidth = root.widgetWidth;
                root.previewHeight = root.widgetHeight;
                root.dragOverrideW = root.widgetWidth;
                root.dragOverrideH = root.widgetHeight;
            }

            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const currentPos = root.useGhostPreview ? Qt.point(mouse.x, mouse.y) : mapToGlobal(mouse.x, mouse.y);
                let newW = Math.max(root.minWidth, Math.min(startWidth + currentPos.x - startPos.x, root.screenWidth - root.widgetX));
                let newH = Math.max(root.minHeight, Math.min(startHeight + currentPos.y - startPos.y, root.screenHeight - root.widgetY));
                if (root.gridEnabled) {
                    newW = Math.max(root.minWidth, root.snapToGrid(newW));
                    newH = Math.max(root.minHeight, root.snapToGrid(newH));
                }
                if (root.forceSquare) {
                    const size = Math.max(newW, newH);
                    newW = Math.min(size, root.screenWidth - root.widgetX);
                    newH = Math.min(size, root.screenHeight - root.widgetY);
                }
                if (root.useGhostPreview) {
                    root.previewWidth = newW;
                    root.previewHeight = newH;
                    return;
                }
                root.dragOverrideW = newW;
                root.dragOverrideH = newH;
            }

            onReleased: {
                const finalW = root.useGhostPreview ? root.previewWidth : root.dragOverrideW;
                const finalH = root.useGhostPreview ? root.previewHeight : root.dragOverrideH;
                root.saveSize(finalW, finalH);
                root.clearDragOverrides();
            }
        }

        TapHandler {
            acceptedButtons: Qt.RightButton
            enabled: !root.layoutEditActive
            onTapped: eventPoint => {
                widgetMenu.x = eventPoint.position.x;
                widgetMenu.y = eventPoint.position.y;
                widgetMenu.open();
            }
        }

        Menu {
            id: widgetMenu
            MenuItem {
                text: I18n.tr("Edit desktop layout")
                icon.name: "dashboard_customize"
                onTriggered: {
                    LayoutEditService.begin("desktop", root.screenKey);
                    LayoutEditService.selectDesktopWidget(root.instanceId);
                }
            }
            MenuItem {
                text: I18n.tr("Duplicate widget")
                icon.name: "content_copy"
                enabled: root.isInstance
                onTriggered: {
                    LayoutEditService.begin("desktop", root.screenKey);
                    LayoutEditService.selectDesktopWidget(root.instanceId);
                    LayoutEditService.duplicateSelected();
                }
            }
            MenuItem {
                text: I18n.tr("Remove widget")
                icon.name: "delete"
                enabled: root.isInstance
                onTriggered: {
                    LayoutEditService.begin("desktop", root.screenKey);
                    LayoutEditService.selectDesktopWidget(root.instanceId);
                    LayoutEditService.removeSelected();
                }
            }
        }
    }

    PanelWindow {
        id: editActionsWindow
        screen: root.screen
        visible: root.layoutSelected && !root.isInteracting
        color: "transparent"
        anchors.left: true
        anchors.top: true
        implicitWidth: 286
        implicitHeight: 52

        WlrLayershell.namespace: "kaskados:desktop-widget-actions:" + root.instanceId
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.margins.left: Math.max(8, Math.min(root.screenWidth - implicitWidth - 8,
                                                        root.widgetX + root.widgetWidth / 2 - implicitWidth / 2))
        WlrLayershell.margins.top: root.widgetY >= implicitHeight + 12
                                      ? root.widgetY - implicitHeight - 8
                                      : Math.min(root.screenHeight - implicitHeight - 8,
                                                 root.widgetY + root.widgetHeight + 8)

        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingS

            EditAction {
                iconName: root.syncPositionAcrossScreens ? "sync" : "sync_disabled"
                label: root.syncPositionAcrossScreens ? "Одинаково на экранах" : "Отдельно для экрана"
                active: root.syncPositionAcrossScreens
                onTriggered: {
                    LayoutEditService.checkpoint();
                    SettingsData.updateDesktopWidgetInstanceConfig(root.instanceId, {
                        syncPositionAcrossScreens: !root.syncPositionAcrossScreens
                    });
                }
            }
            EditAction { iconName: "content_copy"; label: "Создать копию"; onTriggered: LayoutEditService.duplicateSelected() }
            EditAction {
                iconName: "tune"
                label: "Параметры виджета"
                onTriggered: {
                    LayoutEditService.requestDesktopWidgetSettings(root.instanceId);
                    LayoutEditService.commit();
                    PopoutService.openSettingsWithTab("desktop_widgets");
                }
            }
            EditAction { iconName: "delete"; label: "Удалить"; danger: true; onTriggered: LayoutEditService.removeSelected() }
        }
    }

    Loader {
        active: root.isInteracting && root.useGhostPreview

        sourceComponent: PanelWindow {
            id: ghostPreviewWindow
            screen: root.screen
            color: "transparent"

            anchors {
                left: true
                right: true
                top: true
                bottom: true
            }

            mask: Region {}

            WlrLayershell.namespace: "kaskad-shell:desktop-widget-preview"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                id: gridOverlay
                anchors.fill: parent
                visible: root.gridEnabled
                opacity: 0.3

                Repeater {
                    model: Math.ceil(root.screenWidth / root.gridSize)

                    Rectangle {
                        required property int index
                        x: index * root.gridSize
                        y: 0
                        width: 1
                        height: root.screenHeight
                        color: Theme.primary
                    }
                }

                Repeater {
                    model: Math.ceil(root.screenHeight / root.gridSize)

                    Rectangle {
                        required property int index
                        x: 0
                        y: index * root.gridSize
                        width: root.screenWidth
                        height: 1
                        color: Theme.primary
                    }
                }
            }

            Rectangle {
                x: root.previewX
                y: root.previewY
                width: root.previewWidth
                height: root.previewHeight
                color: "transparent"
                border.color: Theme.primary
                border.width: 2
                radius: Theme.cornerRadius

                Rectangle {
                    width: 48
                    height: 48
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                    }
                    topLeftRadius: Theme.cornerRadius
                    bottomRightRadius: Theme.cornerRadius
                    color: Theme.primary
                    opacity: resizeArea.pressed ? 1 : 0.6
                }
            }
        }
    }

    Loader {
        active: root.isInteracting && root.gridEnabled && !root.useGhostPreview

        sourceComponent: PanelWindow {
            screen: root.screen
            color: "transparent"

            anchors {
                left: true
                right: true
                top: true
                bottom: true
            }

            mask: Region {}

            WlrLayershell.namespace: "kaskad-shell:desktop-widget-grid"
            WlrLayershell.layer: root.overviewActive && (root.showOnOverview || root.showOnOverviewOnly) ? WlrLayer.Overlay : WlrLayer.Background
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                anchors.fill: parent
                opacity: 0.3

                Repeater {
                    model: Math.ceil(root.screenWidth / root.gridSize)

                    Rectangle {
                        required property int index
                        x: index * root.gridSize
                        y: 0
                        width: 1
                        height: root.screenHeight
                        color: Theme.primary
                    }
                }

                Repeater {
                    model: Math.ceil(root.screenHeight / root.gridSize)

                    Rectangle {
                        required property int index
                        x: 0
                        y: index * root.gridSize
                        width: root.screenWidth
                        height: 1
                        color: Theme.primary
                    }
                }
            }
        }
    }

    Loader {
        active: root.isInteracting

        sourceComponent: PanelWindow {
            id: helperWindow
            screen: root.screen
            color: "transparent"

            WlrLayershell.namespace: "kaskad-shell:desktop-widget-helper"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                bottom: true
                left: true
                right: true
            }

            implicitHeight: 60

            Rectangle {
                id: helperContent
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.spacingL
                width: helperRow.implicitWidth + Theme.spacingM * 2
                height: 32
                radius: Theme.cornerRadius
                color: Theme.surface

                Row {
                    id: helperRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingM
                    height: parent.height

                    KaskadIcon {
                        name: "grid_on"
                        size: 16
                        color: root.gridEnabled ? Theme.primary : Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.gridEnabled ? I18n.tr("Grid: ON", "Widget grid snap status") : I18n.tr("Grid: OFF", "Widget grid snap status")
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        color: root.gridEnabled ? Theme.primary : Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: 1
                        height: 16
                        color: Theme.outline
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.gridSize + "px"
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: 1
                        height: 16
                        color: Theme.outline
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: I18n.tr("G: grid • Z/X: size", "Widget grid keyboard hints")
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        font.italic: true
                        color: Theme.surfaceText
                        opacity: 0.7
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    component EditAction: Rectangle {
        id: action
        property string iconName: ""
        property string label: ""
        property bool active: false
        property bool danger: false
        signal triggered

        width: 44
        height: 44
        radius: 22
        color: danger ? Theme.withAlpha(Theme.error, actionArea.containsMouse ? 0.28 : 0.17)
                      : active ? Theme.primary
                      : Theme.withAlpha(actionArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer, 0.96)
        border.width: active ? 0 : 1
        border.color: danger ? Theme.withAlpha(Theme.error, 0.55) : Theme.outline

        KaskadIcon {
            anchors.centerIn: parent
            name: action.iconName
            size: 19
            color: action.active ? Theme.primaryText : (action.danger ? Theme.error : Theme.surfaceText)
        }

        MouseArea {
            id: actionArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.triggered()
        }

        ToolTip.visible: actionArea.containsMouse
        ToolTip.text: action.label
        ToolTip.delay: 400
    }
}

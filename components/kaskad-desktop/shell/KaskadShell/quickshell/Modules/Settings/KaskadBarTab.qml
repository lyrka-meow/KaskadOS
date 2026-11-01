import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: kaskadBarTab

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var parentModal: null
    property bool appearanceOnly: false
    property string selectedBarId: SettingsUiState.selectedBarId

    onSelectedBarIdChanged: {
        if (SettingsUiState.selectedBarId !== selectedBarId)
            SettingsUiState.selectedBarId = selectedBarId;
    }

    Connections {
        target: SettingsUiState

        function onSelectedBarIdChanged() {
            if (kaskadBarTab.selectedBarId !== SettingsUiState.selectedBarId)
                kaskadBarTab.selectedBarId = SettingsUiState.selectedBarId;
        }
    }

    property var selectedBarConfig: {
        selectedBarId;
        SettingsData.barConfigs;
        const index = SettingsData.barConfigs.findIndex(cfg => cfg.id === selectedBarId);
        return index !== -1 ? SettingsData.barConfigs[index] : SettingsData.barConfigs[0];
    }
    readonly property string selectedBarName: {
        selectedBarId;
        SettingsData.barConfigs;
        const index = SettingsData.barConfigs.findIndex(config => config.id === selectedBarId);
        if (index < 0)
            return I18n.tr("Bar", "fallback name for an unnamed bar");
        return SettingsData.barConfigs[index].name || I18n.tr("Bar %1", "numbered name for an unnamed bar, %1 is its position").arg(index + 1);
    }

    property bool selectedBarIsVertical: {
        selectedBarId;
        const pos = selectedBarConfig?.position ?? SettingsData.Position.Top;
        return pos === SettingsData.Position.Left || pos === SettingsData.Position.Right;
    }
    readonly property bool connectedFrameModeActive: SettingsData.connectedFrameModeActive

    // Bar Inset Padding: resolve the "auto" sentinel (stored < 0) to each mode's natural inset for the slider display.
    readonly property real insetPadAutoUI: SettingsData.connectedFrameModeActive ? SettingsData.frameThickness : (selectedBarIsVertical ? Theme.spacingXS : Math.max(Theme.spacingXS, (selectedBarConfig?.innerPadding ?? 4) * 0.8))
    readonly property int insetPadDisplayValue: {
        const raw = SettingsData.barInsetPaddingSyncAll ? SettingsData.barInsetPaddingShared : (selectedBarConfig?.barInsetPadding ?? -1);
        return raw < 0 ? Math.round(insetPadAutoUI) : raw;
    }

    Timer {
        id: horizontalBarChangeDebounce
        interval: 500
        repeat: false
        onTriggered: {
            const verticalBars = SettingsData.barConfigs.filter(cfg => {
                const pos = cfg.position ?? SettingsData.Position.Top;
                return pos === SettingsData.Position.Left || pos === SettingsData.Position.Right;
            });

            verticalBars.forEach(bar => {
                if (!bar.enabled)
                    return;
                SettingsData.updateBarConfig(bar.id, {
                    enabled: false
                });
                Qt.callLater(() => SettingsData.updateBarConfig(bar.id, {
                        enabled: true
                    }));
            });
        }
    }

    function _isBarActive(c) {
        if (!c.enabled)
            return false;
        const prefs = c.screenPreferences || ["all"];
        if (prefs.length > 0)
            return true;
        return (c.showOnLastDisplay ?? true) && Quickshell.screens.length === 1;
    }

    function notifyHorizontalBarChange() {
        const configs = SettingsData.barConfigs;
        if (configs.length < 2)
            return;

        const hasHorizontal = configs.some(c => {
            if (!_isBarActive(c))
                return false;
            const p = c.position ?? SettingsData.Position.Top;
            return p === SettingsData.Position.Top || p === SettingsData.Position.Bottom;
        });
        if (!hasHorizontal)
            return;

        const hasVertical = configs.some(c => {
            if (!_isBarActive(c))
                return false;
            const p = c.position ?? SettingsData.Position.Top;
            return p === SettingsData.Position.Left || p === SettingsData.Position.Right;
        });
        if (!hasVertical)
            return;

        horizontalBarChangeDebounce.restart();
    }

    function toggleBarEnabled(barId) {
        if (barId === "default")
            return;
        const config = SettingsData.getBarConfig(barId);
        if (!config)
            return;
        SettingsData.updateBarConfig(barId, {
            enabled: !config.enabled
        });
    }

    function openDirectEditor() {
        parentModal?.close();
        LayoutEditService.begin("panel", "");
        LayoutEditService.selectBar(selectedBarId);
    }

    KaskadFlickable {
        anchors.fill: parent
        clip: true
        contentHeight: mainColumn.height + Theme.spacingXL
        contentWidth: width

        Column {
            id: mainColumn
            topPadding: 4
            width: Math.min(550, parent.width - Theme.spacingL * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingXL

            SettingsCard {
                iconName: "toolbar"
                title: I18n.tr("Panel Settings")
                settingKey: "barAppearance"

                SettingsButtonGroupRow {
                    text: I18n.tr("Editing changes on %1").arg(kaskadBarTab.selectedBarName)
                    model: SettingsData.barConfigs.map((config, index) => config.name || I18n.tr("Bar %1").arg(index + 1))
                    currentIndex: {
                        const index = SettingsData.barConfigs.findIndex(config => config.id === kaskadBarTab.selectedBarId);
                        return Math.max(0, index);
                    }
                    onSelectionChanged: (index, selected) => {
                        if (!selected || index < 0 || index >= SettingsData.barConfigs.length)
                            return;
                        kaskadBarTab.selectedBarId = SettingsData.barConfigs[index].id;
                    }
                }

                KaskadButton {
                    text: I18n.tr("Edit panel")
                    iconName: "dashboard_customize"
                    onClicked: kaskadBarTab.openDirectEditor()
                }
            }

            SettingsCard {
                iconName: selectedBarConfig?.enabled ? "visibility" : "visibility_off"
                title: I18n.tr("Enable Bar")
                visible: !kaskadBarTab.appearanceOnly && selectedBarId !== "default"

                SettingsToggleRow {
                    text: I18n.tr("Toggle visibility of this bar configuration")
                    checked: {
                        selectedBarId;
                        return selectedBarConfig?.enabled ?? false;
                    }
                    onToggled: toggled => kaskadBarTab.toggleBarEnabled(selectedBarId)
                }
            }

            SettingsCard {
                iconName: "visibility"
                title: I18n.tr("Visibility")
                settingKey: "barVisibility"
                collapsible: true
                expanded: true
                visible: !kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled

                SettingsToggleRow {
                    text: I18n.tr("Auto-hide")
                    description: I18n.tr("Automatically hide the bar when the pointer moves away")
                    checked: (selectedBarConfig?.autoHide ?? false) && !(selectedBarConfig?.showOnWindowsOpen ?? false)
                    onToggled: toggled => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            autoHide: toggled,
                            showOnWindowsOpen: false
                        });
                        notifyHorizontalBarChange();
                    }
                }

                SettingsToggleRow {
                    visible: CompositorService.isKaskad || CompositorService.isNiri || CompositorService.isHyprland || CompositorService.isMango
                    text: I18n.tr("Intelligent Auto-hide")
                    description: I18n.tr("Hide the bar only while a window overlaps its area")
                    checked: (selectedBarConfig?.autoHide ?? false) && (selectedBarConfig?.showOnWindowsOpen ?? false)
                    onToggled: toggled => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            autoHide: toggled,
                            showOnWindowsOpen: toggled
                        });
                        notifyHorizontalBarChange();
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: selectedBarConfig?.autoHide ?? false
                    leftPadding: Theme.spacingM

                    Rectangle {
                        width: parent.width - parent.leftPadding
                        height: 1
                        color: Theme.outline
                        opacity: 0.15
                    }

                    SettingsSliderRow {
                        id: hideDelaySlider
                        width: parent.width - parent.parent.leftPadding
                        text: I18n.tr("Hide Delay")
                        description: I18n.tr("Time to wait before hiding after the pointer leaves")
                        value: selectedBarConfig?.autoHideDelay ?? 250
                        minimum: 0
                        maximum: 2000
                        unit: "ms"
                        defaultValue: 250
                        onSliderValueChanged: newValue => {
                            SettingsData.updateBarConfig(selectedBarId, {
                                autoHideDelay: newValue
                            });
                        }

                        Binding {
                            target: hideDelaySlider
                            property: "value"
                            value: selectedBarConfig?.autoHideDelay ?? 250
                            restoreMode: Binding.RestoreBinding
                        }
                    }

                    SettingsToggleRow {
                        width: parent.width - parent.leftPadding
                        text: I18n.tr("Strict auto-hide", "Kaskad bar setting: hide the bar when the pointer leaves even if a menu or bar popover is still open")
                        description: I18n.tr("Hide the bar when the pointer leaves even if a popout is still open")
                        checked: selectedBarConfig?.autoHideStrict ?? false
                        onToggled: toggled => {
                            SettingsData.updateBarConfig(selectedBarId, {
                                autoHideStrict: toggled
                            });
                            notifyHorizontalBarChange();
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                    opacity: 0.15
                }

                SettingsToggleRow {
                    text: I18n.tr("Manual Show/Hide")
                    description: I18n.tr("Toggle bar visibility manually via IPC")
                    checked: selectedBarConfig?.visible ?? true
                    onToggled: toggled => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            visible: toggled
                        });
                        notifyHorizontalBarChange();
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                    opacity: 0.15
                }

                SettingsToggleRow {
                    text: I18n.tr("Click Through")
                    description: I18n.tr("Mouse clicks pass through the bar to windows behind it")
                    checked: selectedBarConfig?.clickThrough ?? false
                    onToggled: toggled => SettingsData.updateBarConfig(selectedBarId, {
                            clickThrough: toggled
                        })
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                    opacity: 0.15
                    visible: CompositorService.isNiri
                }

                SettingsToggleRow {
                    settingKey: "barOpenOnOverview"
                    tags: ["bar", "overview", "niri", "show", "frame"]
                    visible: CompositorService.isNiri
                    text: I18n.tr("Show on Overview")
                    description: SettingsData.frameEnabled ? I18n.tr("Show during Niri overview") : I18n.tr("Show the bar when niri overview is active")
                    checked: SettingsData.frameEnabled ? SettingsData.frameShowOnOverview : (selectedBarConfig?.openOnOverview ?? false)
                    onToggled: toggled => {
                        if (SettingsData.frameEnabled) {
                            SettingsData.set("frameShowOnOverview", toggled);
                            return;
                        }
                        SettingsData.updateBarConfig(selectedBarId, {
                            openOnOverview: toggled
                        });
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                    opacity: 0.15
                }

                SettingsToggleRow {
                    settingKey: "barUseOverlayLayer"
                    tags: ["bar", "fullscreen", "overlay", "layer"]
                    text: I18n.tr("Use Overlay Layer", "bar layer toggle: use Wayland overlay layer")
                    description: I18n.tr("Place the bar on the Wayland overlay layer")
                    checked: selectedBarConfig?.useOverlayLayer ?? false
                    onToggled: toggled => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            useOverlayLayer: toggled
                        });
                        notifyHorizontalBarChange();
                    }
                }
            }

            SettingsCard {
                tab: "appearance"
                iconName: "opacity"
                title: I18n.tr("Opacity")
                settingKey: "barTransparency"
                visible: kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled

                SettingsSliderRow {
                    id: barTransparencySlider
                    visible: !SettingsData.frameEnabled
                    text: I18n.tr("Bar Opacity")
                    value: (selectedBarConfig?.transparency ?? 1.0) * 100
                    minimum: 0
                    maximum: 100
                    unit: "%"
                    defaultValue: 100
                    onSliderDragFinished: finalValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            transparency: finalValue / 100
                        });
                    }

                    Binding {
                        target: barTransparencySlider
                        property: "value"
                        value: (selectedBarConfig?.transparency ?? 1.0) * 100
                        restoreMode: Binding.RestoreBinding
                    }
                }

                SettingsSliderRow {
                    id: widgetTransparencySlider
                    text: I18n.tr("Widget Opacity")
                    value: (selectedBarConfig?.widgetTransparency ?? 1.0) * 100
                    minimum: 0
                    maximum: 100
                    unit: "%"
                    defaultValue: 100
                    onSliderDragFinished: finalValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            widgetTransparency: finalValue / 100
                        });
                    }

                    Binding {
                        target: widgetTransparencySlider
                        property: "value"
                        value: (selectedBarConfig?.widgetTransparency ?? 1.0) * 100
                        restoreMode: Binding.RestoreBinding
                    }
                }

                SettingsControlledByFrame {
                    visible: SettingsData.frameEnabled
                    parentModal: kaskadBarTab.parentModal
                    settingLabel: I18n.tr("Bar Opacity")
                    reason: I18n.tr("Managed by Frame")
                }
            }

            SettingsCard {
                tab: "appearance"
                iconName: "space_bar"
                title: I18n.tr("Spacing")
                settingKey: "barSpacing"
                visible: kaskadBarTab.appearanceOnly && (selectedBarConfig?.enabled ?? false)

                SettingsControlledByFrame {
                    visible: SettingsData.frameEnabled
                    parentModal: kaskadBarTab.parentModal
                    settingLabel: I18n.tr("Bar Spacing")
                    reason: I18n.tr("Edge spacing, exclusive zone, and popup gaps are managed by Frame")
                }

                SettingsSliderRow {
                    id: edgeSpacingSlider
                    visible: !SettingsData.frameEnabled
                    text: I18n.tr("Edge Spacing")
                    description: I18n.tr("Space between the bar and screen edges")
                    value: selectedBarConfig?.spacing ?? 4
                    minimum: 0
                    maximum: 32
                    defaultValue: 4
                    onSliderDragFinished: finalValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            spacing: finalValue
                        });
                    }

                    Binding {
                        target: edgeSpacingSlider
                        property: "value"
                        value: selectedBarConfig?.spacing ?? 4
                        restoreMode: Binding.RestoreBinding
                    }
                }

                SettingsSliderRow {
                    id: exclusiveZoneSlider
                    visible: !SettingsData.frameEnabled
                    text: I18n.tr("Exclusive Zone Offset")
                    description: I18n.tr("Fine-tune the space reserved for the bar from the screen edge")
                    value: selectedBarConfig?.bottomGap ?? 0
                    minimum: -50
                    maximum: 50
                    defaultValue: 0
                    onSliderDragFinished: finalValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            bottomGap: finalValue
                        });
                    }

                    Binding {
                        target: exclusiveZoneSlider
                        property: "value"
                        value: selectedBarConfig?.bottomGap ?? 0
                        restoreMode: Binding.RestoreBinding
                    }
                }

                SettingsSliderRow {
                    id: sizeSlider
                    visible: !SettingsData.frameEnabled
                    text: I18n.tr("Size")
                    description: I18n.tr("Adjust the bar height via inner padding")
                    value: selectedBarConfig?.innerPadding ?? 4
                    minimum: -8
                    maximum: 24
                    defaultValue: 4
                    onSliderDragFinished: finalValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            innerPadding: finalValue
                        });
                    }

                    Binding {
                        target: sizeSlider
                        property: "value"
                        value: selectedBarConfig?.innerPadding ?? 4
                        restoreMode: Binding.RestoreBinding
                    }
                }

                SettingsSliderRow {
                    id: widgetPaddingSlider
                    visible: !SettingsData.frameEnabled
                    text: I18n.tr("Padding")
                    description: I18n.tr("Inner padding applied to each widget")
                    value: selectedBarConfig?.widgetPadding ?? 8
                    minimum: 0
                    maximum: 32
                    unit: "px"
                    defaultValue: 8
                    opacity: (selectedBarConfig?.removeWidgetPadding ?? false) ? 0.5 : 1.0
                    enabled: !(selectedBarConfig?.removeWidgetPadding ?? false)
                    onSliderValueChanged: newValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            widgetPadding: newValue
                        });
                    }

                    Binding {
                        target: widgetPaddingSlider
                        property: "value"
                        value: selectedBarConfig?.widgetPadding ?? 12
                        restoreMode: Binding.RestoreBinding
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                    opacity: 0.15
                    visible: !SettingsData.frameEnabled
                }

                SettingsSliderRow {
                    id: barInsetPaddingSlider
                    visible: !SettingsData.frameEnabled
                    text: I18n.tr("Bar Inset Padding")
                    description: I18n.tr("Gap between the end widgets and the bar ends (0 = edge-to-edge)")
                    tags: ["bar", "padding", "inset", "edge", "corner", "end"]
                    unit: "px"
                    minimum: 0
                    maximum: 48
                    defaultValue: Math.round(kaskadBarTab.insetPadAutoUI)
                    value: kaskadBarTab.insetPadDisplayValue
                    onSliderDragFinished: finalValue => {
                        if (SettingsData.barInsetPaddingSyncAll)
                            SettingsData.set("barInsetPaddingShared", finalValue);
                        else
                            SettingsData.updateBarConfig(selectedBarId, {
                                barInsetPadding: finalValue
                            });
                    }

                    Binding {
                        target: barInsetPaddingSlider
                        property: "value"
                        value: kaskadBarTab.insetPadDisplayValue
                        restoreMode: Binding.RestoreBinding
                    }
                }

                SettingsToggleRow {
                    visible: !SettingsData.frameEnabled
                    text: I18n.tr("Sync Bar Inset Padding")
                    description: I18n.tr("Use one inset value for every bar")
                    tags: ["bar", "padding", "inset", "edge", "sync", "all", "global"]
                    checked: SettingsData.barInsetPaddingSyncAll
                    onToggled: checked => SettingsData.set("barInsetPaddingSyncAll", checked)
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                    opacity: 0.15
                    visible: !SettingsData.frameEnabled
                }

                SettingsToggleRow {
                    visible: !SettingsData.frameEnabled
                    text: I18n.tr("Auto Popup Gaps")
                    description: I18n.tr("Automatically calculate popup gap based on bar spacing")
                    checked: selectedBarConfig?.popupGapsAuto ?? true
                    onToggled: checked => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            popupGapsAuto: checked
                        });
                    }
                }

                Column {
                    width: parent.width
                    leftPadding: Theme.spacingM
                    spacing: Theme.spacingM
                    visible: !SettingsData.frameEnabled && !(selectedBarConfig?.popupGapsAuto ?? true)

                    Rectangle {
                        width: parent.width - parent.leftPadding
                        height: 1
                        color: Theme.outline
                        opacity: 0.15
                    }

                    SettingsSliderRow {
                        id: popupGapsManualSlider
                        width: parent.width - parent.parent.leftPadding
                        text: I18n.tr("Manual Gap Size")
                        description: I18n.tr("Override the popup gap size when auto is disabled")
                        value: selectedBarConfig?.popupGapsManual ?? 4
                        minimum: 0
                        maximum: 50
                        defaultValue: 4
                        onSliderDragFinished: finalValue => {
                            SettingsData.updateBarConfig(selectedBarId, {
                                popupGapsManual: finalValue
                            });
                        }

                        Binding {
                            target: popupGapsManualSlider
                            property: "value"
                            value: selectedBarConfig?.popupGapsManual ?? 4
                            restoreMode: Binding.RestoreBinding
                        }
                    }
                }
            }

            SettingsSliderCard {
                id: fontScaleSliderCard
                tab: "appearance"
                settingKey: "barFontScale"
                iconName: "text_fields"
                title: I18n.tr("Font Scale")
                description: I18n.tr("Scale KaskadBar font sizes independently")
                visible: kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled
                minimum: 50
                maximum: 200
                value: Math.round((selectedBarConfig?.fontScale ?? 1.0) * 100)
                unit: "%"
                defaultValue: 100
                onSliderValueChanged: newValue => {
                    SettingsData.updateBarConfig(selectedBarId, {
                        fontScale: newValue / 100
                    });
                }

                Binding {
                    target: fontScaleSliderCard
                    property: "value"
                    value: Math.round((selectedBarConfig?.fontScale ?? 1.0) * 100)
                    restoreMode: Binding.RestoreBinding
                }
            }

            SettingsSliderCard {
                id: iconScaleSliderCard
                tab: "appearance"
                settingKey: "barIconScale"
                iconName: "interests"
                title: I18n.tr("Icon Scale")
                description: I18n.tr("Scale KaskadBar icon sizes independently")
                visible: kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled
                minimum: 50
                maximum: 200
                value: Math.round((selectedBarConfig?.iconScale ?? 1.0) * 100)
                unit: "%"
                defaultValue: 100
                onSliderValueChanged: newValue => {
                    SettingsData.updateBarConfig(selectedBarId, {
                        iconScale: newValue / 100
                    });
                }

                Binding {
                    target: iconScaleSliderCard
                    property: "value"
                    value: Math.round((selectedBarConfig?.iconScale ?? 1.0) * 100)
                    restoreMode: Binding.RestoreBinding
                }
            }

            SettingsCard {
                tab: "appearance"
                iconName: "rounded_corner"
                title: I18n.tr("Corners & Background")
                settingKey: "barCorners"
                collapsible: true
                expanded: true
                visible: kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled

                SettingsControlledByFrame {
                    visible: SettingsData.frameEnabled
                    parentModal: kaskadBarTab.parentModal
                    settingLabel: I18n.tr("Bar corners and background")
                    reason: I18n.tr("Managed by Frame")
                }

                SettingsToggleRow {
                    text: I18n.tr("Square Corners")
                    description: I18n.tr("Remove corner rounding from the bar")
                    visible: !SettingsData.frameEnabled
                    checked: selectedBarConfig?.squareCorners ?? false
                    onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                            squareCorners: checked
                        })
                }

                SettingsToggleRow {
                    text: I18n.tr("No Background")
                    description: I18n.tr("Make the bar background fully transparent")
                    visible: !SettingsData.frameEnabled
                    checked: selectedBarConfig?.noBackground ?? false
                    onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                            noBackground: checked
                        })
                }

                SettingsToggleRow {
                    text: I18n.tr("Maximize Widget Icons")
                    description: I18n.tr("Stretch widget icons to fill the available bar height")
                    checked: selectedBarConfig?.maximizeWidgetIcons ?? false
                    onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                            maximizeWidgetIcons: checked
                        })
                }

                SettingsToggleRow {
                    text: I18n.tr("Maximize Widget Text")
                    description: I18n.tr("Stretch widget text to fill the available bar height")
                    checked: selectedBarConfig?.maximizeWidgetText ?? false
                    onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                            maximizeWidgetText: checked
                        })
                }

                SettingsToggleRow {
                    text: I18n.tr("Remove Widget Padding")
                    description: I18n.tr("Remove inner padding from all widgets")
                    checked: selectedBarConfig?.removeWidgetPadding ?? false
                    onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                            removeWidgetPadding: checked
                        })
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                    opacity: 0.15
                }

                SettingsToggleRow {
                    text: I18n.tr("Goth Corners")
                    description: I18n.tr("Apply inverse concave corner cutouts to the bar")
                    visible: !SettingsData.frameEnabled
                    checked: selectedBarConfig?.gothCornersEnabled ?? false
                    onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                            gothCornersEnabled: checked
                        })
                }

                SettingsToggleRow {
                    text: I18n.tr("Corner Radius Override")
                    description: I18n.tr("Use a custom radius for goth corner cutouts")
                    checked: selectedBarConfig?.gothCornerRadiusOverride ?? false
                    visible: selectedBarConfig?.gothCornersEnabled ?? false
                    onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                            gothCornerRadiusOverride: checked
                        })
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: (selectedBarConfig?.gothCornersEnabled ?? false) && (selectedBarConfig?.gothCornerRadiusOverride ?? false)
                    leftPadding: Theme.spacingM

                    SettingsSliderRow {
                        id: gothCornerRadiusSlider
                        width: parent.width - parent.leftPadding
                        text: I18n.tr("Goth Corner Radius")
                        value: selectedBarConfig?.gothCornerRadiusValue ?? 12
                        minimum: 0
                        maximum: 64
                        defaultValue: 12
                        onSliderDragFinished: finalValue => {
                            SettingsData.updateBarConfig(selectedBarId, {
                                gothCornerRadiusValue: finalValue
                            });
                        }

                        Binding {
                            target: gothCornerRadiusSlider
                            property: "value"
                            value: selectedBarConfig?.gothCornerRadiusValue ?? 12
                            restoreMode: Binding.RestoreBinding
                        }
                    }
                }
            }

            SettingsToggleCard {
                iconName: "touch_app"
                title: I18n.tr("Hover Popouts")
                description: I18n.tr("Open widget popouts by hovering over the bar. Moving to another widget switches the popout.")
                visible: !kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled
                enabled: !(selectedBarConfig?.clickThrough ?? false)
                opacity: (selectedBarConfig?.clickThrough ?? false) ? 0.5 : 1.0
                checked: selectedBarConfig?.hoverPopouts ?? false
                onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                        hoverPopouts: checked
                    })

                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: selectedBarConfig?.hoverPopouts ?? false
                    leftPadding: Theme.spacingM

                    SettingsSliderRow {
                        id: hoverDelaySlider
                        width: parent.width - parent.leftPadding
                        text: I18n.tr("Open Delay")
                        description: I18n.tr("Time to rest on a widget before its popout opens")
                        value: selectedBarConfig?.hoverPopoutDelay ?? 150
                        minimum: 0
                        maximum: 1000
                        unit: "ms"
                        defaultValue: 150
                        onSliderValueChanged: newValue => {
                            SettingsData.updateBarConfig(selectedBarId, {
                                hoverPopoutDelay: newValue
                            });
                        }

                        Binding {
                            target: hoverDelaySlider
                            property: "value"
                            value: selectedBarConfig?.hoverPopoutDelay ?? 150
                            restoreMode: Binding.RestoreBinding
                        }
                    }
                }
            }

            SettingsToggleCard {
                iconName: "fit_screen"
                title: I18n.tr("Maximize Detection")
                description: I18n.tr("Remove gaps and border when windows are maximized")
                visible: !kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled && (CompositorService.isNiri || CompositorService.isHyprland || CompositorService.isMango)
                checked: selectedBarConfig?.maximizeDetection ?? true
                onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                        maximizeDetection: checked
                    })
            }

            SettingsCard {
                tab: "appearance"
                iconName: "filter_b_and_w"
                title: I18n.tr("System Tray Icon Tint")
                settingKey: "trayIconTint"
                visible: kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled

                StyledText {
                    text: I18n.tr("Choose monochrome or a theme color tint for system tray icons")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                    horizontalAlignment: Text.AlignLeft
                }

                SettingsButtonGroupRow {
                    text: I18n.tr("Mode")
                    model: [I18n.tr("None"), I18n.tr("Monochrome"), I18n.tr("Primary"), I18n.tr("Secondary")]
                    currentIndex: {
                        let mode = SettingsData.systemTrayIconTintMode || "none";
                        switch (mode) {
                        case "monochrome":
                            return 1;
                        case "primary":
                            return 2;
                        case "secondary":
                            return 3;
                        default:
                            return 0;
                        }
                    }
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;

                        let mode = "none";
                        switch (index) {
                        case 1:
                            mode = "monochrome";
                            break;
                        case 2:
                            mode = "primary";
                            break;
                        case 3:
                            mode = "secondary";
                            break;
                        }

                        SettingsData.set("systemTrayIconTintMode", mode);
                    }
                }

                SettingsSliderRow {
                    id: trayTintSaturationSlider
                    text: I18n.tr("Tint Saturation")
                    description: I18n.tr("Controls how much original icon color is removed before applying tint")
                    visible: {
                        const mode = SettingsData.systemTrayIconTintMode || "none";
                        return mode === "primary" || mode === "secondary";
                    }
                    value: SettingsData.systemTrayIconTintSaturation ?? 50
                    minimum: 0
                    maximum: 100
                    unit: "%"
                    defaultValue: 50
                    onSliderDragFinished: finalValue => SettingsData.set("systemTrayIconTintSaturation", finalValue)

                    Binding {
                        target: trayTintSaturationSlider
                        property: "value"
                        value: SettingsData.systemTrayIconTintSaturation ?? 50
                        restoreMode: Binding.RestoreBinding
                    }
                }

                SettingsSliderRow {
                    id: trayTintStrengthSlider
                    text: I18n.tr("Tint Strength")
                    description: I18n.tr("Controls how strongly the selected tint color is applied")
                    visible: {
                        const mode = SettingsData.systemTrayIconTintMode || "none";
                        return mode === "primary" || mode === "secondary";
                    }
                    value: SettingsData.systemTrayIconTintStrength ?? 135
                    minimum: 0
                    maximum: 200
                    unit: "%"
                    defaultValue: 135
                    onSliderDragFinished: finalValue => SettingsData.set("systemTrayIconTintStrength", finalValue)

                    Binding {
                        target: trayTintStrengthSlider
                        property: "value"
                        value: SettingsData.systemTrayIconTintStrength ?? 135
                        restoreMode: Binding.RestoreBinding
                    }
                }
            }

            SettingsToggleCard {
                tab: "appearance"
                settingKey: "barBorder"
                iconName: "border_style"
                title: I18n.tr("Border")
                visible: kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled && !kaskadBarTab.connectedFrameModeActive
                checked: selectedBarConfig?.borderEnabled ?? false
                onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                        borderEnabled: checked
                    })

                SettingsButtonGroupRow {
                    text: I18n.tr("Color")
                    description: I18n.tr("Theme color used for the border")
                    model: ["Surface", "Secondary", "Primary"]
                    currentIndex: {
                        switch (selectedBarConfig?.borderColor || "surfaceText") {
                        case "surfaceText":
                            return 0;
                        case "secondary":
                            return 1;
                        case "primary":
                            return 2;
                        default:
                            return 0;
                        }
                    }
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        let newColor = "surfaceText";
                        switch (index) {
                        case 0:
                            newColor = "surfaceText";
                            break;
                        case 1:
                            newColor = "secondary";
                            break;
                        case 2:
                            newColor = "primary";
                            break;
                        }
                        SettingsData.updateBarConfig(selectedBarId, {
                            borderColor: newColor
                        });
                    }
                }

                SettingsSliderRow {
                    id: borderOpacitySlider
                    text: I18n.tr("Opacity")
                    value: (selectedBarConfig?.borderOpacity ?? 1.0) * 100
                    minimum: 0
                    maximum: 100
                    unit: "%"
                    defaultValue: 100
                    onSliderDragFinished: finalValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            borderOpacity: finalValue / 100
                        });
                    }

                    Binding {
                        target: borderOpacitySlider
                        property: "value"
                        value: (selectedBarConfig?.borderOpacity ?? 1.0) * 100
                        restoreMode: Binding.RestoreBinding
                    }
                }

                SettingsSliderRow {
                    id: borderThicknessSlider
                    text: I18n.tr("Thickness")
                    description: I18n.tr("Width of the border in pixels")
                    value: selectedBarConfig?.borderThickness ?? 1
                    minimum: 1
                    maximum: 10
                    unit: "px"
                    defaultValue: 1
                    onSliderDragFinished: finalValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            borderThickness: finalValue
                        });
                    }

                    Binding {
                        target: borderThicknessSlider
                        property: "value"
                        value: selectedBarConfig?.borderThickness ?? 1
                        restoreMode: Binding.RestoreBinding
                    }
                }
            }

            SettingsToggleCard {
                tab: "appearance"
                settingKey: "barWidgetOutline"
                iconName: "highlight"
                title: I18n.tr("Widget Outline")
                visible: kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled
                checked: selectedBarConfig?.widgetOutlineEnabled ?? false
                onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                        widgetOutlineEnabled: checked
                    })

                SettingsButtonGroupRow {
                    text: I18n.tr("Color")
                    description: I18n.tr("Theme color used for the widget outline")
                    model: ["Surface", "Secondary", "Primary"]
                    currentIndex: {
                        switch (selectedBarConfig?.widgetOutlineColor || "primary") {
                        case "surfaceText":
                            return 0;
                        case "secondary":
                            return 1;
                        case "primary":
                            return 2;
                        default:
                            return 2;
                        }
                    }
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        let newColor = "primary";
                        switch (index) {
                        case 0:
                            newColor = "surfaceText";
                            break;
                        case 1:
                            newColor = "secondary";
                            break;
                        case 2:
                            newColor = "primary";
                            break;
                        }
                        SettingsData.updateBarConfig(selectedBarId, {
                            widgetOutlineColor: newColor
                        });
                    }
                }

                SettingsSliderRow {
                    id: widgetOutlineOpacitySlider
                    text: I18n.tr("Opacity")
                    value: (selectedBarConfig?.widgetOutlineOpacity ?? 1.0) * 100
                    minimum: 0
                    maximum: 100
                    unit: "%"
                    defaultValue: 100
                    onSliderDragFinished: finalValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            widgetOutlineOpacity: finalValue / 100
                        });
                    }

                    Binding {
                        target: widgetOutlineOpacitySlider
                        property: "value"
                        value: (selectedBarConfig?.widgetOutlineOpacity ?? 1.0) * 100
                        restoreMode: Binding.RestoreBinding
                    }
                }

                SettingsSliderRow {
                    id: widgetOutlineThicknessSlider
                    text: I18n.tr("Thickness")
                    description: I18n.tr("Width of the widget outline in pixels")
                    value: selectedBarConfig?.widgetOutlineThickness ?? 1
                    minimum: 1
                    maximum: 10
                    unit: "px"
                    defaultValue: 1
                    onSliderDragFinished: finalValue => {
                        SettingsData.updateBarConfig(selectedBarId, {
                            widgetOutlineThickness: finalValue
                        });
                    }

                    Binding {
                        target: widgetOutlineThicknessSlider
                        property: "value"
                        value: selectedBarConfig?.widgetOutlineThickness ?? 1
                        restoreMode: Binding.RestoreBinding
                    }
                }
            }

            SettingsControlledByFrame {
                visible: kaskadBarTab.appearanceOnly && kaskadBarTab.connectedFrameModeActive
                parentModal: kaskadBarTab.parentModal
                settingLabel: I18n.tr("Bar shadow, border, and corners")
                reason: I18n.tr("Managed by Frame in Connected Mode")
            }

            SettingsCard {
                id: shadowCard
                tab: "appearance"
                iconName: "layers"
                title: I18n.tr("Shadow Override", "bar shadow settings card")
                settingKey: "barShadow"
                collapsible: true
                expanded: false
                visible: kaskadBarTab.appearanceOnly && (selectedBarConfig?.enabled ?? false) && !kaskadBarTab.connectedFrameModeActive

                readonly property bool shadowActive: (selectedBarConfig?.shadowIntensity ?? 0) > 0
                readonly property bool isCustomColor: (selectedBarConfig?.shadowColorMode ?? "default") === "custom"
                readonly property string directionSource: selectedBarConfig?.shadowDirectionMode ?? "inherit"

                StyledText {
                    width: parent.width
                    text: I18n.tr("Enable a custom override below to set per-bar shadow intensity, opacity, and color.")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignLeft
                }

                SettingsToggleRow {
                    text: I18n.tr("Custom Shadow Override")
                    description: I18n.tr("Override the global shadow with per-bar settings")
                    checked: shadowCard.shadowActive
                    onToggled: checked => {
                        if (checked) {
                            SettingsData.updateBarConfig(selectedBarId, {
                                shadowIntensity: 12,
                                shadowOpacity: 60
                            });
                        } else {
                            SettingsData.updateBarConfig(selectedBarId, {
                                shadowIntensity: 0
                            });
                        }
                    }
                }

                SettingsSliderRow {
                    visible: shadowCard.shadowActive
                    text: I18n.tr("Intensity", "shadow intensity slider")
                    description: I18n.tr("Shadow blur radius in pixels")
                    minimum: 0
                    maximum: 100
                    unit: "px"
                    defaultValue: 12
                    value: selectedBarConfig?.shadowIntensity ?? 0
                    onSliderValueChanged: newValue => SettingsData.updateBarConfig(selectedBarId, {
                            shadowIntensity: newValue
                        })
                }

                SettingsSliderRow {
                    visible: shadowCard.shadowActive
                    text: I18n.tr("Opacity")
                    minimum: 10
                    maximum: 100
                    unit: "%"
                    defaultValue: 60
                    value: selectedBarConfig?.shadowOpacity ?? 60
                    onSliderValueChanged: newValue => SettingsData.updateBarConfig(selectedBarId, {
                            shadowOpacity: newValue
                        })
                }

                SettingsDropdownRow {
                    tab: "appearance"
                    visible: shadowCard.shadowActive
                    text: I18n.tr("Direction Source", "bar shadow direction source")
                    description: I18n.tr("Choose how this bar resolves shadow direction")
                    settingKey: "barShadowDirectionSource"
                    options: [I18n.tr("Inherit Global (Default)", "bar shadow direction source option"), I18n.tr("Auto (Bar-aware)", "bar shadow direction source option"), I18n.tr("Manual", "bar shadow direction source option")]
                    currentValue: {
                        switch (shadowCard.directionSource) {
                        case "autoBar":
                            return I18n.tr("Auto (Bar-aware)", "bar shadow direction source option");
                        case "manual":
                            return I18n.tr("Manual", "bar shadow direction source option");
                        default:
                            return I18n.tr("Inherit Global (Default)", "bar shadow direction source option");
                        }
                    }
                    onValueChanged: value => {
                        if (value === I18n.tr("Auto (Bar-aware)", "bar shadow direction source option")) {
                            SettingsData.updateBarConfig(selectedBarId, {
                                shadowDirectionMode: "autoBar"
                            });
                        } else if (value === I18n.tr("Manual", "bar shadow direction source option")) {
                            SettingsData.updateBarConfig(selectedBarId, {
                                shadowDirectionMode: "manual"
                            });
                        } else {
                            SettingsData.updateBarConfig(selectedBarId, {
                                shadowDirectionMode: "inherit"
                            });
                        }
                    }
                }

                SettingsDropdownRow {
                    tab: "appearance"
                    visible: shadowCard.shadowActive && shadowCard.directionSource === "manual"
                    text: I18n.tr("Manual Direction", "bar manual shadow direction")
                    description: I18n.tr("Use a fixed shadow direction for this bar")
                    settingKey: "barShadowDirectionManual"
                    options: [I18n.tr("Top", "shadow direction option"), I18n.tr("Top Left", "shadow direction option"), I18n.tr("Top Right", "shadow direction option"), I18n.tr("Bottom", "shadow direction option")]
                    currentValue: {
                        switch (selectedBarConfig?.shadowDirection) {
                        case "topLeft":
                            return I18n.tr("Top Left", "shadow direction option");
                        case "topRight":
                            return I18n.tr("Top Right", "shadow direction option");
                        case "bottom":
                            return I18n.tr("Bottom", "shadow direction option");
                        default:
                            return I18n.tr("Top", "shadow direction option");
                        }
                    }
                    onValueChanged: value => {
                        if (value === I18n.tr("Top Left", "shadow direction option")) {
                            SettingsData.updateBarConfig(selectedBarId, {
                                shadowDirection: "topLeft"
                            });
                        } else if (value === I18n.tr("Top Right", "shadow direction option")) {
                            SettingsData.updateBarConfig(selectedBarId, {
                                shadowDirection: "topRight"
                            });
                        } else if (value === I18n.tr("Bottom", "shadow direction option")) {
                            SettingsData.updateBarConfig(selectedBarId, {
                                shadowDirection: "bottom"
                            });
                        } else {
                            SettingsData.updateBarConfig(selectedBarId, {
                                shadowDirection: "top"
                            });
                        }
                    }
                }

                Column {
                    visible: shadowCard.shadowActive
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: I18n.tr("Color")
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignLeft
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                    }

                    Item {
                        width: parent.width
                        height: shadowColorGroup.implicitHeight

                        KaskadButtonGroup {
                            id: shadowColorGroup
                            anchors.horizontalCenter: parent.horizontalCenter
                            buttonPadding: parent.width < 420 ? Theme.spacingXS : Theme.spacingS
                            minButtonWidth: parent.width < 420 ? 36 : 56
                            textSize: parent.width < 420 ? Theme.fontSizeSmall : Theme.fontSizeMedium
                            model: [I18n.tr("Default (Black)"), I18n.tr("Surface", "shadow color option"), I18n.tr("Primary"), I18n.tr("Secondary"), I18n.tr("Custom")]
                            selectionMode: "single"
                            currentIndex: {
                                switch (selectedBarConfig?.shadowColorMode || "default") {
                                case "surface":
                                    return 1;
                                case "primary":
                                    return 2;
                                case "secondary":
                                    return 3;
                                case "custom":
                                    return 4;
                                default:
                                    return 0;
                                }
                            }
                            onSelectionChanged: (index, selected) => {
                                if (!selected)
                                    return;
                                let mode = "default";
                                switch (index) {
                                case 1:
                                    mode = "surface";
                                    break;
                                case 2:
                                    mode = "primary";
                                    break;
                                case 3:
                                    mode = "secondary";
                                    break;
                                case 4:
                                    mode = "custom";
                                    break;
                                }
                                SettingsData.updateBarConfig(selectedBarId, {
                                    shadowColorMode: mode
                                });
                            }
                        }
                    }

                    Rectangle {
                        visible: selectedBarConfig?.shadowColorMode === "custom"
                        width: 32
                        height: 32
                        radius: 16
                        color: selectedBarConfig?.shadowCustomColor ?? "#000000"
                        border.color: Theme.outline
                        border.width: 1
                        anchors.horizontalCenter: parent.horizontalCenter

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                PopoutService.colorPickerModal.selectedColor = selectedBarConfig?.shadowCustomColor ?? "#000000";
                                PopoutService.colorPickerModal.pickerTitle = I18n.tr("Color");
                                PopoutService.colorPickerModal.onColorSelectedCallback = function (color) {
                                    SettingsData.updateBarConfig(selectedBarId, {
                                        shadowCustomColor: color.toString()
                                    });
                                };
                                PopoutService.colorPickerModal.show();
                            }
                        }
                    }
                }
            }

            SettingsToggleCard {
                iconName: "mouse"
                title: I18n.tr("Scroll Wheel")
                description: I18n.tr("Control workspaces and columns by scrolling on the bar")
                visible: !kaskadBarTab.appearanceOnly && selectedBarConfig?.enabled
                checked: selectedBarConfig?.scrollEnabled ?? true
                onToggled: checked => SettingsData.updateBarConfig(selectedBarId, {
                        scrollEnabled: checked
                    })

                SettingsButtonGroupRow {
                    text: I18n.tr("Y Axis")
                    description: I18n.tr("Action performed when scrolling vertically on the bar")
                    model: CompositorService.isNiri ? [I18n.tr("None"), I18n.tr("Workspace"), I18n.tr("Column")] : [I18n.tr("None"), I18n.tr("Workspace")]
                    buttonPadding: Theme.spacingS
                    minButtonWidth: 44
                    textSize: Theme.fontSizeSmall
                    currentIndex: {
                        switch (selectedBarConfig?.scrollYBehavior || "workspace") {
                        case "none":
                            return 0;
                        case "workspace":
                            return 1;
                        case "column":
                            return 2;
                        default:
                            return 1;
                        }
                    }
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        let behavior = "workspace";
                        switch (index) {
                        case 0:
                            behavior = "none";
                            break;
                        case 1:
                            behavior = "workspace";
                            break;
                        case 2:
                            behavior = "column";
                            break;
                        }
                        SettingsData.updateBarConfig(selectedBarId, {
                            scrollYBehavior: behavior
                        });
                    }
                }

                SettingsButtonGroupRow {
                    text: I18n.tr("X Axis")
                    description: I18n.tr("Action performed when scrolling horizontally on the bar")
                    visible: CompositorService.isNiri
                    model: [I18n.tr("None"), I18n.tr("Workspace"), I18n.tr("Column")]
                    buttonPadding: Theme.spacingS
                    minButtonWidth: 44
                    textSize: Theme.fontSizeSmall
                    currentIndex: {
                        switch (selectedBarConfig?.scrollXBehavior || "column") {
                        case "none":
                            return 0;
                        case "workspace":
                            return 1;
                        case "column":
                            return 2;
                        default:
                            return 2;
                        }
                    }
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        let behavior = "column";
                        switch (index) {
                        case 0:
                            behavior = "none";
                            break;
                        case 1:
                            behavior = "workspace";
                            break;
                        case 2:
                            behavior = "column";
                            break;
                        }
                        SettingsData.updateBarConfig(selectedBarId, {
                            scrollXBehavior: behavior
                        });
                    }
                }
            }
        }
    }
}

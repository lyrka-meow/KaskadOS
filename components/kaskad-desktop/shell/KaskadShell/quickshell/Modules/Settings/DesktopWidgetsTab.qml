pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var expandedStates: ({})
    property var parentModal: null

    readonly property var allInstances: (SettingsData.desktopWidgetInstances || []).filter(instance => DesktopWidgetRegistry.getWidget(instance.widgetType) !== null)

    function setExpanded(instanceId, expanded) {
        if (expanded === (expandedStates[instanceId] ?? false))
            return;
        var states = Object.assign({}, expandedStates);
        states[instanceId] = expanded;
        expandedStates = states;
    }

    function consumeSettingsTarget() {
        const targetId = LayoutEditService.settingsTargetId;
        if (!targetId)
            return;

        const target = root.allInstances.find(instance => instance.id === targetId);
        if (target)
            root.setExpanded(targetId, true);

        LayoutEditService.settingsTargetId = "";
    }

    Component.onCompleted: Qt.callLater(root.consumeSettingsTarget)

    Connections {
        target: LayoutEditService

        function onSettingsTargetIdChanged() {
            Qt.callLater(root.consumeSettingsTarget);
        }
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
                width: parent.width
                iconName: "widgets"
                title: I18n.tr("Desktop Widgets")

                Row {
                    width: parent.width - Theme.spacingM * 2
                    x: Theme.spacingM
                    spacing: Theme.spacingM

                    StyledText {
                        text: I18n.tr("Configure widget behavior here, or manage the layout directly on the desktop")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignLeft
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - editDesktopButton.width - Theme.spacingM
                    }

                    KaskadButton {
                        id: editDesktopButton
                        text: I18n.tr("Edit desktop")
                        iconName: "dashboard_customize"
                        buttonHeight: 36
                        horizontalPadding: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            root.parentModal?.close();
                            LayoutEditService.begin("desktop", "");
                        }
                    }
                }
            }

            Repeater {
                model: ScriptModel {
                    objectProp: "id"
                    values: root.allInstances
                }

                DesktopWidgetInstanceCard {
                    required property var modelData
                    required property int index

                    width: mainColumn.width
                    instanceData: modelData
                    isExpanded: root.expandedStates[modelData.id] ?? false
                    managementActionsEnabled: false
                    groupSelectionEnabled: false
                    layoutActionsEnabled: false

                    onExpandedChanged: {
                        if (expanded === (root.expandedStates[modelData.id] ?? false))
                            return;
                        root.setExpanded(modelData.id, expanded);
                    }
                }
            }

            StyledText {
                visible: root.allInstances.length === 0
                text: I18n.tr("No desktop widgets yet. Open the desktop editor to add one.")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignLeft
            }
        }
    }
}

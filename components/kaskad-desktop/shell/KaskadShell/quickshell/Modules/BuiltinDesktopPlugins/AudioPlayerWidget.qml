import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root

    property real widgetWidth: 440
    property real widgetHeight: 520
    property real defaultWidth: 440
    property real defaultHeight: 520
    property real minWidth: 340
    property real minHeight: 320

    property string instanceId: ""
    property var instanceData: null
    readonly property var cfg: instanceData?.config ?? ({})
    readonly property var localSession: instanceId && instanceData
                                        ? LocalMediaRegistry.sessionFor(instanceId, cfg)
                                        : null

    Connections {
        target: root.localSession
        function onConfigurationChanged(updates) {
            if (root.instanceId)
                SettingsData.updateDesktopWidgetInstanceConfig(root.instanceId, updates);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainer, root.cfg.transparency ?? 0.96)
        border.color: Theme.outline
        border.width: 1

        Loader {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            active: root.localSession !== null
            sourceComponent: LocalMediaPlayerView {
                session: root.localSession
                compact: true
            }
        }
    }
}

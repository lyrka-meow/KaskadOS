import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root

    required property var session
    property var anchorItem: null
    property var targetScreen: null
    property string barEdge: "top"
    property real barThickness: 48
    property real barSpacing: 4
    property point anchorPos: Qt.point(0, 0)

    function show() {
        const screenObject = targetScreen || Screen;
        if (screenObject)
            screen = screenObject;
        if (anchorItem) {
            const globalPosition = anchorItem.mapToGlobal(anchorItem.width / 2, anchorItem.height / 2);
            anchorPos = Qt.point(globalPosition.x - (screenObject?.x ?? 0),
                                 globalPosition.y - (screenObject?.y ?? 0));
        }
        visible = true;
    }

    function close() {
        visible = false;
    }

    screen: targetScreen
    visible: false
    color: "transparent"
    WlrLayershell.namespace: "kaskados:local-media-player:" + (session?.instanceId ?? "default")
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: root.close()
    }

    Rectangle {
        id: playerContainer
        z: 1
        readonly property real edgeGap: Math.max(Theme.spacingS, root.barSpacing)
        readonly property real desiredWidth: 520
        readonly property real desiredHeight: 640

        width: Math.min(desiredWidth, root.width - Theme.spacingM * 2)
        height: Math.min(desiredHeight, root.height - Theme.spacingM * 2)
        x: {
            if (root.barEdge === "left")
                return Math.min(root.width - width - Theme.spacingM, root.barThickness + edgeGap);
            if (root.barEdge === "right")
                return Math.max(Theme.spacingM, root.width - root.barThickness - edgeGap - width);
            return Math.max(Theme.spacingM, Math.min(root.width - width - Theme.spacingM,
                                                    root.anchorPos.x - width / 2));
        }
        y: {
            if (root.barEdge === "top")
                return Math.min(root.height - height - Theme.spacingM, root.barThickness + edgeGap);
            if (root.barEdge === "bottom")
                return Math.max(Theme.spacingM, root.height - root.barThickness - edgeGap - height);
            return Math.max(Theme.spacingM, Math.min(root.height - height - Theme.spacingM,
                                                    root.anchorPos.y - height / 2));
        }
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
        border.width: BlurService.borderWidth
        border.color: BlurService.borderColor

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => mouse.accepted = true
        }

        Loader {
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            active: root.session !== null && root.session !== undefined

            sourceComponent: LocalMediaPlayerView {
                session: root.session
                onRequestClose: root.close()
            }
        }
    }

    WindowBlur {
        targetWindow: root
        blurX: playerContainer.x
        blurY: playerContainer.y
        blurWidth: root.visible ? playerContainer.width : 0
        blurHeight: root.visible ? playerContainer.height : 0
        blurRadius: Theme.cornerRadius
    }
}

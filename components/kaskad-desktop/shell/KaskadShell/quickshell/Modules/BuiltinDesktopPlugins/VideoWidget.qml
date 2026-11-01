import QtQuick
import QtQuick.Effects
import QtMultimedia
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property real widgetWidth: 480
    property real widgetHeight: 270
    property real defaultWidth: 480
    property real defaultHeight: 270
    property real minWidth: 180
    property real minHeight: 120

    property string instanceId: ""
    property var instanceData: null

    readonly property var cfg: instanceData?.config ?? ({})
    readonly property string configuredPath: cfg.videoPath ?? ""
    readonly property bool muted: cfg.muted ?? true
    readonly property real videoVolume: Math.max(0, Math.min(1, cfg.volume ?? 1.0))
    readonly property real videoOpacity: Math.max(0, Math.min(1, cfg.opacity ?? 1.0))
    readonly property string configuredFillMode: cfg.fillMode ?? "crop"
    readonly property real configuredCornerRadius: Math.max(0, Math.min(Math.min(width, height) / 2, cfg.cornerRadius ?? Theme.cornerRadius))
    property string playbackError: ""
    readonly property url videoSource: {
        const path = configuredPath.trim();
        if (!path)
            return "";
        if (path.startsWith("file://"))
            return path;
        return "file://" + path;
    }

    function setMuted(value) {
        if (!instanceId)
            return;
        SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
            muted: value
        });
    }

    Rectangle {
        id: videoFrame
        anchors.fill: parent
        radius: root.configuredCornerRadius
        color: "black"
        opacity: root.videoOpacity
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: cornerMask
        }

        Video {
            id: videoPlayer
            anchors.fill: parent
            source: root.videoSource
            volume: root.muted ? 0 : root.videoVolume
            loops: MediaPlayer.Infinite
            fillMode: {
                switch (root.configuredFillMode) {
                case "fit":
                    return VideoOutput.PreserveAspectFit;
                case "stretch":
                    return VideoOutput.Stretch;
                default:
                    return VideoOutput.PreserveAspectCrop;
                }
            }

            Component.onCompleted: {
                if (source.toString())
                    play();
            }

            onSourceChanged: {
                root.playbackError = "";
                stop();
                if (source.toString())
                    play();
            }

            onErrorOccurred: (error, errorString) => root.playbackError = errorString
        }
    }

    Rectangle {
        id: cornerMask
        anchors.fill: parent
        radius: root.configuredCornerRadius
        color: "white"
        visible: false
        layer.enabled: true
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            if (videoPlayer.source.toString())
                videoPlayer.play();
        }
    }

    Column {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - Theme.spacingXL * 2)
        spacing: Theme.spacingS
        visible: root.videoSource.toString() === "" || root.playbackError !== ""

        KaskadIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "movie"
            size: Theme.iconSizeLarge
            color: Theme.surfaceVariantText
        }

        StyledText {
            width: parent.width
            text: root.playbackError || I18n.tr("Choose a video in widget settings")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    Rectangle {
        id: soundButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingS
        width: 40
        height: 40
        radius: width / 2
        z: 10
        color: soundArea.containsMouse ? Qt.rgba(0.05, 0.07, 0.06, 0.92) : Qt.rgba(0.05, 0.07, 0.06, 0.76)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.32)
        visible: root.videoSource.toString() !== "" && root.playbackError === ""

        Canvas {
            id: soundIcon
            anchors.centerIn: parent
            width: 24
            height: 24

            onPaint: {
                const context = getContext("2d");
                context.clearRect(0, 0, width, height);
                context.fillStyle = "#ffffff";
                context.strokeStyle = "#ffffff";
                context.lineWidth = 2;
                context.lineCap = "round";
                context.lineJoin = "round";

                context.beginPath();
                context.moveTo(3, 9);
                context.lineTo(7, 9);
                context.lineTo(12, 5);
                context.lineTo(12, 19);
                context.lineTo(7, 15);
                context.lineTo(3, 15);
                context.closePath();
                context.fill();

                context.beginPath();
                if (root.muted) {
                    context.moveTo(16, 9);
                    context.lineTo(21, 15);
                    context.moveTo(21, 9);
                    context.lineTo(16, 15);
                } else {
                    context.moveTo(15, 9);
                    context.quadraticCurveTo(18, 12, 15, 15);
                    context.moveTo(18, 6.5);
                    context.quadraticCurveTo(23, 12, 18, 17.5);
                }
                context.stroke();
            }

            Connections {
                target: root
                function onMutedChanged() {
                    soundIcon.requestPaint();
                }
            }
        }

        MouseArea {
            id: soundArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setMuted(!root.muted)
        }
    }
}

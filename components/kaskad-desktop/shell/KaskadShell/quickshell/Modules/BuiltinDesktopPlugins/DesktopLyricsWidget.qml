import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property real widgetWidth: 620
    property real widgetHeight: 230
    property real defaultWidth: 620
    property real defaultHeight: 230
    property real minWidth: 360
    property real minHeight: 170
    property string instanceId: ""
    property var instanceData: null

    readonly property var cfg: instanceData?.config || ({})
    readonly property string sourceMode: cfg.sourceMode || "auto"
    readonly property var localSession: {
        if (cfg.localInstanceId)
            return LocalMediaRegistry.sessions[cfg.localInstanceId] || null;
        return LocalMediaCoordinator.activeSession;
    }
    readonly property var selectedExternal: {
        const players = MprisController.availablePlayers || [];
        if (sourceMode === "mpris" && cfg.mprisIdentity)
            return players.find(player => player.identity === cfg.mprisIdentity) || MprisController.activePlayer;
        return MprisController.activePlayer;
    }
    readonly property bool useLocal: sourceMode === "local"
                                     || (sourceMode === "auto" && localSession?.hasCurrentTrack)
    readonly property var lines: useLocal ? (localSession?.lyricsLines || []) : externalLyrics.lines
    readonly property real position: Math.max(0, (useLocal ? (localSession?.position || 0)
                                                             : (selectedExternal?.position || 0))
                                                       + ((cfg.syncOffsetMs || 0) / 1000))
    readonly property int currentIndex: indexForTime(position)
    readonly property var previousLine: currentIndex > 0 ? lines[currentIndex - 1] : null
    readonly property var currentLine: currentIndex >= 0 && currentIndex < lines.length ? lines[currentIndex] : null
    readonly property var nextLine: currentIndex + 1 < lines.length ? lines[currentIndex + 1] : null
    readonly property bool playing: useLocal ? (localSession?.playing || false)
                                             : selectedExternal?.playbackState === MprisPlaybackState.Playing
    readonly property string trackTitle: useLocal ? (localSession?.title || "")
                                                  : (selectedExternal?.trackTitle || "")
    readonly property string trackArtist: useLocal ? (localSession?.artist || "")
                                                   : (selectedExternal?.trackArtist || "")
    readonly property string trackLabel: trackArtist ? (trackTitle + "  ·  " + trackArtist) : trackTitle
    property real bassPulse: 0
    property real lineArrival: 1
    property real titleReveal: 1
    readonly property real lineProgress: {
        if (!currentLine)
            return 0;
        const end = nextLine?.time ?? (position + 4);
        return Math.max(0, Math.min(1, (position - currentLine.time) / Math.max(0.2, end - currentLine.time)));
    }

    function indexForTime(seconds) {
        let result = -1;
        for (let index = 0; index < lines.length; index++) {
            if (lines[index].time > seconds + 0.08)
                break;
            result = index;
        }
        return result;
    }

    function updateExternalLyrics() {
        if (useLocal)
            return;
        const player = selectedExternal;
        externalLyrics.loadTrack(player?.trackArtist || "", player?.trackTitle || "",
                                 player?.trackAlbum || "", player?.length || MprisController.activePlayerStableLength || 0);
    }

    function cycleSource() {
        const players = MprisController.availablePlayers || [];
        const localSessions = LocalMediaCoordinator.sessions || [];
        const options = [{ mode: "auto", identity: "", localInstanceId: "" }];
        if (localSessions.length === 0)
            options.push({ mode: "local", identity: "", localInstanceId: "" });
        for (let index = 0; index < localSessions.length; index++)
            options.push({ mode: "local", identity: "", localInstanceId: localSessions[index].instanceId || "" });
        for (let index = 0; index < players.length; index++)
            options.push({ mode: "mpris", identity: players[index].identity || "", localInstanceId: "" });
        let current = options.findIndex(option => option.mode === sourceMode
                                        && (option.mode !== "mpris" || option.identity === (cfg.mprisIdentity || ""))
                                        && (option.mode !== "local" || option.localInstanceId === (cfg.localInstanceId || "")));
        if (current < 0)
            current = 0;
        const next = options[(current + 1) % options.length];
        SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
            sourceMode: next.mode,
            mprisIdentity: next.identity,
            localInstanceId: next.localInstanceId
        });
    }

    function adjustOffset(delta) {
        const next = Math.max(-5000, Math.min(5000, (cfg.syncOffsetMs || 0) + delta));
        SettingsData.updateDesktopWidgetInstanceConfig(instanceId, { syncOffsetMs: next });
    }

    function escaped(value) {
        return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
                                  .replace(/>/g, "&gt;").replace(/\"/g, "&quot;");
    }

    function activeLineMarkup() {
        const value = currentLine?.text || (lines.length === 0 ? I18n.tr("No synchronized lyrics") : "♪");
        const words = value.trim().split(/\s+/).filter(word => word.length > 0);
        if (words.length === 0)
            return "";
        let total = 0;
        const weights = [];
        for (let index = 0; index < words.length; index++) {
            const weight = Math.max(1.4, Math.sqrt(words[index].length + 1));
            weights.push(weight);
            total += weight;
        }
        const sung = lineProgress * total;
        let cursor = 0;
        const activeColor = Theme.primary;
        const waitingColor = Qt.rgba(0.85, 0.87, 0.86, 1);
        const result = [];
        for (let index = 0; index < words.length; index++) {
            const progress = Math.max(0, Math.min(1, (sung - cursor) / weights[index]));
            const color = Qt.rgba(waitingColor.r + (activeColor.r - waitingColor.r) * progress,
                                  waitingColor.g + (activeColor.g - waitingColor.g) * progress,
                                  waitingColor.b + (activeColor.b - waitingColor.b) * progress, 1);
            result.push("<span style=\"color:" + color.toString() + "\">"
                        + escaped(words[index]) + "</span>");
            cursor += weights[index];
        }
        return result.join(" ");
    }

    onSelectedExternalChanged: Qt.callLater(updateExternalLyrics)
    onUseLocalChanged: Qt.callLater(updateExternalLyrics)
    onCurrentIndexChanged: arrivalAnimation.restart()
    onTrackTitleChanged: titleAnimation.restart()
    Component.onCompleted: updateExternalLyrics()

    Connections {
        target: root.selectedExternal
        function onTrackTitleChanged() { root.updateExternalLyrics(); }
        function onTrackArtistChanged() { root.updateExternalLyrics(); }
    }

    LyricsSession { id: externalLyrics }

    TextMetrics {
        id: titleMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        text: root.trackLabel
    }

    Timer {
        interval: 100
        repeat: true
        running: root.selectedExternal?.playbackState === MprisPlaybackState.Playing
        onTriggered: root.selectedExternal?.positionChanged()
    }

    Loader {
        active: root.visible && root.playing
        sourceComponent: Component { Ref { service: CavaService } }
    }

    Connections {
        target: CavaService
        enabled: root.visible && root.playing
        function onValuesChanged() {
            const values = CavaService.compactValues || [];
            const bass = ((values[0] || 0) * 0.7 + (values[1] || 0) * 0.3) / 100;
            root.bassPulse = Math.max(0, Math.min(1, Math.sqrt(bass)));
        }
    }

    SequentialAnimation {
        id: arrivalAnimation
        PropertyAction { target: root; property: "lineArrival"; value: 0 }
        NumberAnimation { target: root; property: "lineArrival"; to: 1; duration: 320; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: titleAnimation
        PropertyAction { target: root; property: "titleReveal"; value: 0 }
        PauseAnimation { duration: 45 }
        NumberAnimation { target: root; property: "titleReveal"; to: 1; duration: 420; easing.type: Easing.OutBack }
    }

    Item {
        anchors.fill: parent

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            Item {
                width: parent.width
                height: 30

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: sourceText.implicitWidth + Theme.spacingM * 2
                    height: 28
                    radius: 14
                    color: Theme.withAlpha(sourceArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer, 0.88)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.72)
                    visible: LayoutEditService.active
                    KaskadIcon { anchors.left: parent.left; anchors.leftMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter; name: root.useLocal ? "library_music" : "cast"; size: 16; color: Theme.primary }
                    StyledText { id: sourceText; anchors.left: parent.left; anchors.leftMargin: 30; anchors.verticalCenter: parent.verticalCenter; text: root.sourceMode === "auto" ? "Автовыбор" : (root.useLocal ? (root.localSession?.title || "Локальный плеер") : (root.selectedExternal?.identity || "Внешний плеер")); color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: sourceArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.cycleSource() }
                }

                Row {
                    id: titleStage
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: (1 - root.titleReveal) * 8
                    width: Math.min(titleMetrics.advanceWidth + 42, parent.width * (LayoutEditService.active ? 0.42 : 0.86))
                    spacing: Theme.spacingS
                    opacity: root.titleReveal
                    scale: 0.9 + root.titleReveal * 0.1

                    CavaWaveform {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 15
                        playing: root.playing
                        waveColor: Theme.primary
                    }
                    StyledText {
                        width: Math.max(0, titleStage.width - 42)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.trackLabel
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: offsetControls
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    visible: LayoutEditService.active
                    Rectangle {
                        width: 28; height: 28; radius: 14; color: Theme.withAlpha(minusArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer, 0.88)
                        StyledText { anchors.centerIn: parent; text: "−"; color: Theme.surfaceText }
                        MouseArea { id: minusArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustOffset(-100) }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.cfg.syncOffsetMs || 0) === 0 ? "Без сдвига" : ((root.cfg.syncOffsetMs || 0) + " мс")
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    Rectangle {
                        width: 28; height: 28; radius: 14; color: Theme.withAlpha(plusArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer, 0.88)
                        StyledText { anchors.centerIn: parent; text: "+"; color: Theme.surfaceText }
                        MouseArea { id: plusArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.adjustOffset(100) }
                    }
                }
            }

            OutlinedLyricsText {
                width: parent.width
                height: 28
                text: root.previousLine?.text || ""
                pixelSize: Math.max(13, Math.min(18, root.widgetWidth / 34))
                maxLines: 1
                fillColor: "#f2f4f3"
                opacity: 0.5
            }

            Item {
                width: parent.width
                height: Math.max(76, Math.min(104, root.widgetHeight * 0.42))

                Item {
                    id: currentMotion
                    anchors.fill: parent
                    opacity: 0.3 + root.lineArrival * 0.7
                    scale: (0.96 + root.lineArrival * 0.04) * (1 + root.bassPulse * 0.012)
                    transform: Translate { y: (1 - root.lineArrival) * 12 }

                    Behavior on scale { NumberAnimation { duration: 75; easing.type: Easing.OutQuad } }

                    OutlinedLyricsText {
                        id: inactiveCurrent
                        anchors.fill: parent
                        text: root.activeLineMarkup()
                        plainText: root.currentLine?.text || (root.lines.length === 0 ? I18n.tr("No synchronized lyrics") : "♪")
                        richText: true
                        fillColor: "#d9dddc"
                        opacity: root.currentLine ? 0.96 : 0.72
                        pixelSize: Math.max(24, Math.min(42, root.widgetWidth / 16))
                        maxLines: 2
                    }
                }
            }

            OutlinedLyricsText {
                width: parent.width
                height: 28
                text: root.nextLine?.text || ""
                pixelSize: Math.max(13, Math.min(18, root.widgetWidth / 34))
                maxLines: 1
                fillColor: "#f2f4f3"
                opacity: 0.66
            }
        }
    }

    component OutlinedLyricsText: Item {
        id: outlined
        property string text: ""
        property int pixelSize: 28
        property int maxLines: 2
        property bool richText: false
        property string plainText: text
        property color fillColor: "white"
        property color outlineColor: "#d90b1115"

        Text {
            x: 3
            y: 4
            width: parent.width
            height: parent.height
            text: outlined.plainText
            textFormat: Text.PlainText
            color: "#b8000000"
            font.family: Theme.fontFamily
            font.pixelSize: outlined.pixelSize
            fontSizeMode: Text.Fit
            minimumPixelSize: Math.max(11, outlined.pixelSize * 0.62)
            font.weight: Font.ExtraBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: outlined.maxLines
        }

        Text {
            anchors.fill: parent
            text: outlined.text
            textFormat: outlined.richText ? Text.RichText : Text.PlainText
            color: outlined.fillColor
            style: Text.Outline
            styleColor: outlined.outlineColor
            font.family: Theme.fontFamily
            font.pixelSize: outlined.pixelSize
            fontSizeMode: Text.Fit
            minimumPixelSize: Math.max(11, outlined.pixelSize * 0.62)
            font.weight: Font.ExtraBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: outlined.maxLines
        }
    }
}

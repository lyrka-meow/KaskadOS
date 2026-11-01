import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property real stableLength: MprisController.activePlayerStableLength
    property var allPlayers: MprisController.availablePlayers
    property var targetScreen: null
    property real popoutX: 0
    property real popoutY: 0
    property real popoutWidth: 0
    property real popoutHeight: 0
    property real contentOffsetY: 0
    property string section: ""
    property int barPosition: SettingsData.Position.Top
    property bool lyricsPanelOpen: false
    readonly property var localSession: LocalMediaCoordinator.activeSession
    readonly property bool externalAvailable: activePlayer !== null
    readonly property bool useLocalPlayer: localSession !== null
                                            && (LocalMediaCoordinator.dashboardSource === "local" || !externalAvailable)
    property bool localLyricsVisible: false

    readonly property color accent: MediaAccentService.accent
    readonly property color onAccent: MediaAccentService.onAccent
    readonly property color accentHover: MediaAccentService.accentHover
    readonly property color accentPressed: MediaAccentService.accentPressed

    signal showVolumeDropdown(point pos, var screen, bool rightEdge, var player, var players)
    signal showAudioDevicesDropdown(point pos, var screen, bool rightEdge)
    signal showPlayersDropdown(point pos, var screen, bool rightEdge, var player, var players)
    signal hideDropdowns
    signal dropdownButtonExited
    signal dropdownButtonEntered

    property bool volumeExpanded: false
    property bool devicesExpanded: false
    property bool playersExpanded: false

    function resetDropdownStates() {
        volumeExpanded = false;
        devicesExpanded = false;
        playersExpanded = false;
        lyricsPanelOpen = false;
    }

    function localizedLyricsError(message) {
        const normalized = String(message || "").toLowerCase();
        if (normalized.includes("not synchronized"))
            return I18n.tr("Lyrics are available, but not synchronized");
        return I18n.tr("Lyrics not found");
    }

    function localDisplayName(path) {
        if (!path)
            return "";
        const slash = path.lastIndexOf("/");
        return path.substring(slash + 1).replace(/\.[^.]+$/, "");
    }

    function localTrackTitle(path) {
        return localDisplayName(path).replace(/^\s*\d+\s*[-_.–—]\s*/, "");
    }

    function toggleMediaSource() {
        if (!localSession || !externalAvailable)
            return;
        if (useLocalPlayer) {
            if (localSession.playing)
                localSession.togglePlaying();
            LocalMediaCoordinator.setDashboardSource("external");
        } else {
            if (activePlayer?.canPause && activePlayer.playbackState === MprisPlaybackState.Playing)
                activePlayer.pause();
            LocalMediaCoordinator.setDashboardSource("local");
        }
    }

    readonly property bool isRightEdge: {
        if (barPosition === SettingsData.Position.Right)
            return true;
        if (barPosition === SettingsData.Position.Left)
            return false;
        return section === "right";
    }
    readonly property bool __isChromeBrowser: {
        if (!activePlayer?.identity)
            return false;
        const id = activePlayer.identity.toLowerCase();
        return id.includes("chrome") || id.includes("chromium");
    }
    readonly property bool volumeAvailable: useLocalPlayer || !!((activePlayer && activePlayer.volumeSupported && !__isChromeBrowser) || (AudioService.sink && AudioService.sink.audio))
    readonly property bool usePlayerVolume: useLocalPlayer || (activePlayer && activePlayer.volumeSupported && !__isChromeBrowser)
    readonly property real currentVolume: useLocalPlayer ? (localSession?.volume ?? 0)
                                                     : (usePlayerVolume ? activePlayer.volume : (AudioService.sink?.audio?.volume ?? 0))

    property bool isSwitching: false
    property int lyricIndex: -1
    readonly property var displayedLyricsLines: useLocalPlayer ? (localSession?.lyricsLines ?? []) : LyricsService.lines
    readonly property bool displayedLyricsLoading: useLocalPlayer ? (localSession?.lyricsLoading ?? false) : LyricsService.loading
    readonly property string displayedLyricsError: useLocalPlayer ? (localSession?.lyricsError ?? "") : LyricsService.error
    readonly property int lyricDisplayIndex: lyricIndex >= 0 ? lyricIndex : (displayedLyricsLines.length > 0 ? 0 : -1)

    function updateLyrics() {
        if (useLocalPlayer) {
            lyricIndex = localSession?.lyricIndex ?? -1;
            return;
        }
        if (!activePlayer) {
            LyricsService.loadTrack("", "", "", 0);
            lyricIndex = -1;
            return;
        }
        LyricsService.loadTrack(activePlayer.trackArtist, activePlayer.trackTitle,
                                activePlayer.trackAlbum, stableLength);
        lyricIndex = LyricsService.indexForTime(activePlayer.position || 0);
    }

    onStableLengthChanged: updateLyrics()
    onUseLocalPlayerChanged: Qt.callLater(updateLyrics)
    Component.onCompleted: updateLyrics()

    // Derived "no players" state: always correct, no timers.
    readonly property int _playerCount: allPlayers ? allPlayers.length : 0
    readonly property bool _noneAvailable: !useLocalPlayer && _playerCount === 0
    readonly property bool showNoPlayerNow: !useLocalPlayer && (!_switchHold) && (_noneAvailable || !activePlayer)

    FolderDialog {
        id: localFolderDialog
        title: I18n.tr("Choose a music folder")
        currentFolder: root.localSession?.folderPath ? Paths.toFileUrl(root.localSession.folderPath) : Paths.home
        onAccepted: root.localSession?.setFolder(selectedFolder)
    }

    property bool _switchHold: false
    Timer {
        id: _switchHoldTimer
        interval: 1500
        repeat: false
        onTriggered: _switchHold = false
    }

    onActivePlayerChanged: {
        if (!activePlayer) {
            isSwitching = false;
            _switchHold = true;
            _switchHoldTimer.restart();
            return;
        }
        isSwitching = true;
        _switchHold = true;
        _switchHoldTimer.restart();
        Qt.callLater(updateLyrics);
    }

    function maybeFinishSwitch() {
        if (activePlayer && activePlayer.trackTitle !== "") {
            isSwitching = false;
            _switchHold = false;
        }
    }

    readonly property real ratio: {
        if (!activePlayer || stableLength <= 0) {
            return 0;
        }
        const pos = (activePlayer.position || 0) % Math.max(1, stableLength);
        const calculatedRatio = pos / stableLength;
        return Math.max(0, Math.min(1, calculatedRatio));
    }

    implicitWidth: SettingsData.showWeekNumber ? 736 : 700
    implicitHeight: 410

    Connections {
        target: activePlayer
        ignoreUnknownSignals: true
        function onTrackTitleChanged() {
            _switchHoldTimer.restart();
            maybeFinishSwitch();
            root.updateLyrics();
        }
        function onTrackArtistChanged() { root.updateLyrics(); }
        function onTrackAlbumChanged() { root.updateLyrics(); }
    }

    Connections {
        target: LyricsService
        function onLinesChanged() {
            if (!root.useLocalPlayer)
                root.lyricIndex = LyricsService.indexForTime(root.activePlayer?.position || 0);
        }
    }

    Connections {
        target: root.localSession
        function onLyricIndexChanged() {
            if (root.useLocalPlayer)
                root.lyricIndex = root.localSession?.lyricIndex ?? -1;
        }
        function onLyricsLinesChanged() {
            if (root.useLocalPlayer)
                root.lyricIndex = root.localSession?.lyricIndex ?? -1;
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.visible && !!root.activePlayer
        onTriggered: root.lyricIndex = root.useLocalPlayer
                                      ? (root.localSession?.lyricIndex ?? -1)
                                      : LyricsService.indexForTime(root.activePlayer?.position || 0)
    }

    Connections {
        target: MprisController
        function onAvailablePlayersChanged() {
            if ((MprisController.availablePlayers?.length || 0) === 0)
                isSwitching = false;
            _switchHold = true;
            _switchHoldTimer.restart();
        }
    }

    function getAudioDeviceIcon(device) {
        if (!device || !device.name)
            return "speaker";

        const name = device.name.toLowerCase();

        if (name.includes("bluez") || name.includes("bluetooth"))
            return "headset";
        if (name.includes("hdmi"))
            return "tv";
        if (name.includes("usb"))
            return "headset";
        if (name.includes("analog") || name.includes("built-in"))
            return "speaker";

        return "speaker";
    }

    function getVolumeIcon() {
        if (!volumeAvailable)
            return "volume_off";

        const volume = currentVolume;

        if (usePlayerVolume) {
            if (volume === 0.0)
                return "music_off";
            return "music_note";
        }

        if (volume === 0.0)
            return "volume_off";
        if (volume <= 0.33)
            return "volume_down";
        if (volume <= 0.66)
            return "volume_up";
        return "volume_up";
    }

    function adjustVolume(step) {
        if (!volumeAvailable)
            return;
        const maxVol = usePlayerVolume ? 100 : AudioService.sinkMaxVolume;
        const current = Math.round(currentVolume * 100);
        const newVolume = Math.min(maxVol, Math.max(0, current + step));

        SessionData.suppressOSDTemporarily();
        if (useLocalPlayer) {
            localSession.setVolume(newVolume / 100);
        } else if (usePlayerVolume) {
            activePlayer.volume = newVolume / 100;
        } else if (AudioService.sink?.audio) {
            AudioService.sink.audio.volume = newVolume / 100;
        }
    }

    function triggerVolumeDropdown() {
        if (!volumeAvailable)
            return;
        if (volumeExpanded)
            return;
        hideDropdowns();
        volumeExpanded = true;
        const buttonsOnRight = !isRightEdge;
        const btnY = volumeButton.y + volumeButton.height / 2;
        const screenX = buttonsOnRight ? (popoutX + popoutWidth) : popoutX;
        const screenY = popoutY + contentOffsetY + btnY;
        showVolumeDropdown(Qt.point(screenX, screenY), targetScreen, buttonsOnRight, activePlayer, allPlayers);
    }

    function toggleMute() {
        if (!volumeAvailable)
            return;
        SessionData.suppressOSDTemporarily();
        if (currentVolume > 0) {
            volumeButton.previousVolume = currentVolume;
            if (useLocalPlayer) {
                localSession.setVolume(0);
            } else if (usePlayerVolume) {
                activePlayer.volume = 0;
            } else if (AudioService.sink?.audio) {
                AudioService.sink.audio.volume = 0;
            }
        } else {
            const restoreVolume = volumeButton.previousVolume > 0 ? volumeButton.previousVolume : 0.5;
            if (useLocalPlayer) {
                localSession.setVolume(restoreVolume);
            } else if (usePlayerVolume) {
                activePlayer.volume = restoreVolume;
            } else if (AudioService.sink?.audio) {
                AudioService.sink.audio.volume = restoreVolume;
            }
        }
    }

    function handleKeyEvent(event) {
        if (event.key === Qt.Key_Escape && lyricsPanelOpen) {
            lyricsPanelOpen = false;
            return true;
        }

        if (!activePlayer)
            return false;

        // 1. Number keys 0-9 to seek to 0%-90%
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            if (activePlayer.canSeek && stableLength > 0) {
                const ratio = (event.key - Qt.Key_0) * 0.1;
                const targetPosition = ratio * stableLength;
                activePlayer.position = Math.max(0.1, Math.min(targetPosition, stableLength * 0.99));
                return true;
            }
        }

        // 2. Left / Right arrows to seek backward / forward 5s
        if (event.key === Qt.Key_Left) {
            if (activePlayer.canSeek) {
                activePlayer.position = Math.max(0.1, activePlayer.position - 5);
                return true;
            }
        }
        if (event.key === Qt.Key_Right) {
            if (activePlayer.canSeek && stableLength > 0) {
                activePlayer.position = Math.max(0.1, Math.min(stableLength - 1, activePlayer.position + 5));
                return true;
            }
        }

        // 3. Up / Down arrows to adjust volume
        if (event.key === Qt.Key_Up) {
            adjustVolume(5);
            triggerVolumeDropdown();
            dropdownButtonExited();
            return true;
        }
        if (event.key === Qt.Key_Down) {
            adjustVolume(-5);
            triggerVolumeDropdown();
            dropdownButtonExited();
            return true;
        }

        // 4. Spacebar to play/pause
        if (event.key === Qt.Key_Space) {
            if (activePlayer.canTogglePlaying) {
                activePlayer.togglePlaying();
                return true;
            }
        }

        // 5. M key to toggle mute
        if (event.key === Qt.Key_M) {
            toggleMute();
            triggerVolumeDropdown();
            dropdownButtonExited();
            return true;
        }

        return false;
    }

    property bool isSeeking: false

    Timer {
        interval: 1000
        running: activePlayer?.playbackState === MprisPlaybackState.Playing && !isSeeking
        repeat: true
        onTriggered: activePlayer?.positionChanged()
    }

    Item {
        id: bgContainer
        anchors.fill: parent

        readonly property string curArt: root.useLocalPlayer ? (root.localSession?.artworkUrl ?? "") : TrackArtService.activeArtUrl
        // Two layers crossfade: new art loads into the hidden one and fades in once decoded.
        property bool _showA: true
        visible: layerA.ready || layerB.ready

        onCurArtChanged: syncArt()
        Component.onCompleted: syncArt()

        function syncArt() {
            if (curArt === "") {
                layerA.art = "";
                layerB.art = "";
                return;
            }
            const front = _showA ? layerA : layerB;
            const back = _showA ? layerB : layerA;
            if (front.art == curArt)
                return;
            if (back.art == curArt) {
                // Already decoded in the hidden layer; flip once ready (else promote() does).
                if (back.ready)
                    _showA = !_showA;
                return;
            }
            back.art = curArt;
        }

        // Flip to the hidden layer only when it holds the current art, ignoring stale
        // Ready re-emits (e.g. popout re-expose) that would otherwise ping-pong _showA.
        function promote(layer) {
            const back = _showA ? layerB : layerA;
            if (layer !== back)
                return;
            if (layer.art != curArt)
                return;
            _showA = (layer === layerA);
            root.maybeFinishSwitch();
        }

        BgBlurLayer {
            id: layerA
            front: bgContainer._showA
            onLoaded: bgContainer.promote(layerA)
        }

        BgBlurLayer {
            id: layerB
            front: !bgContainer._showA
            onLoaded: bgContainer.promote(layerB)
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: "#080607"
            opacity: 0.74
        }
    }

    component BgBlurLayer: ClippingRectangle {
        id: layer
        property alias art: layerImg.source
        readonly property bool ready: layerImg.status === Image.Ready && layerImg.source != ""
        property bool front: false
        signal loaded

        anchors.fill: parent
        radius: Theme.cornerRadius
        color: "transparent"
        antialiasing: true
        opacity: front ? 0.48 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 350
                easing.type: Easing.InOutQuad
            }
        }

        Image {
            id: layerImg
            anchors.centerIn: parent
            width: Math.max(parent.width, parent.height) * 1.1
            height: width
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
            onStatusChanged: {
                if (status === Image.Ready && source != "")
                    layer.loaded();
            }
        }

        MultiEffect {
            anchors.centerIn: parent
            width: layerImg.width
            height: layerImg.height
            source: layerImg
            blurEnabled: true
            blurMax: 64
            blur: 0.8
            saturation: -0.2
            brightness: -0.25
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingM
        visible: showNoPlayerNow

        KaskadIcon {
            name: "music_note"
            size: Theme.iconSize * 3
            color: Theme.surfaceTextSecondary
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: I18n.tr("No Active Players")
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.surfaceTextMedium
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Item {
        id: playerStage
        anchors.fill: parent
        visible: root.useLocalPlayer || (!_noneAvailable && !showNoPlayerNow)

        // When artwork is missing, Cava belongs to the card itself. Its strokes
        // begin on the real left, right and bottom card edges and grow inward.
        CavaEdgeVisualizer {
            anchors.fill: parent
            z: 0
            visible: !albumArt.hasArtwork
            activePlayer: root.useLocalPlayer ? null : root.activePlayer
            playingOverride: root.useLocalPlayer ? (root.localSession?.playing ?? false)
                                                  : root.activePlayer?.playbackState === MprisPlaybackState.Playing
            usePlayingOverride: true
            edgeInset: 3
            maxLength: Math.min(width, height) * 0.28
            opacity: 0.72
        }

        KaskadAlbumArt {
            id: albumArt
            z: 1
            x: 35
            y: 22
            width: 220
            height: 220
            albumSize: 154
            activePlayer: root.useLocalPlayer ? null : root.activePlayer
            artUrl: root.useLocalPlayer ? (root.localSession?.artworkUrl ?? "") : TrackArtService.activeArtUrl
            artKey: root.useLocalPlayer ? (root.localSession?.currentTrackPath ?? "") : TrackArtService.activeTrackKey
            usePlayingOverride: root.useLocalPlayer
            playingOverride: root.localSession?.playing ?? false
            showNoArtworkVisualizer: false
        }

        Rectangle {
            id: transportDeck
            z: 3
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 94
            anchors.rightMargin: 94
            anchors.bottomMargin: 18
            height: 56
            radius: 18
            color: Theme.withAlpha(Theme.surfaceContainer, 0.86)
            border.width: 1
            border.color: Theme.withAlpha(root.accent, 0.17)

            Rectangle {
                x: 148
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 11
                anchors.bottomMargin: 11
                width: 1
                color: Theme.withAlpha(Theme.surfaceText, 0.12)
            }
        }

        Row {
            id: playbackControls
            parent: transportDeck
            z: 4
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                width: 32
                height: 32
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: prevBtnArea.containsMouse ? Theme.withAlpha(Theme.surfaceContainerHigh, 0.92) : Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)

                KaskadIcon {
                    anchors.centerIn: parent
                    name: "skip_previous"
                    size: 22
                    color: Theme.surfaceText
                }

                MouseArea {
                    id: prevBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.useLocalPlayer ? root.localSession.previous() : MprisController.previousOrRewind()
                }
            }

            Rectangle {
                width: 44
                height: 44
                radius: 14
                anchors.verticalCenter: parent.verticalCenter
                color: root.accent

                KaskadIcon {
                    anchors.centerIn: parent
                    name: root.useLocalPlayer ? (root.localSession?.playing ? "pause" : "play_arrow")
                                              : (activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow")
                    size: 25
                    color: root.onAccent
                    weight: 600
                }

                StateLayer {
                    disabled: root.useLocalPlayer ? !(root.localSession?.tracks?.length > 0)
                                                  : (!root.activePlayer || !root.activePlayer.canTogglePlaying)
                    stateColor: root.onAccent
                    cornerRadius: parent.radius
                    onClicked: root.useLocalPlayer ? root.localSession.togglePlaying() : root.activePlayer.togglePlaying()
                }

                ElevationShadow {
                    anchors.fill: parent
                    z: -1
                    level: Theme.elevationLevel2
                    fallbackOffset: 4
                    targetRadius: parent.radius
                    targetColor: parent.color
                    shadowOpacity: 0.36
                    shadowEnabled: Theme.elevationEnabled
                }
            }

            Rectangle {
                width: 32
                height: 32
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: nextBtnArea.containsMouse ? Theme.withAlpha(Theme.surfaceContainerHigh, 0.92) : Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)

                KaskadIcon {
                    anchors.centerIn: parent
                    name: "skip_next"
                    size: 22
                    color: Theme.surfaceText
                }

                MouseArea {
                    id: nextBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.useLocalPlayer ? root.localSession.next() : MprisController.next()
                }
            }
        }

        Item {
            id: trackDetails
            z: 4
            x: albumArt.hasArtwork ? transportDeck.x + 166 : (root.width - 410) / 2
            y: 39
            width: albumArt.hasArtwork ? transportDeck.width - 166 - 16 : 410
            height: transportDeck.y - y - 10

            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            StyledText {
                id: trackTitle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                text: root.useLocalPlayer ? (root.localSession?.title || I18n.tr("Choose music"))
                                          : (MprisController.stableTitle || I18n.tr("Unknown Track"))
                font.pixelSize: 25
                font.weight: Font.Bold
                color: Theme.surfaceText
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                id: trackArtist
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: trackTitle.bottom
                anchors.topMargin: 4
                text: root.useLocalPlayer ? (root.localSession?.artist || root.localSession?.folderPath || I18n.tr("Local music"))
                                          : (MprisController.stableArtist || I18n.tr("Unknown Artist"))
                font.pixelSize: 12
                font.weight: Font.Medium
                color: root.accent
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Column {
                id: inlineLyrics
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: trackArtist.bottom
                anchors.topMargin: 17
                height: 165
                spacing: 0
                visible: !root.useLocalPlayer || root.localLyricsVisible

                Repeater {
                    model: 5

                    Item {
                        required property int index
                        readonly property int sourceIndex: root.lyricDisplayIndex + index - 2
                        readonly property bool currentLine: index === 2
                        readonly property var lyricLine: sourceIndex >= 0 && sourceIndex < root.displayedLyricsLines.length
                            ? root.displayedLyricsLines[sourceIndex]
                            : null
                        width: inlineLyrics.width
                        height: currentLine ? 53 : 28

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: parent.currentLine ? Math.min(32, parent.height - 12) : 18
                            radius: 2
                            color: root.accent
                            visible: parent.currentLine && !!parent.lyricLine
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: parent.currentLine && parent.lyricLine ? 10 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (parent.lyricLine)
                                    return parent.lyricLine.text || "♪";
                                if (!parent.currentLine)
                                    return "";
                                if (root.displayedLyricsLoading)
                                    return I18n.tr("Loading lyrics…");
                                return root.localizedLyricsError(root.displayedLyricsError);
                            }
                            font.pixelSize: parent.currentLine ? 19 : 13
                            font.weight: parent.currentLine ? Font.DemiBold : Font.Normal
                            color: parent.currentLine ? Theme.surfaceText : Theme.surfaceTextSecondary
                            opacity: parent.currentLine ? 1 : (parent.index === 1 || parent.index === 3 ? 0.56 : 0.36)
                            wrapMode: parent.currentLine ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                            elide: Text.ElideRight
                            maximumLineCount: parent.currentLine ? 2 : 1
                            lineHeight: parent.currentLine ? 0.96 : 1

                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !!parent.lyricLine && (root.useLocalPlayer || !!root.activePlayer?.canSeek)
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.useLocalPlayer)
                                    root.localSession.seek(parent.lyricLine.time + 0.01);
                                else
                                    root.activePlayer.position = parent.lyricLine.time + 0.01;
                            }
                        }
                    }
                }
            }

            ListView {
                id: localTrackList
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: trackArtist.bottom
                anchors.topMargin: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 0
                visible: root.useLocalPlayer && !root.localLyricsVisible
                clip: true
                spacing: 1
                model: root.localSession?.tracks ?? []
                currentIndex: root.localSession?.currentIndex ?? -1
                preferredHighlightBegin: height * 0.35
                preferredHighlightEnd: height * 0.58
                highlightRangeMode: ListView.ApplyRange
                highlightMoveDuration: 320
                highlightResizeDuration: 220
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 2600

                onCurrentIndexChanged: {
                    if (currentIndex >= 0)
                        positionViewAtIndex(currentIndex, ListView.Contain);
                }

                delegate: Rectangle {
                    required property string modelData
                    required property int index

                    readonly property bool currentTrack: index === root.localSession.currentIndex
                    readonly property int distanceFromCurrent: root.localSession.currentIndex < 0
                                                               ? 0 : Math.abs(index - root.localSession.currentIndex)

                    width: ListView.view.width - (currentTrack ? 0 : 10)
                    x: currentTrack ? 0 : 5
                    height: currentTrack ? 38 : 28
                    radius: currentTrack ? 12 : 9
                    opacity: currentTrack ? 1 : Math.max(0.68, 0.98 - distanceFromCurrent * 0.05)
                    color: currentTrack
                           ? Theme.withAlpha(root.accent, 0.22)
                           : (localTrackMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.09) : "transparent")
                    border.width: currentTrack ? 1 : 0
                    border.color: Theme.withAlpha(root.accent, 0.34)

                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on color { ColorAnimation { duration: 180 } }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: parent.currentTrack ? 20 : 0
                        radius: 2
                        color: root.accent
                        opacity: parent.currentTrack ? 1 : 0

                        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }

                    Item {
                        id: localTrackMarker
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 25
                        height: 18

                        StyledText {
                            anchors.centerIn: parent
                            text: (index + 1 < 10 ? "0" : "") + (index + 1)
                            font.pixelSize: parent.parent.currentTrack ? 11 : 10
                            font.weight: parent.parent.currentTrack ? Font.DemiBold : Font.Normal
                            color: parent.parent.currentTrack ? root.accent : Theme.surfaceTextSecondary
                            visible: !(parent.parent.currentTrack && root.localSession.playing)
                        }

                        CavaWaveform {
                            anchors.fill: parent
                            playing: parent.parent.currentTrack && root.localSession.playing
                            waveColor: root.accent
                            visible: playing
                        }
                    }

                    StyledText {
                        anchors.left: localTrackMarker.right
                        anchors.right: parent.right
                        anchors.leftMargin: 7
                        anchors.rightMargin: 11
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.localTrackTitle(modelData)
                        color: parent.currentTrack ? Theme.surfaceText : Theme.surfaceTextMedium
                        font.pixelSize: parent.currentTrack ? 12 : 11
                        font.weight: parent.currentTrack ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        maximumLineCount: 1

                        Behavior on color { ColorAnimation { duration: 180 } }
                    }

                    MouseArea {
                        id: localTrackMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.localSession.playIndex(index)
                    }
                }
            }

            KaskadSeekbar {
                id: seekbar
                parent: transportDeck
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 166
                anchors.rightMargin: 16
                anchors.top: parent.top
                anchors.topMargin: 5
                height: 20
                activePlayer: root.activePlayer
                localSession: root.useLocalPlayer ? root.localSession : null
                isSeeking: root.isSeeking
                onIsSeekingChanged: root.isSeeking = isSeeking
            }

            Item {
                id: timeLabels
                parent: transportDeck
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 166
                anchors.rightMargin: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                height: 16

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (root.useLocalPlayer) {
                            const localPos = Math.max(0, root.localSession?.position ?? 0);
                            const localMinutes = Math.floor(localPos / 60);
                            const localSeconds = Math.floor(localPos % 60);
                            return localMinutes + ":" + (localSeconds < 10 ? "0" : "") + localSeconds;
                        }
                        if (!activePlayer)
                            return "0:00";
                        const rawPos = Math.max(0, activePlayer.position || 0);
                        const pos = stableLength ? rawPos % Math.max(1, stableLength) : rawPos;
                        const minutes = Math.floor(pos / 60);
                        const seconds = Math.floor(pos % 60);
                        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
                    }
                    font.pixelSize: 10
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (root.useLocalPlayer) {
                            const localLength = root.localSession?.duration ?? 0;
                            if (localLength <= 0)
                                return "--:--";
                            const localMinutes = Math.floor(localLength / 60);
                            const localSeconds = Math.floor(localLength % 60);
                            return localMinutes + ":" + (localSeconds < 10 ? "0" : "") + localSeconds;
                        }
                        if (!activePlayer || stableLength <= 0)
                            return "--:--";
                        const minutes = Math.floor(stableLength / 60);
                        const seconds = Math.floor(stableLength % 60);
                        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
                    }
                    font.pixelSize: 10
                    color: Theme.surfaceVariantText
                }
            }
        }

        Rectangle {
            id: actionDeck
            readonly property int buttonCount: (sourceSwitchButton.visible ? 1 : 0)
                                                + 3
                                                + (root.useLocalPlayer ? 1 : 0)
            x: root.width - width - 10
            y: sourceSwitchButton.visible ? 67 : 87
            width: 50
            height: 14 + buttonCount * 42
            radius: 18
            z: 99
            color: Theme.withAlpha(Theme.surfaceContainer, 0.86)
            border.width: 1
            border.color: Theme.withAlpha(root.accent, 0.17)

            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: sourceSwitchButton
            width: 38
            height: 38
            radius: 14
            x: root.width - width - 16
            y: 73
            z: 100
            visible: root.localSession !== null && root.externalAvailable
            color: sourceSwitchArea.containsMouse
                   ? Theme.withAlpha(Theme.surfaceText, 0.10) : "transparent"
            border.width: 0

            KaskadIcon {
                anchors.centerIn: parent
                name: "swap_horiz"
                size: 19
                color: Theme.surfaceText
            }

            MouseArea {
                id: sourceSwitchArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleMediaSource()
            }
        }

        Rectangle {
            id: playerSelectorButton
            width: 38
            height: 38
            radius: 14
            x: root.width - width - 16
            y: sourceSwitchButton.visible ? 115 : 93
            z: 100
            visible: root.useLocalPlayer || (allPlayers?.length || 0) >= 1
            color: playersExpanded ? Theme.withAlpha(root.accent, 0.16)
                                  : (playerSelectorArea.containsMouse
                                     ? Theme.withAlpha(Theme.surfaceText, 0.10) : "transparent")
            border.width: 0

            KaskadIcon {
                anchors.centerIn: parent
                name: root.useLocalPlayer ? "folder_open" : "queue_music"
                size: 19
                color: Theme.surfaceText
            }

            MouseArea {
                id: playerSelectorArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.useLocalPlayer) {
                        localFolderDialog.open();
                        return;
                    }
                    if (playersExpanded) {
                        const players = (root.allPlayers || []).filter(p => p && !MprisController.isIdle(p));
                        if (players.length > 1) {
                            let currentIndex = players.indexOf(root.activePlayer);
                            MprisController.setActivePlayer(players[(currentIndex + 1) % players.length]);
                        }
                        return;
                    }
                    hideDropdowns();
                    playersExpanded = true;
                    const buttonsOnRight = !isRightEdge;
                    showPlayersDropdown(Qt.point(buttonsOnRight ? popoutX + popoutWidth : popoutX,
                                                  popoutY + contentOffsetY + playerSelectorButton.y + playerSelectorButton.height / 2),
                                        targetScreen, buttonsOnRight, activePlayer, allPlayers);
                }
                onEntered: {
                    if (root.useLocalPlayer)
                        return;
                    dropdownButtonEntered();
                    if (playersExpanded)
                        return;
                    hideDropdowns();
                    playersExpanded = true;
                    const buttonsOnRight = !isRightEdge;
                    showPlayersDropdown(Qt.point(buttonsOnRight ? popoutX + popoutWidth : popoutX,
                                                  popoutY + contentOffsetY + playerSelectorButton.y + playerSelectorButton.height / 2),
                                        targetScreen, buttonsOnRight, activePlayer, allPlayers);
                }
                onExited: {
                    if (playersExpanded)
                        dropdownButtonExited();
                }
            }
        }

        Rectangle {
            id: volumeButton
            width: 38
            height: 38
            radius: 14
            x: root.width - width - 16
            y: sourceSwitchButton.visible ? 157 : 135
            z: 101
            enabled: volumeAvailable
            color: volumeExpanded ? Theme.withAlpha(root.accent, 0.16)
                                  : (volumeButtonArea.containsMouse
                                     ? Theme.withAlpha(Theme.surfaceText, 0.10) : "transparent")
            border.width: 0

            property real previousVolume: 0.0

            KaskadIcon {
                anchors.centerIn: parent
                name: currentVolume <= 0 ? "volume_off" : (currentVolume <= 0.5 ? "volume_down" : "volume_up")
                size: 18
                color: volumeAvailable ? Theme.surfaceText : Theme.surfaceTextSecondary
            }

            MouseArea {
                id: volumeButtonArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    dropdownButtonEntered();
                    if (volumeExpanded)
                        return;
                    hideDropdowns();
                    volumeExpanded = true;
                    const buttonsOnRight = !isRightEdge;
                    showVolumeDropdown(Qt.point(buttonsOnRight ? popoutX + popoutWidth : popoutX,
                                                 popoutY + contentOffsetY + volumeButton.y + volumeButton.height / 2),
                                       targetScreen, buttonsOnRight, activePlayer, allPlayers);
                }
                onExited: {
                    if (volumeExpanded)
                        dropdownButtonExited();
                }
                onClicked: {
                    if (root.useLocalPlayer)
                        root.triggerVolumeDropdown();
                    else
                        root.toggleMute();
                }
                property real wheelAccum: 0
                onWheel: wheelEvent => {
                    wheelEvent.accepted = true;
                    wheelAccum += wheelEvent.angleDelta.y;
                    const notches = wheelAccum > 0 ? Math.floor(wheelAccum / 120) : Math.ceil(wheelAccum / 120);
                    if (notches === 0)
                        return;
                    wheelAccum -= notches * 120;
                    root.adjustVolume(notches * AudioService.wheelVolumeStep);
                }
            }
        }

        Rectangle {
            id: audioDevicesButton
            width: 38
            height: 38
            radius: 14
            x: root.width - width - 16
            y: sourceSwitchButton.visible ? 199 : 177
            z: 100
            color: devicesExpanded ? Theme.withAlpha(root.accent, 0.16)
                                   : (audioDevicesArea.containsMouse
                                      ? Theme.withAlpha(Theme.surfaceText, 0.10) : "transparent")
            border.width: 0

            KaskadIcon {
                anchors.centerIn: parent
                name: "speaker"
                size: 18
                color: Theme.surfaceText
            }

            MouseArea {
                id: audioDevicesArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton)
                        mouse.accepted = true;
                }
                onWheel: wheelEvent => {
                    if (wheelEvent.angleDelta.y !== 0) {
                        AudioService.cycleAudioOutputDirection(wheelEvent.angleDelta.y < 0);
                        wheelEvent.accepted = true;
                    }
                }
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        if (AudioService.sink?.audio) {
                            SessionData.suppressOSDTemporarily();
                            AudioService.sink.audio.muted = !AudioService.sink.audio.muted;
                        }
                        return;
                    }
                    if (devicesExpanded) {
                        const sinks = AudioService.getAvailableSinks();
                        if (sinks && sinks.length > 1) {
                            let currentIndex = -1;
                            for (let i = 0; i < sinks.length; i++) {
                                if (sinks[i]?.name === AudioService.sink?.name) {
                                    currentIndex = i;
                                    break;
                                }
                            }
                            AudioService.setSink(sinks[(currentIndex + 1) % sinks.length]);
                        }
                        return;
                    }
                    hideDropdowns();
                    devicesExpanded = true;
                    const buttonsOnRight = !isRightEdge;
                    showAudioDevicesDropdown(Qt.point(buttonsOnRight ? popoutX + popoutWidth : popoutX,
                                                       popoutY + contentOffsetY + audioDevicesButton.y + audioDevicesButton.height / 2),
                                             targetScreen, buttonsOnRight);
                }
                onEntered: {
                    dropdownButtonEntered();
                    if (devicesExpanded)
                        return;
                    hideDropdowns();
                    devicesExpanded = true;
                    const buttonsOnRight = !isRightEdge;
                    showAudioDevicesDropdown(Qt.point(buttonsOnRight ? popoutX + popoutWidth : popoutX,
                                                       popoutY + contentOffsetY + audioDevicesButton.y + audioDevicesButton.height / 2),
                                             targetScreen, buttonsOnRight);
                }
                onExited: {
                    if (devicesExpanded)
                        dropdownButtonExited();
                }
            }
        }

        Rectangle {
            width: 38
            height: 38
            radius: 14
            x: root.width - width - 16
            y: sourceSwitchButton.visible ? 241 : 219
            z: 100
            visible: root.useLocalPlayer
            color: root.localLyricsVisible ? Theme.withAlpha(root.accent, 0.16)
                                           : (localLyricsArea.containsMouse
                                              ? Theme.withAlpha(Theme.surfaceText, 0.10) : "transparent")
            border.width: 0

            KaskadIcon {
                anchors.centerIn: parent
                name: root.localLyricsVisible ? "queue_music" : "lyrics"
                size: 19
                color: root.localLyricsVisible ? root.accent : Theme.surfaceText
            }

            MouseArea {
                id: localLyricsArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.localLyricsVisible = !root.localLyricsVisible
            }
        }
    }

}

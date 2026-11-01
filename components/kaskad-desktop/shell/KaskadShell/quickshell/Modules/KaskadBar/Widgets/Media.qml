import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Modules.KaskadBar.Components
import qs.Services
import qs.Widgets

BasePill {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool localPriority: !!localSession?.hasCurrentTrack
    readonly property bool playerAvailable: localPriority || activePlayer !== null
    readonly property bool _hoverPreview: MprisController.isFirefoxYoutubeHoverPreview(activePlayer)
    readonly property bool _isPlaying: localPriority ? (localSession?.playing ?? false)
                                                      : !!activePlayer && activePlayer.playbackState === 1 && !_hoverPreview

    readonly property bool __isChromeBrowser: {
        if (!activePlayer?.identity)
            return false;
        const id = activePlayer.identity.toLowerCase();
        return id.includes("chrome") || id.includes("chromium");
    }
    readonly property bool usePlayerVolume: localPriority || (activePlayer && activePlayer.volumeSupported && !__isChromeBrowser)
    property bool compactMode: false
    property var widgetData: null
    readonly property bool adaptiveWidthEnabled: SettingsData.mediaAdaptiveWidthEnabled
    readonly property int maxTextWidth: {
        const size = widgetData?.mediaSize !== undefined ? widgetData.mediaSize : SettingsData.mediaSize;
        switch (size) {
        case 0:
            return 0;
        case 2:
            return 180;
        case 3:
            return 240;
        default:
            return 120;
        }
    }
    readonly property int currentContentWidth: {
        if (isVerticalOrientation) {
            return widgetThickness - horizontalPadding * 2;
        }
        return 0;
    }
    readonly property int currentContentHeight: {
        if (!isVerticalOrientation) {
            return widgetThickness - horizontalPadding * 2;
        }
        const audioVizHeight = 20;
        const playButtonHeight = 24;
        return audioVizHeight + Theme.spacingXS + playButtonHeight;
    }

    property real scrollAccumulatorY: 0
    property real touchpadThreshold: 100
    readonly property string localInstanceId: root.widgetData?.instanceId ?? ""
    readonly property var localSession: root.widgetData && localInstanceId
                                        ? LocalMediaRegistry.sessionFor(localInstanceId, root.widgetData)
                                        : null

    function toggleCurrent() {
        if (localPriority)
            localSession.togglePlaying();
        else if (activePlayer)
            activePlayer.togglePlaying();
        else
            LocalMediaCoordinator.activate(localSession);
    }

    function prepareDashboard() {
        if (localSession)
            LocalMediaCoordinator.activate(localSession);
    }

    function previousCurrent() {
        if (localPriority)
            localSession.previous();
        else
            MprisController.previousOrRewind();
    }

    function nextCurrent() {
        if (localPriority)
            localSession.next();
        else
            MprisController.next();
    }

    Connections {
        target: root.localSession
        function onConfigurationChanged(updates) {
            if (root.localInstanceId)
                SettingsData.updateBarWidgetInstance(root.localInstanceId, updates);
        }
    }

    onWheel: function (wheelEvent) {
        if (SettingsData.audioScrollMode === "nothing")
            return;

        if (SettingsData.audioScrollMode === "volume") {
            if (!usePlayerVolume)
                return;

            wheelEvent.accepted = true;

            const deltaY = wheelEvent.angleDelta.y;
            const isMouseWheelY = Math.abs(deltaY) >= 120 && (Math.abs(deltaY) % 120) === 0;

            const currentVolume = (localPriority ? localSession.volume : activePlayer.volume) * 100;

            let newVolume = currentVolume;
            if (isMouseWheelY) {
                if (deltaY > 0) {
                    newVolume = Math.min(100, currentVolume + SettingsData.audioWheelScrollAmount);
                } else if (deltaY < 0) {
                    newVolume = Math.max(0, currentVolume - SettingsData.audioWheelScrollAmount);
                }
            } else {
                scrollAccumulatorY += deltaY;
                if (Math.abs(scrollAccumulatorY) >= touchpadThreshold) {
                    if (scrollAccumulatorY > 0) {
                        newVolume = Math.min(100, currentVolume + 1);
                    } else {
                        newVolume = Math.max(0, currentVolume - 1);
                    }
                    scrollAccumulatorY = 0;
                }
            }

            if (localPriority)
                localSession.setVolume(newVolume / 100);
            else
                activePlayer.volume = newVolume / 100;
        } else if (SettingsData.audioScrollMode === "song") {
            if (!root.playerAvailable)
                return;

            wheelEvent.accepted = true;

            const deltaY = wheelEvent.angleDelta.y;
            const isMouseWheelY = Math.abs(deltaY) >= 120 && (Math.abs(deltaY) % 120) === 0;

            if (isMouseWheelY) {
                if (deltaY > 0) {
                    previousCurrent();
                } else {
                    nextCurrent();
                }
            } else {
                scrollAccumulatorY += deltaY;
                if (Math.abs(scrollAccumulatorY) >= touchpadThreshold) {
                    if (scrollAccumulatorY > 0) {
                        previousCurrent();
                    } else {
                        nextCurrent();
                    }
                    scrollAccumulatorY = 0;
                }
            }
        }
    }

    content: Component {
        Item {
            id: contentRoot
            readonly property real measuredTextWidth: {
                if (root.maxTextWidth <= 0 || !textContainer.visible)
                    return 0;
                // Preserve the fixed-width text slot even if metadata is briefly empty.
                if (!root.adaptiveWidthEnabled)
                    return root.maxTextWidth;
                if (textContainer.displayText.length === 0)
                    return 0;
                const rawWidth = mediaText.contentWidth;
                if (!isFinite(rawWidth) || rawWidth <= 0)
                    return 0;
                return Math.min(root.maxTextWidth, Math.ceil(rawWidth));
            }
            readonly property int horizontalContentWidth: {
                const controlsWidth = root.playerAvailable ? 20 + Theme.spacingXS + 24 + Theme.spacingXS + 20 : 0;
                const audioVizWidth = 20;
                const baseWidth = audioVizWidth + (controlsWidth > 0 ? Theme.spacingXS + controlsWidth : 0);
                return baseWidth + (measuredTextWidth > 0 ? measuredTextWidth + Theme.spacingXS : 0);
            }

            implicitWidth: root.isVerticalOrientation ? root.currentContentWidth : horizontalContentWidth
            implicitHeight: root.currentContentHeight
            opacity: 1

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }

            Behavior on implicitWidth {
                NumberAnimation {
                    duration: Theme.mediumDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
                }
            }

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }

            Column {
                id: verticalLayout
                visible: root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                Item {
                    width: 20
                    height: 20
                    anchors.horizontalCenter: parent.horizontalCenter

                    AudioVisualization {
                        anchors.fill: parent
                        forcePlaying: root.localPriority && (root.localSession?.playing ?? false)
                        visible: root.playerAvailable && CavaService.cavaAvailable && SettingsData.audioVisualizerEnabled
                    }

                    KaskadIcon {
                        anchors.fill: parent
                        name: "music_note"
                        size: 20
                        color: Theme.primary
                        visible: !root.playerAvailable || !CavaService.cavaAvailable || !SettingsData.audioVisualizerEnabled
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            root.triggerRipple(this, mouse.x, mouse.y);
                        }
                        onClicked: root.clicked()
                    }
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root._isPlaying ? Theme.primary : Theme.primaryHover
                    visible: root.playerAvailable
                    opacity: root.playerAvailable ? 1 : 0.3

                    KaskadIcon {
                        anchors.centerIn: parent
                        name: root._isPlaying ? "pause" : "play_arrow"
                        size: 14
                        color: root._isPlaying ? Theme.background : Theme.primary
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.playerAvailable
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onClicked: mouse => {
                            if (!root.playerAvailable)
                                return;
                            if (mouse.button === Qt.LeftButton) {
                                root.toggleCurrent();
                            } else if (mouse.button === Qt.MiddleButton) {
                                root.previousCurrent();
                            } else if (mouse.button === Qt.RightButton) {
                                root.nextCurrent();
                            }
                        }
                    }
                }
            }

            Row {
                id: mediaRow
                visible: !root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                Row {
                    id: mediaInfo
                    spacing: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter

                    Item {
                        width: 20
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter

                        AudioVisualization {
                            anchors.fill: parent
                            forcePlaying: root.localPriority && (root.localSession?.playing ?? false)
                            visible: root.playerAvailable && CavaService.cavaAvailable && SettingsData.audioVisualizerEnabled
                        }

                        KaskadIcon {
                            anchors.fill: parent
                            name: "music_note"
                            size: 20
                            color: Theme.primary
                            visible: !root.playerAvailable || !CavaService.cavaAvailable || !SettingsData.audioVisualizerEnabled
                        }
                    }

                    Rectangle {
                        id: textContainer
                        readonly property string cachedIdentity: activePlayer ? (activePlayer.identity || "") : ""
                        readonly property string lowerIdentity: cachedIdentity.toLowerCase()
                        readonly property bool isWebMedia: lowerIdentity.includes("firefox") || lowerIdentity.includes("chrome") || lowerIdentity.includes("chromium") || lowerIdentity.includes("edge") || lowerIdentity.includes("safari")

                        property string displayText: {
                            if (root.localPriority) {
                                const localSubtitle = localSession.artist || I18n.tr("Local music");
                                return localSession.title + " • " + localSubtitle;
                            }
                            if (!activePlayer || !MprisController.stableTitle)
                                return I18n.tr("Choose music");
                            const title = MprisController.stableTitle;
                            const subtitle = isWebMedia ? (MprisController.stableArtist || cachedIdentity) : MprisController.stableArtist;
                            return subtitle.length > 0 ? title + " • " + subtitle : title;
                        }

                        anchors.verticalCenter: parent.verticalCenter
                        width: contentRoot.measuredTextWidth
                        height: root.widgetThickness
                        visible: {
                            const size = widgetData?.mediaSize !== undefined ? widgetData.mediaSize : SettingsData.mediaSize;
                            return size > 0;
                        }
                        clip: true
                        color: "transparent"

                        Behavior on width {
                            NumberAnimation {
                                duration: Theme.mediumDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
                            }
                        }

                        Item {
                            id: textClip
                            anchors.fill: parent
                            clip: true

                            StyledText {
                                id: mediaText
                                readonly property bool onScreen: Window.window?.visible ?? false
                                property bool needsScrolling: implicitWidth > textContainer.width && SettingsData.scrollTitleEnabled
                                readonly property bool scrollActive: needsScrolling && textContainer.visible && onScreen && root._isPlaying
                                readonly property real maxScrollOffset: Math.max(0, implicitWidth - textContainer.width + 5)
                                property real scrollOffset: 0
                                property int scrollDirection: 1
                                property real scrollHoldMs: 2000
                                property real textShift: 0

                                function resetScroll() {
                                    scrollOffset = 0;
                                    scrollDirection = 1;
                                    scrollHoldMs = 2000;
                                }

                                function stepScroll(deltaMs) {
                                    if (scrollHoldMs > 0) {
                                        scrollHoldMs -= deltaMs;
                                        return;
                                    }
                                    const next = scrollOffset + scrollDirection * deltaMs / 60;
                                    if (next >= maxScrollOffset) {
                                        scrollOffset = maxScrollOffset;
                                        scrollDirection = -1;
                                        scrollHoldMs = 2000;
                                        return;
                                    }
                                    if (next <= 0) {
                                        scrollOffset = 0;
                                        scrollDirection = 1;
                                        scrollHoldMs = 2000;
                                        return;
                                    }
                                    scrollOffset = next;
                                }

                                onScrollActiveChanged: {
                                    if (!scrollActive)
                                        resetScroll();
                                }

                                anchors.verticalCenter: parent.verticalCenter
                                text: textContainer.displayText
                                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                                color: Theme.widgetTextColor
                                wrapMode: Text.NoWrap
                                x: Math.round((needsScrolling ? -scrollOffset : 0) + textShift)
                                opacity: 1

                                onTextChanged: {
                                    resetScroll();
                                    textShift = 0;
                                    textChangeAnimation.restart();
                                }

                                // Timer stepping, not NumberAnimation — a running animation commits frames every vsync (#2863).
                                // When cava frames are already driving renders, scroll steps ride those ticks instead —
                                // two unsynchronized tick sources nearly double the surface commit rate (#2863).
                                Timer {
                                    id: scrollTimer

                                    interval: 60
                                    repeat: true
                                    running: mediaText.scrollActive
                                    onTriggered: {
                                        if (cavaTickWatch.running)
                                            return;
                                        mediaText.stepScroll(60);
                                    }
                                }

                                Timer {
                                    id: cavaTickWatch
                                    interval: 150
                                }

                                Connections {
                                    target: CavaService
                                    enabled: mediaText.scrollActive && SettingsData.audioVisualizerEnabled && CavaService.cavaAvailable
                                    function onValuesChanged() {
                                        cavaTickWatch.restart();
                                        mediaText.stepScroll(40);
                                    }
                                }

                                SequentialAnimation {
                                    id: textChangeAnimation

                                    ParallelAnimation {
                                        NumberAnimation {
                                            target: mediaText
                                            property: "opacity"
                                            from: 0.7
                                            to: 1
                                            duration: Theme.shortDuration
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
                                        }

                                        NumberAnimation {
                                            target: mediaText
                                            property: "textShift"
                                            from: 4
                                            to: 0
                                            duration: Theme.shortDuration
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.playerAvailable
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => {
                                root.triggerRipple(this, mouse.x, mouse.y);
                                if (root.popoutTarget && root.popoutTarget.setTriggerPosition) {
                                    const globalPos = mapToItem(null, 0, 0);
                                    const currentScreen = root.parentScreen || Screen;
                                    const barPosition = root.axis?.edge === "left" ? 2 : (root.axis?.edge === "right" ? 3 : (root.axis?.edge === "top" ? 0 : 1));
                                    const pos = SettingsData.getPopupTriggerPosition(globalPos, currentScreen, root.barThickness, root.width, root.barSpacing, barPosition, root.barConfig);
                                    root.popoutTarget.setTriggerPosition(pos.x, pos.y, pos.width, root.section, currentScreen, barPosition, root.barThickness, root.barSpacing, root.barConfig);
                                }
                                root.clicked();
                            }
                        }
                    }
                }

                Row {
                    spacing: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.playerAvailable

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: prevArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0)
                        visible: root.playerAvailable
                        opacity: root.localPriority ? (localSession.canGoPrevious ? 1 : 0.3)
                                                    : ((activePlayer && activePlayer.canGoPrevious) ? 1 : 0.3)

                        KaskadIcon {
                            anchors.centerIn: parent
                            name: "skip_previous"
                            size: 12
                            color: Theme.widgetTextColor
                        }

                        MouseArea {
                            id: prevArea
                            anchors.fill: parent
                            enabled: root.playerAvailable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.previousCurrent()
                        }
                    }

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: root._isPlaying ? Theme.primary : Theme.primaryHover
                        visible: root.playerAvailable
                        opacity: root.playerAvailable ? 1 : 0.3

                        KaskadIcon {
                            anchors.centerIn: parent
                            name: root._isPlaying ? "pause" : "play_arrow"
                            size: 14
                            color: root._isPlaying ? Theme.background : Theme.primary
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.playerAvailable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.toggleCurrent();
                            }
                        }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: nextArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0)
                        visible: playerAvailable
                        opacity: root.localPriority ? (localSession.canGoNext ? 1 : 0.3)
                                                    : ((activePlayer && activePlayer.canGoNext) ? 1 : 0.3)

                        KaskadIcon {
                            anchors.centerIn: parent
                            name: "skip_next"
                            size: 12
                            color: Theme.widgetTextColor
                        }

                        MouseArea {
                            id: nextArea
                            anchors.fill: parent
                            enabled: root.playerAvailable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.nextCurrent();
                            }
                        }
                    }
                }
            }
        }
    }
}

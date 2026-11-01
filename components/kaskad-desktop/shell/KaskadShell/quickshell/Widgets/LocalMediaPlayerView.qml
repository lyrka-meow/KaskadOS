pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import qs.Common
import qs.Widgets

Item {
    id: root

    required property var session
    property bool compact: false
    property bool showFolderButton: true
    property bool showLyrics: false

    signal requestClose

    function displayName(path) {
        if (!path)
            return "";
        const slash = path.lastIndexOf("/");
        return path.substring(slash + 1).replace(/\.[^.]+$/, "");
    }

    function formatTime(seconds) {
        const safe = Math.max(0, Math.floor(seconds || 0));
        const minutes = Math.floor(safe / 60);
        const rest = safe % 60;
        return minutes + ":" + (rest < 10 ? "0" : "") + rest;
    }

    FolderDialog {
        id: folderDialog
        title: I18n.tr("Choose a music folder")
        currentFolder: root.session.folderPath ? Paths.toFileUrl(root.session.folderPath) : Paths.home
        onAccepted: root.session.setFolder(selectedFolder)
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingM

        Row {
            width: parent.width
            spacing: Theme.spacingS

            Rectangle {
                width: 52
                height: 52
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                clip: true

                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: root.session.artworkUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }

                KaskadIcon {
                    anchors.centerIn: parent
                    name: "album"
                    size: Theme.iconSizeLarge
                    color: Theme.surfaceVariantText
                    visible: coverImage.status !== Image.Ready
                }
            }

            Column {
                width: Math.max(0, parent.width - 52 - folderButton.width - closeButton.width - parent.spacing * 3)
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    width: parent.width
                    text: root.session.hasCurrentTrack ? root.session.title : I18n.tr("KaskadOS Audio Player")
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: root.session.hasCurrentTrack
                          ? (root.session.artist || root.displayName(root.session.currentTrackPath))
                          : (root.session.folderPath || I18n.tr("Choose a folder and then select a track"))
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideMiddle
                }
            }

            KaskadActionButton {
                id: folderButton
                visible: root.showFolderButton
                iconName: "folder_open"
                tooltipText: I18n.tr("Choose music folder")
                onClicked: folderDialog.open()
            }

            KaskadActionButton {
                id: closeButton
                visible: !root.compact
                iconName: "close"
                tooltipText: I18n.tr("Close")
                onClicked: root.requestClose()
            }
        }

        Rectangle {
            width: parent.width
            height: 6
            radius: 3
            color: Theme.surfaceVariant
            visible: root.session.hasCurrentTrack

            Rectangle {
                width: parent.width * (root.session.duration > 0 ? root.session.position / root.session.duration : 0)
                height: parent.height
                radius: parent.radius
                color: Theme.primary
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.session.duration > 0
                onClicked: mouse => root.session.seek(root.session.duration * mouse.x / width)
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                width: 42
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatTime(root.session.position)
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Item {
                width: Math.max(0, (parent.width - 42 * 2 - controls.width - parent.spacing * 4) / 2)
                height: 1
            }

            Row {
                id: controls
                spacing: Theme.spacingS

                KaskadActionButton {
                    iconName: "skip_previous"
                    enabled: root.session.canGoPrevious
                    tooltipText: I18n.tr("Previous")
                    onClicked: root.session.previous()
                }

                KaskadActionButton {
                    iconName: root.session.playing ? "pause" : "play_arrow"
                    enabled: root.session.tracks.length > 0
                    tooltipText: root.session.playing ? I18n.tr("Pause") : I18n.tr("Play")
                    onClicked: root.session.togglePlaying()
                }

                KaskadActionButton {
                    iconName: "skip_next"
                    enabled: root.session.canGoNext
                    tooltipText: I18n.tr("Next")
                    onClicked: root.session.next()
                }
            }

            Item {
                width: Math.max(0, (parent.width - 42 * 2 - controls.width - parent.spacing * 4) / 2)
                height: 1
            }

            StyledText {
                width: 42
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: root.formatTime(root.session.duration)
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            KaskadActionButton {
                iconName: root.session.shuffle ? "shuffle_on" : "shuffle"
                iconColor: root.session.shuffle ? Theme.primary : Theme.surfaceText
                tooltipText: I18n.tr("Shuffle")
                onClicked: root.session.setShuffle(!root.session.shuffle)
            }

            KaskadActionButton {
                iconName: root.session.repeatMode === "one" ? "repeat_one" : "repeat"
                iconColor: root.session.repeatMode !== "none" ? Theme.primary : Theme.surfaceText
                tooltipText: root.session.repeatMode === "none" ? I18n.tr("Do not repeat")
                           : root.session.repeatMode === "all" ? I18n.tr("Repeat folder")
                           : I18n.tr("Repeat track")
                onClicked: {
                    if (root.session.repeatMode === "none")
                        root.session.setRepeatMode("all");
                    else if (root.session.repeatMode === "all")
                        root.session.setRepeatMode("one");
                    else
                        root.session.setRepeatMode("none");
                }
            }

            KaskadActionButton {
                iconName: root.session.recursive ? "account_tree" : "folder"
                iconColor: root.session.recursive ? Theme.primary : Theme.surfaceText
                tooltipText: I18n.tr("Include subfolders")
                onClicked: root.session.setRecursive(!root.session.recursive)
            }

            KaskadActionButton {
                iconName: "lyrics"
                iconColor: root.showLyrics ? Theme.primary : Theme.surfaceText
                enabled: root.session.hasCurrentTrack
                tooltipText: I18n.tr("Lyrics")
                onClicked: root.showLyrics = !root.showLyrics
            }

            Item { width: Math.max(0, parent.width - 292); height: 1 }

            KaskadActionButton {
                iconName: root.session.volume <= 0 ? "volume_off" : "volume_up"
                tooltipText: I18n.tr("Volume") + " " + Math.round(root.session.volume * 100) + "%"
                onClicked: root.session.setVolume(root.session.volume > 0 ? 0 : 0.8)
            }

            KaskadSlider {
                width: 100
                height: 32
                minimum: 0
                maximum: 100
                showValue: false
                valueOverride: Math.round(root.session.volume * 100)
                value: Math.round(root.session.volume * 100)
                onSliderValueChanged: newValue => root.session.setVolume(newValue / 100)
            }
        }

        Rectangle {
            width: parent.width
            height: Math.max(0, parent.height - y)
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.color: Theme.outline
            border.width: 1

            KaskadSpinner {
                anchors.centerIn: parent
                visible: root.session.scanning
            }

            Column {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - Theme.spacingXL * 2)
                spacing: Theme.spacingS
                visible: !root.session.scanning && root.session.tracks.length === 0

                KaskadIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: root.session.errorString ? "error" : "library_music"
                    size: Theme.iconSizeLarge
                    color: root.session.errorString ? Theme.error : Theme.surfaceVariantText
                }

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.session.errorString || (root.session.folderPath
                          ? I18n.tr("No supported audio files were found")
                          : I18n.tr("Choose a folder containing MP3, FLAC, OGG, OPUS, WAV, M4A, AAC, or WMA files"))
                    color: Theme.surfaceVariantText
                }
            }

            ListView {
                id: trackList
                anchors.fill: parent
                anchors.margins: Theme.spacingXS
                clip: true
                spacing: 2
                model: root.session.tracks
                visible: !root.showLyrics && !root.session.scanning && root.session.tracks.length > 0

                delegate: Rectangle {
                    required property string modelData
                    required property int index

                    width: trackList.width
                    height: 44
                    radius: Theme.cornerRadius
                    color: index === root.session.currentIndex ? Theme.primaryHover
                         : trackMouse.containsMouse ? Theme.surfaceHover : "transparent"

                    KaskadIcon {
                        id: stateIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        name: index === root.session.currentIndex && root.session.playing ? "graphic_eq" : "music_note"
                        size: Theme.iconSize
                        color: index === root.session.currentIndex ? Theme.primary : Theme.surfaceVariantText
                        visible: !(index === root.session.currentIndex && root.session.playing)
                    }

                    CavaWaveform {
                        anchors.centerIn: stateIcon
                        width: Theme.iconSize
                        height: Theme.iconSize
                        playing: index === root.session.currentIndex && root.session.playing
                        visible: playing
                    }

                    StyledText {
                        anchors.left: stateIcon.right
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.displayName(modelData)
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: trackMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.session.playIndex(index)
                    }
                }
            }


            Flickable {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                visible: root.showLyrics
                clip: true
                contentWidth: width
                contentHeight: lyricsColumn.height

                Column {
                    id: lyricsColumn
                    width: parent.width
                    spacing: Theme.spacingM

                    KaskadSpinner {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.session.lyricsLoading
                    }

                    StyledText {
                        width: parent.width
                        text: root.session.lyricsText || root.session.lyricsError || I18n.tr("Lyrics will be loaded from the internet when available")
                        color: root.session.lyricsText ? Theme.surfaceText : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        lineHeight: 1.25
                    }
                }
            }
        }
    }
}

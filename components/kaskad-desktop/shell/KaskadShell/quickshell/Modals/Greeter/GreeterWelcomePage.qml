import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root
    property var greeterRoot: null
    property var previewProfile: null

    FileDialog {
        id: importDialog
        title: I18n.tr("Import KaskadOS layout")
        fileMode: FileDialog.OpenFile
        nameFilters: [I18n.tr("KaskadOS layouts (*.kaskadlayout)"), I18n.tr("All files (*)")]
        currentFolder: Paths.home
        onAccepted: {
            LayoutEditService.begin("desktop", "");
            LayoutProfileService.loadPreview(selectedFile);
        }
    }

    Connections {
        target: LayoutProfileService
        function onPreviewReady(profile) { root.previewProfile = profile; }
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(650, parent.width - Theme.spacingXL * 2)
        spacing: Theme.spacingL

        Image {
            width: 72
            height: 80
            anchors.horizontalCenter: parent.horizontalCenter
            fillMode: Image.PreserveAspectFit
            source: "file://" + Theme.shellDir + "/assets/kaskados-logo.png"
            layer.enabled: true
            layer.effect: MultiEffect { saturation: 0; colorization: 1; colorizationColor: Theme.primary }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingXS
            StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: I18n.tr("Set up KaskadOS your way"); color: Theme.surfaceText; font.pixelSize: Theme.fontSizeXLarge + 3; font.weight: Font.Bold }
            StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: I18n.tr("Start immediately, bring a friend's layout, or take a short tour."); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeMedium }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingM

            ChoiceCard {
                width: (parent.width - Theme.spacingM * 2) / 3
                iconName: "rocket_launch"
                title: I18n.tr("Standard layout")
                description: I18n.tr("Use the balanced KaskadOS defaults and start now")
                primary: true
                onActivated: root.greeterRoot?.finish()
            }
            ChoiceCard {
                width: (parent.width - Theme.spacingM * 2) / 3
                iconName: "file_open"
                title: I18n.tr("Import layout")
                description: I18n.tr("Open a .kaskadlayout file from disk, USB or Downloads")
                onActivated: importDialog.open()
            }
            ChoiceCard {
                width: (parent.width - Theme.spacingM * 2) / 3
                iconName: "school"
                title: I18n.tr("2-minute tour")
                description: I18n.tr("See the panel, launcher, apps, quick settings and layout mode")
                onActivated: root.greeterRoot?.nextPage()
            }
        }

        Rectangle {
            width: parent.width
            height: root.previewProfile ? 118 : 0
            visible: height > 0
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Theme.primary

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS
                StyledText { text: root.previewProfile?.name || ""; color: Theme.surfaceText; font.weight: Font.Bold }
                StyledText { text: root.previewProfile ? I18n.tr("%1 panels · %2 widgets · private data excluded").arg(root.previewProfile.layout.bars.length).arg(root.previewProfile.layout.desktopWidgets.length) : ""; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                Row {
                    spacing: Theme.spacingS
                    KaskadButton { text: I18n.tr("Cancel"); onClicked: { root.previewProfile = null; LayoutEditService.cancel(); } }
                    KaskadButton { text: I18n.tr("Apply and continue"); iconName: "check"; onClicked: { if (LayoutProfileService.applyPending()) { LayoutEditService.commit(); root.greeterRoot?.finish(); } } }
                }
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: LayoutProfileService.error || I18n.tr("You can skip the tour and reopen it later from Settings.")
            color: LayoutProfileService.error ? Theme.error : Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    component ChoiceCard: Rectangle {
        id: card
        property string iconName: ""
        property string title: ""
        property string description: ""
        property bool primary: false
        signal activated
        height: 190
        radius: Theme.cornerRadius * 1.25
        color: area.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        border.width: primary ? 2 : 1
        border.color: primary ? Theme.primary : Theme.outline
        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM
            KaskadIcon { name: card.iconName; size: 34; color: card.primary ? Theme.primary : Theme.surfaceText }
            StyledText { width: parent.width; text: card.title; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Bold; wrapMode: Text.WordWrap }
            StyledText { width: parent.width; text: card.description; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap }
        }
        MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.activated() }
    }
}

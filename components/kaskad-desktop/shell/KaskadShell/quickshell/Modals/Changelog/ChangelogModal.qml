import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

FloatingWindow {
    id: root

    property bool disablePopupTransparency: true
    readonly property int modalWidth: 680
    readonly property int modalHeight: screen ? Math.min(720, screen.height - 80) : 720

    signal changelogDismissed

    function show() {
        visible = true;
    }

    objectName: "changelogModal"
    title: "Что нового"
    minimumSize: Qt.size(modalWidth, modalHeight)
    maximumSize: Qt.size(modalWidth, modalHeight)
    implicitWidth: modalWidth
    implicitHeight: modalHeight
    color: Theme.surfaceContainer
    visible: false

    onClosed: visible = false

    FocusScope {
        id: contentFocusScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: event => {
            root.dismiss();
            event.accepted = true;
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.dismiss();
                event.accepted = true;
                break;
            }
        }

        KaskadFlickable {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: footerRow.top
            anchors.topMargin: Theme.spacingS
            clip: true
            contentHeight: mainColumn.height + Theme.spacingL * 2
            contentWidth: width

            ChangelogContent {
                id: mainColumn
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(600, parent.width - Theme.spacingXL * 2)
            }
        }

        Rectangle {
            id: footerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.round(Theme.fontSizeMedium * 4.5)
            color: Theme.surfaceContainerHigh

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.outlineMedium
                opacity: 0.5
            }

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingM

                KaskadButton {
                    visible: ChangelogService.releaseUrl.length > 0
                    text: "Все изменения"
                    iconName: "open_in_new"
                    backgroundColor: Theme.surfaceContainerHighest
                    textColor: Theme.surfaceText
                    onClicked: Qt.openUrlExternally(ChangelogService.releaseUrl)
                }

                KaskadButton {
                    text: "Понятно"
                    iconName: "check"
                    backgroundColor: Theme.primary
                    textColor: Theme.primaryText
                    onClicked: root.dismiss()
                }
            }
        }
    }

    function dismiss() {
        ChangelogService.dismissChangelog();
        changelogDismissed();
        visible = false;
    }
}

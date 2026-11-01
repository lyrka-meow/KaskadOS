import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root
    property var greeterRoot: null
    property int step: 0
    readonly property var steps: [
        { icon: "view_day", title: I18n.tr("The panel"), body: I18n.tr("Your workspaces, running apps, media, clock and system controls live here. Every section can be rearranged visually.") },
        { icon: "apps", title: I18n.tr("Launcher and applications"), body: I18n.tr("Open the launcher to search apps and actions. Install software from the KaskadOS application center.") },
        { icon: "tune", title: I18n.tr("Quick settings"), body: I18n.tr("Network, sound, Bluetooth, displays and power controls are grouped by task, not scattered across unrelated pages.") },
        { icon: "dashboard_customize", title: I18n.tr("Edit the layout directly"), body: I18n.tr("Enter Layout mode, click a widget, drag it with the left mouse button, resize from the visible handle, and use Undo if needed.") },
        { icon: "ios_share", title: I18n.tr("Share layouts safely"), body: I18n.tr("Export one .kaskadlayout file. It contains appearance and placement, never passwords, networks, accounts or personal media folders.") }
    ]

    Column {
        anchors.centerIn: parent
        width: Math.min(590, parent.width - Theme.spacingXL * 2)
        spacing: Theme.spacingXL
        KaskadIcon { anchors.horizontalCenter: parent.horizontalCenter; name: root.steps[root.step].icon; size: 72; color: Theme.primary }
        StyledText { width: parent.width; text: root.steps[root.step].title; horizontalAlignment: Text.AlignHCenter; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeXLarge + 4; font.weight: Font.Bold }
        StyledText { width: parent.width; text: root.steps[root.step].body; horizontalAlignment: Text.AlignHCenter; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeMedium; wrapMode: Text.WordWrap; lineHeight: 1.25 }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingS
            Repeater {
                model: root.steps.length
                Rectangle { required property int index; width: index === root.step ? 30 : 9; height: 9; radius: 5; color: index === root.step ? Theme.primary : Theme.outline; Behavior on width { NumberAnimation { duration: Theme.shortDuration } } }
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingM
            KaskadButton { text: I18n.tr("Back"); iconName: "arrow_back"; enabled: root.step > 0; onClicked: root.step-- }
            KaskadButton { text: root.step < root.steps.length - 1 ? I18n.tr("Next") : I18n.tr("Show it on my desktop"); iconName: root.step < root.steps.length - 1 ? "arrow_forward" : "ads_click"; onClicked: { if (root.step < root.steps.length - 1) root.step++; else root.greeterRoot?.beginInteractiveTour(); } }
        }
    }
}

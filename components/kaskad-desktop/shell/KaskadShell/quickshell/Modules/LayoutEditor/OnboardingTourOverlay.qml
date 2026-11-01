import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: tourWindow
        required property var modelData

        readonly property int step: OnboardingTourService.step
        readonly property var activeBar: SettingsData.getEnabledBarConfigs().find(bar =>
            CompositorService.isKaskad
                ? SessionData.isBarVisibleInContext(bar.id, modelData.name)
                : SettingsData.isScreenInPreferences(modelData, bar.screenPreferences || ["all"])) || null
        readonly property int barPosition: activeBar?.position ?? SettingsData.Position.Top
        readonly property real barSize: SettingsData.getActiveBarThicknessForScreen(modelData) || 42
        readonly property var descriptions: [
            { title: I18n.tr("This is your panel"), body: I18n.tr("It keeps workspaces, running apps and status controls close without taking over the desktop.") },
            { title: I18n.tr("Launcher and applications"), body: I18n.tr("Open the launcher here, then search applications, files and actions from one place.") },
            { title: I18n.tr("Quick settings"), body: I18n.tr("Network, sound, Bluetooth, display and power controls are grouped here.") },
            { title: I18n.tr("Desktop widgets"), body: I18n.tr("Widgets stay live on the real desktop. Outside Layout mode they cannot be moved accidentally.") },
            { title: I18n.tr("Layout mode"), body: I18n.tr("Open it from Settings, a widget's right-click menu, or a panel's empty area. Drag with the left mouse button and finish with Done.") }
        ]
        readonly property rect focusRect: {
            const width = modelData.width;
            const height = modelData.height;
            if (step === 0) {
                if (barPosition === SettingsData.Position.Bottom) return Qt.rect(16, height - barSize - 16, width - 32, barSize);
                if (barPosition === SettingsData.Position.Left) return Qt.rect(16, 16, barSize, height - 32);
                if (barPosition === SettingsData.Position.Right) return Qt.rect(width - barSize - 16, 16, barSize, height - 32);
                return Qt.rect(16, 16, width - 32, barSize);
            }
            if (step === 1)
                return Qt.rect(18, barPosition === SettingsData.Position.Bottom ? height - barSize - 18 : 18, 150, Math.max(42, barSize));
            if (step === 2)
                return Qt.rect(width - 220, barPosition === SettingsData.Position.Bottom ? height - barSize - 18 : 18, 200, Math.max(42, barSize));
            if (step === 3)
                return Qt.rect(width * 0.18, height * 0.2, width * 0.64, height * 0.5);
            return Qt.rect(width * 0.18, height - 118, width * 0.64, 82);
        }

        screen: modelData
        visible: OnboardingTourService.active
        color: "transparent"
        anchors { left: true; right: true; top: true; bottom: true }
        WlrLayershell.namespace: "kaskados:onboarding-tour"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Item {
            anchors.fill: parent
            readonly property color shade: Theme.withAlpha("#000000", 0.72)
            Rectangle { x: 0; y: 0; width: parent.width; height: Math.max(0, tourWindow.focusRect.y - 8); color: parent.shade }
            Rectangle { x: 0; y: tourWindow.focusRect.y - 8; width: Math.max(0, tourWindow.focusRect.x - 8); height: tourWindow.focusRect.height + 16; color: parent.shade }
            Rectangle { x: tourWindow.focusRect.x + tourWindow.focusRect.width + 8; y: tourWindow.focusRect.y - 8; width: Math.max(0, parent.width - x); height: tourWindow.focusRect.height + 16; color: parent.shade }
            Rectangle { x: 0; y: tourWindow.focusRect.y + tourWindow.focusRect.height + 8; width: parent.width; height: Math.max(0, parent.height - y); color: parent.shade }

            Rectangle {
                x: tourWindow.focusRect.x - 5
                y: tourWindow.focusRect.y - 5
                width: tourWindow.focusRect.width + 10
                height: tourWindow.focusRect.height + 10
                color: "transparent"
                radius: Theme.cornerRadius
                border.width: 3
                border.color: Theme.primary
                SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.5; duration: 700 } NumberAnimation { to: 1; duration: 700 } }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: tourWindow.focusRect.y > parent.height / 2 ? parent.top : undefined
                anchors.topMargin: tourWindow.focusRect.y > parent.height / 2 ? 28 : 0
                anchors.bottom: tourWindow.focusRect.y <= parent.height / 2 ? parent.bottom : undefined
                anchors.bottomMargin: tourWindow.focusRect.y <= parent.height / 2 ? 28 : 0
                width: Math.min(610, parent.width - 48)
                height: 190
                radius: Theme.cornerRadius * 1.5
                color: Theme.surfaceContainer
                border.width: 1
                border.color: Theme.outline

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM
                    StyledText { width: parent.width; text: tourWindow.descriptions[tourWindow.step].title; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
                    StyledText { width: parent.width; text: tourWindow.descriptions[tourWindow.step].body; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeMedium; wrapMode: Text.WordWrap }
                    Row {
                        spacing: Theme.spacingS
                        KaskadButton { text: I18n.tr("Skip"); onClicked: OnboardingTourService.skip() }
                        KaskadButton { text: I18n.tr("Back"); iconName: "arrow_back"; enabled: tourWindow.step > 0; onClicked: OnboardingTourService.previous() }
                        KaskadButton { text: tourWindow.step === OnboardingTourService.stepCount - 1 ? I18n.tr("Done") : I18n.tr("Next"); iconName: tourWindow.step === OnboardingTourService.stepCount - 1 ? "check" : "arrow_forward"; onClicked: OnboardingTourService.next() }
                    }
                }
            }

            MouseArea { anchors.fill: parent; z: -1 }
        }
    }
}

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Card {
    id: root

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                const hours = systemClock?.date?.getHours() ?? 0;
                const displayHours = SettingsData.use24HourClock ? hours : (hours === 0 ? 12 : hours > 12 ? hours - 12 : hours);
                const minutes = String(systemClock?.date?.getMinutes() ?? 0).padStart(2, '0');
                const seconds = SettingsData.showSeconds ? ":" + String(systemClock?.date?.getSeconds() ?? 0).padStart(2, '0') : "";
                return String(displayHours).padStart(2, '0') + ":" + minutes + seconds;
            }
            font.family: Theme.monoFontFamily
            font.pixelSize: SettingsData.showSeconds ? 22 : 38
            color: Theme.primary
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            LayoutMirroring.enabled: false
        }

        StyledText {
            width: parent.width
            text: systemClock?.date?.toLocaleDateString(I18n.locale(), "ddd, MMM d")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceTextMedium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    SystemClock {
        id: systemClock
        precision: SettingsData.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            systemClock.enabled = false;
            systemClock.enabled = true;
        }
    }
}

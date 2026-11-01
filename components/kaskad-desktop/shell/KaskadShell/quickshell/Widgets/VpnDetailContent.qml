import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root

    property real listHeight: 200
    property var parentPopout: null

    spacing: Theme.spacingM

    function statusText() {
        if (RegaliaService.availabilityState === "checking")
            return I18n.tr("Checking Regalia");
        if (!RegaliaService.installed)
            return I18n.tr("Regalia is not installed");
        if (!RegaliaService.available)
            return I18n.tr("Regalia service is not running");
        if (!RegaliaService.configurationReady)
            return I18n.tr("Choose a VPN server in Settings");
        if (RegaliaService.busy)
            return RegaliaService.enabled ? I18n.tr("Disconnecting...") : I18n.tr("Connecting...");
        if (RegaliaService.enabled)
            return RegaliaService.activeServer?.name || I18n.tr("Connected");
        return I18n.tr("Disabled");
    }

    Rectangle {
        id: statusCard

        width: parent.width
        height: 72
        radius: Theme.cornerRadius
        color: Theme.surfaceLight
        border.width: RegaliaService.enabled ? 2 : 1
        border.color: RegaliaService.enabled ? Theme.primary : Theme.outlineLight

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingM

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: RegaliaService.enabled ? Theme.primaryHoverLight : Theme.surfaceVariant

                KaskadIcon {
                    anchors.centerIn: parent
                    name: RegaliaService.enabled ? "vpn_lock" : "vpn_key_off"
                    size: 22
                    color: RegaliaService.enabled ? Theme.primary : Theme.surfaceVariantText
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: RegaliaService.activeRoute?.name || I18n.tr("Regalia VPN")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: RegaliaService.enabled ? Theme.primary : Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText()
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }
            }

            KaskadToggle {
                checked: RegaliaService.enabled
                enabled: RegaliaService.available && RegaliaService.configurationReady && !RegaliaService.busy
                onToggled: checked => RegaliaService.setEnabled(checked)
            }
        }
    }

    RowLayout {
        id: actions

        width: parent.width
        height: 38
        spacing: Theme.spacingS

        KaskadButton {
            Layout.fillWidth: true
            text: I18n.tr("VPN Settings")
            iconName: "settings"
            onClicked: {
                root.parentPopout?.close();
                PopoutService.openSettingsWithTabIndex(41);
            }
        }

        KaskadActionButton {
            buttonSize: 38
            iconName: "refresh"
            tooltipText: I18n.tr("Refresh")
            enabled: !RegaliaService.statusRequestPending
            onClicked: RegaliaService.refreshStatus()
        }
    }
}

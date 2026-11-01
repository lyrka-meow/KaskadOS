import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.ControlCenter.Components

BuiltinWidget {
    id: root

    Ref {
        service: RegaliaService
    }

    readonly property bool vpnActivating: RegaliaService.busy
    readonly property bool vpnActivated: RegaliaService.enabled

    ccWidgetIcon: "vpn_key"
    ccWidgetPrimaryText: I18n.tr("VPN")
    ccWidgetSecondaryText: {
        if (vpnActivating)
            return I18n.tr("Connecting...");
        if (!vpnActivated)
            return I18n.tr("Disconnected");
        return RegaliaService.activeServer?.name || I18n.tr("Connected");
    }
    ccWidgetIsActive: vpnActivated

    onCcWidgetToggled: RegaliaService.setEnabled(!RegaliaService.enabled)

    ccDetailContent: Component {
        VpnDetailContent {
            listHeight: 260
        }
    }
}

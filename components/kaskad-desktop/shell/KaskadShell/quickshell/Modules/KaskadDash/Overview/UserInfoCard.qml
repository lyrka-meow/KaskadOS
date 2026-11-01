import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Card {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingM

        KaskadCircularImage {
            id: avatarContainer

            width: 64
            height: width
            anchors.verticalCenter: parent.verticalCenter
            imageSource: {
                if (PortalService.profileImage === "")
                    return "";

                if (PortalService.profileImage.startsWith("/"))
                    return "file://" + PortalService.profileImage;

                return PortalService.profileImage;
            }
            fallbackIcon: "person"
        }

        StyledText {
            width: parent.width - avatarContainer.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: UserInfoService.username || I18n.tr("User")
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
            color: Theme.surfaceText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }
    }
}

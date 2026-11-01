import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Widgets

Item {
    id: root

    property string source: ""
    property int glyphSize: 14

    readonly property var sourceAsset: ({
            "flatpak": "../../assets/package-sources/flatpak.svg"
        })

    readonly property string assetPath: sourceAsset[source] || ""

    visible: SettingsData.kaskadLauncherV2ShowSourceBadges && (assetPath.length > 0 || source === "windows")
    implicitWidth: glyphSize
    implicitHeight: glyphSize

    IconImage {
        anchors.fill: parent
        visible: root.assetPath.length > 0
        source: root.assetPath ? Qt.resolvedUrl(root.assetPath) : ""
        implicitSize: root.glyphSize * 2
        backer.sourceSize: Qt.size(root.glyphSize * 2, root.glyphSize * 2)
        smooth: true
        mipmap: true
        asynchronous: true
    }

    KaskadIcon {
        anchors.centerIn: parent
        visible: root.source === "windows"
        name: "window"
        size: root.glyphSize
        color: Theme.primary
    }
}

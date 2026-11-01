import QtQuick
import qs.Common
import qs.Modules.KaskadBar.Components
import qs.Services
import qs.Widgets

BasePill {
    id: root

    property var widgetData: null
    property bool minimumWidth: (widgetData && widgetData.minimumWidth !== undefined) ? widgetData.minimumWidth : true
    property var selectedIds: (widgetData && widgetData.gpuDeviceIds !== undefined && widgetData.gpuDeviceIds !== null) ? widgetData.gpuDeviceIds : null
    property var visibleDevices: {
        const all = GpuUsageService.devices || [];
        if (selectedIds === null)
            return all;
        return all.filter(device => selectedIds.includes(device.id));
    }
    property real highestUsage: {
        let result = 0;
        for (const device of visibleDevices)
            result = Math.max(result, device.utilization || 0);
        return result;
    }

    signal gpuUsageClicked

	function baseDeviceLabel(device) {
        if (device.kind === "integrated")
            return "iGPU";
        const name = device.displayName || device.name || "";
        const family = name.match(/\b(RTX|GTX|RX|ARC)\b/i);
        if (family)
            return family[1].toUpperCase();
        if (device.kind === "discrete")
            return "dGPU";
        return (device.driver || "GPU").toUpperCase();
    }

	function deviceLabel(device, deviceIndex) {
		const base = baseDeviceLabel(device);
		const matching = visibleDevices.filter(item => baseDeviceLabel(item) === base);
		if (matching.length < 2)
			return base;
		let ordinal = 0;
		for (let index = 0; index <= deviceIndex; index++) {
			if (baseDeviceLabel(visibleDevices[index]) === base)
				ordinal++;
		}
		return base + " " + ordinal;
	}

    function usageText(device, deviceIndex, includeLabel) {
        const value = device.usageAvailable ? Math.round(device.utilization || 0) + "%" : "--%";
        return includeLabel ? deviceLabel(device, deviceIndex) + " " + value : value;
    }

    Component.onCompleted: {
        GpuUsageService.addRef();
        DgopService.addRef(["gpu"]);
    }
    Component.onDestruction: {
        GpuUsageService.removeRef();
        DgopService.removeRef(["gpu"]);
    }

    content: Component {
        Item {
            implicitWidth: root.isVerticalOrientation ? (root.widgetThickness - root.horizontalPadding * 2) : horizontalContent.implicitWidth
            implicitHeight: root.isVerticalOrientation ? verticalContent.implicitHeight : horizontalContent.implicitHeight

            Column {
                id: verticalContent
                visible: root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: 1

                KaskadIcon {
                    name: "speed"
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: root.highestUsage > 80 ? Theme.tempDanger : (root.highestUsage > 60 ? Theme.tempWarning : Theme.widgetIconColor)
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: root.visibleDevices.length > 0 ? Math.round(root.highestUsage) : "--"
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: Theme.widgetTextColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Row {
                id: horizontalContent
                visible: !root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                KaskadIcon {
                    name: "speed"
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: root.highestUsage > 80 ? Theme.tempDanger : (root.highestUsage > 60 ? Theme.tempWarning : Theme.widgetIconColor)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    spacing: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: root.visibleDevices
                        delegate: Row {
                            required property var modelData
                            required property int index
                            spacing: Theme.spacingXS

                            StyledText {
                                visible: index > 0
                                text: "·"
                                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                                color: Theme.outline
                            }

                            StyledText {
                                text: root.usageText(modelData, index, root.visibleDevices.length > 1)
                                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                                color: Theme.widgetTextColor
                            }
                        }
                    }

                    StyledText {
                        visible: root.visibleDevices.length === 0
                        text: "--%"
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: Theme.widgetTextColor
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => {
            root.triggerRipple(this, mouse.x, mouse.y);
            DgopService.setSortBy("cpu");
            root.gpuUsageClicked();
        }
    }
}

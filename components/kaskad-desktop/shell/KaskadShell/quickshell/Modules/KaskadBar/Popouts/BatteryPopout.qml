import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Common
import qs.Services
import qs.Widgets

KaskadPopout {
    id: root

    layerNamespace: "kaskad-shell:battery"
    property var triggerScreen: null

    function isActiveProfile(profile) {
        return typeof PowerProfiles !== "undefined" && PowerProfiles.profile === profile;
    }

    function setProfile(profile) {
        if (PowerProfileWatcher.applyProfile(profile))
            return;
        ToastService.showError(PowerProfileWatcher.available
            ? I18n.tr("Failed to set power profile")
            : I18n.tr("power-profiles-daemon not available"));
    }

    popupWidth: 480
    popupHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
    triggerWidth: 70
    positioning: ""
    screen: triggerScreen

    onBackgroundClicked: close()

    content: Component {
        Rectangle {
            id: batteryContent

            property bool processMonitoringActive: false
            property string processScope: "user"

            readonly property var profileModel: Array.from(new Set(PowerProfileWatcher.availableProfiles || []))
            readonly property int currentProfileIndex: {
                if (typeof PowerProfiles === "undefined")
                    return -1;
                return profileModel.findIndex(profile => root.isActiveProfile(profile));
            }
            readonly property int currentProfile: currentProfileIndex >= 0 ? profileModel[currentProfileIndex] : -1
            readonly property real powerRate: Math.abs(BatteryService.changeRate)
            readonly property string estimateTitle: {
                if (!BatteryService.batteryAvailable)
                    return I18n.tr("Battery data unavailable");
                if (BatteryService.isPluggedIn && !BatteryService.isCharging)
                    return I18n.tr("Fully charged", "battery summary");
                return BatteryService.isCharging
                    ? I18n.tr("Until fully charged", "battery summary")
                    : I18n.tr("Estimated battery time", "battery summary");
            }
            readonly property string estimateValue: {
                if (!BatteryService.batteryAvailable)
                    return "—";
                if (BatteryService.isPluggedIn && !BatteryService.isCharging)
                    return I18n.tr("Ready", "battery fully charged value");
                return BatteryService.formatDuration(BatteryService.estimatedSeconds);
            }
            readonly property string estimateDetails: {
                if (!BatteryService.batteryAvailable)
                    return "";
                if (BatteryService.isPluggedIn && !BatteryService.isCharging)
                    return I18n.tr("Power is supplied by the charger");
                const clock = BatteryService.estimatedClockTime();
                if (!clock)
                    return I18n.tr("The estimate appears after power use stabilizes");
                return BatteryService.isCharging
                    ? I18n.tr("Full charge around %1").arg(clock)
                    : I18n.tr("Approximately until %1 at the current load").arg(clock);
            }
            readonly property string rateLabel: {
                if (!BatteryService.batteryAvailable)
                    return "—";
                if (powerRate <= 0.05)
                    return "0.0 W";
                return powerRate.toFixed(1) + " W";
            }
            readonly property var topProcesses: {
                const source = DgopService.allProcesses || [];
                let processes = source.filter(process => {
                    if (!process || !process.command || process.command === "dgop")
                        return false;
                    return processScope === "all" || process.username === UserInfoService.username;
                });
                processes.sort((a, b) => {
                    const cpuDifference = (b.cpu || 0) - (a.cpu || 0);
                    return Math.abs(cpuDifference) > 0.01 ? cpuDifference : (b.memoryKB || 0) - (a.memoryKB || 0);
                });
                return processes.slice(0, 5);
            }

            function syncProcessMonitoring() {
                const shouldMonitor = root.shouldBeVisible;
                if (shouldMonitor === processMonitoringActive)
                    return;
                processMonitoringActive = shouldMonitor;
                if (shouldMonitor)
                    DgopService.addRef(["processes", "cpu", "memory"]);
                else
                    DgopService.removeRef(["processes", "cpu", "memory"]);
            }

            function processDisplayName(process) {
                const command = process?.command || I18n.tr("Unknown");
                const fullCommand = (process?.fullCommand || "").toLowerCase();
                if (fullCommand.includes("minecraft"))
                    return "Minecraft";
                if (command === "qs")
                    return I18n.tr("Desktop shell");
                const desktopEntry = DesktopEntries.heuristicLookup(command);
                return desktopEntry?.name || command;
            }

            Component.onCompleted: syncProcessMonitoring()
            Component.onDestruction: {
                if (processMonitoringActive)
                    DgopService.removeRef(["processes", "cpu", "memory"]);
            }

            Connections {
                target: root
                function onShouldBeVisibleChanged() {
                    batteryContent.syncProcessMonitoring();
                }
            }

            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true
            implicitHeight: contentColumn.implicitHeight + Theme.spacingL * 2
            color: "transparent"

            Column {
                id: contentColumn
                width: parent.width - Theme.spacingL * 2
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                Row {
                    width: parent.width
                    height: 48
                    spacing: Theme.spacingM

                    KaskadIcon {
                        name: BatteryService.getBatteryIcon()
                        size: Theme.iconSizeLarge
                        color: BatteryService.isLowBattery && !BatteryService.isCharging
                            ? Theme.error
                            : (BatteryService.isCharging || BatteryService.isPluggedIn ? Theme.primary : Theme.surfaceText)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        width: parent.width - Theme.iconSizeLarge - Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Row {
                            spacing: Theme.spacingS

                            StyledText {
                                id: batteryLevelText
                                text: BatteryService.batteryAvailable ? BatteryService.batteryLevel + "%" : "—"
                                font.pixelSize: Theme.fontSizeXLarge
                                font.weight: Font.Bold
                                color: BatteryService.isLowBattery && !BatteryService.isCharging ? Theme.error : Theme.surfaceText
                            }

                            StyledText {
                                text: BatteryService.batteryStatus
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceTextMedium
                                anchors.baseline: batteryLevelText.baseline
                            }
                        }

                        StyledText {
                            text: I18n.tr("Battery and current power use")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 8
                    radius: height / 2
                    color: Theme.surfaceContainerHighest
                    visible: BatteryService.batteryAvailable

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, BatteryService.batteryLevel / 100))
                        height: parent.height
                        radius: parent.radius
                        color: BatteryService.isLowBattery && !BatteryService.isCharging ? Theme.error : Theme.primary

                        Behavior on width {
                            NumberAnimation { duration: Theme.mediumDuration }
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: 86
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.width: 0

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        Column {
                            width: parent.width * 0.62
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                text: batteryContent.estimateTitle
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                            }

                            StyledText {
                                text: batteryContent.estimateValue
                                font.pixelSize: Theme.fontSizeXLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }

                            StyledText {
                                width: parent.width
                                text: batteryContent.estimateDetails
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            width: 1
                            height: parent.height - Theme.spacingS
                            color: Theme.outlineLight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width * 0.32
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                text: BatteryService.isCharging ? I18n.tr("Charging power") : I18n.tr("Power draw")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                            }

                            StyledText {
                                text: batteryContent.rateLabel
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: BatteryService.isCharging ? Theme.primary : (batteryContent.powerRate > 20 ? Theme.warning : Theme.surfaceText)
                            }

                            StyledText {
                                text: BatteryService.isCharging
                                    ? I18n.tr("into the battery")
                                    : (BatteryService.isPluggedIn ? I18n.tr("battery is idle") : I18n.tr("right now"))
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 66
                    spacing: Theme.spacingS
                    visible: BatteryService.batteryAvailable

                    Repeater {
                        model: [
                            {
                                "label": I18n.tr("Energy left"),
                                "value": BatteryService.batteryEnergy > 0 ? BatteryService.batteryEnergy.toFixed(1) + " Wh" : "—",
                                "detail": BatteryService.batteryCapacity > 0 ? I18n.tr("of %1 Wh").arg(BatteryService.batteryCapacity.toFixed(1)) : ""
                            },
                            {
                                "label": I18n.tr("Battery health"),
                                "value": BatteryService.batteryHealth,
                                "detail": I18n.tr("of original capacity")
                            },
                            {
                                "label": I18n.tr("CPU load"),
                                "value": DgopService.dgopAvailable ? DgopService.cpuUsage.toFixed(0) + "%" : "—",
                                "detail": DgopService.dgopAvailable ? DgopService.cpuTemperature.toFixed(0) + " °C" : I18n.tr("No data")
                            }
                        ]

                        delegate: StyledRect {
                            required property var modelData
                            width: (parent.width - Theme.spacingS * 2) / 3
                            height: parent.height
                            radius: Theme.cornerRadius
                            color: Theme.nestedSurface
                            border.width: 0

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                StyledText {
                                    text: modelData.label
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: modelData.value
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: modelData.detail
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    color: Theme.surfaceTextMedium
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: PowerProfileWatcher.available && batteryContent.profileModel.length > 0

                    Row {
                        width: parent.width

                        StyledText {
                            text: I18n.tr("Power mode")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            anchors.right: parent.right
                            text: batteryContent.currentProfile >= 0 ? Theme.getPowerProfileDescription(batteryContent.currentProfile) : ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                        }
                    }

                    Item {
                        width: parent.width
                        height: profileButtons.height * profileButtons.scale

                        KaskadButtonGroup {
                            id: profileButtons
                            model: batteryContent.profileModel.map(profile => Theme.getPowerProfileLabel(profile))
                            currentIndex: batteryContent.currentProfileIndex
                            selectionMode: "single"
                            scale: Math.min(1, parent.width / implicitWidth)
                            transformOrigin: Item.Center
                            anchors.horizontalCenter: parent.horizontalCenter
                            onSelectionChanged: (index, selected) => {
                                if (selected && index >= 0)
                                    root.setProfile(batteryContent.profileModel[index]);
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outlineLight
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Row {
                        width: parent.width
                        height: 32

                        Column {
                            width: parent.width - processScopeButtons.width - Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            StyledText {
                                text: I18n.tr("Power activity")
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: I18n.tr("Live CPU and memory use")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                            }
                        }

                        KaskadButtonGroup {
                            id: processScopeButtons
                            model: [I18n.tr("Mine"), I18n.tr("All")]
                            currentIndex: batteryContent.processScope === "user" ? 0 : 1
                            selectionMode: "single"
                            anchors.verticalCenter: parent.verticalCenter
                            onSelectionChanged: (index, selected) => {
                                if (selected)
                                    batteryContent.processScope = index === 0 ? "user" : "all";
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("Linux reports real CPU and memory load; exact watts cannot be assigned to individual apps.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                        wrapMode: Text.WordWrap
                    }

                    Column {
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: ScriptModel {
                                values: batteryContent.topProcesses
                                objectProp: "pid"
                            }

                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width
                                height: 42
                                radius: Theme.cornerRadius
                                color: Theme.nestedSurface

                                readonly property real processCpu: modelData.cpu || 0
                                readonly property real processMemory: modelData.memoryKB || 0

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.rightMargin: Theme.spacingS
                                    spacing: Theme.spacingS

                                    KaskadIcon {
                                        name: DgopService.getProcessIcon(modelData.command || "")
                                        size: Theme.iconSize
                                        color: processCpu >= 50 ? Theme.warning : Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Column {
                                        width: parent.width - Theme.iconSize - usageColumn.width - Theme.spacingS * 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3

                                        StyledText {
                                            width: parent.width
                                            text: batteryContent.processDisplayName(modelData)
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            width: parent.width
                                            height: 4
                                            radius: height / 2
                                            color: Theme.surfaceContainerHighest

                                            Rectangle {
                                                width: parent.width * Math.max(0, Math.min(1, processCpu / 100))
                                                height: parent.height
                                                radius: parent.radius
                                                color: processCpu >= 50 ? Theme.warning : Theme.primary
                                            }
                                        }
                                    }

                                    Column {
                                        id: usageColumn
                                        width: 112
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1

                                        StyledText {
                                            anchors.right: parent.right
                                            text: "CPU " + processCpu.toFixed(1) + "%"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: processCpu >= 50 ? Theme.warning : Theme.surfaceText
                                        }

                                        StyledText {
                                            anchors.right: parent.right
                                            text: DgopService.formatMemoryUsage(processMemory)
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceTextMedium
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            width: parent.width
                            height: 42
                            text: DgopService.dgopAvailable ? I18n.tr("Collecting process data…") : I18n.tr("System monitor data is unavailable")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: batteryContent.topProcesses.length === 0
                        }
                    }

                    KaskadButton {
                        width: parent.width
                        text: I18n.tr("Open System Monitor")
                        iconName: "monitoring"
                        buttonHeight: 36
                        onClicked: {
                            root.close();
                            PopoutService.showProcessListModal();
                        }
                    }
                }
            }
        }
    }
}

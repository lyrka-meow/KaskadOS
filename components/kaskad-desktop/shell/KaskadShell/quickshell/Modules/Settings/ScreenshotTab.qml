pragma ComponentBehavior: Bound

import Kaskad.Ipc
import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.Widgets

Item {
    id: root

    property string recordingProfileId: ""

    readonly property var captureLabels: [
        I18n.tr("Selected area"),
        I18n.tr("Active window"),
        I18n.tr("Current screen"),
        I18n.tr("All screens"),
        I18n.tr("Last selected area")
    ]
    readonly property var captureValues: ["region", "window", "full", "all", "last"]
    readonly property var formatLabels: ["PNG", "JPEG", "PPM"]
    readonly property var formatValues: ["png", "jpg", "ppm"]

    function profiles() {
        return JSON.parse(JSON.stringify(SettingsData.screenshotProfiles || []));
    }

    function profileIndex(profileId) {
        const list = SettingsData.screenshotProfiles || [];
        for (let i = 0; i < list.length; ++i) {
            if (list[i]?.id === profileId)
                return i;
        }
        return -1;
    }

    function updateProfile(profileId, key, value) {
        const list = profiles();
        const index = list.findIndex(profile => profile?.id === profileId);
        if (index < 0)
            return;
        list[index][key] = value;
        if (key === "clipboard" && value === false && list[index].saveFile !== true)
            list[index].saveFile = true;
        if (key === "saveFile" && value === false && list[index].clipboard !== true)
            list[index].clipboard = true;
        SettingsData.setScreenshotProfiles(list);
    }

    function duplicateProfile(profileId) {
        const list = profiles();
        const source = list.find(profile => profile?.id === profileId);
        if (!source)
            return;
        const copy = JSON.parse(JSON.stringify(source));
        copy.id = "custom-" + Date.now();
        copy.name = (copy.name || I18n.tr("Screenshot")) + " — " + I18n.tr("copy");
        copy.shortcut = "";
        list.push(copy);
        SettingsData.setScreenshotProfiles(list);
    }

    function addProfile() {
        const list = profiles();
        list.push({
            "id": "custom-" + Date.now(),
            "name": I18n.tr("New screenshot profile"),
            "enabled": true,
            "shortcut": "",
            "capture": "region",
            "clipboard": true,
            "saveFile": false,
            "outputDir": "",
            "filename": "",
            "format": "png",
            "quality": 90,
            "includeCursor": false,
            "confirmSelection": true,
            "quietOverlay": false,
            "notify": false
        });
        SettingsData.setScreenshotProfiles(list);
    }

    function removeProfile(profileId) {
        if (profileId === "quick-region")
            return;
        SettingsData.setScreenshotProfiles(profiles().filter(profile => profile?.id !== profileId));
    }

    function shortcutConflict(profileId, shortcut) {
        if (!shortcut)
            return "";
        const normalized = shortcut.toLowerCase();
        const list = SettingsData.screenshotProfiles || [];
        for (let i = 0; i < list.length; ++i) {
            const profile = list[i];
            if (profile?.id !== profileId && (profile?.shortcut || "").toLowerCase() === normalized)
                return profile.name || profile.id;
        }
        return "";
    }

    function startShortcutRecording(profileId) {
        recordingProfileId = profileId;
        Kaskad.setShortcutCaptureActive(true);
    }

    function stopShortcutRecording() {
        recordingProfileId = "";
        Kaskad.setShortcutCaptureActive(false);
    }

    Component.onDestruction: stopShortcutRecording()

    Connections {
        target: Kaskad

        function onShortcutCaptured(shortcut) {
            if (!root.recordingProfileId)
                return;
            const profileId = root.recordingProfileId;
            root.stopShortcutRecording();
            const conflict = root.shortcutConflict(profileId, shortcut);
            if (conflict) {
                ToastService.showError(I18n.tr("Shortcut is already in use"), conflict);
                return;
            }
            root.updateProfile(profileId, "shortcut", shortcut);
        }
    }

    KaskadFlickable {
        anchors.fill: parent
        clip: true
        contentHeight: mainColumn.height + Theme.spacingXL * 2
        contentWidth: width

        Column {
            id: mainColumn
            topPadding: Theme.spacingXL
            bottomPadding: Theme.spacingXL
            width: Math.min(720, parent.width - Theme.spacingL * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingL

            Column {
                width: parent.width
                spacing: Theme.spacingXS

                StyledText {
                    text: I18n.tr("Screenshots")
                    font.pixelSize: Theme.fontSizeXLarge
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    text: I18n.tr("Each profile is an independent capture action with its own shortcut, source, output, and feedback.")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            Repeater {
                model: SettingsData.screenshotProfiles || []

                delegate: SettingsCard {
                    id: profileCard
                    required property var modelData
                    width: mainColumn.width
                    title: modelData.name || modelData.id
                    iconName: "screenshot_region"
                    collapsible: true
                    expanded: modelData.id === "quick-region"

                    headerActions: [
                        KaskadButton {
                            text: I18n.tr("Run")
                            enabled: profileCard.modelData.enabled !== false
                            onClicked: Quickshell.execDetached(["kaskad-shell", "ipc", "call", "screenshot", "capture", profileCard.modelData.id])
                        },
                        KaskadButton {
                            text: I18n.tr("Duplicate")
                            onClicked: root.duplicateProfile(profileCard.modelData.id)
                        },
                        KaskadButton {
                            text: I18n.tr("Delete")
                            enabled: profileCard.modelData.id !== "quick-region"
                            onClicked: root.removeProfile(profileCard.modelData.id)
                        }
                    ]

                    SettingsToggleRow {
                        text: I18n.tr("Enabled")
                        description: I18n.tr("Disabled profiles cannot be launched and do not reserve their shortcut.")
                        checked: profileCard.modelData.enabled !== false
                        onToggled: checked => root.updateProfile(profileCard.modelData.id, "enabled", checked)
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: I18n.tr("Name")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        KaskadTextField {
                            width: parent.width
                            text: profileCard.modelData.name || ""
                            onEditingFinished: root.updateProfile(profileCard.modelData.id, "name", text.trim() || profileCard.modelData.id)
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        Column {
                            width: parent.width - clearShortcut.width - Theme.spacingS
                            spacing: Theme.spacingXS

                            StyledText {
                                text: I18n.tr("Shortcut")
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            KaskadButton {
                                width: parent.width
                                text: root.recordingProfileId === profileCard.modelData.id
                                    ? I18n.tr("Press a shortcut…")
                                    : (profileCard.modelData.shortcut || I18n.tr("Not assigned"))
                                onClicked: {
                                    if (root.recordingProfileId === profileCard.modelData.id)
                                        root.stopShortcutRecording();
                                    else
                                        root.startShortcutRecording(profileCard.modelData.id);
                                }
                            }
                        }

                        KaskadButton {
                            id: clearShortcut
                            anchors.bottom: parent.bottom
                            text: I18n.tr("Clear")
                            enabled: !!profileCard.modelData.shortcut
                            onClicked: root.updateProfile(profileCard.modelData.id, "shortcut", "")
                        }
                    }

                    SettingsDropdownRow {
                        property int captureIndex: root.captureValues.indexOf(profileCard.modelData.capture || "region")
                        text: I18n.tr("Capture")
                        options: root.captureLabels
                        currentValue: root.captureLabels[Math.max(0, captureIndex)]
                        onValueChanged: value => {
                            const index = root.captureLabels.indexOf(value);
                            if (index >= 0)
                                root.updateProfile(profileCard.modelData.id, "capture", root.captureValues[index]);
                        }
                    }

                    SettingsToggleRow {
                        text: I18n.tr("Copy image to clipboard")
                        checked: profileCard.modelData.clipboard === true
                        onToggled: checked => root.updateProfile(profileCard.modelData.id, "clipboard", checked)
                    }

                    SettingsToggleRow {
                        text: I18n.tr("Save to file")
                        checked: profileCard.modelData.saveFile === true
                        onToggled: checked => root.updateProfile(profileCard.modelData.id, "saveFile", checked)
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: profileCard.modelData.saveFile === true

                        StyledText {
                            text: I18n.tr("Save folder")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        KaskadTextField {
                            width: parent.width
                            text: profileCard.modelData.outputDir || ""
                            placeholderText: I18n.tr("Default Pictures/Screenshots folder")
                            onEditingFinished: root.updateProfile(profileCard.modelData.id, "outputDir", text.trim())
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: profileCard.modelData.saveFile === true

                        StyledText {
                            text: I18n.tr("File name")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        KaskadTextField {
                            width: parent.width
                            text: profileCard.modelData.filename || ""
                            placeholderText: I18n.tr("Automatic date and time")
                            onEditingFinished: root.updateProfile(profileCard.modelData.id, "filename", text.trim())
                        }

                        StyledText {
                            width: parent.width
                            text: I18n.tr("Available variables: {date}, {time}, {datetime}. Existing files are never overwritten.")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }
                    }

                    SettingsDropdownRow {
                        property int formatIndex: root.formatValues.indexOf((profileCard.modelData.format || "png").toLowerCase())
                        text: I18n.tr("File format")
                        visible: profileCard.modelData.saveFile === true
                        options: root.formatLabels
                        currentValue: root.formatLabels[Math.max(0, formatIndex)]
                        onValueChanged: value => {
                            const index = root.formatLabels.indexOf(value);
                            if (index >= 0)
                                root.updateProfile(profileCard.modelData.id, "format", root.formatValues[index]);
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: profileCard.modelData.saveFile === true && ["jpg", "jpeg"].includes((profileCard.modelData.format || "png").toLowerCase())

                        StyledText {
                            text: I18n.tr("JPEG quality (1–100)")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        KaskadTextField {
                            width: 120
                            text: String(profileCard.modelData.quality ?? 90)
                            onEditingFinished: root.updateProfile(profileCard.modelData.id, "quality", Math.max(1, Math.min(100, parseInt(text, 10) || 90)))
                        }
                    }

                    SettingsToggleRow {
                        text: I18n.tr("Include pointer")
                        checked: profileCard.modelData.includeCursor === true
                        onToggled: checked => root.updateProfile(profileCard.modelData.id, "includeCursor", checked)
                    }

                    SettingsToggleRow {
                        text: I18n.tr("Confirm selected area")
                        description: I18n.tr("When disabled, capture immediately when the mouse button is released.")
                        visible: ["region", "last"].includes(profileCard.modelData.capture || "region")
                        checked: profileCard.modelData.confirmSelection === true
                        onToggled: checked => root.updateProfile(profileCard.modelData.id, "confirmSelection", checked)
                    }

                    SettingsToggleRow {
                        text: I18n.tr("Minimal selection overlay")
                        description: I18n.tr("Keep the screen unchanged and show only the selection outline.")
                        visible: profileCard.modelData.capture === "region"
                        checked: profileCard.modelData.quietOverlay === true
                        onToggled: checked => root.updateProfile(profileCard.modelData.id, "quietOverlay", checked)
                    }

                    SettingsToggleRow {
                        text: I18n.tr("Show notification")
                        checked: profileCard.modelData.notify === true
                        onToggled: checked => root.updateProfile(profileCard.modelData.id, "notify", checked)
                    }
                }
            }

            KaskadButton {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Add screenshot profile")
                onClicked: root.addProfile()
            }
        }
    }
}

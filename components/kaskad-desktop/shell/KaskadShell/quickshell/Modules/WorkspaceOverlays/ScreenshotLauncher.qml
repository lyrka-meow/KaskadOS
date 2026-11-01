/*
    SPDX-License-Identifier: GPL-3.0-or-later
    SPDX-FileCopyrightText: 2026 The KaskadOS contributors
*/

import Kaskad.Ipc
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Scope {
    id: root

    property string activeProfileId: ""
    property string lastError: ""

    function profiles() {
        return Array.isArray(SettingsData.screenshotProfiles) ? SettingsData.screenshotProfiles : [];
    }

    function profileById(profileId) {
        const list = profiles();
        for (let i = 0; i < list.length; ++i) {
            if (list[i]?.id === profileId)
                return list[i];
        }
        return null;
    }

    function normalizedDirectory(path) {
        const value = (path || "").trim();
        if (value === "~")
            return Quickshell.env("HOME");
        if (value.indexOf("~/") === 0)
            return Quickshell.env("HOME") + value.slice(1);
        return value;
    }

    function commandForProfile(profile) {
        const command = ["kaskad-shell", "screenshot"];
        const capture = profile.capture || "region";
        if (capture !== "region")
            command.push(capture);

        if (profile.clipboard !== true)
            command.push("--no-clipboard");
        if (profile.saveFile !== true)
            command.push("--no-file");
        if (profile.notify !== true)
            command.push("--no-notify");
        if (capture === "region" && profile.confirmSelection !== true)
            command.push("--no-confirm");
        if (capture === "region" && profile.quietOverlay === true)
            command.push("--quiet-overlay");
        if (profile.includeCursor === true)
            command.push("--cursor=on");

        const format = (profile.format || "png").toLowerCase();
        command.push("--format", format);
        if (format === "jpg" || format === "jpeg")
            command.push("--quality", String(Math.max(1, Math.min(100, profile.quality ?? 90))));

        const directory = normalizedDirectory(profile.outputDir);
        if (profile.saveFile === true && directory)
            command.push("--dir", directory);
        if (profile.saveFile === true && (profile.filename || "").trim())
            command.push("--filename", profile.filename.trim());
        return command;
    }

    function launch(profileId) {
        if (captureProcess.running)
            return false;
        const profile = profileById(profileId);
        if (!profile || profile.enabled === false)
            return false;
        if (profile.clipboard !== true && profile.saveFile !== true) {
            ToastService.showError(I18n.tr("Screenshot profile has no output"), I18n.tr("Enable clipboard, file saving, or both."));
            return false;
        }

        PopoutManager.closeAllPopouts();
        activeProfileId = profileId;
        lastError = "";
        captureProcess.command = commandForProfile(profile);
        captureProcess.running = true;
        return true;
    }

    function syncShortcuts() {
        if (!Kaskad.available)
            return;
        const list = profiles();
        const shortcutProfiles = [];
        for (let i = 0; i < list.length; ++i) {
            const profile = list[i];
            if (!profile)
                continue;
            if (profile.id === "quick-region") {
                Kaskad.setScreenshotShortcut(profile.enabled === false ? "" : (profile.shortcut || ""));
            } else if (profile.enabled !== false) {
                shortcutProfiles.push({
                    "id": profile.id,
                    "name": profile.name || profile.id,
                    "shortcut": profile.shortcut || ""
                });
            }
        }
        Kaskad.setScreenshotProfiles(shortcutProfiles);
    }

    Component.onCompleted: Qt.callLater(syncShortcuts)

    Connections {
        target: SettingsData

        function onScreenshotProfilesChanged() {
            root.syncShortcuts();
        }
    }

    Connections {
        target: Kaskad

        function onAvailableChanged() {
            if (Kaskad.available)
                root.syncShortcuts();
        }

        function onScreenshotProfileRequested(profileId) {
            root.launch(profileId);
        }
    }

    IpcHandler {
        target: "screenshot"

        function capture(profileId: string): string {
            return root.launch(profileId || "quick-region") ? "SCREENSHOT_STARTED" : "SCREENSHOT_NOT_STARTED";
        }
    }

    Process {
        id: captureProcess
        running: false

        stderr: StdioCollector {
            onStreamFinished: root.lastError = text.trim()
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.lastError)
                ToastService.showError(I18n.tr("Could not take screenshot"), root.lastError);
            root.activeProfileId = "";
        }
    }
}

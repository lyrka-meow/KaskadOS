pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.I3
import qs.Common
import "../Common/ApplicationCommand.js" as ApplicationCommand
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("SessionService")

    // Qt.platform.os is "unix" on the BSDs (qtdeclarative qqmlplatform.cpp)
    readonly property bool isBSD: Qt.platform.os === "unix"
    property bool hasUwsm: false
    property bool isElogind: false
    property bool loginctlCommandAvailable: false
    property bool systemctlCommandAvailable: false
    property bool hibernateSupported: false
    property bool inhibitorAvailable: true
    property bool idleInhibited: false
    property string inhibitReason: "Keep system awake"
    property string nvidiaCommand: ""
    property int applicationLaunchSequence: 0

    property bool loginctlAvailable: false
    property string sessionId: ""
    property string sessionPath: ""
    property bool locked: false
    property bool active: false
    property bool idleHint: false
    property bool lockedHint: false
    property bool preparingForSleep: false
    property string sessionType: ""
    property string userName: ""
    property string seat: ""
    property string display: ""

    signal sessionLocked
    signal sessionUnlocked
    signal sessionResumed
    signal loginctlStateChanged

    property bool stateInitialized: false
    property string prepareForSleepSubscriptionId: ""
    property bool prepareForSleepSubscriptionPending: false
    property double lastResumeSignalTimestamp: 0

    readonly property string socketPath: Quickshell.env("KASKAD_SOCKET")

    Timer {
        id: sessionInitTimer
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            detectUwsmProcess.running = true;
            detectElogindProcess.running = true;
            detectLoginctlProcess.running = true;
            detectSystemctlProcess.running = true;
            detectHibernateProcess.running = true;
            detectPrimeRunProcess.running = true;
            if (!SettingsData.loginctlLockIntegration) {
                log.debug("loginctl lock integration disabled by user");
                return;
            }
            if (socketPath && socketPath.length > 0) {
                checkKaskadCapabilities();
            } else {
                log.debug("KASKAD_SOCKET not set");
            }
        }
    }

    Process {
        id: detectUwsmProcess
        running: false
        command: ["sh", "-c", "command -v uwsm > /dev/null 2>&1 && systemctl --user is-active --quiet 'wayland-wm@*.service' 2> /dev/null"]

        onExited: function (exitCode) {
            hasUwsm = (exitCode === 0);
        }
    }

    Process {
        id: detectElogindProcess
        running: false
        command: ["sh", "-c", "ps -eo comm= | grep -E '^(elogind|elogind-daemon)$'"]

        onExited: function (exitCode) {
            log.debug("Elogind detection exited with code", exitCode);
            isElogind = (exitCode === 0);
        }
    }

    Process {
        id: detectLoginctlProcess
        running: false
        command: ["sh", "-c", "command -v loginctl"]

        onExited: function (exitCode) {
            loginctlCommandAvailable = (exitCode === 0);
        }
    }

    Process {
        id: detectSystemctlProcess
        running: false
        command: ["sh", "-c", "command -v systemctl"]

        onExited: function (exitCode) {
            systemctlCommandAvailable = (exitCode === 0);
        }
    }

    Process {
        id: detectHibernateProcess
        running: false
        command: ["grep", "-q", "disk", "/sys/power/state"]

        onExited: function (exitCode) {
            hibernateSupported = (exitCode === 0);
        }
    }

    Process {
        id: hibernateProcess
        running: false

        property string errorOutput: ""

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => hibernateProcess.errorOutput += data.trim()
        }

        onExited: function (exitCode) {
            if (exitCode === 0) {
                errorOutput = "";
                return;
            }
            ToastService.showError(I18n.tr("Hibernate failed"), errorOutput);
            errorOutput = "";
        }
    }

    Process {
        id: suspendProcess

        property string errorOutput: ""

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => suspendProcess.errorOutput += data.trim() + "\n"
        }

        onExited: function (exitCode) {
            if (exitCode !== 0)
                ToastService.showError(I18n.tr("Suspend failed"), errorOutput.trim());
            errorOutput = "";
        }
    }

    Process {
        id: detectPrimeRunProcess
        running: false
        command: ["sh", "-c", "command -v prime-run"]

        onExited: function (exitCode) {
            if (exitCode === 0) {
                nvidiaCommand = "prime-run";
            } else {
                detectNvidiaOffloadProcess.running = true;
            }
        }
    }

    Process {
        id: detectNvidiaOffloadProcess
        running: false
        command: ["sh", "-c", "command -v nvidia-offload"]

        onExited: function (exitCode) {
            if (exitCode === 0) {
                nvidiaCommand = "nvidia-offload";
            }
        }
    }

    Process {
        id: uwsmLogout
        command: ["uwsm", "stop"]
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.trim().toLowerCase().includes("not running")) {
                    _logout();
                }
            }
        }

        onExited: function (exitCode) {
            if (exitCode === 0) {
                return;
            }
            _logout();
        }
    }

    function escapeShellArg(arg) {
        return "'" + arg.replace(/'/g, "'\\''") + "'";
    }

    function needsShellExecution(prefix) {
        if (!prefix || prefix.length === 0)
            return false;
        return /[;&|<>()$`\\"']/.test(prefix);
    }

    function parseEnvVars(text) {
        return ApplicationCommand.environment(text);
    }

    function isolatedApplicationCommand(appId, command, workDir, environment) {
        // Quickshell.execDetached() starts applications in the desktop session
        // cgroup. Unrelated applications then share one socket owner, making
        // per-application VPN routing impossible. Start every desktop entry as
        // a transient user service so the application and all of its helpers
        // inherit one dedicated app.slice cgroup before their first socket is
        // created.
        applicationLaunchSequence++;
        const safeId = (appId || "application").toString()
            .replace(/\.desktop$/i, "")
            .replace(/[^A-Za-z0-9_.-]/g, "-")
            .substring(0, 80) || "application";
        const unit = `app-kaskados-${safeId}-${Date.now()}-${applicationLaunchSequence}`;
        let wrapped = [
            "systemd-run",
            "--user",
            "--collect",
            "--quiet",
            "--service-type=exec",
            "--expand-environment=no",
            `--unit=${unit}`,
            `--working-directory=${workDir || Quickshell.env("HOME")}`
        ];
        const env = environment || {};
        for (const key of Object.keys(env))
            wrapped.push(`--setenv=${key}=${env[key]}`);
        const sessionKeys = [
            "DISPLAY",
            "WAYLAND_DISPLAY",
            "XAUTHORITY",
            "XDG_RUNTIME_DIR",
            "DBUS_SESSION_BUS_ADDRESS",
            "XDG_SESSION_TYPE",
            "XDG_CURRENT_DESKTOP",
            "DESKTOP_SESSION",
            "QT_QPA_PLATFORM"
        ];
        for (const key of sessionKeys) {
            if (env[key] !== undefined)
                continue;
            const value = Quickshell.env(key);
            if (value && value.length > 0)
                wrapped.push(`--setenv=${key}=${value}`);
        }
        wrapped.push("--");
        return wrapped.concat(command);
    }

    Component {
        id: applicationLauncherComponent
        Process {
            id: applicationLauncher
            property string applicationName: ""
            onExited: (exitCode, exitStatus) => {
                if (exitCode !== 0 || exitStatus !== 0)
                    ToastService.showError("Не удалось запустить приложение", applicationName + ": проверьте команду, рабочую папку и наличие программы. Код ошибки: " + exitCode);
                destroy();
            }
        }
    }

    function launchIsolatedApplication(appId, command, workDir, environment) {
        const process = applicationLauncherComponent.createObject(root, {
            applicationName: appId || "Приложение",
            command: isolatedApplicationCommand(appId, command, workDir, environment)
        });
        if (!process) {
            ToastService.showError("Не удалось запустить приложение", appId);
            return false;
        }
        process.running = true;
        return true;
    }

    function launchDesktopEntry(desktopEntry, useNvidia, forceNew) {
        return launchConfiguredApplication(desktopEntry, null, useNvidia, forceNew);
    }

    function launchDesktopAction(desktopEntry, action, useNvidia) {
        if (!action)
            return false;
        return launchConfiguredApplication(desktopEntry, action, useNvidia, true);
    }

    function launchConfiguredApplication(entry, action, useNvidia, forceNew) {
        if (!entry)
            return false;
        const appId = entry.id || entry.execString || entry.exec || "";
        const override = SessionData.getAppOverride(appId);
        let prepared;
        try {
            prepared = ApplicationCommand.prepare(entry, override, action);
        } catch (error) {
            ToastService.showError("Не удалось запустить приложение", String(error.message || error));
            return false;
        }
        // A new launch is required to apply explicitly requested GPU or edited
        // launch parameters; focusing an old process would silently ignore them.
        const editedLaunch = override && (override.command || override.extraFlags || override.envVars || override.workingDirectory || override.runInTerminal !== undefined || override.launchOnDgpu);
        if (!action && !forceNew && !useNvidia && !editedLaunch && CompositorService.activateExistingApp(appId))
            return true;

        let cmd = prepared.command;
        const dgpu = useNvidia || override?.launchOnDgpu;
        if (dgpu && nvidiaCommand)
            cmd = [nvidiaCommand].concat(cmd);
        const userPrefix = SettingsData.launchPrefix?.trim() || "";
        const prefix = userPrefix || Quickshell.env("KASKAD_DEFAULT_LAUNCH_PREFIX") || "";
        const workDir = prepared.workingDirectory || Quickshell.env("HOME");
        const cursorEnv = typeof SettingsData.getCursorEnvironment === "function" ? SettingsData.getCursorEnvironment() : {};
        const environment = Object.assign({}, cursorEnv, prepared.environment);

        // Preserve the existing explicit global shell-prefix contract. The
        // per-application command editor never introduces shell evaluation.
        if (prefix.length > 0 && needsShellExecution(prefix)) {
            cmd = ["sh", "-c", prefix + " " + cmd.map(arg => escapeShellArg(arg)).join(" ")];
        } else if (prefix.length > 0) {
            cmd = ApplicationCommand.parse(prefix).concat(cmd);
        }
        if (prepared.runInTerminal)
            cmd = [SessionData.resolveTerminal() || "xterm", "-e"].concat(cmd);
        return launchIsolatedApplication(appId, cmd, workDir, environment);
    }

    // * Session management
    function logout() {
        if (hasUwsm) {
            uwsmLogout.running = true;
        }
        _logout();
    }

    function _logout() {
        if (SettingsData.customPowerActionLogout.length === 0) {
            if (CompositorService.isKaskad) {
                log.info("Exiting the KaskadOS session");
                Qt.quit();
                return;
            }

            if (CompositorService.isNiri) {
                NiriService.quit();
                return;
            }

            if (CompositorService.isMango) {
                MangoService.quit();
                return;
            }

            if (CompositorService.isLabwc) {
                LabwcService.quit();
                return;
            }

            if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
                try {
                    I3.dispatch("exit");
                } catch (_) {}
                return;
            }

            HyprlandService.exit();
        } else {
            Quickshell.execDetached(["sh", "-c", SettingsData.customPowerActionLogout]);
        }
    }

    function powerManagerCommand(action) {
        if (isBSD)
            return bsdPowerCommand(action);
        const useLoginctl = isElogind || (loginctlCommandAvailable && !systemctlCommandAvailable);
        return [useLoginctl ? "loginctl" : "systemctl", action];
    }

    function bsdPowerCommand(action) {
        switch (action) {
        case "suspend":
        case "suspend-then-hibernate":
            return ["acpiconf", "-s", "3"];
        case "hibernate":
            return ["acpiconf", "-s", "4"];
        case "reboot":
            return ["shutdown", "-r", "now"];
        default:
            return ["shutdown", "-p", "now"];
        }
    }

    function suspend() {
        if (suspendProcess.running)
            return;
        suspendProcess.errorOutput = "";
        suspendProcess.command = SettingsData.customPowerActionSuspend.length === 0
            ? powerManagerCommand("suspend")
            : ["sh", "-c", SettingsData.customPowerActionSuspend];
        suspendProcess.running = true;
    }

    function hibernate() {
        hibernateProcess.errorOutput = "";
        if (SettingsData.customPowerActionHibernate.length > 0) {
            hibernateProcess.command = ["sh", "-c", SettingsData.customPowerActionHibernate];
        } else {
            hibernateProcess.command = powerManagerCommand("hibernate");
        }
        hibernateProcess.running = true;
    }

    function suspendThenHibernate() {
        Quickshell.execDetached(powerManagerCommand("suspend-then-hibernate"));
    }

    function suspendWithBehavior(behavior) {
        if (behavior === SettingsData.SuspendBehavior.Hibernate) {
            hibernate();
        } else if (behavior === SettingsData.SuspendBehavior.SuspendThenHibernate) {
            suspendThenHibernate();
        } else {
            suspend();
        }
    }

    function reboot() {
        if (SettingsData.customPowerActionReboot.length === 0) {
            Quickshell.execDetached(powerManagerCommand("reboot"));
        } else {
            Quickshell.execDetached(["sh", "-c", SettingsData.customPowerActionReboot]);
        }
    }

    function poweroff() {
        if (SettingsData.customPowerActionPowerOff.length === 0) {
            Quickshell.execDetached(powerManagerCommand("poweroff"));
        } else {
            Quickshell.execDetached(["sh", "-c", SettingsData.customPowerActionPowerOff]);
        }
    }

    // * Idle Inhibitor
    signal inhibitorChanged

    function enableIdleInhibit() {
        if (idleInhibited)
            return;
        idleInhibited = true;
        inhibitorChanged();
    }

    function disableIdleInhibit() {
        if (!idleInhibited)
            return;
        idleInhibited = false;
        inhibitorChanged();
    }

    function toggleIdleInhibit() {
        if (idleInhibited) {
            disableIdleInhibit();
        } else {
            enableIdleInhibit();
        }
    }

    function setInhibitReason(reason) {
        inhibitReason = reason;
    }

    Connections {
        target: KaskadService

        function onConnectionStateChanged() {
            if (KaskadService.isConnected) {
                checkKaskadCapabilities();
            } else {
                clearPrepareForSleepSubscriptionState();
            }
        }

        function onCapabilitiesReceived() {
            syncSleepInhibitor();
        }
    }

    Connections {
        target: KaskadService
        enabled: KaskadService.isConnected

        function onCapabilitiesChanged() {
            checkKaskadCapabilities();
        }

        function onDbusSignalReceived(subscriptionId, data) {
            if (subscriptionId !== prepareForSleepSubscriptionId) {
                return;
            }
            handlePrepareForSleepSignal(data);
        }
    }

    Connections {
        target: SettingsData

        function onLoginctlLockIntegrationChanged() {
            if (SettingsData.loginctlLockIntegration) {
                if (socketPath && socketPath.length > 0 && loginctlAvailable) {
                    if (!stateInitialized) {
                        stateInitialized = true;
                        getLoginctlState();
                        syncLockBeforeSuspend();
                    }
                }
            } else {
                stateInitialized = false;
            }
            syncSleepInhibitor();
        }

        function onLockBeforeSuspendChanged() {
            if (SettingsData.loginctlLockIntegration) {
                syncLockBeforeSuspend();
            }
            syncSleepInhibitor();
        }
    }

    Connections {
        target: KaskadService
        enabled: SettingsData.loginctlLockIntegration

        function onLoginctlStateUpdate(data) {
            updateLoginctlState(data);
        }
    }

    function checkKaskadCapabilities() {
        if (!KaskadService.isConnected) {
            return;
        }

        if (KaskadService.capabilities.length === 0) {
            return;
        }

        if (KaskadService.capabilities.includes("loginctl")) {
            loginctlAvailable = true;
            if (SettingsData.loginctlLockIntegration && !stateInitialized) {
                stateInitialized = true;
                getLoginctlState();
                syncLockBeforeSuspend();
            }
        } else {
            loginctlAvailable = false;
            log.debug("loginctl capability not available in Kaskad");
        }

        if (KaskadService.capabilities.includes("dbus")) {
            ensurePrepareForSleepSubscription();
        } else {
            clearPrepareForSleepSubscriptionState();
        }
    }

    function clearPrepareForSleepSubscriptionState() {
        prepareForSleepSubscriptionId = "";
        prepareForSleepSubscriptionPending = false;
    }

    function ensurePrepareForSleepSubscription() {
        if (!KaskadService.isConnected || !KaskadService.capabilities.includes("dbus")) {
            return;
        }

        if (prepareForSleepSubscriptionId || prepareForSleepSubscriptionPending) {
            return;
        }

        prepareForSleepSubscriptionPending = true;
        KaskadService.dbusSubscribe("system", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PrepareForSleep", response => {
            prepareForSleepSubscriptionPending = false;

            if (response.error) {
                log.warn("Failed to subscribe to PrepareForSleep:", response.error);
                return;
            }

            prepareForSleepSubscriptionId = response.result?.subscriptionId || "";
        });
    }

    function emitSessionResumedOnce() {
        const now = Date.now();
        if ((now - lastResumeSignalTimestamp) < 1000) {
            return;
        }
        lastResumeSignalTimestamp = now;
        sessionResumed();
    }

    function handlePrepareForSleepSignal(data) {
        if (!data?.body || data.body.length === 0) {
            return;
        }

        const wasSleeping = preparingForSleep;
        preparingForSleep = data.body[0] === true;

        if (wasSleeping && !preparingForSleep) {
            emitSessionResumedOnce();
        }
    }

    function getLoginctlState() {
        if (!loginctlAvailable)
            return;
        KaskadService.sendRequest("loginctl.getState", null, response => {
            if (response.result) {
                updateLoginctlState(response.result);
            }
        });
    }

    function syncLockBeforeSuspend() {
        if (!loginctlAvailable)
            return;
        KaskadService.sendRequest("loginctl.setLockBeforeSuspend", {
            enabled: SettingsData.lockBeforeSuspend
        }, response => {
            if (response.error) {
                log.warn("Failed to sync lock before suspend:", response.error);
            } else {
                log.debug("Synced lock before suspend:", SettingsData.lockBeforeSuspend);
            }
        });
    }

    function syncSleepInhibitor() {
        if (!loginctlAvailable)
            return;
        if (!KaskadService.apiVersion || KaskadService.apiVersion < 4)
            return;
        KaskadService.sendRequest("loginctl.setSleepInhibitorEnabled", {
            enabled: SettingsData.loginctlLockIntegration && SettingsData.lockBeforeSuspend
        }, response => {
            if (response.error) {
                log.warn("Failed to sync sleep inhibitor:", response.error);
            } else {
                log.debug("Synced sleep inhibitor:", SettingsData.loginctlLockIntegration);
            }
        });
    }

    function updateLoginctlState(state) {
        const wasLocked = locked;
        const wasSleeping = preparingForSleep;

        sessionId = state.sessionId || "";
        sessionPath = state.sessionPath || "";
        locked = state.locked || false;
        active = state.active || false;
        idleHint = state.idleHint || false;
        lockedHint = state.lockedHint || false;
        preparingForSleep = state.preparingForSleep || false;
        sessionType = state.sessionType || "";
        userName = state.userName || "";
        seat = state.seat || "";
        display = state.display || "";

        if (locked && !wasLocked) {
            sessionLocked();
        } else if (!locked && wasLocked) {
            sessionUnlocked();
        }

        if (wasSleeping && !preparingForSleep) {
            emitSessionResumedOnce();
        }

        loginctlStateChanged();
    }
}

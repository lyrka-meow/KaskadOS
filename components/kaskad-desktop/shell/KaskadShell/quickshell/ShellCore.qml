import QtQuick
import Quickshell
import Kaskad.Ipc
import qs.Common
import qs.Modules.KaskadBar
import qs.Modules.Frame
import qs.Modules.WorkspaceOverlays
import qs.Modals.Common
import qs.Services

Item {
    id: root

    readonly property var log: Log.scoped("ShellCore")

    property bool barSurfacesLoaded: true
    property int pendingFrameTransitionRevision: 0
    property bool frameSurfacesLoaded: true

    property alias kaskadBarRepeater: kaskadBarRepeater
    property alias hyprlandOverviewLoader: hyprlandOverviewLoader

    signal surfaceRecoveryPass

    Connections {
        target: Kaskad
        enabled: CompositorService.isKaskad

        function onMessageRequested(message, iconName, timeout) {
            ToastService.showInfo(message, "", "", "kaskad-osd", timeout);
        }

        function onMessageHideRequested() {
            ToastService.dismissCategory("kaskad-osd");
        }

        function onLogoutConfirmationRequested(applications) {
            const names = Array.from(applications || []);
            const applicationList = names.length > 0
                ? "\n\n• " + names.join("\n• ")
                : "";
            logoutConfirm.showWithOptions({
                title: I18n.tr("Applications are still running"),
                message: I18n.tr("The following applications did not close:")
                    + applicationList
                    + "\n\n"
                    + I18n.tr("KaskadOS will log out automatically in two minutes."),
                confirmText: I18n.tr("Log out anyway"),
                cancelText: I18n.tr("Cancel logout"),
                confirmColor: Theme.error,
                onConfirm: () => Kaskad.respondToLogoutConfirmation(true),
                onCancel: () => Kaskad.respondToLogoutConfirmation(false)
            });
        }

        function onLogoutConfirmationDismissed() {
            logoutConfirm.close();
        }

        function onUnresponsiveWindowRequested(windowId, title, appId, outputName) {
            const outputScreen = Quickshell.screens.find(screen => screen.name === outputName);
            unresponsiveWindowConfirm.targetScreen = outputScreen ?? Quickshell.screens[0];
            unresponsiveWindowConfirm.showForWindow(windowId, {
                title: I18n.tr("Application is not responding"),
                message: I18n.tr("%1 is not responding. You can wait for it to recover or force it to close.").arg(title || appId || I18n.tr("The application")),
                confirmText: I18n.tr("Force close"),
                cancelText: I18n.tr("Wait"),
                confirmColor: Theme.error,
                onConfirm: () => Kaskad.respondToUnresponsiveWindow(windowId, true),
                onCancel: () => Kaskad.respondToUnresponsiveWindow(windowId, false)
            });
        }

        function onUnresponsiveWindowDismissed(windowId) {
            if (unresponsiveWindowConfirm.windowId === windowId)
                unresponsiveWindowConfirm.close();
        }

        function onWindowActionPromptRequested(windowId, title, action, outputName, shortcut, shortcutSource) {
            const outputScreen = Quickshell.screens.find(screen => screen.name === outputName);
            windowActionConfirm.targetScreen = outputScreen ?? Quickshell.screens[0];
            const fullscreen = action === "fullscreen";
            let message = fullscreen
                ? I18n.tr("%1 is now fullscreen. If the application does not provide its own way to leave fullscreen, use the window controls.").arg(title || I18n.tr("The window"))
                : I18n.tr("%1 is now shown without a frame. Use the window controls to restore it.").arg(title || I18n.tr("The window"));
            if (shortcut) {
                message += shortcutSource === "action"
                    ? " " + I18n.tr("You can also use the %1 shortcut.").arg(shortcut)
                    : " " + I18n.tr("You can open the window menu with %1.").arg(shortcut);
            }
            windowActionConfirm.showForWindow(windowId, action, {
                title: fullscreen ? I18n.tr("Fullscreen enabled") : I18n.tr("Window frame hidden"),
                message: message,
                confirmText: I18n.tr("Keep"),
                cancelText: fullscreen ? I18n.tr("Undo fullscreen") : I18n.tr("Restore frame"),
                showDontAskAgain: true,
                dontAskAgainText: I18n.tr("Do not show these window warnings again"),
                onConfirm: dontAskAgain => Kaskad.respondToWindowActionPrompt(windowId, action, false, dontAskAgain),
                onCancel: dontAskAgain => Kaskad.respondToWindowActionPrompt(windowId, action, true, dontAskAgain)
            });
        }

        function onWindowActionPromptDismissed(windowId, action) {
            if (windowActionConfirm.windowId === windowId && windowActionConfirm.action === action)
                windowActionConfirm.close();
        }
    }

    ConfirmModal {
        id: logoutConfirm
        layerNamespace: "kaskados:logout-confirmation"
    }

    ConfirmModal {
        id: unresponsiveWindowConfirm
        property string windowId: ""
        layerNamespace: "kaskados:unresponsive-window"

        function showForWindow(id, options) {
            windowId = id;
            showWithOptions(options);
        }

        onDialogClosed: windowId = ""
    }

    ConfirmModal {
        id: windowActionConfirm
        property string windowId: ""
        property string action: ""
        layerNamespace: "kaskados:window-action-warning"

        function showForWindow(id, actionName, options) {
            windowId = id;
            action = actionName;
            showWithOptions(options);
        }

        onDialogClosed: {
            windowId = "";
            action = "";
        }
    }

    KaskadWindowMenu {
    }

    property string _barLayoutStateJson: {
        if (!barSurfacesLoaded)
            return "[]";
        const configs = SettingsData.barConfigs;
        const mapped = configs.map(c => ({
                    id: c.id,
                    position: c.position,
                    autoHide: c.autoHide,
                    visible: c.visible
                })).sort((a, b) => {
            const aVertical = a.position === SettingsData.Position.Left || a.position === SettingsData.Position.Right;
            const bVertical = b.position === SettingsData.Position.Left || b.position === SettingsData.Position.Right;
            if (aVertical !== bVertical) {
                return aVertical - bVertical;
            }
            return String(a.id).localeCompare(String(b.id));
        });
        return JSON.stringify(mapped);
    }

    function recreateBarSurfaces() {
        log.info("Recreating bar surfaces, screens:", Quickshell.screens.length, Quickshell.screens.map(s => s.name).join(","));
        if (barSurfacesLoaded)
            barSurfacesLoaded = false;
        barSurfaceReloadAction.schedule();
    }

    // Holds the bar rebuild until the compositor applies the layout, so the swap lands in one pass
    function runPendingFrameTransition() {
        if (pendingFrameTransitionRevision <= 0 || !CompositorService.frameCompositorLayoutReady)
            return;
        recreateBarSurfaces();
    }

    DeferredAction {
        id: barSurfaceReloadAction
        onTriggered: {
            // Ack first so the latch flips and new bars build directly in the post-transition state
            if (root.pendingFrameTransitionRevision > 0 && CompositorService.frameCompositorLayoutReady) {
                FrameTransitionState.acknowledge(root.pendingFrameTransitionRevision);
                root.pendingFrameTransitionRevision = 0;
            }
            root.barSurfacesLoaded = true;
        }
    }

    Connections {
        target: FrameTransitionState
        function onTransitionRequested(revision) {
            root.pendingFrameTransitionRevision = Math.max(root.pendingFrameTransitionRevision, revision);
            root.runPendingFrameTransition();
        }
    }

    Connections {
        target: CompositorService
        function onFrameCompositorLayoutReadyChanged() {
            root.runPendingFrameTransition();
        }
    }

    Connections {
        target: SettingsData
        function onForceKaskadBarLayoutRefresh() {
            root.recreateBarSurfaces();
        }
    }

    Loader {
        active: root.frameSurfacesLoaded
        asynchronous: false
        sourceComponent: Frame {}
    }

    Loader {
        active: FrameTransitionState.effectiveFrameEnabled && SettingsData.frameLauncherEdgeHover
        asynchronous: false
        sourceComponent: FrameLauncherHoverZone {}
    }

    DeferredAction {
        id: frameSurfaceReloadAction
        onTriggered: root.frameSurfacesLoaded = true
    }

    Repeater {
        id: kaskadBarRepeater
        model: ScriptModel {
            id: barRepeaterModel
            values: JSON.parse(root._barLayoutStateJson)
        }

        Component.onCompleted: BarWidgetService.kaskadBarRepeater = kaskadBarRepeater

        property var hyprlandOverviewLoaderRef: hyprlandOverviewLoader

        // Horizontal bars must claim their exclusive zones first, so vertical bars wait for every enabled horizontal bar to load
        readonly property int horizontalWanted: SettingsData.barConfigs.filter(c => (c.enabled ?? false) && c.position !== SettingsData.Position.Left && c.position !== SettingsData.Position.Right).length
        property int horizontalReady: 0

        function recountHorizontalReady() {
            let ready = 0;
            for (let i = 0; i < count; i++) {
                const loader = itemAt(i);
                if (loader?.item && !loader.isVertical)
                    ready++;
            }
            horizontalReady = ready;
        }

        delegate: Loader {
            id: barLoader
            required property var modelData
            property var barConfig: SettingsData.barConfigs.find(cfg => cfg.id === modelData.id) || null
            readonly property bool isVertical: modelData.position === SettingsData.Position.Left || modelData.position === SettingsData.Position.Right
            active: root.barSurfacesLoaded && (barConfig?.enabled ?? false) && (!isVertical || kaskadBarRepeater.horizontalReady >= kaskadBarRepeater.horizontalWanted)
            asynchronous: false
            onItemChanged: kaskadBarRepeater.recountHorizontalReady()

            sourceComponent: KaskadBar {
                barConfig: barLoader.barConfig
                hyprlandOverviewLoader: kaskadBarRepeater.hyprlandOverviewLoaderRef

                onColorPickerRequested: {
                    const modal = PopoutService.colorPickerModal;
                    if (!modal)
                        return;
                    if (modal.shouldBeVisible) {
                        modal.close();
                    } else {
                        modal.show();
                    }
                }
            }
        }
    }

    property bool hadRealScreen: true
    property var previousRealScreenNames: []
    // Guards for the screen-reconnect recovery path (see scheduleScreenReconnectRecovery).
    property bool _screenRecoveryCooldown: false
    property bool _screenRecoveryPending: false

    function _getRealScreenNames() {
        const names = [];
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name.length > 0)
                names.push(Quickshell.screens[i].name);
        }
        return names;
    }

    function _hasRealScreen() {
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name.length > 0)
                return true;
        }
        return false;
    }

    function triggerSurfaceRecovery(source) {
        log.info("Surface recovery triggered by:", source, "screens:", Quickshell.screens.length, Quickshell.screens.map(s => s.name).join(","), "barLoaded:", root.barSurfacesLoaded, "frameLoaded:", root.frameSurfacesLoaded);
        surfaceResumeRecoveryTimer.pass = 0;
        surfaceResumeRecoveryTimer.interval = 800;
        surfaceResumeRecoveryTimer.restart();
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            const hasReal = root._hasRealScreen();
            const currentNames = root._getRealScreenNames();
            log.info("Screens changed:", Quickshell.screens.length, Quickshell.screens.map(s => "'" + s.name + "'").join(","), "hasReal:", hasReal, "hadReal:", root.hadRealScreen);
            const fullReconnect = !root.hadRealScreen && hasReal;
            const partialReconnect = root.previousRealScreenNames.length > 0 && currentNames.some(name => !root.previousRealScreenNames.includes(name));
            if (fullReconnect || partialReconnect) {
                log.info("Screen reconnect detected, scheduling surface recovery", "full:", fullReconnect, "partial:", partialReconnect);
                root.scheduleScreenReconnectRecovery();
            }
            root.hadRealScreen = hasReal;
            root.previousRealScreenNames = currentNames;
        }
    }

    // A DPMS off/on cycle removes an output from the screen list and re-adds it,
    // which is indistinguishable here from a hotplug. Recovering immediately on
    // every such event lets a flapping monitor (or a recovery that itself perturbs
    // the output) drive an endless recovery storm that power-cycles the display
    // (#2642). Debounce a burst of changes into a single pass, then hold a cooldown
    // so repeated flaps trigger at most one recovery per window. Recovery still runs
    // once per resume, so a partial DPMS resume keeps redrawing its surfaces (#2579).
    function scheduleScreenReconnectRecovery() {
        if (root._screenRecoveryCooldown) {
            root._screenRecoveryPending = true;
            return;
        }
        screenReconnectDebounce.restart();
    }

    Timer {
        id: screenReconnectDebounce
        // Wide enough to collapse the output-remove + output-re-add pair that one
        // DPMS off/on cycle emits as two near-simultaneous events into one recovery.
        interval: 450
        repeat: false
        onTriggered: {
            root._screenRecoveryCooldown = true;
            root._screenRecoveryPending = false;
            screenReconnectCooldown.restart();
            root.triggerSurfaceRecovery("screen-reconnect");
        }
    }

    Timer {
        id: screenReconnectCooldown
        // Must exceed the full two-pass surfaceResumeRecoveryTimer sequence
        // (800 + 2000 ms) so the cooldown still covers an in-flight recovery;
        // raise this if those passes are lengthened.
        interval: 4000
        repeat: false
        onTriggered: {
            root._screenRecoveryCooldown = false;
            if (root._screenRecoveryPending) {
                root._screenRecoveryPending = false;
                screenReconnectDebounce.restart();
            }
        }
    }

    Timer {
        id: surfaceResumeRecoveryTimer
        interval: 800
        repeat: false
        property int pass: 0
        onTriggered: {
            pass++;
            log.info("Surface recovery pass", pass, "screens:", Quickshell.screens.length, Quickshell.screens.map(s => s.name).join(","));

            root.recreateBarSurfaces();

            if (root.frameSurfacesLoaded) {
                root.frameSurfacesLoaded = false;
                frameSurfaceReloadAction.schedule();
            }

            root.surfaceRecoveryPass();

            if (pass < 2) {
                interval = 2000;
                restart();
            } else {
                pass = 0;
                interval = 800;
            }
        }
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            log.info("Session resumed: screens:", Quickshell.screens.length, Quickshell.screens.map(s => s.name).join(","), "barLoaded:", root.barSurfacesLoaded, "frameLoaded:", root.frameSurfacesLoaded);

            // This path runs its own recovery directly, so drop any queued or
            // in-flight screen-reconnect recovery to avoid a redundant pass once
            // its cooldown expires.
            screenReconnectDebounce.stop();
            screenReconnectCooldown.stop();
            root._screenRecoveryCooldown = false;
            root._screenRecoveryPending = false;

            root.triggerSurfaceRecovery("sessionResumed");
        }
    }

    LazyLoader {
        id: hyprlandOverviewLoader
        active: CompositorService.isHyprland || CompositorService.isKaskad
        component: CompositorService.isKaskad ? kaskadOverviewComponent : hyprlandOverviewComponent
    }

    KaskadScreenCastChooser {}
    ScreenshotLauncher {}

    Component {
        id: hyprlandOverviewComponent

        HyprlandOverview {}
    }

    Component {
        id: kaskadOverviewComponent

        KaskadOverview {}
    }
}

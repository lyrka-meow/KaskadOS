pragma Singleton

import QtQuick
import Quickshell
import Kaskad.Ipc 1.0
import qs.Common
import qs.Services

Singleton {
    id: root

    readonly property bool ready: CompositorService.isKaskad && Kaskad.available
    property bool operationPending: false

    function scheduleSync() {
        if (ready)
            syncTimer.restart();
    }

    function workspaceHasWindow(workspaceId, outputName) {
        const windows = Array.from(Kaskad.windows || []);
        return windows.some(window => {
            if (!window || window.skipTaskbar)
                return false;
            return window.output === outputName && Array.from(window.workspaces || []).includes(workspaceId);
        });
    }

    function workspaceHasContent(workspaceId, outputName) {
        // Only an application window occupies a dynamic workspace. Shell
        // configuration is persisted separately and must not keep otherwise
        // empty workspace numbers visible forever.
        return workspaceHasWindow(workspaceId, outputName);
    }

    function sortedWorkspaces(outputName) {
        return SessionData.workspacesForOutput(outputName).sort((a, b) => a.position - b.position);
    }

    function createWorkspace(outputName, localNumber) {
        const id = Kaskad.createWorkspaceForOutput(
            Array.from(Kaskad.workspaces || []).length + 1,
            "Рабочий стол " + localNumber,
            outputName);
        if (id)
            SessionData.setWorkspaceOutput(id, outputName);
        return !!id;
    }

    function sync() {
        if (!ready || operationPending)
            return;

        SessionData.ensureWorkspaceOutputAssignments();
        // Disconnected monitors keep their compositor-owned workspace profile,
        // but they are not live targets. Do not create or prune desktops for
        // an output until it is enabled again.
        const outputs = Array.from(Kaskad.outputs || [])
            .filter(output => output && output.enabled !== false)
            .map(output => output.name)
            .filter(name => !!name);
        for (const outputName of outputs) {
            const workspaces = sortedWorkspaces(outputName);
            if (workspaces.length === 0) {
                operationPending = true;
                createWorkspace(outputName, 1);
                operationCooldown.restart();
                return;
            }

            // Every output always has its current workspace and one empty
            // workspace ready for the next task.
            if (workspaces.length < 2) {
                operationPending = true;
                createWorkspace(outputName, workspaces.length + 1);
                operationCooldown.restart();
                return;
            }

            const last = workspaces[workspaces.length - 1];
            const lastIsCurrent = Array.from(last.currentOutputs || []).includes(outputName);
            // GNOME-style dynamic workspaces, independently per output:
            // entering the last workspace immediately exposes one fresh empty
            // workspace after it. Atomic compositor assignment keeps that new
            // workspace on this output instead of leaking it to the primary.
            if (lastIsCurrent || workspaceHasContent(last.id, outputName)) {
                operationPending = true;
                createWorkspace(outputName, workspaces.length + 1);
                operationCooldown.restart();
                return;
            }

            if (workspaces.length > 2 && !lastIsCurrent) {
                const previous = workspaces[workspaces.length - 2];
                const previousIsCurrent = Array.from(previous.currentOutputs || []).includes(outputName);
                if (!previousIsCurrent && !workspaceHasContent(previous.id, outputName)) {
                    operationPending = true;
                    SessionData.forgetWorkspaceOutput(last.id);
                    Kaskad.removeWorkspace(last.id);
                    operationCooldown.restart();
                    return;
                }
            }
        }
    }

    Timer {
        id: syncTimer
        interval: 180
        repeat: false
        onTriggered: root.sync()
    }

    Timer {
        id: operationCooldown
        interval: 180
        repeat: false
        onTriggered: {
            root.operationPending = false;
            root.scheduleSync();
        }
    }

    Connections {
        target: Kaskad

        function onWorkspacesChanged() {
            root.scheduleSync();
        }

        function onWindowsChanged() {
            root.scheduleSync();
        }

        function onOutputsChanged() {
            // Hotplug is topology, not merely geometry. Every enabled output
            // needs its own current workspace before role-scoped panel and
            // dock placements can resolve on it.
            root.scheduleSync();
        }
    }

    Connections {
        target: SessionData

        function onPinnedAppsByWorkspaceChanged() {
            root.scheduleSync();
        }

        function onBarPinnedAppsByWorkspaceChanged() {
            root.scheduleSync();
        }

        function onBarWorkspaceContextsChanged() {
            root.scheduleSync();
        }

        function onDockWorkspaceContextsChanged() {
            root.scheduleSync();
        }
    }

    Component.onCompleted: scheduleSync()
    onReadyChanged: scheduleSync()
}

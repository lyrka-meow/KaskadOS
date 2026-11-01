import Quickshell
import QtQml
import Kaskad.Ipc 1.0

ShellRoot {
    Timer {
        interval: 100
        running: true

        onTriggered: {
            console.log("Kaskad outputs:", JSON.stringify(Kaskad.outputs))
            console.log("Kaskad workspaces:", JSON.stringify(Kaskad.workspaces))
            if (!Kaskad.available)
                throw new Error("Kaskad IPC is unavailable")
            if (Kaskad.protocolVersion !== 26)
                throw new Error("Unexpected protocol version: " + Kaskad.protocolVersion)
            if (!Kaskad.setCursorAccent("#a884ff"))
                throw new Error("Cursor accent could not be applied through Kaskad IPC")
            if (Kaskad.compositorVersion !== "0.1.0-dev")
                throw new Error("Unexpected compositor version: " + Kaskad.compositorVersion)
            if (Kaskad.outputs.length !== 1 || Kaskad.outputs[0].name !== "Virtual-0")
                throw new Error("Virtual output was not exposed")
            if (Kaskad.workspaces.length !== 1 || Kaskad.workspaces[0].name !== "Desktop 1")
                throw new Error("Default workspace was not exposed")
            if (!Array.from(Kaskad.workspaces[0].currentOutputs || []).includes("Virtual-0"))
                throw new Error("Topology snapshot did not pair Virtual-0 with its current workspace")
            if (Kaskad.keyboardLayouts.length < 1 || Kaskad.availableKeyboardLayouts.length < 1)
                throw new Error("Keyboard layouts were not exposed")

            const workspaceId = Kaskad.createWorkspace(2, "QML workspace")
            if (!workspaceId || !Kaskad.activateWorkspace(workspaceId))
                throw new Error("Workspace creation or activation failed")
            if (!Kaskad.renameWorkspace(workspaceId, "QML renamed"))
                throw new Error("Workspace rename failed")
            Kaskad.refresh()
            if (Kaskad.workspaces.length !== 2 || !Kaskad.workspaces.some(workspace => workspace.id === workspaceId && workspace.current && workspace.name === "QML renamed"))
                throw new Error("Workspace changes were not reflected in QML")
            if (!Kaskad.removeWorkspace(workspaceId))
                throw new Error("Workspace removal failed")

            console.log("Kaskad QML module smoke test passed")
            Qt.quit()
        }
    }
}

package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestKaskadWorkspaceFilterKeepsPinnedWindows(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Services/CompositorService.qml")
	if err != nil {
		t.Fatalf("read CompositorService.qml: %v", err)
	}

	qml := string(raw)
	if !strings.Contains(qml, "toplevel.onAllWorkspaces === true") {
		t.Fatal("Kaskad workspace filtering must keep windows pinned to all workspaces")
	}
	if !strings.Contains(qml, "workspaceIds.length === 0") {
		t.Fatal("Kaskad workspace filtering must support older all-workspace snapshots with an empty workspace list")
	}
}

func TestKaskadWindowSnapshotExposesPinnedState(t *testing.T) {
	raw, err := os.ReadFile("../../../../../compositor/src/kaskadipc.cpp")
	if err != nil {
		t.Fatalf("read kaskadipc.cpp: %v", err)
	}

	source := string(raw)
	if !strings.Contains(source, "{QStringLiteral(\"onAllWorkspaces\"), window->isOnAllDesktops()}") {
		t.Fatal("Kaskad IPC window snapshots must expose the all-workspaces state")
	}
	if !strings.Contains(source, "changed({QStringLiteral(\"workspaces\"), QStringLiteral(\"onAllWorkspaces\")})") {
		t.Fatal("Kaskad IPC must notify the shell when a window is pinned or unpinned")
	}
}

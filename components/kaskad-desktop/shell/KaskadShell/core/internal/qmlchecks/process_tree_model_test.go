package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestProcessMonitorUsesCompleteUnmergedProcessTree(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Services/DgopService.qml")
	if err != nil {
		t.Fatalf("read DgopService.qml: %v", err)
	}
	text := string(raw)
	for _, required := range []string{
		`cmd.push("--limit", "0")`,
		`cmd.push("--merge-children=false")`,
		`pid=,ppid=,state=,stat=,uid=,etimes=,nice=,cls=,psr=,unit=,uunit=,comm=`,
		`function categoryFor(proc, meta)`,
		`function descendantPids(pid)`,
		`function signalProcess(process, signal, includeTree)`,
		`"canControl": proc.username === UserInfoService.username && !isProtected`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("process model is missing required invariant %q", required)
		}
	}
	if strings.Contains(text, `cmd.push("--limit", "100")`) {
		t.Fatal("the process manager must not silently truncate the process list")
	}
}

func TestProcessActionsRespectOwnershipAndTreeBoundary(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Modules/ProcessList/ProcessContextMenu.qml")
	if err != nil {
		t.Fatalf("read ProcessContextMenu.qml: %v", err)
	}
	text := string(raw)
	for _, required := range []string{
		`processData?.canControl`,
		`DgopService.signalProcess(processData, "TERM", false)`,
		`DgopService.signalProcess(processData, "TERM", true)`,
		`DgopService.signalProcess(processData, "KILL", false)`,
		`DgopService.signalProcess(processData, "KILL", true)`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("process actions are missing required invariant %q", required)
		}
	}
	if strings.Contains(text, `processData.pid > 1000`) {
		t.Fatal("PID magnitude is not an authorization boundary")
	}
}

func TestProcessViewExposesOriginsAndHierarchy(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Modules/ProcessList/ProcessesView.qml")
	if err != nil {
		t.Fatalf("read ProcessesView.qml: %v", err)
	}
	text := string(raw)
	for _, required := range []string{
		`property var expandedTreePids`,
		`function toggleTree(pid)`,
		`"treeDepth": depth`,
		`process.category === processFilter`,
		`processItemRoot.process?.statusLabel`,
		`processItemRoot.process?.categoryLabel`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("process view is missing required invariant %q", required)
		}
	}
}

package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestUnresponsiveWindowControlStaysOwnedByCompositorAndShell(t *testing.T) {
	if _, err := os.Stat("../../../../../compositor/src/helpers/killer"); !os.IsNotExist(err) {
		t.Fatal("the legacy KDE killer helper sources must be deleted")
	}

	killPromptRaw, err := os.ReadFile("../../../../../compositor/src/killprompt.cpp")
	if err != nil {
		t.Fatalf("read killprompt.cpp: %v", err)
	}
	killPrompt := string(killPromptRaw)
	if strings.Contains(killPrompt, "kwin_killer_helper") || strings.Contains(killPrompt, "QProcess") {
		t.Fatal("the compositor must not launch the old KDE unresponsive-window UI helper")
	}
	if !strings.Contains(killPrompt, "requestUnresponsiveWindowAction") || !strings.Contains(killPrompt, "dismissUnresponsiveWindowRequest") {
		t.Fatal("the compositor must route unresponsive-window requests to the KaskadOS shell")
	}

	ipcRaw, err := os.ReadFile("../../../../../compositor/src/kaskadipc.cpp")
	if err != nil {
		t.Fatalf("read kaskadipc.cpp: %v", err)
	}
	ipc := string(ipcRaw)
	if !strings.Contains(ipc, "m_unresponsiveWindowRequests.remove(id)") ||
		!strings.Contains(ipc, "forceClose && window && window->isClient() && window->unresponsive()") ||
		!strings.Contains(ipc, "window->killWindow()") {
		t.Fatal("force-close must require a live compositor request for a still-unresponsive client")
	}

	shellRaw, err := os.ReadFile("../../../quickshell/ShellCore.qml")
	if err != nil {
		t.Fatalf("read ShellCore.qml: %v", err)
	}
	shell := string(shellRaw)
	if !strings.Contains(shell, "onUnresponsiveWindowRequested") ||
		!strings.Contains(shell, "Kaskad.respondToUnresponsiveWindow(windowId, true)") ||
		!strings.Contains(shell, "Kaskad.respondToUnresponsiveWindow(windowId, false)") {
		t.Fatal("QtkShell must offer both force-close and wait responses")
	}
}

func TestCompositorOsdIsRenderedByQtkShell(t *testing.T) {
	osdRaw, err := os.ReadFile("../../../../../compositor/src/osd.cpp")
	if err != nil {
		t.Fatalf("read osd.cpp: %v", err)
	}
	osd := string(osdRaw)
	if !strings.Contains(osd, "messageRequested") || !strings.Contains(osd, "messageHideRequested") {
		t.Fatal("compositor OSD events must be forwarded over the shell IPC")
	}
	if strings.Contains(osd, "QQmlComponent") || strings.Contains(osd, "QDialog") {
		t.Fatal("the compositor OSD bridge must not render its own interface")
	}

	if _, err := os.Stat("../../../../../compositor/src/onscreennotification.cpp"); !os.IsNotExist(err) {
		t.Fatal("the legacy compositor-owned OSD renderer must be deleted")
	}

	shellRaw, err := os.ReadFile("../../../quickshell/ShellCore.qml")
	if err != nil {
		t.Fatalf("read ShellCore.qml: %v", err)
	}
	shell := string(shellRaw)
	if !strings.Contains(shell, "onMessageRequested") ||
		!strings.Contains(shell, "ToastService.showInfo") ||
		!strings.Contains(shell, "onMessageHideRequested") ||
		!strings.Contains(shell, "ToastService.dismissCategory") {
		t.Fatal("QtkShell must own showing and hiding compositor OSD messages")
	}
}

func TestFrozenApplicationVisualFeedbackRemainsEnabled(t *testing.T) {
	raw, err := os.ReadFile("../../../../../compositor/src/plugins/frozenapp/package/contents/code/main.js")
	if err != nil {
		t.Fatalf("read frozenapp effect: %v", err)
	}

	effect := string(raw)
	if !strings.Contains(effect, "window.windowUnresponsiveChanged.connect") ||
		!strings.Contains(effect, "type: Effect.Saturation") {
		t.Fatal("unresponsive clients must still be visually desaturated")
	}
}

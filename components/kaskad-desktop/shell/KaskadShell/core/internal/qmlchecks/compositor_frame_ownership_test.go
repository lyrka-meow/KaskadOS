package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestFloatingApplicationsLeaveWindowChromeToCompositor(t *testing.T) {
	paths := []string{
		"../../../quickshell/Modals/Changelog/ChangelogModal.qml",
		"../../../quickshell/Modals/FileManagerWindow.qml",
		"../../../quickshell/Modals/Greeter/GreeterModal.qml",
		"../../../quickshell/Modals/KeybindsModalWindow.qml",
		"../../../quickshell/Modals/ProcessListModal.qml",
		"../../../quickshell/Modals/Settings/SettingsModal.qml",
		"../../../quickshell/Modals/WindowRuleModal.qml",
		"../../../quickshell/Modals/WorkspaceRenameModal.qml",
		"../../../quickshell/Modules/Notepad/NotepadPopoutWindow.qml",
		"../../../quickshell/Modules/Settings/DesktopWidgetBrowser.qml",
		"../../../quickshell/Modules/Settings/WidgetSelectionPopup.qml",
		"../../../quickshell/Modules/Settings/Widgets/AppBrowserPopup.qml",
	}

	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		text := string(raw)
		for _, legacyChrome := range []string{
			"FloatingWindowControls",
			"windowControls.tryStartMove",
			"windowControls.tryToggleMaximize",
		} {
			if strings.Contains(text, legacyChrome) {
				t.Errorf("%s still contains application-owned window chrome %q", path, legacyChrome)
			}
		}
	}

	if _, err := os.Stat("../../../quickshell/Widgets/FloatingWindowControls.qml"); !os.IsNotExist(err) {
		t.Fatal("the unused application-owned window chrome wrapper must stay deleted")
	}
}

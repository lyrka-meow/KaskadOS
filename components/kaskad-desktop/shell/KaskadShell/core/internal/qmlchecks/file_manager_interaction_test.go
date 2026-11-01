package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestFileManagerKeepsDesktopInteractionsAvailable(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Modals/FileManagerWindow.qml")
	if err != nil {
		t.Fatal(err)
	}
	qml := string(raw)
	for _, required := range []string{
		`title: "Файлы - KaskadOS"`,
		`sequence: StandardKey.Copy`,
		`sequence: StandardKey.Cut`,
		`sequence: StandardKey.Paste`,
		`sequence: StandardKey.Delete`,
		`sequence: "F3"`,
		`Drag.keys: ["kaskados-file-entry"]`,
		`FileManagerService.moveEntryTo`,
		`FileManagerService.currentPath || FileManagerService.homePath`,
		`primaryScrollPositions`,
		`onDirectoryListingReady`,
	} {
		if !strings.Contains(qml, required) {
			t.Errorf("file manager is missing %q", required)
		}
	}
	if strings.Contains(qml, `Файлы — KaskadOS`) {
		t.Error("file manager title still uses an em dash")
	}
}

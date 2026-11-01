package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestKeyboardLayoutWidgetUsesNativeKaskadState(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Modules/KaskadBar/Widgets/KeyboardLayoutName.qml")
	if err != nil {
		t.Fatalf("read KeyboardLayoutName.qml: %v", err)
	}

	qml := string(raw)
	for _, required := range []string{
		"import Kaskad.Ipc 1.0",
		"CompositorService.isKaskad",
		"Kaskad.keyboardLayouts",
		"Kaskad.currentKeyboardLayout",
		"Kaskad.setCurrentKeyboardLayout(next.index)",
	} {
		if !strings.Contains(qml, required) {
			t.Fatalf("native Kaskad keyboard layout integration is missing %q", required)
		}
	}
}

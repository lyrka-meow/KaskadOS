package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestPublicSurfacesUseCanonicalProductOrComponentName(t *testing.T) {
	paths := map[string]string{
		"../../../quickshell/Modules/Settings/AboutTab.qml":                         "KaskadOS",
		"../../../quickshell/Modals/Changelog/ChangelogContent.qml":                 "KaskadOS",
		"../../../quickshell/Services/SystemUpdateService.qml":                      "KaskadOS",
		"../../../quickshell/Services/DisplayService.qml":                           "KaskadOS",
		"../../../quickshell/Modals/Greeter/GreeterWelcomePage.qml":                 "KaskadOS",
		"../../../quickshell/Modals/Greeter/GreeterCompletePage.qml":                "KaskadOS",
		"../../../quickshell/Modules/Settings/DisplayConfig/NoBackendMessage.qml":   "KaskadOS",
		"../../../quickshell/Modules/Settings/DisplayConfig/DisplayConfigState.qml": "KaskadOS",
		"../../../quickshell/Modules/Settings/GammaControlTab.qml":                  "KaskadOS",
		"../../../assets/org.kaskados.Shell.desktop":                                "Kaskad DE",
		"../../../assets/org.kaskados.Notepad.desktop":                              "KaskadOS",
		"../../../assets/kaskad-shell-open.desktop":                                 "Kaskad Shell",
	}

	for path, expected := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		text := string(raw)
		if !strings.Contains(text, expected) {
			t.Errorf("%s does not expose canonical name %q", path, expected)
		}
		if strings.Contains(text, "KaskadDesktop") || strings.Contains(text, "KaskadShell") {
			t.Errorf("%s exposes a legacy implementation name", path)
		}
	}
}

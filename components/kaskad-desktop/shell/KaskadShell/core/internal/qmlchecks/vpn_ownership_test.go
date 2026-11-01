package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestRegaliaIsTheOnlyShellVPNBackend(t *testing.T) {
	files := []string{
		"../../go.mod",
		"../server/server.go",
		"../server/router.go",
		"../../../quickshell/Services/KaskadService.qml",
		"../../../quickshell/Modules/ControlCenter/Models/WidgetModel.qml",
		"../../../quickshell/Modules/ControlCenter/Components/DragDropGrid.qml",
		"../../../quickshell/Modules/ControlCenter/Components/DetailHost.qml",
	}
	for _, path := range files {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		text := string(raw)
		for _, forbidden := range []string{"TailscaleService", "TailscaleWidget", "tailscale."} {
			if strings.Contains(text, forbidden) {
				t.Errorf("%s still contains retired standalone VPN integration %q", path, forbidden)
			}
		}
	}

	for _, path := range []string{
		"../server/tailscale",
		"../../../quickshell/Services/TailscaleService.qml",
		"../../../quickshell/Modules/ControlCenter/BuiltinPlugins/TailscaleWidget.qml",
	} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Errorf("retired standalone VPN component still exists: %s", path)
		}
	}
}

func TestRetiredVPNWidgetIsMigratedOut(t *testing.T) {
	settingsData, err := os.ReadFile("../../../quickshell/Common/SettingsData.qml")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(settingsData), "settingsConfigVersion: 18") {
		t.Fatal("settings schema was not advanced for the retired VPN widget migration")
	}

	store, err := os.ReadFile("../../../quickshell/Common/settings/SettingsStore.js")
	if err != nil {
		t.Fatal(err)
	}
	text := string(store)
	if !strings.Contains(text, `widget.id !== "builtin_tailscale"`) ||
		!strings.Contains(text, "settings.configVersion = 17") {
		t.Fatal("settings migration does not remove the retired Tailscale widget")
	}
}

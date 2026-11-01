package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestKaskadScreenshotUsesBuiltInEngineAndProfiles(t *testing.T) {
	launcherPath := "../../../quickshell/Modules/WorkspaceOverlays/ScreenshotLauncher.qml"
	raw, err := os.ReadFile(launcherPath)
	if err != nil {
		t.Fatalf("read screenshot launcher: %v", err)
	}
	launcher := string(raw)
	for _, required := range []string{
		`["kaskad-shell", "screenshot"]`,
		`--no-clipboard`,
		`--no-file`,
		`--dir`,
		`--format`,
		`onScreenshotProfileRequested`,
	} {
		if !strings.Contains(launcher, required) {
			t.Errorf("screenshot launcher is missing %q", required)
		}
	}
	if strings.Contains(strings.ToLower(launcher), "flameshot") {
		t.Fatal("screenshot launcher still depends on Flameshot")
	}

	if _, err := os.Stat("../../../quickshell/Modules/WorkspaceOverlays/FlameshotLauncher.qml"); !os.IsNotExist(err) {
		t.Fatal("retired Flameshot launcher still exists")
	}

	settings, err := os.ReadFile("../../../quickshell/Common/SettingsData.qml")
	if err != nil {
		t.Fatalf("read screenshot settings: %v", err)
	}
	settingsText := string(settings)
	for _, required := range []string{
		`property var screenshotProfiles`,
		`"id": "quick-region"`,
		`"shortcut": "Super+Shift+S"`,
		`"clipboard": true`,
		`"saveFile": false`,
	} {
		if !strings.Contains(settingsText, required) {
			t.Errorf("screenshot profile settings are missing %q", required)
		}
	}
}

func TestScreenshotDefaultsDoNotRequirePrintScreen(t *testing.T) {
	paths := []string{
		"../config/embedded/hypr-binds.lua",
		"../config/embedded/mango-binds.conf",
		"../config/embedded/niri-binds.kdl",
	}
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		text := string(raw)
		if strings.Contains(text, "Print { screenshot") || strings.Contains(text, "XF86Launch1 { screenshot") {
			t.Errorf("%s still requires a dedicated screenshot key", path)
		}
		hasKaskadCommand := strings.Contains(text, "kaskad-shell screenshot") || strings.Contains(text, `"kaskad-shell" "screenshot"`)
		if !strings.Contains(strings.ToLower(text), "shift") || !hasKaskadCommand {
			t.Errorf("%s does not expose a keyboard-independent Kaskad screenshot shortcut", path)
		}
	}
}

func TestDisabledQuickProfileClearsItsGlobalShortcut(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Modules/WorkspaceOverlays/ScreenshotLauncher.qml")
	if err != nil {
		t.Fatalf("read screenshot launcher: %v", err)
	}
	if !strings.Contains(string(raw), `profile.enabled === false ? "" : (profile.shortcut || "")`) {
		t.Fatal("disabling the quick screenshot profile does not clear its registered shortcut")
	}
}

func TestKaskadScreenshotUsesNativeCompositorCapture(t *testing.T) {
	backend, err := os.ReadFile("../screenshot/kaskad_capture.go")
	if err != nil {
		t.Fatalf("read Kaskad screenshot backend: %v", err)
	}
	backendText := string(backend)
	for _, required := range []string{
		`org.kde.KWin.ScreenShot2`,
		`CaptureActiveWindow`,
		`CaptureArea`,
		`CaptureScreen`,
	} {
		if !strings.Contains(backendText, required) {
			t.Errorf("native Kaskad screenshot backend is missing %q", required)
		}
	}

	permissions, err := os.ReadFile("../../../../../compositor/src/utils/serviceutils.h")
	if err != nil {
		t.Fatalf("read compositor screenshot permissions: %v", err)
	}
	permissionsText := string(permissions)
	if !strings.Contains(permissionsText, `s_kaskadShellExecutable = QStringLiteral("kaskad-shell")`) ||
		!strings.Contains(permissionsText, `executableName == s_kaskadShellExecutable`) {
		t.Fatal("the compositor does not grant its first-party screenshot backend access to ScreenShot2")
	}
}

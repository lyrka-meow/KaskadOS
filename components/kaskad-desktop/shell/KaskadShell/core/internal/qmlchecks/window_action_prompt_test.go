package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestWindowActionWarningsAreOwnedByCompositorAndShell(t *testing.T) {
	if _, err := os.Stat("../../../../../compositor/src/useractionprompt.cpp"); !os.IsNotExist(err) {
		t.Fatal("the legacy compositor-owned prompt source must be deleted")
	}

	ipcRaw, err := os.ReadFile("../../../../../compositor/src/kaskadipc.cpp")
	if err != nil {
		t.Fatalf("read kaskadipc.cpp: %v", err)
	}
	ipc := string(ipcRaw)
	if !strings.Contains(ipc, "m_windowActionPrompts.value(id) != action") ||
		!strings.Contains(ipc, "window->isFullScreen()") ||
		!strings.Contains(ipc, "window->noBorder()") {
		t.Fatal("undo must be limited to the matching live compositor request and current window state")
	}
	if !strings.Contains(ipc, "requestWindowActionPrompt(window, QStringLiteral(\"fullscreen\"))") ||
		!strings.Contains(ipc, "requestWindowActionPrompt(window, QStringLiteral(\"noborder\"))") {
		t.Fatal("the real KaskadOS fullscreen and border actions must create shell-owned warnings")
	}

	shellRaw, err := os.ReadFile("../../../quickshell/ShellCore.qml")
	if err != nil {
		t.Fatalf("read ShellCore.qml: %v", err)
	}
	shell := string(shellRaw)
	if !strings.Contains(shell, "onWindowActionPromptRequested") ||
		!strings.Contains(shell, "respondToWindowActionPrompt(windowId, action, false, dontAskAgain)") ||
		!strings.Contains(shell, "respondToWindowActionPrompt(windowId, action, true, dontAskAgain)") {
		t.Fatal("QtkShell must offer both keep and undo responses")
	}
}

func TestLegacyInternalWindowMenuIsRemoved(t *testing.T) {
	paths := []string{
		"../../../../../compositor/CMakeLists.txt",
		"../../../../../compositor/src/CMakeLists.txt",
		"../../../../../compositor/src/useractions.cpp",
		"../../../../../compositor/src/workspace.cpp",
		"../../../../../compositor/src/workspace.h",
		"../../../../../compositor/src/scripting/scripting.cpp",
		"../../../../../compositor/src/scripting/scripting.h",
	}
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		text := string(raw)
		for _, forbidden := range []string{"KASKAD_BUILD_INTERNAL_UI", "UserActionsMenu", "registerUserActionsMenu", "ShortcutDialog"} {
			if strings.Contains(text, forbidden) {
				t.Fatalf("%s still contains removed internal UI symbol %q", path, forbidden)
			}
		}
	}

	for _, path := range []string{
		"../../../../../compositor/src/useractions.h",
		"../../../../../compositor/src/useractionprompt.h",
		"../../../../../compositor/src/shortcutdialog.ui",
	} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("legacy internal UI file must be deleted: %s", path)
		}
	}
}

func TestLegacyWindowActionDialogHelperIsOutsideBuildGraph(t *testing.T) {
	if _, err := os.Stat("../../../../../compositor/src/helpers/CMakeLists.txt"); !os.IsNotExist(err) {
		t.Fatal("the legacy compositor helper sources must be deleted")
	}

	cmakeRaw, err := os.ReadFile("../../../../../compositor/src/CMakeLists.txt")
	if err != nil {
		t.Fatalf("read compositor CMakeLists.txt: %v", err)
	}
	if strings.Contains(string(cmakeRaw), "KWIN_DIALOG_BIN") {
		t.Fatal("the compositor must not retain a binary path for the old dialog helper")
	}
}

func TestLogoutConfirmationIsRenderedByQtkShell(t *testing.T) {
	smRaw, err := os.ReadFile("../../../../../compositor/src/sm.cpp")
	if err != nil {
		t.Fatalf("read sm.cpp: %v", err)
	}
	sm := string(smRaw)
	if strings.Contains(sm, "KNotification") || !strings.Contains(sm, "logoutConfirmationRequested") {
		t.Fatal("logout confirmation must be an IPC request, not compositor-owned KDE UI")
	}

	shellRaw, err := os.ReadFile("../../../quickshell/ShellCore.qml")
	if err != nil {
		t.Fatalf("read ShellCore.qml: %v", err)
	}
	shell := string(shellRaw)
	if !strings.Contains(shell, "onLogoutConfirmationRequested") ||
		!strings.Contains(shell, "respondToLogoutConfirmation(true)") ||
		!strings.Contains(shell, "respondToLogoutConfirmation(false)") {
		t.Fatal("QtkShell must own both logout confirmation responses")
	}
}

func TestCompositorHasFixedNativeOutlineAndNoLegacyKdeUiTrees(t *testing.T) {
	for _, path := range []string{
		"../../../../../compositor/src/qml/outline/outline.qml",
		"../../../../../compositor/src/kcms/CMakeLists.txt",
		"../../../../../compositor/src/tabbox/CMakeLists.txt",
		"../../../../../compositor/src/plugins/overview/CMakeLists.txt",
		"../../../../../compositor/src/plugins/windowview/CMakeLists.txt",
		"../../../../../compositor/src/plugins/keynotification/CMakeLists.txt",
	} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("legacy UI source tree must be deleted: %s", path)
		}
	}

	outlineRaw, err := os.ReadFile("../../../../../compositor/src/outline.cpp")
	if err != nil {
		t.Fatalf("read outline.cpp: %v", err)
	}
	outline := string(outlineRaw)
	if strings.Contains(outline, "QQmlComponent") || strings.Contains(outline, "QStandardPaths") ||
		!strings.Contains(outline, "OutlinedBorderItem") || !strings.Contains(outline, "accentColor") {
		t.Fatal("the selection outline must be fixed native compositor rendering with the KaskadOS accent")
	}
}

func TestWindowAccentOutlineCanBeDisabledFromSettings(t *testing.T) {
	settingsRaw, err := os.ReadFile("../../../quickshell/Common/SettingsData.qml")
	if err != nil {
		t.Fatalf("read SettingsData.qml: %v", err)
	}
	settings := string(settingsRaw)
	if !strings.Contains(settings, "property bool windowOutlineEnabled: false") ||
		!strings.Contains(settings, "onWindowOutlineEnabledChanged: saveSettings()") {
		t.Fatal("the window outline preference must be persisted and disabled by default")
	}
	specRaw, err := os.ReadFile("../../../quickshell/Common/settings/SettingsSpec.js")
	if err != nil {
		t.Fatalf("read SettingsSpec.js: %v", err)
	}
	if !strings.Contains(string(specRaw), "windowOutlineEnabled: { def: false }") {
		t.Fatal("the window outline preference must be registered in SettingsSpec so the toggle can change it")
	}
	headerRaw, err := os.ReadFile("../../../../../compositor/src/decorations/decorationbridge.h")
	if err != nil {
		t.Fatalf("read decorationbridge.h: %v", err)
	}
	if !strings.Contains(string(headerRaw), "bool m_outlineEnabled = false;") {
		t.Fatal("the compositor fallback must keep the window outline disabled for new profiles")
	}

	shellRaw, err := os.ReadFile("../../../quickshell/shell.qml")
	if err != nil {
		t.Fatalf("read shell.qml: %v", err)
	}
	shell := string(shellRaw)
	if !strings.Contains(shell, `"outlineEnabled": SettingsData.windowOutlineEnabled`) {
		t.Fatal("the shell must send the window outline preference to the compositor")
	}

	bridgeRaw, err := os.ReadFile("../../../../../compositor/src/decorations/decorationbridge.cpp")
	if err != nil {
		t.Fatalf("read decorationbridge.cpp: %v", err)
	}
	bridge := string(bridgeRaw)
	if !strings.Contains(bridge, `group.writeEntry("OutlineEnabled", m_outlineEnabled)`) ||
		!strings.Contains(bridge, `palette.value(QStringLiteral("outlineEnabled")).toBool()`) {
		t.Fatal("the compositor must apply and persist the window outline preference")
	}

	decorationRaw, err := os.ReadFile("../../../../../compositor/src/decorations/kaskaddecoration.cpp")
	if err != nil {
		t.Fatalf("read kaskaddecoration.cpp: %v", err)
	}
	decoration := string(decorationRaw)
	if !strings.Contains(decoration, "m_bridge->outlineEnabled() ? visualBorder : 0.0") {
		t.Fatal("disabling the preference must remove the native outline layer")
	}
}

func TestScriptedEffectsAreRestrictedToBuiltInPackages(t *testing.T) {
	loaderRaw, err := os.ReadFile("../../../../../compositor/src/effect/effectloader.cpp")
	if err != nil {
		t.Fatalf("read effectloader.cpp: %v", err)
	}
	loader := string(loaderRaw)
	if !strings.Contains(loader, "s_internalScriptedEffects") ||
		!strings.Contains(loader, "QCoreApplication::applicationDirPath()") ||
		!strings.Contains(loader, "canonicalFilePath()") {
		t.Fatal("scripted effects must be allowlisted and loaded from the installed compositor tree")
	}

	quickRaw, err := os.ReadFile("../../../../../compositor/src/scripting/scriptedquicksceneeffect.cpp")
	if err != nil {
		t.Fatalf("read scriptedquicksceneeffect.cpp: %v", err)
	}
	quick := string(quickRaw)
	if strings.Contains(quick, "QStandardPaths::locate") || !strings.Contains(quick, "metaData.fileName()") {
		t.Fatal("effect configuration must not be overridden through user data paths")
	}
}

package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestKaskadSurfacePlacementHasOneRuntimeAuthority(t *testing.T) {
	sessionRaw, err := os.ReadFile("../../../quickshell/Common/SessionData.qml")
	if err != nil {
		t.Fatalf("read SessionData.qml: %v", err)
	}
	session := string(sessionRaw)
	for _, contract := range []string{
		`readonly property int sessionConfigVersion: 11`,
		`values.includes("all::" + slot)`,
		`values.includes("primary::" + slot)`,
		`function reconcileBarScreenPreferences`,
		`function reconcileDockScreenPreferences`,
	} {
		if !strings.Contains(session, contract) {
			t.Fatalf("stable multi-monitor surface contract is missing %q", contract)
		}
	}

	barRaw, err := os.ReadFile("../../../quickshell/Modules/KaskadBar/KaskadBar.qml")
	if err != nil {
		t.Fatalf("read KaskadBar.qml: %v", err)
	}
	bar := string(barRaw)
	if !strings.Contains(bar, `if (CompositorService.isKaskad)`) ||
		!strings.Contains(bar, `SessionData.isBarVisibleInContext(root.barConfig?.id || "", screen.name)`) {
		t.Fatal("Kaskad panel instances must be selected by SessionData surface contexts")
	}

	settingsRaw, err := os.ReadFile("../../../quickshell/Common/SettingsData.qml")
	if err != nil {
		t.Fatalf("read SettingsData.qml: %v", err)
	}
	settings := string(settingsRaw)
	if !strings.Contains(settings, `SessionData.reconcileBarScreenPreferences(barId, newScreenPreferences)`) {
		t.Fatal("changing a panel screen scope must atomically reconcile its stable contexts")
	}

	displayRaw, err := os.ReadFile("../../../quickshell/Modules/Settings/DisplayWidgetsTab.qml")
	if err != nil {
		t.Fatalf("read DisplayWidgetsTab.qml: %v", err)
	}
	if !strings.Contains(string(displayRaw), `SessionData.reconcileDockScreenPreferences(screenNames)`) {
		t.Fatal("changing the dock screen scope must atomically reconcile its stable contexts")
	}
}

func TestSurfaceContextSchemaMigratesToRoleScopes(t *testing.T) {
	storeRaw, err := os.ReadFile("../../../quickshell/Common/settings/SessionStore.js")
	if err != nil {
		t.Fatalf("read SessionStore.js: %v", err)
	}
	store := string(storeRaw)
	if !strings.Contains(store, "if (version < 11)") ||
		!strings.Contains(store, "session.surfaceContextScopeMigrationDone = false") {
		t.Fatal("old physical surface contexts must receive the role-scope migration")
	}
}

func TestHotplugKeepsPrimaryRoleStableAndCreatesOutputWorkspaces(t *testing.T) {
	dynamicRaw, err := os.ReadFile("../../../quickshell/Services/DynamicWorkspaceService.qml")
	if err != nil {
		t.Fatalf("read DynamicWorkspaceService.qml: %v", err)
	}
	dynamic := string(dynamicRaw)
	if !strings.Contains(dynamic, "function onOutputsChanged()") ||
		!strings.Contains(dynamic, "root.scheduleSync()") ||
		!strings.Contains(dynamic, "createWorkspace(outputName, 1)") {
		t.Fatal("hotplugged outputs must trigger creation of their own dynamic workspaces")
	}

	compositorRaw, err := os.ReadFile("../../../quickshell/Services/CompositorService.qml")
	if err != nil {
		t.Fatalf("read CompositorService.qml: %v", err)
	}
	compositor := string(compositorRaw)
	if !strings.Contains(compositor, "output.enabled !== false && output.primary") ||
		!strings.Contains(compositor, "getScreenByName(authoritative?.name") {
		t.Fatal("the primary role must follow the compositor, not Quickshell screen enumeration order")
	}
}

func TestLayoutProfilesRoundTripPanelAndDockContexts(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Services/LayoutProfileService.qml")
	if err != nil {
		t.Fatalf("read LayoutProfileService.qml: %v", err)
	}
	qml := string(raw)
	for _, contract := range []string{
		"readonly property int formatVersion: 2",
		"barWorkspaceContexts: clone(SessionData.barWorkspaceContexts",
		"workspaceContexts: clone(SessionData.dockWorkspaceContexts",
		"SessionData.reconcileBarScreenPreferences",
		"SessionData.reconcileDockScreenPreferences",
	} {
		if !strings.Contains(qml, contract) {
			t.Fatalf("layout profile monitor placement contract is missing %q", contract)
		}
	}
}

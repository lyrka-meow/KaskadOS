package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestKaskadBarDoesNotDisableWidgetTreeWhenAutoHideIsOff(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Modules/KaskadBar/KaskadBarWindow.qml")
	if err != nil {
		t.Fatalf("read KaskadBarWindow.qml: %v", err)
	}

	qml := string(raw)
	if strings.Contains(qml, "enabled: (barConfig?.autoHide ?? false) && !inOverview") {
		t.Fatal("topBarMouseArea must not disable the complete widget tree when auto-hide is off")
	}
	if !strings.Contains(qml, "id: topBarMouseArea") || !strings.Contains(qml, "enabled: true") {
		t.Fatal("the bar content parent must remain enabled so widgets receive pointer input")
	}
}

func TestVpnDetailLetsColumnComputeItsImplicitHeight(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/Widgets/VpnDetailContent.qml")
	if err != nil {
		t.Fatalf("read VpnDetailContent.qml: %v", err)
	}

	qml := string(raw)
	if strings.Contains(qml, "implicitHeight: statusCard.height + actions.height + spacing") {
		t.Fatal("Column.implicitHeight is read-only; assigning it prevents KaskadShell and every panel popout from loading")
	}
}

func TestShellCompilesKaskadShellAsATypedComponent(t *testing.T) {
	raw, err := os.ReadFile("../../../quickshell/shell.qml")
	if err != nil {
		t.Fatalf("read shell.qml: %v", err)
	}

	qml := string(raw)
	if strings.Contains(qml, "source: \"KaskadShell.qml\"") {
		t.Fatal("KaskadShell must be a typed sourceComponent so dependency errors fail visibly instead of leaving a decorative but inert panel")
	}
	if !strings.Contains(qml, "sourceComponent: Component {") || !strings.Contains(qml, "KaskadShell {}") {
		t.Fatal("shell.qml must instantiate KaskadShell through a typed sourceComponent")
	}
}

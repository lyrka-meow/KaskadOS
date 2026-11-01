package qmlchecks

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestGPUUsageWidgetUsesDynamicDeviceSelection(t *testing.T) {
	_, filename, _, _ := runtime.Caller(0)
	qmlRoot := filepath.Join(filepath.Dir(filename), "..", "..", "..", "quickshell")

	assertContains := func(relative string, required ...string) {
		t.Helper()
		content, err := os.ReadFile(filepath.Join(qmlRoot, relative))
		if err != nil {
			t.Fatalf("read %s: %v", relative, err)
		}
		text := string(content)
		for _, value := range required {
			if !strings.Contains(text, value) {
				t.Errorf("%s does not contain %q", relative, value)
			}
		}
	}

	assertContains("Services/GpuUsageService.qml", "gpu.getState", "property var devices", "interval: 1000")
	assertContains("Modules/KaskadBar/Widgets/GpuUsage.qml", "gpuDeviceIds", "GpuUsageService.devices", "visibleDevices.length > 1")
	assertContains("Modules/Settings/WidgetsTab.qml", `"id": "gpuUsage"`, "gpuDeviceIds")
	assertContains("Modules/Settings/WidgetsTabSection.qml", "gpuDevicesChanged", "All detected graphics processors")
	assertContains("Modules/KaskadBar/KaskadBarContent.qml", `"gpuUsage": gpuUsageComponent`, "GpuUsage {")
}

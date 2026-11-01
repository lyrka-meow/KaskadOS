package network

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestInspectHotspotRuntime(t *testing.T) {
	for _, test := range []struct {
		name, missing, processName, forwarding, status string
		stale, enabled                                 bool
		want                                           string
	}{
		{name: "healthy", enabled: true, want: "active"},
		{name: "hostapd crashed", missing: "proc/123/comm", want: "degraded"},
		{name: "dnsmasq crashed", missing: "proc/456/comm", enabled: true, want: "degraded"},
		{name: "interface disappeared", missing: "net/kaskad-ap", want: "degraded"},
		{name: "PID reused", processName: "sleep", want: "degraded"},
		{name: "forwarding reset", forwarding: "0", enabled: true, want: "degraded"},
		{name: "routing repair failed", status: "degraded\nНе удалось восстановить передачу интернета.\n", enabled: true, want: "degraded"},
		{name: "routing never confirmed", status: "starting\n", enabled: true, want: "degraded"},
		{name: "watchdog stopped", stale: true, enabled: true, want: "degraded"},
	} {
		t.Run(test.name, func(t *testing.T) {
			root := t.TempDir()
			runtimeDirectory := filepath.Join(root, "run")
			write := func(name, content string) {
				t.Helper()
				path := filepath.Join(root, name)
				if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(path, []byte(content), 0644); err != nil {
					t.Fatal(err)
				}
			}
			write("run/active", "kaskad-ap\n")
			write("run/hostapd.pid", "123\n")
			write("run/dnsmasq.pid", "456\n")
			write("proc/123/comm", "hostapd\n")
			write("proc/456/comm", "dnsmasq\n")
			write("proc/123/cmdline", "hostapd\x00"+runtimeDirectory+"/hostapd.conf\x00")
			write("proc/456/cmdline", "dnsmasq\x00--pid-file="+runtimeDirectory+"/dnsmasq.pid\x00")
			write("proc/sys/net/ipv4/ip_forward", "1\n")
			write("status", "active\n\n")
			write("net/kaskad-ap", "")
			if test.missing != "" {
				if err := os.Remove(filepath.Join(root, test.missing)); err != nil {
					t.Fatal(err)
				}
			}
			if test.processName != "" {
				write("proc/123/comm", test.processName)
			}
			if test.forwarding != "" {
				write("proc/sys/net/ipv4/ip_forward", test.forwarding)
			}
			if test.status != "" {
				write("status", test.status)
			}
			now := time.Now()
			if test.stale {
				now = now.Add(time.Minute)
			}
			health := inspectHotspotRuntime(runtimeDirectory, filepath.Join(root, "status"), filepath.Join(root, "proc"), filepath.Join(root, "net"), now)
			if !health.Managed || health.Enabled != test.enabled || health.Status != test.want {
				t.Fatalf("unexpected health: %+v", health)
			}
			if test.want == "degraded" && health.Message == "" {
				t.Fatal("a failure needs a useful message")
			}
		})
	}
}

func TestInspectHotspotRuntimeKeepsCrashReasonAfterCleanup(t *testing.T) {
	root := t.TempDir()
	statusPath := filepath.Join(root, "status")
	if err := os.WriteFile(statusPath, []byte("degraded\nРаздача остановилась.\n"), 0644); err != nil {
		t.Fatal(err)
	}
	health := inspectHotspotRuntime(filepath.Join(root, "missing"), statusPath, root, root, time.Now())
	if health.Managed || health.Enabled || health.Status != "degraded" || health.Message != "Раздача остановилась." {
		t.Fatalf("unexpected cleaned health: %+v", health)
	}
}

func TestHotspotProcessAliveRejectsAnotherDaemon(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "123"), 0755); err != nil {
		t.Fatal(err)
	}
	for path, content := range map[string]string{
		"dnsmasq.pid": "123", "123/comm": "dnsmasq", "123/cmdline": "dnsmasq\x00--conf-file=/etc/dnsmasq.conf",
	} {
		if err := os.WriteFile(filepath.Join(root, path), []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	if hotspotProcessAlive(root, root, "dnsmasq") {
		t.Fatal("a reused PID belonging to a different dnsmasq instance is not our hotspot")
	}
}

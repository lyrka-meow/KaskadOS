package network

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	hotspotRuntimeDirectory = "/run/kaskados-hotspot"
	hotspotRuntimeStatus    = "/run/kaskados-hotspot.status"
)

type hotspotRuntimeHealth struct {
	Managed bool
	Enabled bool
	Status  string
	Message string
}

func hotspotProcessAlive(runtimeDirectory, procRoot, service string) bool {
	pidBytes, err := os.ReadFile(filepath.Join(runtimeDirectory, service+".pid"))
	if err != nil {
		return false
	}
	pid := strings.TrimSpace(string(pidBytes))
	pidNumber, err := strconv.Atoi(pid)
	if err != nil || pidNumber <= 1 {
		return false
	}
	processDirectory := filepath.Join(procRoot, pid)
	name, err := os.ReadFile(filepath.Join(processDirectory, "comm"))
	if err != nil || strings.TrimSpace(string(name)) != service {
		return false
	}
	command, err := os.ReadFile(filepath.Join(processDirectory, "cmdline"))
	return err == nil && strings.Contains(string(command), runtimeDirectory+"/")
}

// Read-only: the root-owned helper maintains forwarding; the desktop reports
// local failures without invoking polkit, restarting clients, or probing users.
func inspectHotspotRuntime(runtimeDirectory, statusPath, procRoot, netRoot string, now time.Time) hotspotRuntimeHealth {
	health := hotspotRuntimeHealth{Status: "stopped"}
	_, err := os.Stat(runtimeDirectory)
	health.Managed = err == nil
	status, statusErr := os.ReadFile(statusPath)
	routingConfirmed := false
	if statusErr == nil {
		lines := strings.SplitN(strings.TrimSpace(string(status)), "\n", 2)
		routingConfirmed = lines[0] == "active"
		if lines[0] == "degraded" {
			health.Status = "degraded"
			if len(lines) == 2 {
				health.Message = lines[1]
			}
		}
	}
	if !health.Managed {
		return health
	}
	active, err := os.ReadFile(filepath.Join(runtimeDirectory, "active"))
	if err != nil || strings.TrimSpace(string(active)) != kaskadShellHotspotVirtualIface {
		health.Status = "degraded"
		health.Message = "Раздача не завершила запуск. Включите её ещё раз."
		return health
	}
	_, interfaceErr := os.Stat(filepath.Join(netRoot, kaskadShellHotspotVirtualIface))
	health.Enabled = interfaceErr == nil && hotspotProcessAlive(runtimeDirectory, procRoot, "hostapd")
	if !health.Enabled {
		health.Status = "degraded"
		health.Message = "Раздача остановилась. Включите её ещё раз."
		return health
	}
	if !hotspotProcessAlive(runtimeDirectory, procRoot, "dnsmasq") {
		health.Status = "degraded"
		health.Message = "Точка доступа включена, но служба адресов и DNS остановилась. Включите раздачу заново."
		return health
	}
	forwarding, err := os.ReadFile(filepath.Join(procRoot, "sys/net/ipv4/ip_forward"))
	if err != nil || strings.TrimSpace(string(forwarding)) != "1" {
		health.Status = "degraded"
		health.Message = "Передача интернета отключена. Ожидается автоматическое восстановление."
		return health
	}
	if health.Status == "degraded" {
		return health
	}
	info, err := os.Stat(statusPath)
	if err != nil || !routingConfirmed || now.Sub(info.ModTime()) > 45*time.Second {
		health.Status = "degraded"
		health.Message = "Состояние передачи интернета не подтверждено. Перезапустите раздачу."
		return health
	}
	health.Status = "active"
	return health
}

func currentHotspotRuntimeHealth() hotspotRuntimeHealth {
	return inspectHotspotRuntime(hotspotRuntimeDirectory, hotspotRuntimeStatus, "/proc", "/sys/class/net", time.Now())
}

func externalHotspotRunning() bool {
	return currentHotspotRuntimeHealth().Enabled
}

func (b *NetworkManagerBackend) refreshHotspotHealth() {
	b.stateMutex.RLock()
	previousStatus, previousMessage := b.state.HotspotStatus, b.state.HotspotStatusMessage
	previousEnabled := b.state.HotspotEnabled
	b.stateMutex.RUnlock()
	if err := b.updateHotspotState(); err != nil {
		return
	}
	b.stateMutex.RLock()
	changed := previousStatus != b.state.HotspotStatus || previousMessage != b.state.HotspotStatusMessage || previousEnabled != b.state.HotspotEnabled
	b.stateMutex.RUnlock()
	if changed && b.onStateChange != nil {
		b.onStateChange()
	}
}

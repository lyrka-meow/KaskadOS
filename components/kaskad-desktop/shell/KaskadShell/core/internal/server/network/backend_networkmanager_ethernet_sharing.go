package network

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
)

const (
	kaskadEthernetSharingConnectionID = "Kaskad Ethernet Sharing"
	kaskadEthernetSharingStableID     = "kaskad-ethernet-sharing"
	kaskadEthernetRestoreUUIDKey      = "org.kaskados.restore-uuid"
	kaskadEthernetUseVPNKey           = "org.kaskados.use-vpn"
	ethernetSharingCheckpointSeconds  = 30
)

var _ EthernetSharingBackend = (*NetworkManagerBackend)(nil)

// SetEthernetSharing switches one physical Ethernet adapter into
// NetworkManager's native shared IPv4 mode. The user's ordinary wired profile
// is never edited: Kaskad owns a separate profile and stores the UUID that was
// active before sharing so disabling the mode can restore it.
func (b *NetworkManagerBackend) SetEthernetSharing(enabled bool, interfaceName string, useVPN bool) error {
	b.ethernetSharingMu.Lock()
	defer b.ethernetSharingMu.Unlock()

	if enabled {
		return b.enableEthernetSharing(interfaceName, useVPN)
	}
	return b.disableEthernetSharing()
}

func (b *NetworkManagerBackend) enableEthernetSharing(interfaceName string, useVPN bool) error {
	b.stateMutex.RLock()
	wifiConnected := b.state.WiFiConnected
	alreadyEnabled := b.state.EthernetSharingEnabled
	b.stateMutex.RUnlock()
	if alreadyEnabled {
		return nil
	}
	if !wifiConnected {
		return errors.New("сначала подключитесь к Wi‑Fi — он будет источником интернета")
	}

	info, err := b.ethernetSharingDevice(interfaceName)
	if err != nil {
		return err
	}
	carrier, err := info.wired.GetPropertyCarrier()
	if err != nil {
		return fmt.Errorf("не удалось проверить Ethernet-кабель: %w", err)
	}
	if !carrier {
		return errors.New("подключите Ethernet-кабель к другому компьютеру")
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	checkpoint, err := nm.CheckpointCreate(
		[]gonetworkmanager.Device{info.device},
		ethernetSharingCheckpointSeconds,
		uint32(gonetworkmanager.NmCheckpointCreateFlagsDeleteNewConnections),
	)
	if err != nil {
		return fmt.Errorf("не удалось создать точку безопасного отката: %w", err)
	}

	connection, existing, err := b.findKaskadEthernetSharingConnection()
	if err != nil {
		_, _ = nm.CheckpointRollback(checkpoint)
		b.setEthernetSharingError(err)
		return err
	}
	// The ordinary profile is not active while sharing is running and may not
	// be active at all while carrier is down. Its UUID is therefore recovered
	// from Kaskad's persisted metadata before rebuilding the sharing profile.
	// Falling back only to the current sharing profile would reintroduce a bad
	// auto-negotiation/MAC combination after one failed link cycle.
	restoreUUID := b.activeOrdinaryWiredUUID(info.device)
	if restoreUUID == "" {
		restoreUUID = ethernetSharingRestoreUUID(existing)
	}
	var hardwareProfile gonetworkmanager.ConnectionSettings
	if restoreUUID != "" {
		if _, ordinarySettings, findErr := b.findWiredConnection(restoreUUID); findErr == nil {
			hardwareProfile = ordinarySettings
		}
	}
	rollback := func(cause error) error {
		_ = runHotspotInterfaceControl("stop-ethernet-vpn", info.name)
		_, _ = nm.CheckpointRollback(checkpoint)
		_ = b.updateEthernetSharingState()
		b.setEthernetSharingError(cause)
		return cause
	}
	settings := buildEthernetSharingSettings(info.name, restoreUUID, true, useVPN, existing, hardwareProfile)
	if connection == nil {
		settingsManager, settingsErr := b.networkManagerSettings()
		if settingsErr != nil {
			return rollback(settingsErr)
		}
		connection, err = settingsManager.AddConnection(settings)
		if err != nil {
			return rollback(fmt.Errorf("не удалось создать профиль раздачи: %w", err))
		}
	} else if err := connection.Update(settings); err != nil {
		return rollback(fmt.Errorf("не удалось обновить профиль раздачи: %w", err))
	}
	if useVPN {
		if err := runHotspotInterfaceControl("start-ethernet-vpn", info.name); err != nil {
			return rollback(fmt.Errorf("не удалось направить раздачу через VPN: %w", err))
		}
	} else if err := runHotspotInterfaceControl("stop-ethernet-vpn", info.name); err != nil {
		return rollback(fmt.Errorf("не удалось подготовить прямую раздачу: %w", err))
	}

	b.stateMutex.Lock()
	b.state.EthernetSharingActivating = true
	b.state.EthernetSharingStatus = "starting"
	b.state.EthernetSharingDevice = info.name
	b.state.EthernetSharingLastError = ""
	b.stateMutex.Unlock()
	if b.onStateChange != nil {
		b.onStateChange()
	}

	if _, err := nm.ActivateConnection(connection, info.device, nil); err != nil {
		if useVPN {
			_ = runHotspotInterfaceControl("stop-ethernet-vpn", info.name)
		}
		return rollback(fmt.Errorf("не удалось включить раздачу через Ethernet: %w", err))
	}
	if err := b.waitForEthernetSharing(info.device, 12*time.Second); err != nil {
		if useVPN {
			_ = runHotspotInterfaceControl("stop-ethernet-vpn", info.name)
		}
		return rollback(err)
	}
	if err := nm.CheckpointDestroy(checkpoint); err != nil {
		return rollback(fmt.Errorf("не удалось подтвердить режим раздачи: %w", err))
	}

	_ = b.updateEthernetSharingState()
	b.updateAllEthernetDevices()
	b.updateEthernetState()
	b.listEthernetConnections()
	if b.onStateChange != nil {
		b.onStateChange()
	}
	return nil
}

func (b *NetworkManagerBackend) disableEthernetSharing() error {
	connection, settings, err := b.findKaskadEthernetSharingConnection()
	if err != nil {
		return err
	}
	if connection == nil {
		_ = runHotspotInterfaceControl("stop-ethernet-vpn")
		_ = b.updateEthernetSharingState()
		return nil
	}

	interfaceName := ethernetSharingDeviceFromSettings(settings)
	info, exists := b.ethernetDeviceByIface(interfaceName)
	if !exists {
		// The adapter may have been unplugged. Prevent automatic reactivation;
		// there is no live device or connection left to restore.
		disabledSettings := buildEthernetSharingSettings(interfaceName, ethernetSharingRestoreUUID(settings), false, ethernetSharingVPNFromSettings(settings), settings, settings)
		if err := connection.Update(disabledSettings); err != nil {
			return fmt.Errorf("не удалось выключить автозапуск раздачи: %w", err)
		}
		_ = b.updateEthernetSharingState()
		_ = runHotspotInterfaceControl("stop-ethernet-vpn", interfaceName)
		return nil
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	checkpoint, err := nm.CheckpointCreate(
		[]gonetworkmanager.Device{info.device},
		ethernetSharingCheckpointSeconds,
		uint32(gonetworkmanager.NmCheckpointCreateFlagsNone),
	)
	if err != nil {
		return fmt.Errorf("не удалось создать точку безопасного отката: %w", err)
	}
	rollback := func(cause error) error {
		_, _ = nm.CheckpointRollback(checkpoint)
		_ = b.updateEthernetSharingState()
		b.setEthernetSharingError(cause)
		return cause
	}

	b.stateMutex.Lock()
	b.state.EthernetSharingActivating = true
	b.state.EthernetSharingStatus = "stopping"
	b.state.EthernetSharingLastError = ""
	b.stateMutex.Unlock()
	if b.onStateChange != nil {
		b.onStateChange()
	}

	disabledSettings := buildEthernetSharingSettings(interfaceName, ethernetSharingRestoreUUID(settings), false, ethernetSharingVPNFromSettings(settings), settings, settings)
	if err := connection.Update(disabledSettings); err != nil {
		return rollback(fmt.Errorf("не удалось сохранить выключенный режим раздачи: %w", err))
	}
	active, err := b.findActiveKaskadEthernetSharingConnection()
	if err != nil {
		return rollback(err)
	}
	if active != nil {
		if err := nm.DeactivateConnection(active); err != nil {
			return rollback(fmt.Errorf("не удалось остановить раздачу: %w", err))
		}
	}

	restoreUUID := ethernetSharingRestoreUUID(disabledSettings)
	restored := false
	if restoreUUID != "" {
		restoreConnection, _, findErr := b.findWiredConnection(restoreUUID)
		if findErr == nil && restoreConnection != nil {
			if _, err := nm.ActivateConnection(restoreConnection, info.device, nil); err != nil {
				return rollback(fmt.Errorf("раздача остановлена, но прежнее Ethernet-подключение не восстановлено: %w", err))
			}
			restored = true
		}
	}
	if err := b.waitForEthernetSharingStopped(info.device, restoreUUID, restored, 12*time.Second); err != nil {
		return rollback(err)
	}
	if err := nm.CheckpointDestroy(checkpoint); err != nil {
		return rollback(fmt.Errorf("не удалось подтвердить отключение раздачи: %w", err))
	}
	if err := runHotspotInterfaceControl("stop-ethernet-vpn", interfaceName); err != nil {
		return fmt.Errorf("раздача выключена, но не удалось очистить VPN-маршрутизацию: %w", err)
	}

	b.stateMutex.Lock()
	b.state.EthernetSharingActivating = false
	b.stateMutex.Unlock()
	_ = b.updateEthernetSharingState()
	b.updateAllEthernetDevices()
	b.updateEthernetState()
	b.listEthernetConnections()
	if b.onStateChange != nil {
		b.onStateChange()
	}
	return nil
}

func (b *NetworkManagerBackend) ethernetSharingDevice(interfaceName string) (*ethernetDeviceInfo, error) {
	if strings.TrimSpace(interfaceName) != "" {
		if info, ok := b.ethernetDeviceByIface(interfaceName); ok {
			return info, nil
		}
		return nil, fmt.Errorf("Ethernet-адаптер %q не найден", interfaceName)
	}
	devices := b.ethernetDevicesSnapshot()
	if len(devices) == 0 {
		return nil, errors.New("Ethernet-адаптер не найден")
	}
	if len(devices) > 1 {
		return nil, errors.New("выберите Ethernet-адаптер для раздачи")
	}
	for _, info := range devices {
		return info, nil
	}
	return nil, errors.New("Ethernet-адаптер не найден")
}

func buildEthernetSharingSettings(interfaceName, restoreUUID string, autoconnect, useVPN bool, existing, hardwareProfile gonetworkmanager.ConnectionSettings) gonetworkmanager.ConnectionSettings {
	if restoreUUID == "" && existing != nil {
		restoreUUID = ethernetSharingRestoreUUID(existing)
	}
	connectionID := kaskadEthernetSharingConnectionID
	if useVPN {
		connectionID += " (VPN)"
	}
	connection := map[string]any{
		"id":                   connectionID,
		"type":                 "802-3-ethernet",
		"interface-name":       interfaceName,
		"autoconnect":          autoconnect,
		"autoconnect-priority": int32(100),
		"stable-id":            kaskadEthernetSharingStableID,
	}
	if existingConnection := existing["connection"]; existingConnection != nil {
		if uuid, ok := existingConnection["uuid"].(string); ok && uuid != "" {
			connection["uuid"] = uuid
		}
	}
	wired := canonicalEthernetHardwareSettings(hardwareProfile)
	if len(wired) == 0 {
		wired = canonicalEthernetHardwareSettings(existing)
	}
	return gonetworkmanager.ConnectionSettings{
		"connection":     connection,
		"802-3-ethernet": wired,
		"ipv4":           {"method": "shared", "never-default": true},
		"ipv6":           {"method": "ignore"},
		// NMSettingUser is the supported place for application metadata. Keep
		// the previous ordinary wired profile out of the connection setting so
		// NetworkManager can validate and persist the profile normally.
		"user": {"data": map[string]string{
			kaskadEthernetRestoreUUIDKey: restoreUUID,
			kaskadEthernetUseVPNKey:      fmt.Sprintf("%t", useVPN),
		}},
	}
}

// canonicalEthernetHardwareSettings copies only scalar link-layer options.
// NetworkManager's legacy address arrays cannot be round-tripped safely by
// gonetworkmanager, while these properties are both type-stable and necessary
// for adapters/peers that require a particular negotiation or stable MAC mode.
func canonicalEthernetHardwareSettings(profile gonetworkmanager.ConnectionSettings) map[string]any {
	result := make(map[string]any)
	if profile == nil {
		return result
	}
	wired := profile["802-3-ethernet"]
	for _, key := range []string{
		"mtu",
		"cloned-mac-address",
		"generate-mac-address-mask",
		"wake-on-lan",
		"accept-all-mac-addresses",
		"port",
	} {
		value, exists := wired[key]
		if !exists {
			continue
		}
		switch value.(type) {
		case bool, string, int32, uint32, int64, uint64:
			result[key] = value
		}
	}
	// A fixed Ethernet mode is a three-field invariant. NetworkManager accepts
	// auto-negotiate=false with speed=0 and no duplex, but the driver then falls
	// back to negotiation and some 10/100 peers repeatedly lose carrier. Copy
	// the fixed mode only when it is complete; otherwise leave negotiation at
	// NetworkManager's safe default instead of persisting a contradictory state.
	autoNegotiate, hasAutoNegotiate := wired["auto-negotiate"].(bool)
	if hasAutoNegotiate && autoNegotiate {
		result["auto-negotiate"] = true
	} else if hasAutoNegotiate {
		speed, speedOK := ethernetLinkSpeed(wired["speed"])
		duplex, duplexOK := wired["duplex"].(string)
		if speedOK && speed > 0 && duplexOK && (duplex == "full" || duplex == "half") {
			result["auto-negotiate"] = false
			result["speed"] = speed
			result["duplex"] = duplex
		}
	}
	return result
}

func ethernetLinkSpeed(value any) (uint32, bool) {
	switch speed := value.(type) {
	case uint32:
		return speed, true
	case int32:
		if speed >= 0 {
			return uint32(speed), true
		}
	case uint64:
		if speed <= uint64(^uint32(0)) {
			return uint32(speed), true
		}
	case int64:
		if speed >= 0 && uint64(speed) <= uint64(^uint32(0)) {
			return uint32(speed), true
		}
	}
	return 0, false
}

func isKaskadEthernetSharingConnection(settings gonetworkmanager.ConnectionSettings) bool {
	connection := settings["connection"]
	if connection == nil {
		return false
	}
	connectionType, _ := connection["type"].(string)
	stableID, _ := connection["stable-id"].(string)
	ipv4 := settings["ipv4"]
	method, _ := ipv4["method"].(string)
	return connectionType == "802-3-ethernet" && stableID == kaskadEthernetSharingStableID && method == "shared"
}

func ethernetSharingDeviceFromSettings(settings gonetworkmanager.ConnectionSettings) string {
	device, _ := settings["connection"]["interface-name"].(string)
	return device
}

func ethernetSharingRestoreUUID(settings gonetworkmanager.ConnectionSettings) string {
	user := settings["user"]
	if user == nil {
		return ""
	}
	data := user["data"]
	switch typed := data.(type) {
	case map[string]string:
		return typed[kaskadEthernetRestoreUUIDKey]
	case map[string]any:
		uuid, _ := typed[kaskadEthernetRestoreUUIDKey].(string)
		return uuid
	default:
		return ""
	}
}

func ethernetSharingVPNFromSettings(settings gonetworkmanager.ConnectionSettings) bool {
	user := settings["user"]
	if user == nil {
		return false
	}
	data := user["data"]
	switch typed := data.(type) {
	case map[string]string:
		return typed[kaskadEthernetUseVPNKey] == "true"
	case map[string]any:
		value, _ := typed[kaskadEthernetUseVPNKey].(string)
		return value == "true"
	default:
		return false
	}
}

func (b *NetworkManagerBackend) findKaskadEthernetSharingConnection() (gonetworkmanager.Connection, gonetworkmanager.ConnectionSettings, error) {
	settingsManager, err := b.networkManagerSettings()
	if err != nil {
		return nil, nil, err
	}
	connections, err := settingsManager.ListConnections()
	if err != nil {
		return nil, nil, fmt.Errorf("не удалось получить подключения NetworkManager: %w", err)
	}
	for _, connection := range connections {
		settings, err := connection.GetSettings()
		if err == nil && isKaskadEthernetSharingConnection(settings) {
			return connection, settings, nil
		}
	}
	return nil, nil, nil
}

func (b *NetworkManagerBackend) findActiveKaskadEthernetSharingConnection() (gonetworkmanager.ActiveConnection, error) {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	activeConnections, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return nil, fmt.Errorf("не удалось проверить активные подключения: %w", err)
	}
	for _, active := range activeConnections {
		connection, err := active.GetPropertyConnection()
		if err != nil || connection == nil {
			continue
		}
		settings, err := connection.GetSettings()
		if err == nil && isKaskadEthernetSharingConnection(settings) {
			return active, nil
		}
	}
	return nil, nil
}

func (b *NetworkManagerBackend) activeOrdinaryWiredUUID(device gonetworkmanager.Device) string {
	active, err := device.GetPropertyActiveConnection()
	if err != nil || active == nil || active.GetPath() == "/" {
		return ""
	}
	connection, err := active.GetPropertyConnection()
	if err != nil || connection == nil {
		return ""
	}
	settings, err := connection.GetSettings()
	if err != nil || isKaskadEthernetSharingConnection(settings) {
		return ""
	}
	uuid, _ := settings["connection"]["uuid"].(string)
	return uuid
}

func (b *NetworkManagerBackend) waitForEthernetSharing(device gonetworkmanager.Device, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		active, err := device.GetPropertyActiveConnection()
		if err == nil && active != nil && active.GetPath() != "/" {
			connection, connectionErr := active.GetPropertyConnection()
			if connectionErr == nil && connection != nil {
				settings, settingsErr := connection.GetSettings()
				if settingsErr == nil && isKaskadEthernetSharingConnection(settings) {
					state, _ := device.GetPropertyState()
					if state == gonetworkmanager.NmDeviceStateActivated && b.getDeviceIP(device) != "" {
						return nil
					}
				}
			}
		}
		time.Sleep(250 * time.Millisecond)
	}
	return errors.New("Ethernet не перешёл в режим раздачи; предыдущие настройки восстановлены")
}

func (b *NetworkManagerBackend) waitForEthernetSharingStopped(device gonetworkmanager.Device, restoreUUID string, restored bool, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		active, err := device.GetPropertyActiveConnection()
		if err != nil || active == nil || active.GetPath() == "/" {
			if !restored {
				return nil
			}
			time.Sleep(200 * time.Millisecond)
			continue
		}
		connection, err := active.GetPropertyConnection()
		if err != nil || connection == nil {
			time.Sleep(200 * time.Millisecond)
			continue
		}
		settings, err := connection.GetSettings()
		if err != nil {
			time.Sleep(200 * time.Millisecond)
			continue
		}
		if isKaskadEthernetSharingConnection(settings) {
			time.Sleep(200 * time.Millisecond)
			continue
		}
		if !restored {
			return nil
		}
		uuid, _ := settings["connection"]["uuid"].(string)
		// Restoring means handing the adapter back to the previous profile. That
		// profile may legitimately remain in DHCP configuration when the peer is
		// another client computer, so do not require it to have Internet or an IP.
		if uuid == restoreUUID {
			return nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	return errors.New("не удалось надёжно завершить раздачу; предыдущее состояние восстановлено")
}

func (b *NetworkManagerBackend) updateEthernetSharingState() error {
	connection, settings, err := b.findKaskadEthernetSharingConnection()
	if err != nil {
		return err
	}
	active, activeErr := b.findActiveKaskadEthernetSharingConnection()
	if activeErr != nil {
		return activeErr
	}

	configured := connection != nil
	enabled := active != nil
	device := ""
	address := ""
	if configured {
		device = ethernetSharingDeviceFromSettings(settings)
	}
	if enabled {
		config := activeWiredIPv4(active)
		if len(config.IPs) > 0 {
			address = config.IPs[0]
		}
	}

	b.stateMutex.Lock()
	b.state.EthernetSharingConfigured = configured
	b.state.EthernetSharingEnabled = enabled
	b.state.EthernetSharingDevice = device
	b.state.EthernetSharingAddress = address
	b.state.EthernetSharingUseVPN = ethernetSharingVPNFromSettings(settings)
	if enabled {
		b.state.EthernetSharingActivating = false
		b.state.EthernetSharingStatus = "active"
		b.state.EthernetSharingLastError = ""
	} else if !b.state.EthernetSharingActivating {
		b.state.EthernetSharingStatus = "stopped"
	}
	b.stateMutex.Unlock()
	return nil
}

func (b *NetworkManagerBackend) setEthernetSharingError(cause error) {
	b.stateMutex.Lock()
	b.state.EthernetSharingActivating = false
	b.state.EthernetSharingStatus = "error"
	b.state.EthernetSharingLastError = cause.Error()
	b.stateMutex.Unlock()
	if b.onStateChange != nil {
		b.onStateChange()
	}
}

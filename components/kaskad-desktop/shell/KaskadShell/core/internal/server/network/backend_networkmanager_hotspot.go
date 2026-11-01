package network

import (
	"encoding/base64"
	"fmt"
	"sort"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/errdefs"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/log"
)

const (
	nmWiFiDeviceCapAP        uint32 = 0x00000040
	nmWiFiDeviceCapFreqValid uint32 = 0x00000100
	nmWiFiDeviceCapFreq2GHz  uint32 = 0x00000200
	nmWiFiDeviceCapFreq5GHz  uint32 = 0x00000400

	kaskadShellHotspotConnectionID = "KaskadShell Hotspot"
	kaskadShellHotspotStableID     = "kaskad-shell-hotspot"
	kaskadShellHotspotVirtualIface = "kaskad-ap"
)

var _ HotspotBackend = (*NetworkManagerBackend)(nil)

// ConfigureHotspot validates only Kaskad-owned constraints: SSID presence, band
// names, device capability, and the not-active guard. SSID byte-length and
// WPA-PSK password policy are deliberately left to NetworkManager, whose
// AddConnection/Update errors are returned to the caller; duplicating its
// evolving rules here would only let them drift.
func (b *NetworkManagerBackend) ConfigureHotspot(req HotspotRequest) error {
	if req.SSID == "" {
		return fmt.Errorf("hotspot SSID cannot be empty")
	}
	if req.Compatibility {
		req.Band = "bg"
	}
	if err := validateHotspotBandName(req.Band); err != nil {
		return err
	}

	b.stateMutex.RLock()
	hotspotActive := b.state.HotspotEnabled || b.state.HotspotActivating
	b.stateMutex.RUnlock()
	if hotspotActive {
		return fmt.Errorf("stop the hotspot before changing its configuration")
	}

	if req.Device != "" {
		if _, err := b.getAPCapableWiFiDevice(req.Device, req.Band); err != nil {
			return err
		}
	} else if err := b.validateAutoHotspotBand(req.Band); err != nil {
		return err
	}

	settingsMgr, err := b.networkManagerSettings()
	if err != nil {
		return err
	}

	existing, existingSettings, err := b.findKaskadHotspotConnection()
	if err != nil {
		return err
	}

	settings := buildHotspotSettings(req, existingSettings)
	if existing != nil {
		if err := existing.Update(settings); err != nil {
			return fmt.Errorf("failed to update hotspot profile: %w", err)
		}
	} else if _, err := settingsMgr.AddConnection(settings); err != nil {
		return fmt.Errorf("failed to create hotspot profile: %w", err)
	}

	if err := b.updateHotspotState(); err != nil {
		return err
	}

	return nil
}

func (b *NetworkManagerBackend) StartHotspot() error {
	conn, settings, err := b.findKaskadHotspotConnection()
	if err != nil {
		return err
	}
	if conn == nil {
		return fmt.Errorf("hotspot is not configured")
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	wifiEnabled, err := nm.GetPropertyWirelessEnabled()
	if err != nil {
		return fmt.Errorf("failed to read WiFi radio state: %w", err)
	}
	if !wifiEnabled {
		if err := b.SetWiFiEnabled(true); err != nil {
			return fmt.Errorf("failed to enable WiFi for hotspot: %w", err)
		}
	}

	devInfo, err := b.getAPCapableWiFiDevice(hotspotDeviceFromSettings(settings), hotspotBandFromSettings(settings))
	if err != nil {
		return err
	}
	if state, stateErr := devInfo.device.GetPropertyState(); stateErr == nil && state == gonetworkmanager.NmDeviceStateActivated && !b.activeKaskadHotspotDevicePaths()[string(devInfo.device.GetPath())] {
		return b.startWiFiRepeater(conn, settings, devInfo)
	}
	devInfo, restoreProfile, concurrent, err := b.prepareHotspotDevice(nm, conn, settings, devInfo)
	if err != nil {
		return err
	}
	if err := waitForHotspotDeviceReady(nm, devInfo.device); err != nil {
		if restoreProfile != nil {
			_ = restoreProfile()
		}
		if concurrent {
			_ = cleanupHotspotVirtualInterface()
		}
		return err
	}
	if err := runHotspotInterfaceControl("prepare-analytics-log"); err != nil {
		if restoreProfile != nil {
			_ = restoreProfile()
		}
		if concurrent {
			_ = cleanupHotspotVirtualInterface()
		}
		return fmt.Errorf("failed to prepare hotspot analytics: %w", err)
	}

	deviceName := ""
	if devInfo.device != nil {
		deviceName, _ = devInfo.device.GetPropertyInterface()
	}

	// Mark the start before the D-Bus activation call. Fast adapters can emit
	// Activating -> Activated before ActivateConnection returns; setting this
	// afterwards loses that transition and leaves the UI stuck on "Starting".
	b.stateMutex.Lock()
	b.state.HotspotActivating = true
	b.state.HotspotLastError = ""
	b.hotspotPendingDevice = deviceName
	b.hotspotStartedAt = time.Now()
	b.stateMutex.Unlock()

	active, activateErr := nm.ActivateConnection(conn, devInfo.device, nil)
	if activateErr != nil {
		b.clearHotspotStart()
		if restoreProfile != nil {
			_ = restoreProfile()
		}
		if concurrent {
			_ = cleanupHotspotVirtualInterface()
		}
		return fmt.Errorf("failed to start hotspot: %w", activateErr)
	}

	if restoreProfile != nil {
		if err := restoreProfile(); err != nil {
			_ = nm.DeactivateConnection(active)
			b.clearHotspotStart()
			if concurrent {
				_ = cleanupHotspotVirtualInterface()
			}
			return fmt.Errorf("failed to restore hotspot profile after starting WiFi sharing: %w", err)
		}
	}

	if err := b.updateHotspotState(); err != nil {
		return fmt.Errorf("failed to start hotspot: %w", err)
	}

	return nil
}

func (b *NetworkManagerBackend) startWiFiRepeater(conn gonetworkmanager.Connection, settings gonetworkmanager.ConnectionSettings, devInfo *wifiDeviceInfo) error {
	activeAP, err := devInfo.wireless.GetPropertyActiveAccessPoint()
	if err != nil || activeAP == nil || activeAP.GetPath() == "/" {
		return fmt.Errorf("не удалось определить канал входящего Wi‑Fi")
	}
	frequency, err := activeAP.GetPropertyFrequency()
	if err != nil {
		return fmt.Errorf("не удалось определить канал входящего Wi‑Fi: %w", err)
	}
	channel := frequencyToChannel(frequency)
	if channel == 0 {
		return fmt.Errorf("канал входящего Wi‑Fi не поддерживается для повторителя")
	}
	password := ""
	if hotspotSecuredFromSettings(settings) {
		secrets, secretErr := conn.GetSecrets("802-11-wireless-security")
		if secretErr != nil {
			return fmt.Errorf("не удалось прочитать пароль точки доступа: %w", secretErr)
		}
		if security, ok := secrets["802-11-wireless-security"]; ok {
			password, _ = security["psk"].(string)
		}
	}
	band := "a"
	if frequency < 5000 {
		band = "g"
	}
	ssid := hotspotSSIDFromSettings(settings)
	b.stateMutex.Lock()
	b.state.HotspotActivating = true
	b.state.HotspotStatus = "starting"
	b.state.HotspotStatusMessage = "Раздача запускается…"
	b.hotspotPendingDevice = devInfo.name
	b.hotspotStartedAt = time.Now()
	b.stateMutex.Unlock()
	if err := runHotspotInterfaceControl(
		"start-repeater", devInfo.name, kaskadShellHotspotVirtualIface,
		base64.StdEncoding.EncodeToString([]byte(ssid)),
		base64.StdEncoding.EncodeToString([]byte(password)),
		fmt.Sprintf("%d", channel), band,
	); err != nil {
		b.clearHotspotStart()
		b.stateMutex.Lock()
		b.state.HotspotStatus = "degraded"
		b.state.HotspotStatusMessage = err.Error()
		b.stateMutex.Unlock()
		return fmt.Errorf("не удалось запустить Wi‑Fi‑повторитель: %w", err)
	}
	b.stateMutex.Lock()
	b.state.HotspotEnabled = true
	b.state.HotspotActivating = false
	b.state.HotspotLastError = ""
	b.state.HotspotStatus = "active"
	b.state.HotspotStatusMessage = ""
	b.hotspotPendingDevice = ""
	b.hotspotStartedAt = time.Time{}
	b.stateMutex.Unlock()
	if b.onStateChange != nil {
		b.onStateChange()
	}
	return nil
}

func (b *NetworkManagerBackend) clearHotspotStart() {
	b.stateMutex.Lock()
	b.state.HotspotActivating = false
	b.hotspotPendingDevice = ""
	b.hotspotStartedAt = time.Time{}
	b.stateMutex.Unlock()
}

func cloneHotspotSettings(settings gonetworkmanager.ConnectionSettings) gonetworkmanager.ConnectionSettings {
	cloned := make(gonetworkmanager.ConnectionSettings, len(settings))
	for section, values := range settings {
		sectionCopy := make(map[string]any, len(values))
		for key, value := range values {
			sectionCopy[key] = value
		}
		cloned[section] = sectionCopy
	}
	return cloned
}

// prepareHotspotDevice keeps an existing Wi-Fi client connection alive. A
// mac80211 radio cannot run client and AP roles on the same netdev, even when
// the hardware supports both roles, so create a second virtual netdev and pin
// its AP to the client's channel. The saved profile is restored immediately
// after NetworkManager has taken its activation snapshot.
func (b *NetworkManagerBackend) prepareHotspotDevice(
	nm gonetworkmanager.NetworkManager,
	conn gonetworkmanager.Connection,
	settings gonetworkmanager.ConnectionSettings,
	devInfo *wifiDeviceInfo,
) (*wifiDeviceInfo, func() error, bool, error) {
	state, err := devInfo.device.GetPropertyState()
	if err != nil || state != gonetworkmanager.NmDeviceStateActivated {
		return devInfo, nil, false, nil
	}
	if b.activeKaskadHotspotDevicePaths()[string(devInfo.device.GetPath())] {
		return devInfo, nil, false, nil
	}

	activeAP, err := devInfo.wireless.GetPropertyActiveAccessPoint()
	if err != nil || activeAP == nil || activeAP.GetPath() == "/" {
		return nil, nil, false, fmt.Errorf("cannot determine the channel of the incoming WiFi connection")
	}
	frequency, err := activeAP.GetPropertyFrequency()
	if err != nil {
		return nil, nil, false, fmt.Errorf("cannot determine the channel of the incoming WiFi connection: %w", err)
	}
	channel := frequencyToChannel(frequency)
	if channel == 0 {
		return nil, nil, false, fmt.Errorf("the incoming WiFi channel is not supported for sharing")
	}

	if err := runHotspotInterfaceControl("create-interface", devInfo.name, kaskadShellHotspotVirtualIface); err != nil {
		return nil, nil, false, fmt.Errorf("this WiFi adapter could not enable simultaneous client and hotspot mode: %w", err)
	}

	virtualInfo, err := waitForNetworkManagerWiFiDevice(nm, kaskadShellHotspotVirtualIface)
	if err != nil {
		_ = cleanupHotspotVirtualInterface()
		return nil, nil, false, err
	}

	runtimeSettings := cloneHotspotSettings(settings)
	connection := runtimeSettings["connection"]
	connection["interface-name"] = kaskadShellHotspotVirtualIface
	wifi := runtimeSettings["802-11-wireless"]
	wifi["channel"] = channel
	delete(wifi, "channel-width")
	if frequency < 5000 {
		wifi["band"] = "bg"
	} else {
		wifi["band"] = "a"
	}
	if err := conn.Update(runtimeSettings); err != nil {
		_ = cleanupHotspotVirtualInterface()
		return nil, nil, false, fmt.Errorf("failed to prepare WiFi sharing profile: %w", err)
	}

	restore := func() error { return conn.Update(settings) }
	return virtualInfo, restore, true, nil
}

func waitForNetworkManagerWiFiDevice(nm gonetworkmanager.NetworkManager, interfaceName string) (*wifiDeviceInfo, error) {
	deadline := time.Now().Add(8 * time.Second)
	var lastErr error
	for time.Now().Before(deadline) {
		device, err := nm.GetDeviceByIpIface(interfaceName)
		if err == nil && device != nil {
			wireless, wirelessErr := gonetworkmanager.NewDeviceWireless(device.GetPath())
			if wirelessErr == nil {
				state, stateErr := device.GetPropertyState()
				if stateErr == nil && state >= gonetworkmanager.NmDeviceStateDisconnected && state < gonetworkmanager.NmDeviceStateFailed {
					hwAddress, _ := wireless.GetPropertyHwAddress()
					return &wifiDeviceInfo{device: device, wireless: wireless, name: interfaceName, hwAddress: hwAddress}, nil
				}
				lastErr = stateErr
			} else {
				lastErr = wirelessErr
			}
		} else {
			lastErr = err
		}
		time.Sleep(100 * time.Millisecond)
	}
	if lastErr != nil {
		return nil, fmt.Errorf("NetworkManager did not make the hotspot interface ready: %w", lastErr)
	}
	return nil, fmt.Errorf("NetworkManager did not make the hotspot interface ready")
}

func cleanupHotspotVirtualInterface() error {
	return runHotspotInterfaceControl("delete-interface", kaskadShellHotspotVirtualIface)
}

// Enabling the NetworkManager Wi-Fi radio is asynchronous. The D-Bus setter
// can return while wpa_supplicant is still being recreated and the device is
// temporarily Unavailable. Activating an AP during that short window fails
// immediately with "device is not available", so wait for NetworkManager's
// device state rather than guessing with a fixed delay.
func waitForHotspotDeviceReady(nm gonetworkmanager.NetworkManager, device gonetworkmanager.Device) error {
	const timeout = 8 * time.Second
	deadline := time.Now().Add(timeout)
	lastState := gonetworkmanager.NmDeviceStateUnknown

	for {
		wifiEnabled, wifiErr := nm.GetPropertyWirelessEnabled()
		state, stateErr := device.GetPropertyState()
		if stateErr == nil {
			lastState = state
		}

		if wifiErr == nil && wifiEnabled && stateErr == nil &&
			state >= gonetworkmanager.NmDeviceStateDisconnected &&
			state < gonetworkmanager.NmDeviceStateFailed {
			return nil
		}

		if time.Now().After(deadline) {
			if wifiErr != nil {
				return fmt.Errorf("failed to confirm WiFi radio state: %w", wifiErr)
			}
			if stateErr != nil {
				return fmt.Errorf("failed to read WiFi device state: %w", stateErr)
			}
			return fmt.Errorf("WiFi device did not become ready for hotspot (state %s)", lastState)
		}

		time.Sleep(100 * time.Millisecond)
	}
}

func (b *NetworkManagerBackend) StopHotspot() error {
	_, _, _ = b.ListHotspotClients()
	b.stateMutex.Lock()
	b.state.HotspotActivating = false
	b.state.HotspotLastError = ""
	b.hotspotPendingDevice = ""
	b.hotspotStartedAt = time.Time{}
	b.stateMutex.Unlock()
	if currentHotspotRuntimeHealth().Managed {
		if err := runHotspotInterfaceControl("stop-repeater", kaskadShellHotspotVirtualIface); err != nil {
			return fmt.Errorf("не удалось остановить Wi‑Fi‑повторитель: %w", err)
		}
		return b.updateHotspotState()
	}

	active, err := b.findActiveKaskadHotspotConnection()
	if err != nil {
		return err
	}
	if active == nil {
		_ = cleanupHotspotVirtualInterface()
		return nil
	}
	usesVirtualInterface := activeConnectionUsesInterface(active, kaskadShellHotspotVirtualIface)

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	if err := nm.DeactivateConnection(active); err != nil {
		return fmt.Errorf("failed to stop hotspot: %w", err)
	}
	if usesVirtualInterface {
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			state, stateErr := active.GetPropertyState()
			if stateErr != nil || state == gonetworkmanager.NmActiveConnectionStateDeactivated {
				break
			}
			time.Sleep(100 * time.Millisecond)
		}
		if err := cleanupHotspotVirtualInterface(); err != nil {
			log.Warnf("[StopHotspot] Failed to remove virtual hotspot interface: %v", err)
		}
	}

	if err := b.updateHotspotState(); err != nil {
		return err
	}

	return nil
}

func activeConnectionUsesInterface(active gonetworkmanager.ActiveConnection, interfaceName string) bool {
	devices, err := active.GetPropertyDevices()
	if err != nil {
		return false
	}
	for _, device := range devices {
		if device == nil {
			continue
		}
		if name, err := device.GetPropertyInterface(); err == nil && name == interfaceName {
			return true
		}
	}
	return false
}

func (b *NetworkManagerBackend) GetHotspotSecrets() (string, error) {
	conn, settings, err := b.findKaskadHotspotConnection()
	if err != nil {
		return "", err
	}
	if conn == nil {
		return "", fmt.Errorf("hotspot is not configured")
	}
	if !hotspotSecuredFromSettings(settings) {
		return "", nil
	}

	secrets, err := conn.GetSecrets("802-11-wireless-security")
	if err != nil {
		return "", fmt.Errorf("failed to read hotspot password: %w", err)
	}

	if security, ok := secrets["802-11-wireless-security"]; ok {
		if psk, ok := security["psk"].(string); ok {
			return psk, nil
		}
	}

	return "", nil
}

func (b *NetworkManagerBackend) networkManagerSettings() (gonetworkmanager.Settings, error) {
	s := b.settings
	if s == nil {
		var err error
		s, err = gonetworkmanager.NewSettings()
		if err != nil {
			return nil, fmt.Errorf("failed to get settings: %w", err)
		}
		b.settings = s
	}

	settingsMgr, ok := s.(gonetworkmanager.Settings)
	if !ok {
		return nil, fmt.Errorf("invalid NetworkManager settings handle")
	}
	return settingsMgr, nil
}

func buildHotspotSettings(req HotspotRequest, existing gonetworkmanager.ConnectionSettings) gonetworkmanager.ConnectionSettings {
	connection := map[string]any{
		"id":          kaskadShellHotspotConnectionID,
		"type":        "802-11-wireless",
		"autoconnect": false,
		"stable-id":   kaskadShellHotspotStableID,
	}
	if req.Device != "" {
		connection["interface-name"] = req.Device
	}
	if existingConnection, ok := existing["connection"]; ok {
		if uuid, ok := existingConnection["uuid"].(string); ok && uuid != "" {
			connection["uuid"] = uuid
		}
	}

	wifi := map[string]any{
		"mode": "ap",
		"ssid": []byte(req.SSID),
	}
	if req.Compatibility {
		wifi["band"] = "bg"
		wifi["channel"] = uint32(6)
		wifi["channel-width"] = uint32(20)
	} else if req.Band != "" {
		wifi["band"] = req.Band
	}

	settings := gonetworkmanager.ConnectionSettings{
		"connection":      connection,
		"802-11-wireless": wifi,
		"ipv4":            {"method": "shared"},
		"ipv6":            {"method": "ignore"},
	}

	if req.Password != "" {
		wifi["security"] = "802-11-wireless-security"
		security := map[string]any{
			"key-mgmt":  "wpa-psk",
			"psk":       req.Password,
			"psk-flags": uint32(0),
		}
		if req.Compatibility {
			security["proto"] = []string{"rsn"}
			security["pairwise"] = []string{"ccmp"}
			security["group"] = []string{"ccmp"}
			security["pmf"] = uint32(1)
		}
		settings["802-11-wireless-security"] = security
	}

	return settings
}

func (b *NetworkManagerBackend) findKaskadHotspotConnection() (gonetworkmanager.Connection, gonetworkmanager.ConnectionSettings, error) {
	settingsMgr, err := b.networkManagerSettings()
	if err != nil {
		return nil, nil, err
	}

	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return nil, nil, fmt.Errorf("failed to list connections: %w", err)
	}

	for _, conn := range connections {
		connSettings, err := conn.GetSettings()
		if err != nil {
			continue
		}
		if isKaskadHotspotConnection(connSettings) {
			return conn, connSettings, nil
		}
	}

	return nil, nil, nil
}

func (b *NetworkManagerBackend) findActiveKaskadHotspotConnection() (gonetworkmanager.ActiveConnection, error) {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get active connections: %w", err)
	}

	for _, active := range activeConns {
		connType, err := active.GetPropertyType()
		if err != nil || connType != "802-11-wireless" {
			continue
		}

		conn, err := active.GetPropertyConnection()
		if err != nil || conn == nil {
			continue
		}

		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}
		if isKaskadHotspotConnection(settings) {
			return active, nil
		}
	}

	return nil, nil
}

func isKaskadHotspotConnection(settings gonetworkmanager.ConnectionSettings) bool {
	connMeta, _, ok := wifiConnectionSettings(settings)
	if !ok || !isAPModeWiFiConnection(settings) {
		return false
	}

	stableID, _ := connMeta["stable-id"].(string)
	return stableID == kaskadShellHotspotStableID
}

func wifiConnectionSettings(settings gonetworkmanager.ConnectionSettings) (map[string]any, map[string]any, bool) {
	connMeta, ok := settings["connection"]
	if !ok {
		return nil, nil, false
	}
	connType, _ := connMeta["type"].(string)
	if connType != "802-11-wireless" {
		return nil, nil, false
	}

	wifiSettings, ok := settings["802-11-wireless"]
	if !ok {
		return nil, nil, false
	}

	return connMeta, wifiSettings, true
}

func isAPModeWiFiConnection(settings gonetworkmanager.ConnectionSettings) bool {
	_, wifiSettings, ok := wifiConnectionSettings(settings)
	if !ok {
		return false
	}
	mode, _ := wifiSettings["mode"].(string)
	return mode == "ap"
}

func isClientWiFiConnection(settings gonetworkmanager.ConnectionSettings) bool {
	_, _, ok := wifiConnectionSettings(settings)
	return ok && !isAPModeWiFiConnection(settings)
}

// activeKaskadHotspotDevicePaths returns only the devices hosting the Kaskad-owned
// hotspot, unlike activeAPModeWiFiDevicePaths which matches any AP-mode
// connection (as the client-state isolation requires).
func (b *NetworkManagerBackend) activeKaskadHotspotDevicePaths() map[string]bool {
	paths := make(map[string]bool)
	active, err := b.findActiveKaskadHotspotConnection()
	if err != nil || active == nil {
		return paths
	}

	devices, err := active.GetPropertyDevices()
	if err != nil {
		return paths
	}
	for _, dev := range devices {
		if dev != nil {
			paths[string(dev.GetPath())] = true
		}
	}

	return paths
}

func (b *NetworkManagerBackend) activeAPModeWiFiDevicePaths() map[string]bool {
	paths := make(map[string]bool)
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return paths
	}

	for _, active := range activeConns {
		connType, err := active.GetPropertyType()
		if err != nil || connType != "802-11-wireless" {
			continue
		}

		conn, err := active.GetPropertyConnection()
		if err != nil || conn == nil {
			continue
		}

		settings, err := conn.GetSettings()
		if err != nil || !isAPModeWiFiConnection(settings) {
			continue
		}

		devices, err := active.GetPropertyDevices()
		if err != nil {
			continue
		}
		for _, dev := range devices {
			if dev != nil {
				paths[string(dev.GetPath())] = true
			}
		}
	}

	return paths
}

func (b *NetworkManagerBackend) getAPCapableWiFiDevice(deviceName string, band string) (*wifiDeviceInfo, error) {
	if err := validateHotspotBandName(band); err != nil {
		return nil, err
	}

	if deviceName != "" {
		devInfo, ok := b.wifiDeviceByIface(deviceName)
		if !ok {
			return nil, fmt.Errorf("WiFi device not found: %s", deviceName)
		}
		if err := validateAPCapableWiFiDevice(devInfo, deviceName, band); err != nil {
			return nil, err
		}
		return devInfo, nil
	}

	wifiDevices := b.wifiDevicesSnapshot()
	deviceNames := make([]string, 0, len(wifiDevices))
	for name := range wifiDevices {
		deviceNames = append(deviceNames, name)
	}
	sort.Strings(deviceNames)

	kaskadShellHotspotDevicePaths := b.activeKaskadHotspotDevicePaths()

	// Rank 0: already hosting the Kaskad hotspot (keep it where it is). Radios
	// hosting foreign AP-mode connections must not get this preference and
	// rank as busy through their Activated state instead.
	// Rank 1: genuinely disconnected, so starting the AP disturbs nothing.
	// Rank 2: client activation in progress; grabbing it kills the attempt.
	// Rank 3: carrying an active connection; only used as a last resort.
	// Rank 4: unavailable, failed, or unknown; activation is unlikely to succeed.
	rankDevice := func(devInfo *wifiDeviceInfo) int {
		if len(kaskadShellHotspotDevicePaths) > 0 && kaskadShellHotspotDevicePaths[string(devInfo.device.GetPath())] {
			return 0
		}
		state, err := devInfo.device.GetPropertyState()
		if err != nil {
			return 4
		}
		switch {
		case state == gonetworkmanager.NmDeviceStateDisconnected:
			return 1
		case state == gonetworkmanager.NmDeviceStateActivated:
			return 3
		case state > gonetworkmanager.NmDeviceStateDisconnected && state < gonetworkmanager.NmDeviceStateActivated:
			return 2
		default:
			return 4
		}
	}

	var lastBandErr error
	var best *wifiDeviceInfo
	bestRank := 5
	for _, name := range deviceNames {
		devInfo := wifiDevices[name]
		ok, err := isAPCapableWiFiDevice(devInfo)
		if err != nil || !ok {
			continue
		}
		if err := validateHotspotBand(devInfo, band); err != nil {
			lastBandErr = err
			continue
		}
		if rank := rankDevice(devInfo); rank < bestRank {
			best = devInfo
			bestRank = rank
		}
	}

	if best != nil {
		return best, nil
	}
	if lastBandErr != nil {
		return nil, lastBandErr
	}
	return nil, fmt.Errorf("no hotspot-capable WiFi device available")
}

func validateAPCapableWiFiDevice(devInfo *wifiDeviceInfo, deviceName string, band string) error {
	ok, err := isAPCapableWiFiDevice(devInfo)
	if err != nil {
		return err
	}
	if !ok {
		return fmt.Errorf("WiFi device is not hotspot-capable: %s", deviceName)
	}
	return validateHotspotBand(devInfo, band)
}

func isAPCapableWiFiDevice(devInfo *wifiDeviceInfo) (bool, error) {
	if devInfo == nil || devInfo.device == nil || devInfo.wireless == nil {
		return false, nil
	}

	managed, err := devInfo.device.GetPropertyManaged()
	if err != nil {
		return false, fmt.Errorf("failed to get WiFi device managed state: %w", err)
	}
	if !managed {
		return false, nil
	}

	caps, err := devInfo.wireless.GetPropertyWirelessCapabilities()
	if err != nil {
		return false, fmt.Errorf("failed to get WiFi device capabilities: %w", err)
	}

	return caps&nmWiFiDeviceCapAP != 0, nil
}

func validateHotspotBandName(band string) error {
	if band != "" && band != "bg" && band != "a" {
		return fmt.Errorf("unsupported hotspot band: %s", band)
	}
	return nil
}

func validateHotspotBand(devInfo *wifiDeviceInfo, band string) error {
	if band == "" || devInfo == nil || devInfo.wireless == nil {
		return nil
	}

	caps, err := devInfo.wireless.GetPropertyWirelessCapabilities()
	if err != nil {
		return fmt.Errorf("failed to get WiFi device capabilities: %w", err)
	}
	if caps&nmWiFiDeviceCapFreqValid == 0 {
		return nil
	}

	switch band {
	case "bg":
		if caps&nmWiFiDeviceCapFreq2GHz == 0 {
			return fmt.Errorf("WiFi device does not support 2.4GHz hotspot band")
		}
	case "a":
		if caps&nmWiFiDeviceCapFreq5GHz == 0 {
			return fmt.Errorf("WiFi device does not support 5GHz hotspot band")
		}
	}

	return nil
}

func (b *NetworkManagerBackend) validateAutoHotspotBand(band string) error {
	if band == "" {
		return nil
	}

	var lastBandErr error
	foundAPCapableDevice := false
	for _, devInfo := range b.wifiDevicesSnapshot() {
		apCapable, err := isAPCapableWiFiDevice(devInfo)
		if err != nil {
			// Capability could not be determined, so defer to NetworkManager.
			return nil
		}
		if !apCapable {
			continue
		}

		foundAPCapableDevice = true
		if err := validateHotspotBand(devInfo, band); err == nil {
			return nil
		} else {
			lastBandErr = err
		}
	}

	if foundAPCapableDevice && lastBandErr != nil {
		return lastBandErr
	}
	return nil
}

func hotspotSSIDFromSettings(settings gonetworkmanager.ConnectionSettings) string {
	wifiSettings, ok := settings["802-11-wireless"]
	if !ok {
		return ""
	}
	ssidBytes, ok := wifiSettings["ssid"].([]byte)
	if !ok {
		return ""
	}
	return string(ssidBytes)
}

func hotspotDeviceFromSettings(settings gonetworkmanager.ConnectionSettings) string {
	connMeta, ok := settings["connection"]
	if !ok {
		return ""
	}
	device, _ := connMeta["interface-name"].(string)
	return device
}

func hotspotBandFromSettings(settings gonetworkmanager.ConnectionSettings) string {
	wifiSettings, ok := settings["802-11-wireless"]
	if !ok {
		return ""
	}
	band, _ := wifiSettings["band"].(string)
	return band
}

func (b *NetworkManagerBackend) updateHotspotState() error {
	available := false
	for _, devInfo := range b.wifiDevicesSnapshot() {
		ok, err := isAPCapableWiFiDevice(devInfo)
		if err != nil {
			continue
		}
		if ok {
			available = true
			break
		}
	}

	_, settings, err := b.findKaskadHotspotConnection()
	if err != nil {
		return err
	}

	configured := settings != nil
	runtimeHealth := currentHotspotRuntimeHealth()
	enabled := runtimeHealth.Enabled
	activating := false
	if configured && !enabled {
		active, err := b.findActiveKaskadHotspotConnection()
		if err != nil {
			return err
		}
		if active != nil {
			switch state, _ := active.GetPropertyState(); state {
			case gonetworkmanager.NmActiveConnectionStateActivated:
				enabled = true
			case gonetworkmanager.NmActiveConnectionStateActivating:
				activating = true
			}
		}
	}

	b.stateMutex.RLock()
	wasStarting := b.state.HotspotActivating
	pendingDevice := b.hotspotPendingDevice
	startedAt := b.hotspotStartedAt
	b.stateMutex.RUnlock()

	failureCode := ""
	if wasStarting && !enabled && !activating {
		if devInfo, ok := b.wifiDeviceByIface(pendingDevice); ok && devInfo.device != nil && b.dbusConn != nil {
			reason := b.getDeviceStateReason(devInfo.device)
			// A fresh activation briefly reports no reason; don't misread it as failure.
			if (reason == gonetworkmanager.NmDeviceStateReasonNewActivation || reason == gonetworkmanager.NmDeviceStateReasonNone) && (startedAt.IsZero() || time.Since(startedAt) < 10*time.Second) {
				activating = true
			} else {
				failureCode = classifyHotspotStateReason(reason)
				log.Warnf("[updateHotspotState] Hotspot activation failed: device=%s, reason=%d (%s)", pendingDevice, reason, failureCode)
			}
		} else {
			failureCode = errdefs.ErrHotspotFailed
			log.Warnf("[updateHotspotState] Hotspot activation failed: device %q no longer available", pendingDevice)
		}
	}

	b.stateMutex.Lock()
	b.state.HotspotAvailable = available
	b.state.HotspotConfigured = configured
	b.state.HotspotEnabled = enabled
	b.state.HotspotSSID = hotspotSSIDFromSettings(settings)
	b.state.HotspotDevice = hotspotDeviceFromSettings(settings)
	b.state.HotspotBand = hotspotBandFromSettings(settings)
	b.state.HotspotCompatibility = hotspotCompatibilityFromSettings(settings)
	b.state.HotspotSecured = hotspotSecuredFromSettings(settings)
	cleanupVirtual := false
	if wasStarting {
		switch {
		case enabled:
			b.state.HotspotActivating = false
			b.state.HotspotLastError = ""
			b.hotspotPendingDevice = ""
			b.hotspotStartedAt = time.Time{}
		case failureCode != "":
			cleanupVirtual = pendingDevice == kaskadShellHotspotVirtualIface
			b.state.HotspotActivating = false
			b.state.HotspotLastError = failureCode
			b.hotspotPendingDevice = ""
			b.hotspotStartedAt = time.Time{}
		}
	} else {
		b.state.HotspotActivating = activating
	}
	b.state.HotspotStatus = "stopped"
	b.state.HotspotStatusMessage = ""
	switch {
	case b.state.HotspotActivating:
		b.state.HotspotStatus = "starting"
		b.state.HotspotStatusMessage = "Раздача запускается…"
	case runtimeHealth.Managed || (!enabled && runtimeHealth.Status == "degraded"):
		b.state.HotspotStatus = runtimeHealth.Status
		b.state.HotspotStatusMessage = runtimeHealth.Message
	case enabled:
		b.state.HotspotStatus = "active"
	case failureCode != "":
		b.state.HotspotStatus = "degraded"
		b.state.HotspotStatusMessage = "Не удалось запустить раздачу. Проверьте Wi‑Fi-адаптер и попробуйте ещё раз."
	}
	b.stateMutex.Unlock()
	if cleanupVirtual {
		go func() {
			if err := cleanupHotspotVirtualInterface(); err != nil {
				log.Warnf("[updateHotspotState] Failed to remove virtual hotspot interface: %v", err)
			}
		}()
	}

	return nil
}

func hotspotSecuredFromSettings(settings gonetworkmanager.ConnectionSettings) bool {
	if settings == nil {
		return false
	}
	_, ok := settings["802-11-wireless-security"]
	return ok
}

func hotspotCompatibilityFromSettings(settings gonetworkmanager.ConnectionSettings) bool {
	wifi, ok := settings["802-11-wireless"]
	if !ok || wifi["band"] != "bg" {
		return false
	}
	width, ok := wifi["channel-width"].(uint32)
	if !ok || width != 20 {
		return false
	}
	channel, ok := wifi["channel"].(uint32)
	if !ok || channel != 6 {
		return false
	}
	security, ok := settings["802-11-wireless-security"]
	if !ok {
		return true
	}
	if security["key-mgmt"] != "wpa-psk" {
		return false
	}
	pmf, ok := security["pmf"].(uint32)
	return ok && pmf == 1 && stringListContains(security["proto"], "rsn") && stringListContains(security["pairwise"], "ccmp")
}

func stringListContains(value any, wanted string) bool {
	values, ok := value.([]string)
	if !ok {
		return false
	}
	for _, item := range values {
		if item == wanted {
			return true
		}
	}
	return false
}

// classifyHotspotStateReason uses the gonetworkmanager reason constants; the
// same-named package-local aliases in backend_networkmanager.go carry wrong
// values and must not be used here.
func classifyHotspotStateReason(reason uint32) string {
	switch reason {
	case gonetworkmanager.NmDeviceStateReasonIpConfigUnavailable,
		gonetworkmanager.NmDeviceStateReasonDhcpStartFailed,
		gonetworkmanager.NmDeviceStateReasonDhcpError,
		gonetworkmanager.NmDeviceStateReasonDhcpFailed,
		gonetworkmanager.NmDeviceStateReasonSharedStartFailed,
		gonetworkmanager.NmDeviceStateReasonSharedFailed:
		return errdefs.ErrHotspotIPConfigFailed
	case gonetworkmanager.NmDeviceStateReasonSupplicantDisconnect,
		gonetworkmanager.NmDeviceStateReasonSupplicantConfigFailed,
		gonetworkmanager.NmDeviceStateReasonSupplicantFailed,
		gonetworkmanager.NmDeviceStateReasonSupplicantTimeout:
		return errdefs.ErrHotspotSupplicantFailed
	default:
		return errdefs.ErrHotspotFailed
	}
}

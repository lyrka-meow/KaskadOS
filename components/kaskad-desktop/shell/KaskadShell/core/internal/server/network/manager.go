package network

import (
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/log"
	"github.com/yeqown/go-qrcode/v2"
	"github.com/yeqown/go-qrcode/writer/standard"
)

// ErrNoNetworkBackend is returned when no supported network management daemon
// (NetworkManager, iwd, systemd-networkd, ConnMan, wpa_supplicant) is present
// on the system.
var ErrNoNetworkBackend = errors.New("no supported network backend found")

// ErrHotspotNotSupported is returned when the active backend does not implement
// hotspot operations.
var ErrHotspotNotSupported = errors.New("hotspot not supported by active network backend")

var ErrEthernetSharingNotSupported = errors.New("раздача через Ethernet доступна только через NetworkManager")

func NewManager() (*Manager, error) {
	detection, err := DetectNetworkStack()
	if err != nil {
		return nil, fmt.Errorf("failed to detect network stack: %w", err)
	}

	log.Infof("Network backend detection: %s", detection.ChosenReason)

	var backend Backend
	switch detection.Backend {
	case BackendNetworkManager:
		nm, err := NewNetworkManagerBackend()
		if err != nil {
			return nil, fmt.Errorf("failed to create NetworkManager backend: %w", err)
		}
		backend = nm

	case BackendIwd:
		iwd, err := NewIWDBackend()
		if err != nil {
			return nil, fmt.Errorf("failed to create iwd backend: %w", err)
		}
		backend = iwd

	case BackendNetworkd:
		if detection.HasIwd && !detection.HasNM {
			wifi, err := NewIWDBackend()
			if err != nil {
				return nil, fmt.Errorf("failed to create iwd backend: %w", err)
			}
			l3, err := NewSystemdNetworkdBackend()
			if err != nil {
				return nil, fmt.Errorf("failed to create networkd backend: %w", err)
			}
			hybrid, err := NewHybridIwdNetworkdBackend(wifi, l3)
			if err != nil {
				return nil, fmt.Errorf("failed to create hybrid backend: %w", err)
			}
			backend = hybrid
		} else {
			nd, err := NewSystemdNetworkdBackend()
			if err != nil {
				return nil, fmt.Errorf("failed to create networkd backend: %w", err)
			}
			backend = nd
		}

	case BackendWpaSupplicant:
		wpa, err := NewWpaSupplicantBackend()
		if err != nil {
			return nil, fmt.Errorf("failed to create wpa_supplicant backend: %w", err)
		}
		backend = wpa

	default:
		return nil, fmt.Errorf("%w: %s", ErrNoNetworkBackend, detection.ChosenReason)
	}

	m := &Manager{
		backend: backend,
		state: &NetworkState{
			NetworkStatus:     StatusDisconnected,
			Preference:        PreferenceAuto,
			WiFiNetworks:      []WiFiNetwork{},
			SavedWiFiNetworks: []WiFiNetwork{},
		},
		stateMutex: sync.RWMutex{},

		stopChan: make(chan struct{}),
		dirty:    make(chan struct{}, 1),
	}

	broker := NewSubscriptionBroker(m.broadcastCredentialPrompt)
	if err := backend.SetPromptBroker(broker); err != nil {
		return nil, fmt.Errorf("failed to set prompt broker: %w", err)
	}

	if err := backend.Initialize(); err != nil {
		return nil, fmt.Errorf("failed to initialize backend: %w", err)
	}

	if err := m.syncStateFromBackend(); err != nil {
		return nil, fmt.Errorf("failed to sync initial state: %w", err)
	}
	if pref, initialized, err := loadConnectionPreference(); err != nil {
		log.Warnf("Failed to load network preference: %v", err)
	} else {
		m.state.Preference = pref
		m.state.PreferenceInitialized = initialized
	}

	m.notifierWg.Add(1)
	go m.notifier()

	if err := backend.StartMonitoring(m.onBackendStateChange); err != nil {
		m.Close()
		return nil, fmt.Errorf("failed to start monitoring: %w", err)
	}

	return m, nil
}

func (m *Manager) hotspotBackend() (HotspotBackend, bool) {
	backend, ok := m.backend.(HotspotBackend)
	return backend, ok
}

func (m *Manager) ethernetSharingBackend() (EthernetSharingBackend, bool) {
	backend, ok := m.backend.(EthernetSharingBackend)
	return backend, ok
}

func (m *Manager) syncStateFromBackend() error {
	backendState, err := m.backend.GetCurrentState()
	if err != nil {
		return err
	}
	_, hotspotSupported := m.hotspotBackend()
	_, ethernetSharingSupported := m.ethernetSharingBackend()

	m.stateMutex.Lock()
	m.state.Backend = backendState.Backend
	m.state.NetworkStatus = backendState.NetworkStatus
	m.state.PrimaryConnectionType = backendState.PrimaryConnectionType
	m.state.PrimaryConnectionName = backendState.PrimaryConnectionName
	m.state.PrimaryDevice = backendState.PrimaryDevice
	m.state.Connectivity = backendState.Connectivity
	m.state.EthernetIP = backendState.EthernetIP
	m.state.EthernetDevice = backendState.EthernetDevice
	m.state.EthernetConnected = backendState.EthernetConnected
	m.state.EthernetConnectionUuid = backendState.EthernetConnectionUuid
	m.state.EthernetDevices = backendState.EthernetDevices
	m.state.EthernetSharingSupported = ethernetSharingSupported
	m.state.EthernetSharingConfigured = backendState.EthernetSharingConfigured
	m.state.EthernetSharingEnabled = backendState.EthernetSharingEnabled
	m.state.EthernetSharingActivating = backendState.EthernetSharingActivating
	m.state.EthernetSharingDevice = backendState.EthernetSharingDevice
	m.state.EthernetSharingAddress = backendState.EthernetSharingAddress
	m.state.EthernetSharingUseVPN = backendState.EthernetSharingUseVPN
	m.state.EthernetSharingStatus = backendState.EthernetSharingStatus
	m.state.EthernetSharingLastError = backendState.EthernetSharingLastError
	m.state.WiFiIP = backendState.WiFiIP
	m.state.WiFiDevice = backendState.WiFiDevice
	m.state.WiFiConnected = backendState.WiFiConnected
	m.state.WiFiEnabled = backendState.WiFiEnabled
	m.state.WiFiSSID = backendState.WiFiSSID
	m.state.WiFiBSSID = backendState.WiFiBSSID
	m.state.WiFiSignal = backendState.WiFiSignal
	m.state.WiFiNetworks = backendState.WiFiNetworks
	m.state.SavedWiFiNetworks = backendState.SavedWiFiNetworks
	m.state.WiFiDevices = backendState.WiFiDevices
	m.state.HotspotSupported = hotspotSupported
	if hotspotSupported {
		m.state.HotspotAvailable = backendState.HotspotAvailable
		m.state.HotspotConfigured = backendState.HotspotConfigured
		m.state.HotspotEnabled = backendState.HotspotEnabled
		m.state.HotspotStatus = backendState.HotspotStatus
		m.state.HotspotStatusMessage = backendState.HotspotStatusMessage
		m.state.HotspotActivating = backendState.HotspotActivating
		m.state.HotspotSecured = backendState.HotspotSecured
		m.state.HotspotSSID = backendState.HotspotSSID
		m.state.HotspotDevice = backendState.HotspotDevice
		m.state.HotspotBand = backendState.HotspotBand
		m.state.HotspotCompatibility = backendState.HotspotCompatibility
		m.state.HotspotLastError = backendState.HotspotLastError
	} else {
		m.state.HotspotAvailable = false
		m.state.HotspotConfigured = false
		m.state.HotspotEnabled = false
		m.state.HotspotStatus = "stopped"
		m.state.HotspotStatusMessage = ""
		m.state.HotspotActivating = false
		m.state.HotspotSecured = false
		m.state.HotspotSSID = ""
		m.state.HotspotDevice = ""
		m.state.HotspotBand = ""
		m.state.HotspotCompatibility = false
		m.state.HotspotLastError = ""
	}
	m.state.WiredConnections = backendState.WiredConnections
	m.state.IsConnecting = backendState.IsConnecting
	m.state.ConnectingSSID = backendState.ConnectingSSID
	m.state.ConnectingDevice = backendState.ConnectingDevice
	m.state.LastError = backendState.LastError
	m.stateMutex.Unlock()

	return nil
}

func (m *Manager) onBackendStateChange() {
	if err := m.syncStateFromBackend(); err != nil {
		log.Errorf("failed to sync state from backend: %v", err)
	}
	m.notifySubscribers()
}

func signalChangeSignificant(old, new uint8) bool {
	if old == 0 || new == 0 {
		return true
	}
	diff := int(new) - int(old)
	if diff < 0 {
		diff = -diff
	}
	return diff >= 5
}

func (m *Manager) snapshotState() NetworkState {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	s := *m.state
	s.WiFiNetworks = append([]WiFiNetwork(nil), m.state.WiFiNetworks...)
	s.SavedWiFiNetworks = append([]WiFiNetwork(nil), m.state.SavedWiFiNetworks...)
	s.WiFiDevices = append([]WiFiDevice(nil), m.state.WiFiDevices...)
	s.WiredConnections = append([]WiredConnection(nil), m.state.WiredConnections...)
	s.EthernetDevices = append([]EthernetDevice(nil), m.state.EthernetDevices...)
	return s
}

func stateChangedMeaningfully(old, new *NetworkState) bool {
	if old.NetworkStatus != new.NetworkStatus {
		return true
	}
	if old.Preference != new.Preference {
		return true
	}
	if old.PreferenceInitialized != new.PreferenceInitialized ||
		old.PrimaryConnectionType != new.PrimaryConnectionType ||
		old.PrimaryConnectionName != new.PrimaryConnectionName ||
		old.PrimaryDevice != new.PrimaryDevice || old.Connectivity != new.Connectivity {
		return true
	}
	if old.EthernetConnected != new.EthernetConnected {
		return true
	}
	if old.EthernetIP != new.EthernetIP {
		return true
	}
	if old.EthernetSharingSupported != new.EthernetSharingSupported ||
		old.EthernetSharingConfigured != new.EthernetSharingConfigured ||
		old.EthernetSharingEnabled != new.EthernetSharingEnabled ||
		old.EthernetSharingActivating != new.EthernetSharingActivating ||
		old.EthernetSharingDevice != new.EthernetSharingDevice ||
		old.EthernetSharingAddress != new.EthernetSharingAddress ||
		old.EthernetSharingUseVPN != new.EthernetSharingUseVPN ||
		old.EthernetSharingStatus != new.EthernetSharingStatus ||
		old.EthernetSharingLastError != new.EthernetSharingLastError {
		return true
	}
	if old.WiFiConnected != new.WiFiConnected {
		return true
	}
	if old.WiFiEnabled != new.WiFiEnabled {
		return true
	}
	if old.WiFiSSID != new.WiFiSSID {
		return true
	}
	if old.WiFiBSSID != new.WiFiBSSID {
		return true
	}
	if old.WiFiIP != new.WiFiIP {
		return true
	}
	if old.HotspotSupported != new.HotspotSupported {
		return true
	}
	if old.HotspotAvailable != new.HotspotAvailable {
		return true
	}
	if old.HotspotConfigured != new.HotspotConfigured {
		return true
	}
	if old.HotspotEnabled != new.HotspotEnabled {
		return true
	}
	if old.HotspotStatus != new.HotspotStatus || old.HotspotStatusMessage != new.HotspotStatusMessage {
		return true
	}
	if old.HotspotActivating != new.HotspotActivating {
		return true
	}
	if old.HotspotSecured != new.HotspotSecured {
		return true
	}
	if old.HotspotLastError != new.HotspotLastError {
		return true
	}
	if old.HotspotSSID != new.HotspotSSID {
		return true
	}
	if old.HotspotDevice != new.HotspotDevice {
		return true
	}
	if old.HotspotBand != new.HotspotBand {
		return true
	}
	if old.HotspotCompatibility != new.HotspotCompatibility {
		return true
	}
	if old.WiFiSignal != new.WiFiSignal && signalChangeSignificant(old.WiFiSignal, new.WiFiSignal) {
		return true
	}
	if old.IsConnecting != new.IsConnecting {
		return true
	}
	if old.ConnectingSSID != new.ConnectingSSID {
		return true
	}
	if old.LastError != new.LastError {
		return true
	}
	if len(old.WiFiNetworks) != len(new.WiFiNetworks) {
		return true
	}
	if len(old.SavedWiFiNetworks) != len(new.SavedWiFiNetworks) {
		return true
	}
	if len(old.WiFiDevices) != len(new.WiFiDevices) {
		return true
	}
	if len(old.WiredConnections) != len(new.WiredConnections) {
		return true
	}
	if len(old.EthernetDevices) != len(new.EthernetDevices) {
		return true
	}

	for i := range old.WiFiNetworks {
		oldNet := &old.WiFiNetworks[i]
		newNet := &new.WiFiNetworks[i]
		if oldNet.SSID != newNet.SSID {
			return true
		}
		if oldNet.Connected != newNet.Connected {
			return true
		}
		if oldNet.Saved != newNet.Saved {
			return true
		}
		if oldNet.Autoconnect != newNet.Autoconnect {
			return true
		}
	}

	for i := range old.SavedWiFiNetworks {
		oldNet := &old.SavedWiFiNetworks[i]
		newNet := &new.SavedWiFiNetworks[i]
		if oldNet.SSID != newNet.SSID {
			return true
		}
		if oldNet.Connected != newNet.Connected {
			return true
		}
		if oldNet.Autoconnect != newNet.Autoconnect {
			return true
		}
		if oldNet.OutOfRange != newNet.OutOfRange {
			return true
		}
	}

	// Per-device signal strength is intentionally not compared: it churns
	// constantly and the primary device's signal is already debounced above.
	for i := range old.WiFiDevices {
		oldDev := &old.WiFiDevices[i]
		newDev := &new.WiFiDevices[i]
		if oldDev.Name != newDev.Name {
			return true
		}
		if oldDev.State != newDev.State {
			return true
		}
		if oldDev.Connected != newDev.Connected {
			return true
		}
		if oldDev.APCapable != newDev.APCapable {
			return true
		}
		if oldDev.SSID != newDev.SSID {
			return true
		}
	}

	for i := range old.WiredConnections {
		oldNet := &old.WiredConnections[i]
		newNet := &new.WiredConnections[i]
		if oldNet.ID != newNet.ID {
			return true
		}
		if oldNet.IsActive != newNet.IsActive {
			return true
		}
	}

	for i := range old.EthernetDevices {
		oldDev := &old.EthernetDevices[i]
		newDev := &new.EthernetDevices[i]
		if oldDev.Name != newDev.Name {
			return true
		}
		if oldDev.Connected != newDev.Connected {
			return true
		}
		if oldDev.State != newDev.State {
			return true
		}
		if oldDev.IP != newDev.IP {
			return true
		}
		if oldDev.Carrier != newDev.Carrier {
			return true
		}
	}

	return false
}

func (m *Manager) GetState() NetworkState {
	return m.snapshotState()
}

func (m *Manager) Subscribe(id string) chan NetworkState {
	ch := make(chan NetworkState, 64)
	m.subscribers.Store(id, ch)
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}
}

func (m *Manager) SubscribeCredentials(id string) chan CredentialPrompt {
	ch := make(chan CredentialPrompt, 16)
	m.credentialSubscribers.Store(id, ch)
	return ch
}

func (m *Manager) UnsubscribeCredentials(id string) {
	if ch, ok := m.credentialSubscribers.LoadAndDelete(id); ok {
		close(ch)
	}
}

func (m *Manager) broadcastCredentialPrompt(prompt CredentialPrompt) {
	m.credentialSubscribers.Range(func(key string, ch chan CredentialPrompt) bool {
		select {
		case ch <- prompt:
		default:
		}
		return true
	})
}

func (m *Manager) notifier() {
	defer m.notifierWg.Done()
	const minGap = 100 * time.Millisecond
	timer := time.NewTimer(minGap)
	timer.Stop()
	var pending bool
	for {
		select {
		case <-m.stopChan:
			timer.Stop()
			return
		case <-m.dirty:
			if pending {
				continue
			}
			pending = true
			timer.Reset(minGap)
		case <-timer.C:
			if !pending {
				continue
			}

			currentState := m.snapshotState()

			if m.lastNotifiedState != nil && !stateChangedMeaningfully(m.lastNotifiedState, &currentState) {
				pending = false
				continue
			}

			m.subscribers.Range(func(key string, ch chan NetworkState) bool {
				select {
				case ch <- currentState:
				default:
				}
				return true
			})

			stateCopy := currentState
			m.lastNotifiedState = &stateCopy
			pending = false
		}
	}
}

func (m *Manager) notifySubscribers() {
	select {
	case m.dirty <- struct{}{}:
	default:
	}
}

func (m *Manager) SetPromptBroker(broker PromptBroker) error {
	return m.backend.SetPromptBroker(broker)
}

func (m *Manager) SubmitCredentials(token string, secrets map[string]string, save bool) error {
	return m.backend.SubmitCredentials(token, secrets, save)
}

func (m *Manager) CancelCredentials(token string) error {
	return m.backend.CancelCredentials(token)
}

func (m *Manager) GetPromptBroker() PromptBroker {
	return m.backend.GetPromptBroker()
}

func (m *Manager) Close() {
	close(m.stopChan)
	m.notifierWg.Wait()

	if m.backend != nil {
		m.backend.Close()
	}

	m.subscribers.Range(func(key string, ch chan NetworkState) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
}

func (m *Manager) ScanWiFi() error {
	return m.backend.ScanWiFi()
}

func (m *Manager) GetWiFiNetworks() []WiFiNetwork {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	networks := make([]WiFiNetwork, len(m.state.WiFiNetworks))
	copy(networks, m.state.WiFiNetworks)
	return networks
}

func (m *Manager) GetNetworkInfo(ssid string) (*WiFiNetwork, error) {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()

	for _, network := range m.state.WiFiNetworks {
		if network.SSID == ssid {
			return &network, nil
		}
	}

	return nil, fmt.Errorf("network not found: %s", ssid)
}

func (m *Manager) GetNetworkInfoDetailed(ssid string) (*NetworkInfoResponse, error) {
	return m.backend.GetWiFiNetworkDetails(ssid)
}

func (m *Manager) GetWiFiQRContent(ssid string) (string, error) {
	return m.backend.GetWiFiQRCodeContent(ssid)
}

func (m *Manager) GetNetworkQRCode(ssid string) ([2]string, error) {
	content, err := m.backend.GetWiFiQRCodeContent(ssid)
	if err != nil {
		return [2]string{}, err
	}

	qrc, err := qrcode.New(content)
	if err != nil {
		return [2]string{}, fmt.Errorf("failed to create QR code for `%s`: %w", ssid, err)
	}

	pathThemed, pathNormal := qrCodePaths(ssid)

	wThemed, err := standard.New(
		pathThemed,
		standard.WithBuiltinImageEncoder(standard.PNG_FORMAT),
		standard.WithBgTransparent(),
		standard.WithFgColorRGBHex("#ffffff"),
	)
	if err != nil {
		return [2]string{}, fmt.Errorf("failed to create QR code writer: %w", err)
	}
	if err := qrc.Save(wThemed); err != nil {
		return [2]string{}, fmt.Errorf("failed to save QR code for `%s`: %w", ssid, err)
	}

	wNormal, err := standard.New(pathNormal, standard.WithBuiltinImageEncoder(standard.PNG_FORMAT))
	if err != nil {
		return [2]string{}, fmt.Errorf("failed to create QR code writer: %w", err)
	}
	if err := qrc.Save(wNormal); err != nil {
		return [2]string{}, fmt.Errorf("failed to save QR code for `%s`: %w", ssid, err)
	}

	return [2]string{pathThemed, pathNormal}, nil
}

func (m *Manager) ToggleWiFi() error {
	enabled, err := m.backend.GetWiFiEnabled()
	if err != nil {
		return fmt.Errorf("failed to get WiFi state: %w", err)
	}

	err = m.backend.SetWiFiEnabled(!enabled)
	if err != nil {
		return fmt.Errorf("failed to toggle WiFi: %w", err)
	}

	return nil
}

func (m *Manager) EnableWiFi() error {
	err := m.backend.SetWiFiEnabled(true)
	if err != nil {
		return fmt.Errorf("failed to enable WiFi: %w", err)
	}

	return nil
}

func (m *Manager) DisableWiFi() error {
	err := m.backend.SetWiFiEnabled(false)
	if err != nil {
		return fmt.Errorf("failed to disable WiFi: %w", err)
	}

	return nil
}

func (m *Manager) ConnectWiFi(req ConnectionRequest) error {
	return m.backend.ConnectWiFi(req)
}

func (m *Manager) DisconnectWiFi() error {
	return m.backend.DisconnectWiFi()
}

func (m *Manager) ConfigureHotspot(req HotspotRequest) error {
	backend, ok := m.hotspotBackend()
	if !ok {
		return ErrHotspotNotSupported
	}

	if err := backend.ConfigureHotspot(req); err != nil {
		return err
	}

	if err := m.syncStateFromBackend(); err != nil {
		return err
	}
	m.notifySubscribers()

	return nil
}

func (m *Manager) StartHotspot() error {
	backend, ok := m.hotspotBackend()
	if !ok {
		return ErrHotspotNotSupported
	}

	if err := backend.StartHotspot(); err != nil {
		return err
	}

	if err := m.syncStateFromBackend(); err != nil {
		return err
	}
	m.notifySubscribers()

	return nil
}

func (m *Manager) StopHotspot() error {
	backend, ok := m.hotspotBackend()
	if !ok {
		return ErrHotspotNotSupported
	}

	if err := backend.StopHotspot(); err != nil {
		return err
	}

	if err := m.syncStateFromBackend(); err != nil {
		return err
	}
	m.notifySubscribers()

	return nil
}

func (m *Manager) GetHotspotSecrets() (string, error) {
	backend, ok := m.hotspotBackend()
	if !ok {
		return "", ErrHotspotNotSupported
	}

	return backend.GetHotspotSecrets()
}

func (m *Manager) ListHotspotClients() ([]HotspotClient, []string, error) {
	backend, ok := m.backend.(HotspotClientBackend)
	if !ok {
		return nil, nil, ErrHotspotNotSupported
	}
	return backend.ListHotspotClients()
}

func (m *Manager) DisconnectHotspotClient(mac string) error {
	backend, ok := m.backend.(HotspotClientBackend)
	if !ok {
		return ErrHotspotNotSupported
	}
	return backend.DisconnectHotspotClient(mac)
}

func (m *Manager) SetHotspotClientBlocked(mac string, blocked bool) error {
	backend, ok := m.backend.(HotspotClientBackend)
	if !ok {
		return ErrHotspotNotSupported
	}
	return backend.SetHotspotClientBlocked(mac, blocked)
}

func (m *Manager) SetHotspotClientName(mac, name string) error {
	backend, ok := m.backend.(HotspotClientBackend)
	if !ok {
		return ErrHotspotNotSupported
	}
	return backend.SetHotspotClientName(mac, name)
}

func (m *Manager) GetHotspotAnalytics() (HotspotAnalyticsResponse, error) {
	backend, ok := m.backend.(HotspotAnalyticsBackend)
	if !ok {
		return HotspotAnalyticsResponse{}, ErrHotspotNotSupported
	}
	return backend.GetHotspotAnalytics()
}

func (m *Manager) SetHotspotAnalyticsEnabled(enabled bool) error {
	backend, ok := m.backend.(HotspotAnalyticsBackend)
	if !ok {
		return ErrHotspotNotSupported
	}
	return backend.SetHotspotAnalyticsEnabled(enabled)
}

func (m *Manager) DeleteHotspotAnalyticsSession(mac, sessionID string) error {
	backend, ok := m.backend.(HotspotAnalyticsBackend)
	if !ok {
		return ErrHotspotNotSupported
	}
	return backend.DeleteHotspotAnalyticsSession(mac, sessionID)
}

func (m *Manager) ClearCurrentHotspotAnalytics(mac string) error {
	backend, ok := m.backend.(HotspotAnalyticsBackend)
	if !ok {
		return ErrHotspotNotSupported
	}
	return backend.ClearCurrentHotspotAnalytics(mac)
}

func (m *Manager) ClearHotspotAnalyticsDevice(mac string) error {
	backend, ok := m.backend.(HotspotAnalyticsBackend)
	if !ok {
		return ErrHotspotNotSupported
	}
	return backend.ClearHotspotAnalyticsDevice(mac)
}

func (m *Manager) ClearAllHotspotAnalytics() error {
	backend, ok := m.backend.(HotspotAnalyticsBackend)
	if !ok {
		return ErrHotspotNotSupported
	}
	return backend.ClearAllHotspotAnalytics()
}

func (m *Manager) ForgetWiFiNetwork(ssid string) error {
	return m.backend.ForgetWiFiNetwork(ssid)
}

func (m *Manager) GetWiredConfigs() []WiredConnection {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	configs := make([]WiredConnection, len(m.state.WiredConnections))
	copy(configs, m.state.WiredConnections)
	return configs
}

func (m *Manager) GetWiredNetworkInfoDetailed(uuid string) (*WiredNetworkInfoResponse, error) {
	return m.backend.GetWiredNetworkDetails(uuid)
}

func (m *Manager) GetWiredProfile(uuid string) (*WiredProfileConfig, error) {
	backend, ok := m.backend.(WiredProfileBackend)
	if !ok {
		return nil, fmt.Errorf("расширенные настройки Ethernet доступны только через NetworkManager")
	}
	return backend.GetWiredProfile(uuid)
}

func (m *Manager) ApplyWiredProfile(update WiredProfileUpdate) (*WiredProfileApplyResult, error) {
	backend, ok := m.backend.(WiredProfileBackend)
	if !ok {
		return nil, fmt.Errorf("расширенные настройки Ethernet доступны только через NetworkManager")
	}
	return backend.ApplyWiredProfile(update)
}

func (m *Manager) ConfirmWiredProfile(token string) error {
	backend, ok := m.backend.(WiredProfileBackend)
	if !ok {
		return fmt.Errorf("расширенные настройки Ethernet доступны только через NetworkManager")
	}
	return backend.ConfirmWiredProfile(token)
}

func (m *Manager) RollbackWiredProfile(token string) error {
	backend, ok := m.backend.(WiredProfileBackend)
	if !ok {
		return fmt.Errorf("расширенные настройки Ethernet доступны только через NetworkManager")
	}
	return backend.RollbackWiredProfile(token)
}

func (m *Manager) ConnectEthernet() error {
	return m.backend.ConnectEthernet()
}

func (m *Manager) DisconnectEthernet() error {
	return m.backend.DisconnectEthernet()
}

func (m *Manager) DisconnectEthernetDevice(device string) error {
	return m.backend.DisconnectEthernetDevice(device)
}

func (m *Manager) SetEthernetSharing(enabled bool, device string, useVPN bool) error {
	backend, ok := m.ethernetSharingBackend()
	if !ok {
		return ErrEthernetSharingNotSupported
	}
	if err := backend.SetEthernetSharing(enabled, device, useVPN); err != nil {
		return err
	}
	if err := m.syncStateFromBackend(); err != nil {
		return err
	}
	m.notifySubscribers()
	return nil
}

func (m *Manager) GetEthernetDevices() []EthernetDevice {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	devices := make([]EthernetDevice, len(m.state.EthernetDevices))
	copy(devices, m.state.EthernetDevices)
	return devices
}

func (m *Manager) activateConnection(uuid string) error {
	return m.backend.ActivateWiredConnection(uuid)
}

func (m *Manager) SetWiFiAutoconnect(ssid string, autoconnect bool) error {
	return m.backend.SetWiFiAutoconnect(ssid, autoconnect)
}

func (m *Manager) GetWiFiDevices() []WiFiDevice {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	devices := make([]WiFiDevice, len(m.state.WiFiDevices))
	copy(devices, m.state.WiFiDevices)
	return devices
}

func (m *Manager) ScanWiFiDevice(device string) error {
	return m.backend.ScanWiFiDevice(device)
}

func (m *Manager) DisconnectWiFiDevice(device string) error {
	return m.backend.DisconnectWiFiDevice(device)
}

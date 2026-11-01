package network

type Backend interface {
	Initialize() error
	Close()

	GetWiFiEnabled() (bool, error)
	SetWiFiEnabled(enabled bool) error

	ScanWiFi() error
	ScanWiFiDevice(device string) error
	GetWiFiNetworkDetails(ssid string) (*NetworkInfoResponse, error)
	GetWiFiQRCodeContent(ssid string) (string, error)
	GetWiFiDevices() []WiFiDevice

	ConnectWiFi(req ConnectionRequest) error
	DisconnectWiFi() error
	DisconnectWiFiDevice(device string) error
	ForgetWiFiNetwork(ssid string) error
	SetWiFiAutoconnect(ssid string, autoconnect bool) error

	GetEthernetDevices() []EthernetDevice
	GetWiredConnections() ([]WiredConnection, error)
	GetWiredNetworkDetails(uuid string) (*WiredNetworkInfoResponse, error)
	ConnectEthernet() error
	DisconnectEthernet() error
	DisconnectEthernetDevice(device string) error
	ActivateWiredConnection(uuid string) error

	GetCurrentState() (*BackendState, error)

	StartMonitoring(onStateChange func()) error
	StopMonitoring()

	GetPromptBroker() PromptBroker
	SetPromptBroker(broker PromptBroker) error
	SubmitCredentials(token string, secrets map[string]string, save bool) error
	CancelCredentials(token string) error
}

type HotspotBackend interface {
	ConfigureHotspot(req HotspotRequest) error
	StartHotspot() error
	StopHotspot() error
	GetHotspotSecrets() (string, error)
}

type HotspotClientBackend interface {
	ListHotspotClients() ([]HotspotClient, []string, error)
	DisconnectHotspotClient(mac string) error
	SetHotspotClientBlocked(mac string, blocked bool) error
	SetHotspotClientName(mac string, name string) error
}

type HotspotAnalyticsBackend interface {
	GetHotspotAnalytics() (HotspotAnalyticsResponse, error)
	SetHotspotAnalyticsEnabled(enabled bool) error
	DeleteHotspotAnalyticsSession(mac string, sessionID string) error
	ClearCurrentHotspotAnalytics(mac string) error
	ClearHotspotAnalyticsDevice(mac string) error
	ClearAllHotspotAnalytics() error
}

// WiredProfileBackend is optional because the fallback networkd/iwd backends
// cannot persist NetworkManager connection profiles.
type WiredProfileBackend interface {
	GetWiredProfile(uuid string) (*WiredProfileConfig, error)
	ApplyWiredProfile(update WiredProfileUpdate) (*WiredProfileApplyResult, error)
	ConfirmWiredProfile(checkpointToken string) error
	RollbackWiredProfile(checkpointToken string) error
}

// EthernetSharingBackend is optional because NetworkManager owns the shared
// IPv4 mode (DHCP, DNS and NAT) used by this feature. Other backends must not
// advertise a partially working imitation.
type EthernetSharingBackend interface {
	SetEthernetSharing(enabled bool, device string, useVPN bool) error
}

type BackendState struct {
	Backend                   string
	NetworkStatus             NetworkStatus
	PrimaryConnectionType     string
	PrimaryConnectionName     string
	PrimaryDevice             string
	Connectivity              string
	EthernetIP                string
	EthernetDevice            string
	EthernetConnected         bool
	EthernetConnectionUuid    string
	EthernetDevices           []EthernetDevice
	EthernetSharingConfigured bool
	EthernetSharingEnabled    bool
	EthernetSharingActivating bool
	EthernetSharingDevice     string
	EthernetSharingAddress    string
	EthernetSharingUseVPN     bool
	EthernetSharingStatus     string
	EthernetSharingLastError  string
	WiFiIP                    string
	WiFiDevice                string
	WiFiConnected             bool
	WiFiEnabled               bool
	WiFiSSID                  string
	WiFiBSSID                 string
	WiFiSignal                uint8
	WiFiNetworks              []WiFiNetwork
	SavedWiFiNetworks         []WiFiNetwork
	WiFiDevices               []WiFiDevice
	HotspotAvailable          bool
	HotspotConfigured         bool
	HotspotEnabled            bool
	HotspotStatus             string
	HotspotStatusMessage      string
	HotspotActivating         bool
	HotspotSecured            bool
	HotspotSSID               string
	HotspotDevice             string
	HotspotBand               string
	HotspotCompatibility      bool
	HotspotLastError          string
	WiredConnections          []WiredConnection
	IsConnecting              bool
	ConnectingSSID            string
	ConnectingDevice          string
	ConnectingPreExisting     bool
	LastError                 string
}

package network

import (
	"sync"

	"github.com/godbus/dbus/v5"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/third_party/kaskadgo/syncmap"
)

type NetworkStatus string

const (
	StatusDisconnected NetworkStatus = "disconnected"
	StatusEthernet     NetworkStatus = "ethernet"
	StatusWiFi         NetworkStatus = "wifi"
)

type ConnectionPreference string

const (
	PreferenceAuto     ConnectionPreference = "auto"
	PreferenceWiFi     ConnectionPreference = "wifi"
	PreferenceEthernet ConnectionPreference = "ethernet"
)

type WiFiNetwork struct {
	SSID        string `json:"ssid"`
	BSSID       string `json:"bssid"`
	Signal      uint8  `json:"signal"`
	Secured     bool   `json:"secured"`
	Enterprise  bool   `json:"enterprise"`
	Connected   bool   `json:"connected"`
	Saved       bool   `json:"saved"`
	Autoconnect bool   `json:"autoconnect"`
	Hidden      bool   `json:"hidden"`
	OutOfRange  bool   `json:"outOfRange"`
	Frequency   uint32 `json:"frequency"`
	Mode        string `json:"mode"`
	Rate        uint32 `json:"rate"`
	Channel     uint32 `json:"channel"`
	Device      string `json:"device,omitempty"`
}

type WiFiDevice struct {
	Name      string        `json:"name"`
	HwAddress string        `json:"hwAddress"`
	State     string        `json:"state"`
	Connected bool          `json:"connected"`
	APCapable bool          `json:"apCapable"`
	SSID      string        `json:"ssid,omitempty"`
	BSSID     string        `json:"bssid,omitempty"`
	Signal    uint8         `json:"signal,omitempty"`
	IP        string        `json:"ip,omitempty"`
	Networks  []WiFiNetwork `json:"networks"`
}

type EthernetDevice struct {
	Name      string `json:"name"`
	HwAddress string `json:"hwAddress"`
	State     string `json:"state"`
	Connected bool   `json:"connected"`
	Carrier   bool   `json:"carrier"`
	IP        string `json:"ip,omitempty"`
	Speed     uint32 `json:"speed,omitempty"`
	Driver    string `json:"driver,omitempty"`
}

type NetworkState struct {
	Backend                   string               `json:"backend"`
	NetworkStatus             NetworkStatus        `json:"networkStatus"`
	PrimaryConnectionType     string               `json:"primaryConnectionType"`
	PrimaryConnectionName     string               `json:"primaryConnectionName"`
	PrimaryDevice             string               `json:"primaryDevice"`
	Connectivity              string               `json:"connectivity"`
	Preference                ConnectionPreference `json:"preference"`
	PreferenceInitialized     bool                 `json:"preferenceInitialized"`
	EthernetIP                string               `json:"ethernetIP"`
	EthernetDevice            string               `json:"ethernetDevice"`
	EthernetConnected         bool                 `json:"ethernetConnected"`
	EthernetConnectionUuid    string               `json:"ethernetConnectionUuid"`
	EthernetDevices           []EthernetDevice     `json:"ethernetDevices"`
	EthernetSharingSupported  bool                 `json:"ethernetSharingSupported"`
	EthernetSharingConfigured bool                 `json:"ethernetSharingConfigured"`
	EthernetSharingEnabled    bool                 `json:"ethernetSharingEnabled"`
	EthernetSharingActivating bool                 `json:"ethernetSharingActivating"`
	EthernetSharingDevice     string               `json:"ethernetSharingDevice"`
	EthernetSharingAddress    string               `json:"ethernetSharingAddress"`
	EthernetSharingUseVPN     bool                 `json:"ethernetSharingUseVPN"`
	EthernetSharingStatus     string               `json:"ethernetSharingStatus"`
	EthernetSharingLastError  string               `json:"ethernetSharingLastError"`
	WiFiIP                    string               `json:"wifiIP"`
	WiFiDevice                string               `json:"wifiDevice"`
	WiFiConnected             bool                 `json:"wifiConnected"`
	WiFiEnabled               bool                 `json:"wifiEnabled"`
	WiFiSSID                  string               `json:"wifiSSID"`
	WiFiBSSID                 string               `json:"wifiBSSID"`
	WiFiSignal                uint8                `json:"wifiSignal"`
	WiFiNetworks              []WiFiNetwork        `json:"wifiNetworks"`
	SavedWiFiNetworks         []WiFiNetwork        `json:"savedWifiNetworks"`
	WiFiDevices               []WiFiDevice         `json:"wifiDevices"`
	HotspotSupported          bool                 `json:"hotspotSupported"`
	HotspotAvailable          bool                 `json:"hotspotAvailable"`
	HotspotConfigured         bool                 `json:"hotspotConfigured"`
	HotspotEnabled            bool                 `json:"hotspotEnabled"`
	HotspotStatus             string               `json:"hotspotStatus"`
	HotspotStatusMessage      string               `json:"hotspotStatusMessage"`
	HotspotActivating         bool                 `json:"hotspotActivating"`
	HotspotSecured            bool                 `json:"hotspotSecured"`
	HotspotSSID               string               `json:"hotspotSSID"`
	HotspotDevice             string               `json:"hotspotDevice"`
	HotspotBand               string               `json:"hotspotBand"`
	HotspotCompatibility      bool                 `json:"hotspotCompatibility"`
	HotspotLastError          string               `json:"hotspotLastError"`
	WiredConnections          []WiredConnection    `json:"wiredConnections"`
	IsConnecting              bool                 `json:"isConnecting"`
	ConnectingSSID            string               `json:"connectingSSID"`
	ConnectingDevice          string               `json:"connectingDevice,omitempty"`
	LastError                 string               `json:"lastError"`
}

type ConnectionRequest struct {
	SSID              string `json:"ssid"`
	Password          string `json:"password,omitempty"`
	Username          string `json:"username,omitempty"`
	AnonymousIdentity string `json:"anonymousIdentity,omitempty"`
	DomainSuffixMatch string `json:"domainSuffixMatch,omitempty"`
	Interactive       bool   `json:"interactive,omitempty"`
	Hidden            bool   `json:"hidden,omitempty"`
	Device            string `json:"device,omitempty"`
	EAPMethod         string `json:"eapMethod,omitempty"`
	Phase2Auth        string `json:"phase2Auth,omitempty"`
	CACertPath        string `json:"caCertPath,omitempty"`
	ClientCertPath    string `json:"clientCertPath,omitempty"`
	PrivateKeyPath    string `json:"privateKeyPath,omitempty"`
	UseSystemCACerts  *bool  `json:"useSystemCACerts,omitempty"`
}

type HotspotRequest struct {
	SSID          string `json:"ssid"`
	Password      string `json:"password,omitempty"`
	Device        string `json:"device,omitempty"`
	Band          string `json:"band,omitempty"`
	Compatibility bool   `json:"compatibility,omitempty"`
}

type HotspotClient struct {
	MAC              string `json:"mac"`
	IP               string `json:"ip,omitempty"`
	Name             string `json:"name,omitempty"`
	AutoName         string `json:"autoName,omitempty"`
	Vendor           string `json:"vendor,omitempty"`
	RandomizedMAC    bool   `json:"randomizedMAC"`
	Signal           int    `json:"signal"`
	RxBytes          uint64 `json:"rxBytes"`
	TxBytes          uint64 `json:"txBytes"`
	RxBitrate        string `json:"rxBitrate,omitempty"`
	TxBitrate        string `json:"txBitrate,omitempty"`
	ConnectedSeconds uint64 `json:"connectedSeconds"`
	Blocked          bool   `json:"blocked"`
}

type WiredConnection struct {
	Path     dbus.ObjectPath `json:"path"`
	ID       string          `json:"id"`
	UUID     string          `json:"uuid"`
	Type     string          `json:"type"`
	IsActive bool            `json:"isActive"`
}

type PriorityUpdate struct {
	Preference ConnectionPreference `json:"preference"`
}

type Manager struct {
	backend               Backend
	state                 *NetworkState
	stateMutex            sync.RWMutex
	preferenceMutex       sync.Mutex
	subscribers           syncmap.Map[string, chan NetworkState]
	stopChan              chan struct{}
	dirty                 chan struct{}
	notifierWg            sync.WaitGroup
	lastNotifiedState     *NetworkState
	credentialSubscribers syncmap.Map[string, chan CredentialPrompt]
}

type EventType string

const (
	EventStateChanged    EventType = "state_changed"
	EventNetworksUpdated EventType = "networks_updated"
	EventConnecting      EventType = "connecting"
	EventConnected       EventType = "connected"
	EventDisconnected    EventType = "disconnected"
	EventError           EventType = "error"
)

type NetworkEvent struct {
	Type EventType    `json:"type"`
	Data NetworkState `json:"data"`
}

type PromptRequest struct {
	Name           string      `json:"name"`
	SSID           string      `json:"ssid"`
	ConnType       string      `json:"connType"`
	SettingName    string      `json:"setting"`
	Fields         []string    `json:"fields"`
	FieldsInfo     []FieldInfo `json:"fieldsInfo"`
	Hints          []string    `json:"hints"`
	Reason         string      `json:"reason"`
	ConnectionId   string      `json:"connectionId"`
	ConnectionUuid string      `json:"connectionUuid"`
	ConnectionPath string      `json:"connectionPath"`
}

type PromptReply struct {
	Secrets map[string]string `json:"secrets"`
	Save    bool              `json:"save"`
	Cancel  bool              `json:"cancel"`
}

type FieldInfo struct {
	Name     string `json:"name"`
	Label    string `json:"label"`
	IsSecret bool   `json:"isSecret"`
}

type CredentialPrompt struct {
	Token          string      `json:"token"`
	Name           string      `json:"name"`
	SSID           string      `json:"ssid"`
	ConnType       string      `json:"connType"`
	Setting        string      `json:"setting"`
	Fields         []string    `json:"fields"`
	FieldsInfo     []FieldInfo `json:"fieldsInfo"`
	Hints          []string    `json:"hints"`
	Reason         string      `json:"reason"`
	ConnectionId   string      `json:"connectionId"`
	ConnectionUuid string      `json:"connectionUuid"`
}

type NetworkInfoResponse struct {
	SSID  string        `json:"ssid"`
	Bands []WiFiNetwork `json:"bands"`
}

type WiredNetworkInfoResponse struct {
	UUID   string        `json:"uuid"`
	IFace  string        `json:"iface"`
	Driver string        `json:"driver"`
	HwAddr string        `json:"hwAddr"`
	Speed  string        `json:"speed"`
	IPv4   WiredIPConfig `json:"IPv4s"`
	IPv6   WiredIPConfig `json:"IPv6s"`
}

type WiredIPConfig struct {
	IPs             []string     `json:"ips"`
	Gateway         string       `json:"gateway"`
	DNS             string       `json:"dns"`
	Routes          []WiredRoute `json:"routes,omitempty"`
	HasDefaultRoute bool         `json:"hasDefaultRoute"`
}

type WiredRoute struct {
	Destination string `json:"destination"`
	Prefix      uint32 `json:"prefix"`
	NextHop     string `json:"nextHop,omitempty"`
	Metric      uint32 `json:"metric,omitempty"`
	Source      string `json:"source,omitempty"`
}

type WiredProfileConfig struct {
	UUID                   string        `json:"uuid"`
	Name                   string        `json:"name"`
	Interface              string        `json:"interface"`
	Active                 bool          `json:"active"`
	PermanentMAC           string        `json:"permanentMac"`
	CurrentMAC             string        `json:"currentMac"`
	MACMode                string        `json:"macMode"`
	CustomMAC              string        `json:"customMac,omitempty"`
	IPv4Method             string        `json:"ipv4Method"`
	DefaultRouteMode       string        `json:"defaultRouteMode"`
	ManualGateway          string        `json:"manualGateway,omitempty"`
	RouteMetric            int64         `json:"routeMetric"`
	IPv4                   WiredIPConfig `json:"ipv4"`
	HasClasslessRoutes     bool          `json:"hasClasslessRoutes"`
	MissingDefaultRoute    bool          `json:"missingDefaultRoute"`
	SuggestedGateway       string        `json:"suggestedGateway,omitempty"`
	ConnectionState        string        `json:"connectionState"`
	GatewayReachable       bool          `json:"gatewayReachable"`
	InternetReachable      bool          `json:"internetReachable"`
	InternetCheckCompleted bool          `json:"internetCheckCompleted"`
}

type WiredProfileUpdate struct {
	UUID             string `json:"uuid"`
	MACMode          string `json:"macMode"`
	CustomMAC        string `json:"customMac,omitempty"`
	DefaultRouteMode string `json:"defaultRouteMode"`
	Gateway          string `json:"gateway,omitempty"`
	Metric           int64  `json:"metric"`
	RollbackSeconds  uint32 `json:"rollbackSeconds"`
}

type WiredProfileApplyResult struct {
	Profile         *WiredProfileConfig `json:"profile"`
	CheckpointToken string              `json:"checkpointToken"`
	RollbackSeconds uint32              `json:"rollbackSeconds"`
}

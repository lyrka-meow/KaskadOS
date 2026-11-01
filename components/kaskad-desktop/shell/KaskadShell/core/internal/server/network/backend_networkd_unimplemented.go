package network

import "fmt"

func (b *SystemdNetworkdBackend) GetWiFiEnabled() (bool, error) {
	return true, nil
}

func (b *SystemdNetworkdBackend) SetWiFiEnabled(enabled bool) error {
	return fmt.Errorf("WiFi control not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) ScanWiFi() error {
	return fmt.Errorf("WiFi scan not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) GetWiFiNetworkDetails(ssid string) (*NetworkInfoResponse, error) {
	return nil, fmt.Errorf("WiFi details not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) GetWiFiQRCodeContent(ssid string) (string, error) {
	return "", fmt.Errorf("WiFi QR Code not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) ConnectWiFi(req ConnectionRequest) error {
	return fmt.Errorf("WiFi connect not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) DisconnectWiFi() error {
	return fmt.Errorf("WiFi disconnect not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) ForgetWiFiNetwork(ssid string) error {
	return fmt.Errorf("WiFi forget not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) SetWiFiAutoconnect(ssid string, autoconnect bool) error {
	return fmt.Errorf("WiFi autoconnect not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) ScanWiFiDevice(device string) error {
	return fmt.Errorf("WiFi scan not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) DisconnectWiFiDevice(device string) error {
	return fmt.Errorf("WiFi disconnect not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) GetWiFiDevices() []WiFiDevice {
	return nil
}

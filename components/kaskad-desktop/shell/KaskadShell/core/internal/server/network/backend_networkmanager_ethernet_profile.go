package network

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os/exec"
	"strings"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
)

const wiredConnectivityURL = "https://connectivitycheck.gstatic.com/generate_204"

func (b *NetworkManagerBackend) GetWiredProfile(uuid string) (*WiredProfileConfig, error) {
	connection, settings, err := b.findWiredConnection(uuid)
	if err != nil {
		return nil, err
	}
	_ = connection

	profile := &WiredProfileConfig{
		UUID:             uuid,
		MACMode:          "hardware",
		IPv4Method:       "auto",
		DefaultRouteMode: "auto",
		RouteMetric:      100,
		ConnectionState:  "disconnected",
	}
	if section := settings["connection"]; section != nil {
		profile.Name, _ = section["id"].(string)
		profile.Interface, _ = section["interface-name"].(string)
	}
	if section := settings["802-3-ethernet"]; section != nil {
		if cloned, ok := wiredAssignedMAC(section); ok {
			profile.MACMode, profile.CustomMAC = wiredMACMode(cloned)
		}
	}
	if section := settings["ipv4"]; section != nil {
		if method, ok := section["method"].(string); ok && method != "" {
			profile.IPv4Method = method
		}
		if metric, ok := numericInt64(section["route-metric"]); ok && metric >= 0 {
			profile.RouteMetric = metric
		}
		for _, route := range decodeProfileRoutes(section["route-data"]) {
			if route.Prefix == 0 && route.Destination == "0.0.0.0" {
				profile.DefaultRouteMode = "manual"
				profile.ManualGateway = route.NextHop
				if route.Metric > 0 {
					profile.RouteMetric = int64(route.Metric)
				}
				break
			}
		}
	}

	device, wired, err := b.wiredDeviceForProfile(profile.Interface)
	if err == nil {
		profile.Interface, _ = device.GetPropertyInterface()
		profile.CurrentMAC, _ = wired.GetPropertyHwAddress()
		profile.PermanentMAC, _ = wired.GetPropertyPermHwAddress()
		state, _ := device.GetPropertyState()
		profile.ConnectionState = strings.ToLower(strings.TrimPrefix(state.String(), "NmDeviceState"))
		active, activeErr := device.GetPropertyActiveConnection()
		if activeErr == nil && active != nil {
			activeUUID, _ := active.GetPropertyUUID()
			profile.Active = activeUUID == uuid
			if profile.Active {
				profile.IPv4 = activeWiredIPv4(active)
			}
		}
	}

	for _, route := range profile.IPv4.Routes {
		if route.Prefix == 0 && route.Destination == "0.0.0.0" {
			profile.IPv4.HasDefaultRoute = true
		}
		// A directly connected subnet route is created for every ordinary
		// Ethernet lease.  Only a non-default route that actually goes through
		// a gateway indicates DHCP classless routes (option 121) or an equivalent
		// static route.
		if route.Prefix != 0 && route.NextHop != "" {
			profile.HasClasslessRoutes = true
		}
		if profile.SuggestedGateway == "" && route.NextHop != "" {
			profile.SuggestedGateway = route.NextHop
		}
	}
	if profile.IPv4.Gateway != "" {
		profile.IPv4.HasDefaultRoute = true
		if profile.SuggestedGateway == "" {
			profile.SuggestedGateway = profile.IPv4.Gateway
		}
	}
	profile.MissingDefaultRoute = profile.Active && len(profile.IPv4.IPs) > 0 && profile.HasClasslessRoutes && !profile.IPv4.HasDefaultRoute
	return profile, nil
}

func (b *NetworkManagerBackend) ApplyWiredProfile(update WiredProfileUpdate) (*WiredProfileApplyResult, error) {
	if strings.TrimSpace(update.UUID) == "" {
		return nil, errors.New("не выбран проводной профиль")
	}
	clonedMAC, err := validatedClonedMAC(update.MACMode, update.CustomMAC)
	if err != nil {
		return nil, err
	}
	if update.DefaultRouteMode != "auto" && update.DefaultRouteMode != "manual" {
		return nil, errors.New("неизвестный режим маршрута по умолчанию")
	}
	if update.Metric < 0 || update.Metric > 4_294_967_295 {
		return nil, errors.New("метрика должна быть от 0 до 4294967295")
	}
	gateway := strings.TrimSpace(update.Gateway)
	if update.DefaultRouteMode == "manual" {
		parsed := net.ParseIP(gateway)
		if parsed == nil || parsed.To4() == nil {
			return nil, errors.New("укажите корректный IPv4-адрес шлюза")
		}
	}
	if update.RollbackSeconds == 0 {
		update.RollbackSeconds = 60
	}

	connection, settings, err := b.findWiredConnection(update.UUID)
	if err != nil {
		return nil, err
	}
	// GetSettings exposes both the current address-data/route-data properties and
	// their deprecated binary-array counterparts.  Once decoded into interface{}
	// by the D-Bus library, the legacy IPv6 tuple arrays lose the exact signature
	// required to encode them again (for example a(ayuay) becomes aav).  Never
	// round-trip those duplicate properties; NetworkManager reconstructs them
	// from the modern representation itself.
	removeLegacyIPProperties(settings)
	interfaceName := ""
	if section := settings["connection"]; section != nil {
		interfaceName, _ = section["interface-name"].(string)
	}
	device, wiredDevice, err := b.wiredDeviceForProfile(interfaceName)
	if err != nil {
		return nil, err
	}

	ethernet := settings["802-3-ethernet"]
	if ethernet == nil {
		ethernet = make(map[string]any)
		settings["802-3-ethernet"] = ethernet
	}
	// NetworkManager exposes the current string representation (including the
	// special values permanent/random/stable) as assigned-mac-address.  The old
	// cloned-mac-address D-Bus field is an `ay` byte array and cannot accept a
	// string.  Remove the legacy value returned by GetSettings before updating
	// the profile so the two representations cannot conflict.
	delete(ethernet, "cloned-mac-address")
	ethernet["assigned-mac-address"] = clonedMAC

	ipv4 := settings["ipv4"]
	if ipv4 == nil {
		ipv4 = map[string]any{"method": "auto"}
		settings["ipv4"] = ipv4
	}
	ipv4["method"] = "auto"
	ipv4["never-default"] = false
	ipv4["route-metric"] = update.Metric
	routes := withoutDefaultRouteMaps(profileRouteMaps(ipv4["route-data"]))
	if update.DefaultRouteMode == "manual" {
		routes = append(routes, map[string]any{
			"dest":     "0.0.0.0",
			"prefix":   uint32(0),
			"next-hop": gateway,
			"metric":   uint32(update.Metric),
		})
	}
	ipv4["route-data"] = routes

	// A disconnected Ethernet profile can still be configured usefully.  With
	// no physical carrier there is no connectivity to protect or verify, so save
	// atomically and let NetworkManager apply it when a cable is next connected.
	if carrier, carrierErr := wiredDevice.GetPropertyCarrier(); carrierErr == nil && !carrier {
		if err := connection.Update(settings); err != nil {
			return nil, fmt.Errorf("не удалось сохранить проводной профиль: %w", err)
		}
		profile, err := b.GetWiredProfile(update.UUID)
		if err != nil {
			return nil, err
		}
		return &WiredProfileApplyResult{Profile: profile}, nil
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	checkpoint, err := nm.CheckpointCreate([]gonetworkmanager.Device{device}, update.RollbackSeconds, uint32(gonetworkmanager.NmCheckpointCreateFlagsDeleteNewConnections))
	if err != nil {
		return nil, fmt.Errorf("не удалось создать точку безопасного отката: %w", err)
	}
	token := string(checkpoint.GetPath())
	b.wiredCheckpointMu.Lock()
	b.wiredCheckpoints[token] = checkpoint
	b.wiredCheckpointMu.Unlock()
	go func() {
		time.Sleep(time.Duration(update.RollbackSeconds+5) * time.Second)
		b.forgetWiredCheckpoint(token)
	}()

	rollback := func(cause error) (*WiredProfileApplyResult, error) {
		_, _ = nm.CheckpointRollback(checkpoint)
		b.forgetWiredCheckpoint(token)
		return nil, cause
	}

	if err := connection.Update(settings); err != nil {
		return rollback(fmt.Errorf("не удалось сохранить проводной профиль: %w", err))
	}
	if _, err := nm.ActivateConnection(connection, device, nil); err != nil {
		return rollback(fmt.Errorf("не удалось переподключить Ethernet: %w", err))
	}

	profile, err := b.waitForWiredProfile(update.UUID, 12*time.Second)
	if err != nil {
		return rollback(err)
	}
	profile.GatewayReachable = checkGateway(profile.IPv4.Gateway, profile.ManualGateway)
	profile.InternetReachable, profile.InternetCheckCompleted = checkWiredInternet(profile)
	return &WiredProfileApplyResult{
		Profile:         profile,
		CheckpointToken: token,
		RollbackSeconds: update.RollbackSeconds,
	}, nil
}

func (b *NetworkManagerBackend) ConfirmWiredProfile(checkpointToken string) error {
	checkpoint, err := b.takeWiredCheckpoint(checkpointToken)
	if err != nil {
		return err
	}
	if err := b.nmConn.(gonetworkmanager.NetworkManager).CheckpointDestroy(checkpoint); err != nil {
		return fmt.Errorf("не удалось подтвердить настройки: %w", err)
	}
	return nil
}

func (b *NetworkManagerBackend) RollbackWiredProfile(checkpointToken string) error {
	checkpoint, err := b.takeWiredCheckpoint(checkpointToken)
	if err != nil {
		return err
	}
	if _, err := b.nmConn.(gonetworkmanager.NetworkManager).CheckpointRollback(checkpoint); err != nil {
		return fmt.Errorf("не удалось восстановить предыдущие настройки: %w", err)
	}
	return nil
}

func (b *NetworkManagerBackend) findWiredConnection(uuid string) (gonetworkmanager.Connection, gonetworkmanager.ConnectionSettings, error) {
	settingsManager := b.settings
	if settingsManager == nil {
		manager, err := gonetworkmanager.NewSettings()
		if err != nil {
			return nil, nil, fmt.Errorf("не удалось открыть настройки NetworkManager: %w", err)
		}
		settingsManager = manager
		b.settings = manager
	}
	connections, err := settingsManager.(gonetworkmanager.Settings).ListConnections()
	if err != nil {
		return nil, nil, fmt.Errorf("не удалось получить проводные профили: %w", err)
	}
	for _, connection := range connections {
		settings, err := connection.GetSettings()
		if err != nil {
			continue
		}
		meta := settings["connection"]
		connectionUUID, _ := meta["uuid"].(string)
		connectionType, _ := meta["type"].(string)
		if connectionUUID == uuid && connectionType == "802-3-ethernet" {
			return connection, settings, nil
		}
	}
	return nil, nil, fmt.Errorf("проводной профиль %q не найден", uuid)
}

func (b *NetworkManagerBackend) wiredDeviceForProfile(interfaceName string) (gonetworkmanager.Device, gonetworkmanager.DeviceWired, error) {
	if interfaceName != "" {
		if info, ok := b.ethernetDeviceByIface(interfaceName); ok {
			return info.device, info.wired, nil
		}
	}
	if b.ethernetDevice == nil {
		return nil, nil, errors.New("проводной адаптер не найден")
	}
	device := b.ethernetDevice.(gonetworkmanager.Device)
	wired, err := gonetworkmanager.NewDeviceWired(device.GetPath())
	if err != nil {
		return nil, nil, fmt.Errorf("не удалось открыть проводной адаптер: %w", err)
	}
	return device, wired, nil
}

func activeWiredIPv4(active gonetworkmanager.ActiveConnection) WiredIPConfig {
	result := WiredIPConfig{}
	config, err := active.GetPropertyIP4Config()
	if err != nil || config == nil {
		return result
	}
	if addresses, err := config.GetPropertyAddressData(); err == nil {
		for _, address := range addresses {
			result.IPs = append(result.IPs, fmt.Sprintf("%s/%d", address.Address, address.Prefix))
		}
	}
	result.Gateway, _ = config.GetPropertyGateway()
	if nameservers, err := config.GetPropertyNameserverData(); err == nil {
		parts := make([]string, 0, len(nameservers))
		for _, nameserver := range nameservers {
			parts = append(parts, nameserver.Address)
		}
		result.DNS = strings.Join(parts, "; ")
	}
	if routes, err := config.GetPropertyRouteData(); err == nil {
		for _, route := range routes {
			converted := WiredRoute{
				Destination: route.Destination,
				Prefix:      uint32(route.Prefix),
				NextHop:     route.NextHop,
				Metric:      uint32(route.Metric),
				Source:      route.AdditionalAttributes["source"],
			}
			result.Routes = append(result.Routes, converted)
			if converted.Destination == "0.0.0.0" && converted.Prefix == 0 {
				result.HasDefaultRoute = true
			}
		}
	}
	return result
}

func wiredMACMode(value string) (string, string) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "", "permanent", "preserve":
		return "hardware", ""
	case "random":
		return "random", ""
	case "stable", "stable-ssid":
		return "stable", ""
	default:
		if normalized, err := normalizeUnicastMAC(value); err == nil {
			return "custom", normalized
		}
		return "hardware", ""
	}
}

func wiredAssignedMAC(section map[string]any) (string, bool) {
	if assigned, ok := section["assigned-mac-address"].(string); ok && strings.TrimSpace(assigned) != "" {
		return assigned, true
	}
	// Older NetworkManager versions expose only the deprecated byte-array
	// representation for a concrete cloned address.
	if cloned, ok := section["cloned-mac-address"].([]byte); ok && len(cloned) == 6 {
		return net.HardwareAddr(cloned).String(), true
	}
	return "", false
}

func removeLegacyIPProperties(settings map[string]map[string]any) {
	for _, family := range []string{"ipv4", "ipv6"} {
		section := settings[family]
		if section == nil {
			continue
		}
		if _, hasAddressData := section["address-data"]; hasAddressData {
			delete(section, "addresses")
		}
		if _, hasRouteData := section["route-data"]; hasRouteData {
			delete(section, "routes")
		}
	}
}

func validatedClonedMAC(mode, custom string) (string, error) {
	switch mode {
	case "", "hardware":
		return "permanent", nil
	case "random":
		return "random", nil
	case "stable":
		return "stable", nil
	case "custom":
		return normalizeUnicastMAC(custom)
	default:
		return "", errors.New("неизвестный режим MAC-адреса")
	}
}

func normalizeUnicastMAC(value string) (string, error) {
	mac, err := net.ParseMAC(strings.TrimSpace(value))
	if err != nil || len(mac) != 6 {
		return "", errors.New("MAC-адрес должен иметь формат 00:11:22:33:44:55")
	}
	allZero, allFF := true, true
	for _, octet := range mac {
		allZero = allZero && octet == 0
		allFF = allFF && octet == 0xff
	}
	if allZero || allFF || mac[0]&1 != 0 {
		return "", errors.New("нельзя использовать нулевой, broadcast или multicast MAC-адрес")
	}
	return strings.ToUpper(mac.String()), nil
}

func decodeProfileRoutes(value any) []WiredRoute {
	maps := profileRouteMaps(value)
	routes := make([]WiredRoute, 0, len(maps))
	for _, route := range maps {
		destination, _ := route["dest"].(string)
		prefix, _ := numericUint32(route["prefix"])
		nextHop, _ := route["next-hop"].(string)
		metric, _ := numericUint32(route["metric"])
		if destination == "" {
			continue
		}
		routes = append(routes, WiredRoute{Destination: destination, Prefix: prefix, NextHop: nextHop, Metric: metric, Source: "manual"})
	}
	return routes
}

func profileRouteMaps(value any) []map[string]any {
	var routes []map[string]any
	switch typed := value.(type) {
	case []map[string]any:
		routes = append(routes, typed...)
	case []any:
		for _, item := range typed {
			if route, ok := item.(map[string]any); ok {
				routes = append(routes, route)
			}
		}
	}
	return routes
}

func withoutDefaultRouteMaps(routes []map[string]any) []map[string]any {
	filtered := make([]map[string]any, 0, len(routes))
	for _, route := range routes {
		destination, _ := route["dest"].(string)
		prefix, _ := numericUint32(route["prefix"])
		if destination == "0.0.0.0" && prefix == 0 {
			continue
		}
		filtered = append(filtered, route)
	}
	return filtered
}

func numericUint32(value any) (uint32, bool) {
	integer, ok := numericInt64(value)
	if !ok || integer < 0 || integer > 4_294_967_295 {
		return 0, false
	}
	return uint32(integer), true
}

func numericInt64(value any) (int64, bool) {
	switch typed := value.(type) {
	case int:
		return int64(typed), true
	case int32:
		return int64(typed), true
	case int64:
		return typed, true
	case uint32:
		return int64(typed), true
	case uint64:
		if typed <= uint64(^uint64(0)>>1) {
			return int64(typed), true
		}
	case float64:
		return int64(typed), typed == float64(int64(typed))
	}
	return 0, false
}

func (b *NetworkManagerBackend) waitForWiredProfile(uuid string, timeout time.Duration) (*WiredProfileConfig, error) {
	deadline := time.Now().Add(timeout)
	var last *WiredProfileConfig
	for time.Now().Before(deadline) {
		profile, err := b.GetWiredProfile(uuid)
		if err == nil {
			last = profile
			if profile.Active && len(profile.IPv4.IPs) > 0 {
				return profile, nil
			}
		}
		time.Sleep(350 * time.Millisecond)
	}
	if last != nil && last.Active {
		return last, nil
	}
	return nil, errors.New("Ethernet не получил адрес после применения; предыдущие настройки восстановлены")
}

func checkGateway(dhcpGateway, manualGateway string) bool {
	gateway := dhcpGateway
	if gateway == "" {
		gateway = manualGateway
	}
	if net.ParseIP(gateway) == nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "ping", "-n", "-c", "1", "-W", "2", gateway).Run() == nil
}

func checkWiredInternet(profile *WiredProfileConfig) (bool, bool) {
	if len(profile.IPv4.IPs) == 0 {
		return false, true
	}
	address, _, err := net.ParseCIDR(profile.IPv4.IPs[0])
	if err != nil {
		return false, true
	}
	dialer := &net.Dialer{Timeout: 5 * time.Second, LocalAddr: &net.TCPAddr{IP: address}}
	client := &http.Client{
		Timeout: 7 * time.Second,
		Transport: &http.Transport{
			DialContext:         dialer.DialContext,
			TLSHandshakeTimeout: 4 * time.Second,
		},
	}
	request, err := http.NewRequest(http.MethodGet, wiredConnectivityURL, nil)
	if err != nil {
		return false, true
	}
	response, err := client.Do(request)
	if err != nil {
		return false, true
	}
	defer response.Body.Close()
	return response.StatusCode == http.StatusNoContent, true
}

func (b *NetworkManagerBackend) forgetWiredCheckpoint(token string) {
	b.wiredCheckpointMu.Lock()
	delete(b.wiredCheckpoints, token)
	b.wiredCheckpointMu.Unlock()
}

func (b *NetworkManagerBackend) takeWiredCheckpoint(token string) (gonetworkmanager.Checkpoint, error) {
	b.wiredCheckpointMu.Lock()
	defer b.wiredCheckpointMu.Unlock()
	checkpoint := b.wiredCheckpoints[token]
	if checkpoint == nil {
		return nil, errors.New("срок подтверждения истёк или точка отката не найдена")
	}
	delete(b.wiredCheckpoints, token)
	return checkpoint, nil
}

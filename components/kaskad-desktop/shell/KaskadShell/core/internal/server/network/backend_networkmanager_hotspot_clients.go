package network

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
)

const hotspotControlHelper = "/usr/lib/kaskados/kaskados-hotspot-control"

var hotspotMACPattern = regexp.MustCompile(`(?i)^[0-9a-f]{2}(:[0-9a-f]{2}){5}$`)

func normalizeHotspotMAC(value string) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	if !hotspotMACPattern.MatchString(value) {
		return "", fmt.Errorf("invalid MAC address")
	}
	return value, nil
}

func hotspotBlockedPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "KaskadShell", "hotspot-blocked.json"), nil
}

func hotspotNamesPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "KaskadShell", "hotspot-device-names.json"), nil
}

func loadHotspotNames() (map[string]string, error) {
	names := map[string]string{}
	path, err := hotspotNamesPath()
	if err != nil {
		return names, err
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return names, nil
	}
	if err != nil {
		return names, err
	}
	if err := json.Unmarshal(data, &names); err != nil {
		return nil, err
	}
	return names, nil
}

func saveHotspotNames(names map[string]string) error {
	path, err := hotspotNamesPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(names, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

func hotspotLeaseNames() map[string]string {
	result := map[string]string{}
	for _, path := range []string{"/run/kaskados-hotspot/dnsmasq.leases", "/var/lib/misc/dnsmasq.leases"} {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			fields := strings.Fields(line)
			if len(fields) < 4 || fields[3] == "*" {
				continue
			}
			if mac, err := normalizeHotspotMAC(fields[1]); err == nil {
				result[mac] = fields[3]
			}
		}
	}
	return result
}

var (
	hotspotVendors     map[string]string
	hotspotVendorsOnce sync.Once
)

func hotspotVendor(mac string) string {
	if hotspotMACIsRandomized(mac) || len(mac) < 8 {
		return ""
	}
	hotspotVendorsOnce.Do(func() {
		hotspotVendors = map[string]string{}
		paths := []string{"/usr/share/hwdata/oui.txt", "/usr/share/ieee-data/oui.txt", "/usr/share/misc/oui.txt"}
		for _, path := range paths {
			file, err := os.Open(path)
			if err != nil {
				continue
			}
			scanner := bufio.NewScanner(file)
			for scanner.Scan() {
				parts := strings.SplitN(scanner.Text(), "(hex)", 2)
				if len(parts) != 2 {
					continue
				}
				prefix := strings.ToLower(strings.ReplaceAll(strings.TrimSpace(parts[0]), "-", ":"))
				vendor := strings.TrimSpace(parts[1])
				if len(prefix) == 8 && vendor != "" {
					hotspotVendors[prefix] = vendor
				}
			}
			_ = file.Close()
			if len(hotspotVendors) > 0 {
				break
			}
		}
	})
	return hotspotVendors[strings.ToLower(mac[:8])]
}

func loadHotspotBlocked() (map[string]bool, error) {
	blocked := map[string]bool{}
	path, err := hotspotBlockedPath()
	if err != nil {
		return blocked, err
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return blocked, nil
	}
	if err != nil {
		return blocked, err
	}
	var values []string
	if err := json.Unmarshal(data, &values); err != nil {
		return blocked, err
	}
	for _, value := range values {
		if mac, err := normalizeHotspotMAC(value); err == nil {
			blocked[mac] = true
		}
	}
	return blocked, nil
}

func saveHotspotBlocked(blocked map[string]bool) error {
	path, err := hotspotBlockedPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	values := make([]string, 0, len(blocked))
	for mac := range blocked {
		values = append(values, mac)
	}
	data, err := json.MarshalIndent(values, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

func (b *NetworkManagerBackend) hotspotInterface() (string, error) {
	b.stateMutex.RLock()
	enabled := b.state.HotspotEnabled
	configuredDevice := b.state.HotspotDevice
	b.stateMutex.RUnlock()
	if !enabled {
		return "", fmt.Errorf("hotspot is not running")
	}
	if externalHotspotRunning() {
		return kaskadShellHotspotVirtualIface, nil
	}
	active, err := b.findActiveKaskadHotspotConnection()
	if err != nil {
		return "", fmt.Errorf("cannot determine hotspot interface: %w", err)
	}
	if active != nil {
		devices, err := active.GetPropertyDevices()
		if err != nil {
			return "", fmt.Errorf("cannot determine hotspot interface: %w", err)
		}
		for _, device := range devices {
			if device == nil {
				continue
			}
			if name, err := device.GetPropertyInterface(); err == nil && name != "" {
				return name, nil
			}
		}
	}
	if configuredDevice != "" {
		return configuredDevice, nil
	}
	return "", fmt.Errorf("cannot determine hotspot interface")
}

func (b *NetworkManagerBackend) ListHotspotClients() ([]HotspotClient, []string, error) {
	blocked, err := loadHotspotBlocked()
	if err != nil {
		return nil, nil, err
	}
	blockedList := make([]string, 0, len(blocked))
	for mac := range blocked {
		blockedList = append(blockedList, mac)
	}
	sort.Strings(blockedList)
	iface, err := b.hotspotInterface()
	if err != nil {
		b.observeHotspotAnalytics(nil)
		return []HotspotClient{}, blockedList, nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, "iw", "dev", iface, "station", "dump").Output()
	if err != nil {
		return nil, blockedList, fmt.Errorf("cannot read Wi-Fi stations: %w", err)
	}
	ips := hotspotNeighborIPs(ctx, iface)
	clients := parseHotspotStations(string(output), ips, blocked)
	names, _ := loadHotspotNames()
	leaseNames := hotspotLeaseNames()
	for i := range clients {
		clients[i].AutoName = leaseNames[clients[i].MAC]
		clients[i].Name = names[clients[i].MAC]
		clients[i].RandomizedMAC = hotspotMACIsRandomized(clients[i].MAC)
		clients[i].Vendor = hotspotVendor(clients[i].MAC)
	}
	for _, client := range clients {
		if client.Blocked {
			_ = runHotspotControl("block", iface, client.MAC)
		}
	}
	b.observeHotspotAnalytics(clients)
	return clients, blockedList, nil
}

func hotspotMACIsRandomized(mac string) bool {
	parsed, err := net.ParseMAC(mac)
	return err == nil && len(parsed) > 0 && parsed[0]&0x02 != 0
}

func hotspotNeighborIPs(ctx context.Context, iface string) map[string]string {
	result := map[string]string{}
	output, err := exec.CommandContext(ctx, "ip", "-j", "neigh", "show", "dev", iface).Output()
	if err != nil {
		return result
	}
	var rows []struct {
		Dst    string `json:"dst"`
		LLAddr string `json:"lladdr"`
	}
	if json.Unmarshal(output, &rows) == nil {
		for _, row := range rows {
			if net.ParseIP(row.Dst) != nil {
				result[strings.ToLower(row.LLAddr)] = row.Dst
			}
		}
	}
	return result
}

func parseHotspotStations(output string, ips map[string]string, blocked map[string]bool) []HotspotClient {
	clients := []HotspotClient{}
	var current *HotspotClient
	flush := func() {
		if current != nil {
			clients = append(clients, *current)
		}
	}
	scanner := bufio.NewScanner(strings.NewReader(output))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "Station ") {
			flush()
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				mac := strings.ToLower(fields[1])
				current = &HotspotClient{MAC: mac, IP: ips[mac], Blocked: blocked[mac]}
			}
			continue
		}
		if current == nil {
			continue
		}
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		value = strings.TrimSpace(value)
		number := func() uint64 {
			fields := strings.Fields(value)
			if len(fields) == 0 {
				return 0
			}
			parsed, _ := strconv.ParseUint(fields[0], 10, 64)
			return parsed
		}
		switch strings.TrimSpace(key) {
		case "rx bytes":
			current.RxBytes = number()
		case "tx bytes":
			current.TxBytes = number()
		case "connected time":
			current.ConnectedSeconds = number()
		case "signal":
			fields := strings.Fields(value)
			if len(fields) > 0 {
				current.Signal, _ = strconv.Atoi(fields[0])
			}
		case "rx bitrate":
			current.RxBitrate = value
		case "tx bitrate":
			current.TxBitrate = value
		}
	}
	flush()
	return clients
}

func runHotspotControl(action, iface, mac string) error {
	output, err := exec.Command("pkexec", hotspotControlHelper, action, iface, mac).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func runHotspotInterfaceControl(action string, args ...string) error {
	commandArgs := append([]string{hotspotControlHelper, action}, args...)
	output, err := exec.Command("pkexec", commandArgs...).CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("%s", message)
	}
	return nil
}

func (b *NetworkManagerBackend) DisconnectHotspotClient(value string) error {
	mac, err := normalizeHotspotMAC(value)
	if err != nil {
		return err
	}
	iface, err := b.hotspotInterface()
	if err != nil {
		return err
	}
	return runHotspotControl("disconnect", iface, mac)
}

func (b *NetworkManagerBackend) SetHotspotClientName(value, name string) error {
	mac, err := normalizeHotspotMAC(value)
	if err != nil {
		return err
	}
	name = strings.TrimSpace(name)
	if len([]rune(name)) > 64 || strings.IndexFunc(name, unicode.IsControl) >= 0 {
		return fmt.Errorf("device name must contain at most 64 printable characters")
	}
	names, err := loadHotspotNames()
	if err != nil {
		return err
	}
	if name == "" {
		delete(names, mac)
	} else {
		names[mac] = name
	}
	return saveHotspotNames(names)
}

func (b *NetworkManagerBackend) SetHotspotClientBlocked(value string, shouldBlock bool) error {
	mac, err := normalizeHotspotMAC(value)
	if err != nil {
		return err
	}
	blocked, err := loadHotspotBlocked()
	if err != nil {
		return err
	}
	iface, _ := b.hotspotInterface()
	if iface == "" {
		iface = "wlan0"
	}
	action := "unblock"
	if shouldBlock {
		action = "block"
	}
	if err := runHotspotControl(action, iface, mac); err != nil {
		return err
	}
	if shouldBlock {
		blocked[mac] = true
	} else {
		delete(blocked, mac)
	}
	return saveHotspotBlocked(blocked)
}
